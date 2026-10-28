extends Node
## 在线模式的账号服务端（独立进程，用同一个 Godot 工程跑）。
##
## 启动：
##   godot --headless --path . res://server/server_main.tscn -- --port=9000 --data=user://server/accounts.json
##
## 面板（只读，看账号 / pp / 战绩）：
##   默认 http://127.0.0.1:8080/
##   加 --admin-password=xxx 会要求登录，并默认监听 0.0.0.0 方便从别的电脑看
##   其它参数：--web-port=8080 --web-host=0.0.0.0
##
## 协议：一行一个 JSON，请求带 op 和 id，响应原样带回 id。
##   register  {name, password}          -> {ok, token, account}
##   login     {name, password}          -> {ok, token, account}
##   upload    {token, account}          -> {ok, total_pp}   （服务端重算积分和 pp 后保存）
##   profile   {token}                   -> {ok, account}
##   leaderboard {limit}                 -> {ok, players: [{name, pp, score}]}
##   ping                                -> {ok, time}

const DEFAULT_PORT := 9000
const DEFAULT_WEB_PORT := 8080
const DEFAULT_DATA := "user://server/accounts.json"
const MAX_CLIENTS := 64
const MAX_NAME_LENGTH := 16
const MIN_PASSWORD_LENGTH := 4
## 面板一次最多返回多少条最近游玩
const WEB_RECENT_PLAYS := 30

## 单个连接一条请求的上限，防止有人塞超长行把服务端撑爆
const MAX_REQUEST_BYTES := 4 * 1024 * 1024
## 连接空闲多久后回收（客户端每 45 秒会 ping 一次）
const CLIENT_IDLE_TIMEOUT_MS := 120000
## 每个账号最多保留多少场游玩
const MAX_PLAYS := 2000
## 背包：最多几件、单件最多几个
const MAX_BAG_ITEMS := 32
const MAX_ITEM_COUNT := 99

## 登录失败限流：窗口内失败几次就锁多久
const MAX_LOGIN_FAILURES := 5
const LOGIN_FAILURE_WINDOW_SEC := 600
const LOGIN_BLOCK_SEC := 600

## 密码哈希：SHA-256 迭代轮数。旧存档是单轮，登录成功后就地升级
const HASH_VERSION := 2
const HASH_ROUNDS := 100000

## 各玩法的得分规则，和客户端一致；服务端用它们重算分数
const SCORE_RULES := {
	0: {"correct": 5, "wrong": -1}, # 英汉配对
	1: {"correct": 3, "wrong": -2}, # 快问快答
	2: {"correct": 8, "wrong": -3}, # 快速拼写
}
## 各玩法一局最多能对/错多少（60 秒内的合理上限）
const MAX_CORRECT := {0: 30, 1: 200, 2: 200}
const MAX_WRONG := {0: 200, 1: 200, 2: 200}

var port := DEFAULT_PORT
var web_port := DEFAULT_WEB_PORT
## 空字符串表示按是否设置密码自动决定：有密码就 0.0.0.0，没有就只监听本机
var web_bind := ""
var admin_password := ""
var data_path := DEFAULT_DATA
var tcp := TCPServer.new()
var web_node: Node = null
var started_unix := 0.0

## peer -> {buffer: PackedByteArray, user: String, last_seen: int}
var clients: Dictionary = {}
## 用户名 -> {name, salt, password_hash, hash_version, created_unix, account}
var accounts: Dictionary = {}
## token -> 用户名
var tokens: Dictionary = {}
## ip -> {count: int, first: float, blocked_until: float}
var login_failures: Dictionary = {}


func _ready() -> void:
	started_unix = Time.get_unix_time_from_system()
	_parse_args()
	_load_accounts()
	var listen_error := tcp.listen(port, "0.0.0.0")
	if listen_error != OK:
		push_error("[server] 端口 %d 监听失败：%s" % [port, error_string(listen_error)])
		print("[server] 端口 %d 监听失败：%s" % [port, error_string(listen_error)])
		get_tree().quit(1)
		return
	print("[server] 已启动：端口 %d，数据 %s，已有账号 %d 个" % [port, data_path, accounts.size()])
	_start_web()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		if tcp != null:
			tcp.stop()


## 启动只读面板（内置的小型 HTTP 服务）
func _start_web() -> void:
	var bind := web_bind
	if bind == "":
		bind = "0.0.0.0" if admin_password != "" else "127.0.0.1"
	var web_script: Script = load("res://server/web_server.gd")
	web_node = web_script.new()
	web_node.name = "WebPanel"
	add_child(web_node)
	var err: Error = web_node.start(web_port, bind, admin_password, self)
	if err != OK:
		push_error("[server] 面板端口 %d 启动失败：%s" % [web_port, error_string(err)])
		print("[server] 面板端口 %d 启动失败，账号服务不受影响" % web_port)
		return
	var hint := "需要管理员密码" if admin_password != "" else "仅本机可访问"
	print("[server] 面板：http://%s:%d/ （%s）" % [bind, web_port, hint])


func _process(_delta: float) -> void:
	while tcp.is_connection_available():
		var peer := tcp.take_connection()
		if clients.size() >= MAX_CLIENTS:
			print("[server] 连接数已满（%d），拒绝：%s" % [MAX_CLIENTS, peer.get_connected_host()])
			peer.disconnect_from_host()
			continue
		clients[peer] = {"buffer": PackedByteArray(), "user": "", "last_seen": Time.get_ticks_msec()}
		print("[server] 客户端接入：%s" % peer.get_connected_host())

	for peer in clients.keys():
		_poll_client(peer)


# ---------------------------------------------------------------- 连接


func _poll_client(peer: StreamPeerTCP) -> void:
	# 刚 take_connection() 时状态可能还是 CONNECTING，必须先 poll 推进握手，
	# 否则会把刚连上的客户端当成断线踢掉。
	peer.poll()
	var status := peer.get_status()
	# STATUS_NONE 表示对方已经正常关闭；以前只处理 ERROR，条目会永远留在 clients 里
	if status == StreamPeerTCP.STATUS_ERROR or status == StreamPeerTCP.STATUS_NONE:
		_drop_client(peer)
		return
	if status != StreamPeerTCP.STATUS_CONNECTED:
		return

	var info: Dictionary = clients[peer]
	if Time.get_ticks_msec() - int(info["last_seen"]) > CLIENT_IDLE_TIMEOUT_MS:
		print("[server] 空闲超时，断开：%s" % peer.get_connected_host())
		_drop_client(peer)
		return

	var available := peer.get_available_bytes()
	if available <= 0:
		return
	var received := peer.get_partial_data(available)
	if received[0] != OK:
		_drop_client(peer)
		return

	var buffer: PackedByteArray = info["buffer"]
	buffer.append_array(received[1])
	if buffer.size() > MAX_REQUEST_BYTES:
		print("[server] 单条请求过大，断开：%s" % peer.get_connected_host())
		_drop_client(peer)
		return

	var start := 0
	for i in range(buffer.size()):
		if buffer[i] != 10: # '\n'
			continue
		var line := buffer.slice(start, i).get_string_from_utf8()
		start = i + 1
		if line.strip_edges() != "":
			_handle_line(peer, line)
	info["buffer"] = buffer.slice(start)
	info["last_seen"] = Time.get_ticks_msec()


func _drop_client(peer: StreamPeerTCP) -> void:
	clients.erase(peer)
	peer.disconnect_from_host()


func _handle_line(peer: StreamPeerTCP, line: String) -> void:
	var data = JSON.parse_string(line)
	if data == null or !(data is Dictionary):
		_reply(peer, {"ok": false, "error": "无法解析的 JSON"})
		return
	var response := _dispatch(str(data.get("op", "")), data, peer.get_connected_host())
	response["id"] = data.get("id", 0)
	_reply(peer, response)
	if response.get("close", false):
		_drop_client(peer)


func _reply(peer: StreamPeerTCP, response: Dictionary) -> void:
	peer.put_data((JSON.stringify(response) + "\n").to_utf8_buffer())


func _dispatch(op: String, data: Dictionary, client_ip: String = "") -> Dictionary:
	match op:
		"ping":
			return {"ok": true, "time": Time.get_unix_time_from_system()}
		"register":
			return _op_register(data)
		"login":
			return _op_login(data, client_ip)
		"profile":
			return _op_profile(data)
		"upload":
			return _op_upload(data)
		"leaderboard":
			return _op_leaderboard(data)
	return {"ok": false, "error": "未知指令：%s" % op}


# ---------------------------------------------------------------- 账号


func _op_register(data: Dictionary) -> Dictionary:
	var name := str(data.get("name", "")).strip_edges()
	var password := str(data.get("password", ""))
	if name.length() < 1 or name.length() > MAX_NAME_LENGTH:
		return {"ok": false, "error": "用户名需要 1-%d 个字符" % MAX_NAME_LENGTH}
	if password.length() < MIN_PASSWORD_LENGTH:
		return {"ok": false, "error": "密码至少 %d 位" % MIN_PASSWORD_LENGTH}
	if accounts.has(name):
		return {"ok": false, "error": "用户名已存在"}

	var salt := _random_hex(16)
	accounts[name] = {
		"name": name,
		"salt": salt,
		"password_hash": _hash(salt, password),
		"hash_version": HASH_VERSION,
		"created_unix": Time.get_unix_time_from_system(),
		"account": _default_account(name),
	}
	_save_accounts()
	print("[server] 注册：%s" % name)
	return {"ok": true, "token": _issue_token(name), "account": accounts[name]["account"]}


func _op_login(data: Dictionary, client_ip: String = "") -> Dictionary:
	var now := Time.get_unix_time_from_system()
	if _is_login_blocked(client_ip, now):
		# 被限流：回一条错误并断开，避免继续尝试
		return {"ok": false, "error": "尝试次数过多，请 10 分钟后再试", "close": true}

	var name := str(data.get("name", "")).strip_edges()
	var password := str(data.get("password", ""))
	if !accounts.has(name) or !_verify_password(accounts[name], password):
		_register_login_failure(client_ip, now)
		return {"ok": false, "error": "用户名或密码错误"}

	_clear_login_failures(client_ip)

	# 旧存档是单轮哈希，登录成功后就地升级
	var entry: Dictionary = accounts[name]
	if int(entry.get("hash_version", 1)) < HASH_VERSION:
		var salt := _random_hex(16)
		entry["salt"] = salt
		entry["password_hash"] = _hash(salt, password)
		entry["hash_version"] = HASH_VERSION
		_save_accounts()
		print("[server] 已升级 %s 的密码哈希" % name)

	print("[server] 登录：%s" % name)
	return {"ok": true, "token": _issue_token(name), "account": entry["account"]}


func _op_profile(data: Dictionary) -> Dictionary:
	var name := _user_from_token(str(data.get("token", "")))
	if name == "":
		return {"ok": false, "error": "登录已失效，请重新登录"}
	return {"ok": true, "account": accounts[name]["account"]}


func _op_upload(data: Dictionary) -> Dictionary:
	var name := _user_from_token(str(data.get("token", "")))
	if name == "":
		return {"ok": false, "error": "登录已失效，请重新登录"}
	var account = data.get("account", null)
	if !(account is Dictionary):
		return {"ok": false, "error": "账号数据格式错误"}
	if str(account.get("id", "")) != name:
		return {"ok": false, "error": "账号数据不属于当前登录用户"}

	var sanitized := _sanitize_account(account, name)
	accounts[name]["account"] = sanitized
	_save_accounts()
	return {"ok": true, "total_pp": sanitized["total_pp"], "total_score": sanitized["total_score"]}


func _op_leaderboard(data: Dictionary) -> Dictionary:
	var limit := clampi(int(data.get("limit", 20)), 1, 100)
	var players: Array = []
	for name in accounts:
		var account: Dictionary = accounts[name]["account"]
		players.append({
			"name": name,
			"pp": float(account.get("total_pp", 0.0)),
			"score": int(account.get("total_score", 0)),
		})
	players.sort_custom(func(a, b): return a["pp"] > b["pp"])
	return {"ok": true, "players": players.slice(0, limit)}


## 只保留认识的字段。关键：pp / 分数 / 有效数全部按 correct/wrong 重算，
## 客户端上传的同名字段一律不用（以前这里直接信任客户端，10 秒就能刷到排行榜第一）。
func _sanitize_account(account: Dictionary, name: String) -> Dictionary:
	var stored: Dictionary = {}
	var created_unix := 0.0
	if accounts.has(name):
		var entry: Dictionary = accounts[name]
		stored = entry.get("account", {})
		created_unix = float(entry.get("created_unix", 0.0))

	var now := Time.get_unix_time_from_system()
	var stored_last_play := float(stored.get("last_play_unix", 0.0))

	var plays_in = account.get("plays", [])
	if !(plays_in is Array):
		plays_in = []

	var records: Array = []
	var newest_play_unix := stored_last_play
	for entry in plays_in:
		if !(entry is Dictionary):
			continue
		var play := _sanitize_play(entry, now)
		if play.is_empty():
			continue
		records.append(play)
		newest_play_unix = maxf(newest_play_unix, float(play["unix"]))

	# 只保留最近的若干场，避免存档被刷爆
	if records.size() > MAX_PLAYS:
		records = records.slice(records.size() - MAX_PLAYS)
		newest_play_unix = float(records[records.size() - 1]["unix"])

	var total_score := 0
	var pp_records: Array = []
	for play in records:
		total_score += int(play["score"])
		pp_records.append(PlayRecord.from_dict(play))

	var max_stamina := clampi(int(stored.get("max_stamina", account.get("max_stamina", 240))), 1, 999)
	return {
		"id": name,
		"is_formal": bool(account.get("is_formal", false)),
		"score": total_score,
		"total_score": total_score,
		"total_pp": PPSystem.total_pp(pp_records),
		"stamina": _compute_stamina(stored, account, records, max_stamina, now, created_unix),
		"max_stamina": max_stamina,
		"last_stamina_recovery_unix": now,
		"last_play_unix": maxf(stored_last_play, newest_play_unix),
		"bag": _sanitize_bag(account.get("bag", [])),
		"plays": records,
	}


func _sanitize_play(entry: Dictionary, now: float) -> Dictionary:
	var game := int(entry.get("game", -1))
	if !SCORE_RULES.has(game):
		return {}
	var correct := int(entry.get("correct", 0))
	var wrong := int(entry.get("wrong", 0))
	if correct < 0 or wrong < 0:
		return {}

	correct = mini(correct, int(MAX_CORRECT[game]))
	wrong = mini(wrong, int(MAX_WRONG[game]))
	if correct == 0 and wrong == 0:
		return {}

	var level := -1
	var total := correct + wrong
	if game == Global.GameType.ECP:
		level = clampi(int(entry.get("level", Word.Level.ADVANCED)), Word.Level.PRIMARY, Word.Level.ADVANCED)
		total = Global.ECP_PAIR_COUNT
		correct = mini(correct, total)

	var unix := clampf(float(entry.get("unix", now)), 0.0, now + 86400.0)
	var duration := clampf(float(entry.get("duration", 0.0)), 0.0, 3600.0)
	var rules: Dictionary = SCORE_RULES[game]
	var score := maxi(correct * int(rules["correct"]) + wrong * int(rules["wrong"]), 0)

	return {
		"game": game,
		"level": level,
		"mode": PlayRecord.MODE_ONLINE,
		"unix": unix,
		"duration": duration,
		"score": score,
		"pp": _play_pp(game, level, correct, wrong),
		"correct": correct,
		"wrong": wrong,
		"total": total,
		"effective": maxi(correct - wrong, 0),
		"words": _sanitize_words(entry.get("words", [])),
	}


func _play_pp(game: int, level: int, correct: int, wrong: int) -> float:
	match game:
		Global.GameType.ECP:
			return PPSystem.ecp_pp(level, correct, wrong)
		Global.GameType.QQNA:
			return PPSystem.qqna_pp(correct, wrong)
		Global.GameType.QSPE:
			return PPSystem.qspe_pp(correct, wrong)
	return 0.0


## 逐词明细保留，但截断长度、限制条数，避免被拿来撑存档
func _sanitize_words(value) -> Array:
	var result: Array = []
	if !(value is Array):
		return result
	var allowed := [PlayRecord.RESULT_CORRECT, PlayRecord.RESULT_WRONG, PlayRecord.RESULT_SKIPPED]
	for item in value:
		if result.size() >= 120:
			break
		if !(item is Dictionary):
			continue
		var outcome := str(item.get("result", PlayRecord.RESULT_SKIPPED))
		if !allowed.has(outcome):
			outcome = PlayRecord.RESULT_SKIPPED
		result.append({
			"en": str(item.get("en", "")).substr(0, 64),
			"zh": str(item.get("zh", "")).substr(0, 80),
			"result": outcome,
		})
	return result


## 体力由服务端自己维护：按上次记录恢复，再扣掉这次新出现的游玩
func _compute_stamina(stored: Dictionary, client: Dictionary, records: Array, max_stamina: int, now: float, created_unix: float) -> float:
	var base := float(stored.get("stamina", client.get("stamina", 20.0)))
	var last_recovery := float(stored.get("last_stamina_recovery_unix", now))
	if stored.is_empty():
		last_recovery = now
	var recovered := clampf(
		base + maxf(now - last_recovery, 0.0) * SingleAccount.STAMINA_RECOVERY_PER_SECOND,
		0.0, float(max_stamina)
	)

	# 只扣“比上次记录更新”的场次，重复上传同一批不会重复扣
	var threshold := maxf(float(stored.get("last_play_unix", 0.0)), created_unix)
	var cost := 0
	for play in records:
		if float(play["unix"]) > threshold:
			cost += int(Global.GAME_STAMINA_COST.get(int(play["game"]), 0))
	return clampf(recovered - float(cost), 0.0, float(max_stamina))


## 背包只认 res://assets/items/ 下真实存在的资源，数量收在 1-99
func _sanitize_bag(value) -> Array:
	var result: Array = []
	if !(value is Array):
		return result
	for item in value:
		if result.size() >= MAX_BAG_ITEMS:
			break
		if !(item is Dictionary):
			continue
		var path := str(item.get("path", ""))
		if !path.begins_with("res://assets/items/") or !ResourceLoader.exists(path):
			continue
		var count := clampi(int(item.get("count", 1)), 1, MAX_ITEM_COUNT)
		var merged := false
		for existing in result:
			if existing["path"] == path:
				existing["count"] = mini(int(existing["count"]) + count, MAX_ITEM_COUNT)
				merged = true
				break
		if !merged:
			result.append({"path": path, "count": count})
	return result


func _default_account(name: String) -> Dictionary:
	return {
		"id": name,
		"is_formal": false,
		"score": 0,
		"total_score": 0,
		"total_pp": 0.0,
		"stamina": 20.0,
		"max_stamina": 240,
		"last_stamina_recovery_unix": 0.0,
		"bag": [],
		"plays": [],
	}


func _issue_token(name: String) -> String:
	var token := _random_hex(32)
	tokens[token] = name
	return token


func _user_from_token(token: String) -> String:
	return str(tokens.get(token, ""))


# ---------------------------------------------------------------- 面板数据
# 这几个方法由 web_server 调用，返回给页面用的 JSON。


func get_summary() -> Dictionary:
	var play_count := 0
	var top: Array = []
	for name in accounts:
		var account: Dictionary = accounts[name]["account"]
		var plays: Array = account.get("plays", [])
		play_count += plays.size()
		top.append({
			"name": name,
			"pp": float(account.get("total_pp", 0.0)),
			"score": int(account.get("total_score", 0)),
		})
	top.sort_custom(func(a, b): return a["pp"] > b["pp"])
	return {
		"ok": true,
		"started_unix": started_unix,
		"uptime_sec": int(Time.get_unix_time_from_system() - started_unix),
		"tcp_port": port,
		"web_port": web_port,
		"account_count": accounts.size(),
		"play_count": play_count,
		"online_clients": clients.size(),
		"token_count": tokens.size(),
		"top": top.slice(0, 10),
	}


func get_accounts() -> Dictionary:
	var list: Array = []
	for name in accounts:
		var entry: Dictionary = accounts[name]
		var account: Dictionary = entry["account"]
		var plays: Array = account.get("plays", [])
		var last_unix := 0.0
		if !plays.is_empty():
			last_unix = float(plays[plays.size() - 1].get("unix", 0.0))
		list.append({
			"name": name,
			"pp": float(account.get("total_pp", 0.0)),
			"score": int(account.get("total_score", 0)),
			"plays": plays.size(),
			"last_unix": last_unix,
			"created_unix": float(entry.get("created_unix", 0.0)),
		})
	list.sort_custom(func(a, b): return a["pp"] > b["pp"])
	return {"ok": true, "accounts": list}


func get_account(name: String) -> Dictionary:
	if !accounts.has(name):
		return {"ok": false, "error": "没有这个账号"}
	var entry: Dictionary = accounts[name]
	var account: Dictionary = entry["account"]
	var plays: Array = account.get("plays", [])

	var recent: Array = []
	var first := maxi(0, plays.size() - WEB_RECENT_PLAYS)
	for i in range(plays.size() - 1, first - 1, -1):
		var play: Dictionary = plays[i]
		recent.append({
			"game": int(play.get("game", 0)),
			"level": int(play.get("level", -1)),
			"mode": str(play.get("mode", "")),
			"unix": float(play.get("unix", 0.0)),
			"duration": float(play.get("duration", 0.0)),
			"score": int(play.get("score", 0)),
			"pp": float(play.get("pp", 0.0)),
			"correct": int(play.get("correct", 0)),
			"wrong": int(play.get("wrong", 0)),
			"total": int(play.get("total", 0)),
		})

	return {
		"ok": true,
		"name": name,
		"pp": float(account.get("total_pp", 0.0)),
		"score": int(account.get("total_score", 0)),
		"created_unix": float(entry.get("created_unix", 0.0)),
		"total_plays": plays.size(),
		"plays": recent,
	}


# ---------------------------------------------------------------- 存储


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--port="):
			port = arg.trim_prefix("--port=").to_int()
		elif arg.begins_with("--data="):
			data_path = arg.trim_prefix("--data=")
		elif arg.begins_with("--web-port="):
			web_port = arg.trim_prefix("--web-port=").to_int()
		elif arg.begins_with("--web-host="):
			web_bind = arg.trim_prefix("--web-host=")
		elif arg.begins_with("--admin-password="):
			admin_password = arg.trim_prefix("--admin-password=")


func _load_accounts() -> void:
	if _load_from(data_path):
		return
	# 主文件坏了（写到一半断电之类）就从 .bak 恢复
	var backup := data_path + ".bak"
	if FileAccess.file_exists(backup):
		push_warning("[server] %s 解析失败，尝试从 %s 恢复" % [data_path, backup])
		if _load_from(backup):
			# 恢复成功后立刻写回主文件，避免下次又走回退；不覆盖这份好的 .bak
			_save_accounts(false)
			return
	accounts = {}


func _load_from(path: String) -> bool:
	if !FileAccess.file_exists(path):
		return false
	var text := FileAccess.get_file_as_string(path)
	var data = JSON.parse_string(text)
	if data == null or !(data is Dictionary):
		return false
	var loaded = data.get("accounts", null)
	if !(loaded is Dictionary):
		return false
	accounts = loaded
	return true


## 先写 .tmp，再依次改名成 .bak 和正式文件，避免写到一半把原存档截断。
## make_backup 为 false 时（从 .bak 恢复后写回）不覆盖备份，保住那份好数据。
func _save_accounts(make_backup: bool = true) -> void:
	var dir := data_path.get_base_dir()
	if dir != "":
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))

	var tmp_path := data_path + ".tmp"
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		push_error("[server] 无法写入 %s（错误码 %d）" % [tmp_path, FileAccess.get_open_error()])
		return
	file.store_string(JSON.stringify({
		"schema": 1,
		"saved_unix": Time.get_unix_time_from_system(),
		"accounts": accounts,
	}, "\t", false))
	file.flush()
	file.close()

	var main_abs := ProjectSettings.globalize_path(data_path)
	var tmp_abs := ProjectSettings.globalize_path(tmp_path)
	var backup_abs := ProjectSettings.globalize_path(data_path + ".bak")

	if make_backup:
		if FileAccess.file_exists(data_path + ".bak"):
			DirAccess.remove_absolute(backup_abs)
		if FileAccess.file_exists(data_path):
			if DirAccess.rename_absolute(main_abs, backup_abs) != OK:
				push_error("[server] 备份旧存档失败，本次写入可能没有生效")
				return
	elif FileAccess.file_exists(data_path):
		# 恢复后写回：直接替换掉坏文件，别把好的 .bak 冲掉
		DirAccess.remove_absolute(main_abs)

	if DirAccess.rename_absolute(tmp_abs, main_abs) != OK:
		push_error("[server] 写入 %s 失败" % data_path)


# ---------------------------------------------------------------- 工具


## 迭代哈希：SHA-256 跑 HASH_ROUNDS 轮，单轮彩虹表基本没戏
func _hash(salt: String, password: String) -> String:
	var digest := (salt + password).to_utf8_buffer()
	var context := HashingContext.new()
	for i in range(HASH_ROUNDS):
		context.start(HashingContext.HASH_SHA256)
		context.update(digest)
		digest = context.finish()
	return digest.hex_encode()


## 旧存档用的单轮哈希，只用来验证老记录
func _hash_legacy(salt: String, password: String) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update((salt + password).to_utf8_buffer())
	return context.finish().hex_encode()


func _verify_password(entry: Dictionary, password: String) -> bool:
	var salt := str(entry.get("salt", ""))
	var expected := str(entry.get("password_hash", ""))
	if int(entry.get("hash_version", 1)) >= HASH_VERSION:
		return _hash(salt, password) == expected
	return _hash_legacy(salt, password) == expected


# ---------------------------------------------------------------- 登录限流


func _is_login_blocked(ip: String, now: float) -> bool:
	if ip == "":
		return false
	var state = login_failures.get(ip, null)
	if state == null:
		return false
	return float(state.get("blocked_until", 0.0)) > now


func _register_login_failure(ip: String, now: float) -> void:
	if ip == "":
		return
	var state: Dictionary = login_failures.get(ip, {})
	if state.is_empty():
		state = {"count": 0, "first": now, "blocked_until": 0.0}
	# 窗口外的旧失败不计
	if now - float(state["first"]) > LOGIN_FAILURE_WINDOW_SEC:
		state = {"count": 0, "first": now, "blocked_until": 0.0}
	state["count"] = int(state["count"]) + 1
	if int(state["count"]) >= MAX_LOGIN_FAILURES:
		state["blocked_until"] = now + LOGIN_BLOCK_SEC
		print("[server] IP %s 登录失败过多，封禁 %d 秒" % [ip, LOGIN_BLOCK_SEC])
	login_failures[ip] = state
	_prune_login_failures(now)


func _clear_login_failures(ip: String) -> void:
	login_failures.erase(ip)


func _prune_login_failures(now: float) -> void:
	if login_failures.size() < 512:
		return
	for ip in login_failures.keys():
		var state: Dictionary = login_failures[ip]
		var until := float(state.get("blocked_until", 0.0))
		var expired := until > 0.0 and until <= now
		var stale := until == 0.0 and now - float(state["first"]) > LOGIN_FAILURE_WINDOW_SEC
		if expired or stale:
			login_failures.erase(ip)


func _random_hex(bytes: int) -> String:
	return Crypto.new().generate_random_bytes(bytes).hex_encode()

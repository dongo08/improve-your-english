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
## 用户名 -> {name, salt, password_hash, created_unix, account}
var accounts: Dictionary = {}
## token -> 用户名
var tokens: Dictionary = {}


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
	if status == StreamPeerTCP.STATUS_ERROR:
		_drop_client(peer)
		return
	if status != StreamPeerTCP.STATUS_CONNECTED:
		return
	var available := peer.get_available_bytes()
	if available <= 0:
		return
	var received := peer.get_partial_data(available)
	if received[0] != OK:
		_drop_client(peer)
		return

	var buffer: PackedByteArray = clients[peer]["buffer"]
	buffer.append_array(received[1])
	var start := 0
	for i in range(buffer.size()):
		if buffer[i] != 10: # '\n'
			continue
		var line := buffer.slice(start, i).get_string_from_utf8()
		start = i + 1
		if line.strip_edges() != "":
			_handle_line(peer, line)
	clients[peer]["buffer"] = buffer.slice(start)
	clients[peer]["last_seen"] = Time.get_ticks_msec()


func _drop_client(peer: StreamPeerTCP) -> void:
	clients.erase(peer)
	peer.disconnect_from_host()


func _handle_line(peer: StreamPeerTCP, line: String) -> void:
	var data = JSON.parse_string(line)
	if data == null or !(data is Dictionary):
		_reply(peer, {"ok": false, "error": "无法解析的 JSON"})
		return
	var response := _dispatch(str(data.get("op", "")), data)
	response["id"] = data.get("id", 0)
	_reply(peer, response)


func _reply(peer: StreamPeerTCP, response: Dictionary) -> void:
	peer.put_data((JSON.stringify(response) + "\n").to_utf8_buffer())


func _dispatch(op: String, data: Dictionary) -> Dictionary:
	match op:
		"ping":
			return {"ok": true, "time": Time.get_unix_time_from_system()}
		"register":
			return _op_register(data)
		"login":
			return _op_login(data)
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
		"created_unix": Time.get_unix_time_from_system(),
		"account": _default_account(name),
	}
	_save_accounts()
	print("[server] 注册：%s" % name)
	return {"ok": true, "token": _issue_token(name), "account": accounts[name]["account"]}


func _op_login(data: Dictionary) -> Dictionary:
	var name := str(data.get("name", "")).strip_edges()
	var password := str(data.get("password", ""))
	if !accounts.has(name):
		return {"ok": false, "error": "用户名或密码错误"}
	var entry: Dictionary = accounts[name]
	if _hash(str(entry["salt"]), password) != str(entry["password_hash"]):
		return {"ok": false, "error": "用户名或密码错误"}
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


## 只保留认识的字段，并用服务端的 pp 公式重算，避免客户端随便改数
func _sanitize_account(account: Dictionary, name: String) -> Dictionary:
	var plays: Array = account.get("plays", [])
	if !(plays is Array):
		plays = []
	var records: Array = []
	var total_score := 0
	for entry in plays:
		if !(entry is Dictionary):
			continue
		var record := PlayRecord.from_dict(entry)
		record.score = maxi(record.score, 0)
		record.pp = maxf(record.pp, 0.0)
		record.mode = PlayRecord.MODE_ONLINE
		total_score += record.score
		records.append(record)
	var play_dicts: Array = []
	for record in records:
		play_dicts.append(record.to_dict())

	var max_stamina := clampi(int(account.get("max_stamina", 240)), 1, 9999)
	return {
		"id": name,
		"is_formal": bool(account.get("is_formal", false)),
		"score": total_score,
		"total_score": total_score,
		"total_pp": PPSystem.total_pp(records),
		"stamina": clampf(float(account.get("stamina", 20.0)), 0.0, float(max_stamina)),
		"max_stamina": max_stamina,
		"last_stamina_recovery_unix": float(account.get("last_stamina_recovery_unix", 0.0)),
		"bag": account.get("bag", []),
		"plays": play_dicts,
	}


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
	if !FileAccess.file_exists(data_path):
		return
	var text := FileAccess.get_file_as_string(data_path)
	var data = JSON.parse_string(text)
	if data == null or !(data is Dictionary):
		push_error("[server] %s 解析失败" % data_path)
		return
	accounts = data.get("accounts", {})


func _save_accounts() -> void:
	var dir := data_path.get_base_dir()
	if dir != "":
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var file := FileAccess.open(data_path, FileAccess.WRITE)
	if file == null:
		push_error("[server] 无法写入 %s" % data_path)
		return
	file.store_string(JSON.stringify({
		"schema": 1,
		"saved_unix": Time.get_unix_time_from_system(),
		"accounts": accounts,
	}, "\t", false))
	file.close()


# ---------------------------------------------------------------- 工具


func _hash(salt: String, password: String) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update((salt + password).to_utf8_buffer())
	return context.finish().hex_encode()


func _random_hex(bytes: int) -> String:
	return Crypto.new().generate_random_bytes(bytes).hex_encode()

extends Node
## 联机层自测：一个进程当房主，另一个进程加入，验证分数能实时同步、断线能被发现。
## 用法（两个终端）：
##   godot --headless --path . res://tests/mp_test.tscn -- --host
##   godot --headless --path . res://tests/mp_test.tscn -- --join

const PORT := 7788
const GUEST_SCORE := 17
const HOST_SCORE := 42

var role := "host"


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--join":
			role = "join"
		elif arg == "--host":
			role = "host"
	if role == "host":
		await _run_host()
	else:
		await _run_join()


func _run_host() -> void:
	_log("房主启动，端口 %d" % PORT)
	if NetworkManager.host_game(PORT, "房主") != OK:
		_fail("创建房间失败：" + NetworkManager.last_error)
		return
	if !await _wait_until(func(): return NetworkManager.player_count() >= 2, 25.0):
		_fail("等不到客户端加入")
		return
	_log("客户端已加入：%s" % str(NetworkManager.players.keys()))
	var guest_id := 0
	for id in NetworkManager.players.keys():
		if id != 1:
			guest_id = id
	if guest_id == 0:
		_fail("找不到客户端 id")
		return

	NetworkManager.start_match(1) # QQNA
	if !await _wait_until(func(): return NetworkManager.in_match and NetworkManager.match_game_type == 1, 5.0):
		_fail("没能进入比赛")
		return
	_log("比赛开始，比赛类型=%d" % NetworkManager.match_game_type)

	NetworkManager.report_score(HOST_SCORE)
	if !await _wait_until(func(): return NetworkManager.player_score(guest_id) == GUEST_SCORE, 15.0):
		_fail("没收到客户端分数，当前=%d" % NetworkManager.player_score(guest_id))
		return
	_log("收到客户端分数 %d" % NetworkManager.player_score(guest_id))

	NetworkManager.report_finished(HOST_SCORE)
	if !await _wait_until(func(): return bool(NetworkManager.players[guest_id].get("finished", false)), 10.0):
		_fail("没收到客户端结束标记")
		return
	_log("客户端已结束")

	var ranking := NetworkManager.ranking()
	_log("排名：%s" % str(ranking))
	if ranking.size() != 2 or ranking[0][1] != "房主":
		_fail("排名不对：%s" % str(ranking))
		return

	_log("HOST PASS")
	await _sleep(2.5)
	NetworkManager.leave_game()
	await _sleep(0.5)
	get_tree().quit(0)


func _run_join() -> void:
	await _sleep(0.5)
	_log("客户端连接 127.0.0.1:%d" % PORT)
	if NetworkManager.join_game("127.0.0.1", PORT, "客户端") != OK:
		_fail("连接调用失败：" + NetworkManager.last_error)
		return
	if !await _wait_until(func(): return NetworkManager.is_online, 20.0):
		_fail("连不上房主：" + NetworkManager.last_error)
		return
	_log("已连上，玩家列表：%s" % str(NetworkManager.players.keys()))

	if !await _wait_until(func(): return NetworkManager.in_match, 15.0):
		_fail("没收到开始比赛")
		return
	_log("比赛开始，比赛类型=%d" % NetworkManager.match_game_type)

	NetworkManager.report_score(GUEST_SCORE)
	if !await _wait_until(func(): return NetworkManager.player_score(1) == HOST_SCORE, 15.0):
		_fail("没收到房主分数，当前=%d" % NetworkManager.player_score(1))
		return
	_log("收到房主分数 %d" % NetworkManager.player_score(1))

	NetworkManager.report_finished(GUEST_SCORE)
	if !await _wait_until(func(): return bool(NetworkManager.players[1].get("finished", false)), 10.0):
		_fail("没收到房主结束标记")
		return

	if !await _wait_until(func(): return !NetworkManager.is_online, 15.0):
		_fail("房主离开后没有断开")
		return
	_log("房主离开后已自动断开：%s" % NetworkManager.last_error)

	_log("CLIENT PASS")
	get_tree().quit(0)


# ---------------------------------------------------------------- 工具


func _wait_until(predicate: Callable, timeout: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return true
		await get_tree().process_frame
	return predicate.call()


func _sleep(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _log(message: String) -> void:
	print("[mp_test/%s] %s" % [role, message])


func _fail(message: String) -> void:
	push_error("[mp_test/%s] FAIL: %s" % [role, message])
	print("[mp_test/%s] FAIL: %s" % [role, message])
	get_tree().quit(1)

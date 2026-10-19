extends Node
## 联机流程测试：大厅 → 房主点开始 → 双方自动进入游戏场景 → 分数互相可见。
##   godot --headless --path . res://tests/flow_test.tscn -- --host
##   godot --headless --path . res://tests/flow_test.tscn -- --join

const PORT := 7789
const HOST_SCORE := 30
const GUEST_SCORE := 21

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
	_log("创建房间")
	if NetworkManager.host_game(PORT, "房主") != OK:
		_fail("创建房间失败：" + NetworkManager.last_error)
		return
	_add_lobby()

	if !await _wait_until(func(): return NetworkManager.player_count() >= 2, 25.0):
		_fail("等不到客户端")
		return
	var guest_id := 0
	for id in NetworkManager.players.keys():
		if id != 1:
			guest_id = id
	_log("客户端已加入，开始比赛")
	NetworkManager.start_match(1)

	if !await _wait_until(func(): return _in_match_scene(), 15.0):
		_fail("大厅没有切换到游戏场景，当前场景=%s" % _current_scene_path())
		return
	_log("已进入游戏场景：%s" % _current_scene_path())

	if !await _wait_until(func(): return NetworkManager.in_match, 5.0):
		_fail("游戏场景里 in_match 为 false")
		return

	await _sleep(5.0) # 等开局倒计时结束
	NetworkManager.report_score(HOST_SCORE)
	if !await _wait_until(func(): return NetworkManager.player_score(guest_id) == GUEST_SCORE, 15.0):
		_fail("没同步到客户端分数，当前=%d" % NetworkManager.player_score(guest_id))
		return
	_log("双方分数已同步：房主=%d 客户端=%d" % [NetworkManager.player_score(1), NetworkManager.player_score(guest_id)])
	if NetworkManager.players.size() != 2:
		_fail("结算前玩家数不对：%d" % NetworkManager.players.size())
		return

	await _sleep(2.5) # 留时间让客户端看到分数
	var answer_area: Node = get_tree().current_scene
	if answer_area == null or !answer_area.has_method("_on_timer_timeout"):
		_fail("当前场景不是 answer_area")
		return
	answer_area.get_node("Timer").timeout.emit()
	await _sleep(1.0)
	var end_window: Control = answer_area.get("end_window")
	if end_window == null or !end_window.visible:
		_fail("时间到之后结算窗口没打开")
		return
	var ranking_label: Label = answer_area.get("ranking_label")
	if ranking_label == null or ranking_label.text == "":
		_fail("结算界面的排名是空的")
		return
	_log("结算排名：%s" % ranking_label.text.replace("\n", " / "))
	if !ranking_label.text.contains("客户端"):
		_fail("结算排名里没有客户端")
		return
	if !NetworkManager.players[1].get("finished", false):
		_fail("房主没有标记为已结束")
		return

	var first_scene_id := get_tree().current_scene.get_instance_id()
	_log("房主直接开下一局")
	NetworkManager.start_match(1)
	if !await _wait_until(func(): return get_tree().current_scene != null and get_tree().current_scene.get_instance_id() != first_scene_id, 15.0):
		_fail("重新开始比赛后场景没有重开")
		return
	_log("已重开比赛场景：%s" % _current_scene_path())

	_log("HOST PASS")
	await _sleep(2.0)
	NetworkManager.leave_game()
	await _sleep(0.5)
	get_tree().quit(0)


func _run_join() -> void:
	await _sleep(0.5)
	_log("加入房间")
	if NetworkManager.join_game("127.0.0.1", PORT, "客户端") != OK:
		_fail("连接调用失败：" + NetworkManager.last_error)
		return
	_add_lobby()

	if !await _wait_until(func(): return NetworkManager.is_online, 20.0):
		_fail("连不上房主：" + NetworkManager.last_error)
		return
	if !await _wait_until(func(): return NetworkManager.in_match, 20.0):
		_fail("没收到开始比赛")
		return
	if !await _wait_until(func(): return _in_match_scene(), 15.0):
		_fail("大厅没有切换到游戏场景，当前场景=%s" % _current_scene_path())
		return
	_log("已进入游戏场景：%s" % _current_scene_path())

	await _sleep(5.0)
	NetworkManager.report_score(GUEST_SCORE)
	if !await _wait_until(func(): return NetworkManager.player_score(1) == HOST_SCORE, 15.0):
		_fail("没同步到房主分数，当前=%d" % NetworkManager.player_score(1))
		return
	_log("双方分数已同步：房主=%d 客户端=%d" % [NetworkManager.player_score(1), NetworkManager.player_score(guest_id())])
	# 等房主结算，确认结束标记能同步过来
	if !await _wait_until(func(): return bool(NetworkManager.players[1].get("finished", false)), 20.0):
		_fail("没收到房主的结束标记")
		return
	_log("收到房主结束标记，排名：%s" % str(NetworkManager.ranking()))

	var first_scene_id := get_tree().current_scene.get_instance_id()
	if !await _wait_until(func(): return get_tree().current_scene != null and get_tree().current_scene.get_instance_id() != first_scene_id, 20.0):
		_fail("房主重开比赛后，客户端没有跟着重开")
		return
	_log("已跟随房主重开比赛：%s" % _current_scene_path())

	_log("CLIENT PASS")
	await _sleep(1.0)
	get_tree().quit(0)


func guest_id() -> int:
	for id in NetworkManager.players.keys():
		if id != 1:
			return id
	return 0


func _add_lobby() -> void:
	var lobby: Node = load("res://scenes/multiplayer/lobby.tscn").instantiate()
	add_child(lobby)


func _in_match_scene() -> bool:
	return _current_scene_path().contains("answer_area")


func _current_scene_path() -> String:
	var current := get_tree().current_scene
	if current == null:
		return "<null>"
	return current.scene_file_path


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
	print("[flow/%s] %s" % [role, message])


func _fail(message: String) -> void:
	push_error("[flow/%s] FAIL: %s" % [role, message])
	print("[flow/%s] FAIL: %s" % [role, message])
	get_tree().quit(1)

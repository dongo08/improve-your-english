extends Node
## 在线模式联调测试：注册 → 登录 → 上传存档 → 服务端重算 pp → 重新登录验证持久化。
## 先启动服务端：
##   godot --headless --path . res://server/server_main.tscn -- --port=47653 --data=user://server/test_accounts.json
## 再跑：
##   godot --headless --path . res://tests/online_test.tscn -- --port=47653

const HOST := "127.0.0.1"
const NAME := "tester"
const PASSWORD := "1234"

var port := 47653
var failures := 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--port="):
			port = arg.trim_prefix("--port=").to_int()
	await _run()
	print("[online] %s" % ("ALL PASS" if failures == 0 else "FAILURES: %d" % failures))
	get_tree().quit(0 if failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[online] ok   %s" % message)
	else:
		failures += 1
		print("[online] FAIL %s" % message)


func _run() -> void:
	var bad_password := await Online.login(HOST, port, NAME, "wrong-password")
	_check(!bad_password.get("ok", false), "错误密码被拒绝（%s）" % bad_password.get("error", ""))

	var auth := await Online.register(HOST, port, NAME, PASSWORD)
	if !auth.get("ok", false) and str(auth.get("error", "")).contains("已存在"):
		auth = await Online.login(HOST, port, NAME, PASSWORD)
	if !auth.get("ok", false):
		_check(false, "注册/登录失败：%s" % auth.get("error", "未知错误"))
		return
	_check(true, "注册/登录成功：%s" % Online.user_name)

	var account := SingleAccount.from_dict(auth["account"])
	var record := PlayRecord.new()
	record.game_type = Global.GameType.ECP
	record.level = Word.Level.ADVANCED
	record.score = 30
	record.correct = 30
	record.wrong = 0
	record.total = 30
	record.effective = 30
	record.pp = PPSystem.ecp_pp(Word.Level.ADVANCED, 30, 0)
	record.mode = PlayRecord.MODE_ONLINE
	record.words = [{"en": "abandon", "zh": "vt.舍弃", "result": "correct"}]
	account.settle_play(record)

	var upload := await Online.push_account(account)
	_check(upload.get("ok", false), "上传存档（%s）" % upload.get("error", ""))
	_check(is_equal_approx(float(upload.get("total_pp", 0.0)), 300.0), "服务端重算 pp = 300（实际 %.2f）" % float(upload.get("total_pp", 0.0)))

	var profile := await Online.fetch_profile()
	_check(profile.get("ok", false), "拉取服务端存档")
	var remote := SingleAccount.from_dict(profile["account"])
	_check(remote.plays.size() == 1, "服务端保存了 %d 条游玩记录" % remote.plays.size())
	_check(is_equal_approx(remote.total_pp, 300.0), "服务端存档 pp 正确")
	_check(remote.plays.size() > 0 and remote.plays[0].mode == PlayRecord.MODE_ONLINE, "记录被标记为在线模式")

	# 伪造别的账号 id 应该被拒绝
	var spoof := SingleAccount.from_dict(account.to_dict())
	spoof.id = "someone_else"
	var spoof_response := await Online.push_account(spoof)
	_check(!spoof_response.get("ok", false), "不能上传不属于自己的账号数据")

	# 重新连接登录，确认数据已经落盘
	Online.close_connection()
	var again := await Online.login(HOST, port, NAME, PASSWORD)
	_check(again.get("ok", false), "重新登录")
	if again.get("ok", false):
		var again_account := SingleAccount.from_dict(again["account"])
		_check(again_account.plays.size() == 1, "重新登录后游玩记录还在")
		_check(is_equal_approx(again_account.total_pp, 300.0), "重新登录后 pp 还在")

	var leaderboard := await Online.fetch_leaderboard(10)
	_check(leaderboard.get("ok", false), "拉取排行榜")
	var players: Array = leaderboard.get("players", [])
	_check(!players.is_empty() and players[0]["name"] == NAME, "排行榜里有当前账号")

	Online.close_connection()

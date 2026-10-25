extends Node
## 结算流程自测：真实加载 answer_area，打完一局英汉配对，检查 pp、逐词记录和存档。
## godot --headless --path . res://tests/session_test.tscn

var failures := 0


func _ready() -> void:
	await _run()
	print("[session] %s" % ("ALL PASS" if failures == 0 else "FAILURES: %d" % failures))
	get_tree().quit(0 if failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[session] ok   %s" % message)
	else:
		failures += 1
		print("[session] FAIL %s" % message)


func _run() -> void:
	# 临时账号不放进 account_group，结算只影响内存，不会污染玩家存档
	AccountManager.current_account = SingleAccount.new()
	AccountManager.current_account.id = "__session_test__"
	AccountManager.current_account.stamina = 240.0

	Global.answer_area_type = Global.GameType.ECP
	Global.ecp_level = Word.Level.ADVANCED

	var answer: Control = load("res://scenes/games/answer_area.tscn").instantiate()
	add_child(answer)
	await get_tree().create_timer(4.6).timeout
	if answer.answering_area == null:
		_check(false, "游戏场景没有生成")
		return

	var ecp = answer.answering_area
	var chinese_by_word := {}
	for child in ecp.chinese_area.get_children():
		chinese_by_word[child.word] = child

	for button in ecp.buttons_english:
		var chinese = chinese_by_word.get(button.word)
		if chinese == null:
			continue
		button.button_pressed = true
		chinese.button_pressed = true

	answer._finish_session()
	await get_tree().process_frame

	var record: PlayRecord = answer.last_record
	_check(record != null, "生成了游玩记录")
	if record == null:
		return
	print("[session] 记录：%s" % str(record.to_dict()))
	_check(record.pp == 300.0, "高级全对 pp = 300（实际 %.2f）" % record.pp)
	_check(record.words.size() == 30, "逐词明细 30 条（实际 %d）" % record.words.size())
	_check(record.level == Word.Level.ADVANCED, "记录里保存了难度")
	_check(answer.end_window.visible, "结算窗口打开")
	_check(answer.summary_label.text.contains("300.00"), "结算界面显示 pp")
	_check(AccountManager.current_account.plays.size() == 1, "账号里多了 1 条游玩记录")
	_check(AccountManager.current_account.total_pp == 300.0, "账号总 pp = 300")
	_check(AccountManager.current_account.score == record.score, "账号积分增加了本局得分")

	answer.queue_free()
	await get_tree().process_frame

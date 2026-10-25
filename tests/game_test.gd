extends Node
## 玩法自测：英汉配对按等级抽词并统计，快问快答按词数结束并统计，快速拼写计分。
## godot --headless --path . res://tests/game_test.tscn

var failures := 0


func _ready() -> void:
	await _test_ecp()
	await _test_qqna()
	await _test_qspe()
	print("[game] %s" % ("ALL PASS" if failures == 0 else "FAILURES: %d" % failures))
	get_tree().quit(0 if failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[game] ok   %s" % message)
	else:
		failures += 1
		print("[game] FAIL %s" % message)


func _test_ecp() -> void:
	Global.ecp_level = Word.Level.PRIMARY
	var ecp: ECP = load("res://scenes/games/ECP/EnglishChinese_pairing.tscn").instantiate()
	add_child(ecp)
	await get_tree().process_frame

	var english_buttons: Array = ecp.buttons_english
	_check(english_buttons.size() == 30, "棋盘有 30 个英文按钮（实际 %d）" % english_buttons.size())

	var chinese_by_word := {}
	for child in ecp.chinese_area.get_children():
		chinese_by_word[child.word] = child

	var paired := 0
	for button in english_buttons:
		var chinese = chinese_by_word.get(button.word)
		if chinese == null:
			continue
		button.button_pressed = true
		if !chinese.is_inside_tree():
			continue
		chinese.button_pressed = true
		paired += 1

	var stats: Dictionary = ecp.get_stats()
	print("[game] 英汉配对：%s" % str(stats))
	_check(int(stats["correct"]) == paired, "配对成功数 = %d（实际 %d）" % [paired, stats["correct"]])
	_check(int(stats["wrong"]) == 0, "没有错误")
	_check(ecp.word_results().size() == 30, "逐词明细 30 条")
	_check(is_equal_approx(PPSystem.ecp_pp(Global.ecp_level, stats["correct"], stats["wrong"]), 50.0), "全对拿满 50pp")

	ecp.queue_free()
	await get_tree().process_frame


func _test_qqna() -> void:
	var qqna: QQNA = load("res://scenes/games/QQNA/quickly_qna.tscn").instantiate()
	add_child(qqna)
	await get_tree().process_frame

	var answered := 0
	while answered < 5:
		answered += 1
		var correct_button: CEOption = null
		for button in qqna.buttons:
			if button.word == qqna.current_word:
				correct_button = button
				break
		if correct_button == null:
			break
		var old_word := qqna.current_word
		correct_button.choosed.emit(correct_button)
		# 等答题动画结束、下一题生成
		var deadline := Time.get_ticks_msec() + 3000
		while qqna.current_word == old_word and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame

	var stats: Dictionary = qqna.get_stats()
	print("[game] 快问快答：%s" % str(stats))
	_check(int(stats["correct"]) == 5, "连续答对 5 题（实际 %d）" % stats["correct"])
	_check(int(stats["wrong"]) == 0, "没有答错")
	_check(qqna.word_results().size() == 5, "逐题明细 5 条")
	_check(is_equal_approx(PPSystem.qqna_pp(5, 0), snappedf(200.0 * pow(5.0 / 60.0, 2), 0.01)), "5 题按 60 题基准折算 pp")

	qqna.queue_free()
	await get_tree().process_frame


func _test_qspe() -> void:
	var qspe: QSPE = load("res://scenes/games/QSPE/quickly_spell.tscn").instantiate()
	add_child(qspe)
	await get_tree().process_frame

	var guard := 0
	while guard < 3:
		guard += 1
		if qspe.current_word == null:
			break
		var word: Word = qspe.current_word
		qspe._on_line_edit_text_changed(word.English)
		var deadline := Time.get_ticks_msec() + 3000
		while Time.get_ticks_msec() < deadline:
			if qspe.correct_count >= guard and qspe.current_word != null:
				break
			await get_tree().process_frame

	var stats: Dictionary = qspe.get_stats()
	print("[game] 快速拼写：%s" % str(stats))
	_check(int(stats["correct"]) == 3, "拼对 3 个（实际 %d）" % stats["correct"])
	_check(is_equal_approx(PPSystem.qspe_pp(3, 0), PPSystem.curve(150.0, 3, 20)), "快速拼写 pp 曲线正确")

	qspe.queue_free()
	await get_tree().process_frame

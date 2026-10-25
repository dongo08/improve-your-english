extends Node
## 系统自测：词库等级配比、pp 公式、存档 JSON 往返。
## godot --headless --path . res://tests/systems_test.tscn

var failures := 0


func _ready() -> void:
	_test_level_pools()
	_test_ecp_composition()
	_test_pp_formulas()
	_test_total_pp()
	_test_save_roundtrip()
	if failures == 0:
		print("[systems] ALL PASS")
	else:
		print("[systems] FAILURES: %d" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[systems] ok   %s" % message)
	else:
		failures += 1
		print("[systems] FAIL %s" % message)


func _test_level_pools() -> void:
	var primary := Global.words_by_level(Word.Level.PRIMARY)
	var intermediate := Global.words_by_level(Word.Level.INTERMEDIATE)
	var advanced := Global.words_by_level(Word.Level.ADVANCED)
	print("[systems] 词库：初级 %d，中级 %d，高级 %d" % [primary.size(), intermediate.size(), advanced.size()])
	_check(primary.size() > 500, "初级词足够")
	_check(intermediate.size() > 200, "中级词足够")
	_check(advanced.size() > 500, "高级词足够")
	var total := Global.all_words().size()
	_check(primary.size() + intermediate.size() + advanced.size() == total, "三个等级之和等于总词数")


func _test_ecp_composition() -> void:
	for level in [Word.Level.PRIMARY, Word.Level.INTERMEDIATE, Word.Level.ADVANCED]:
		var words := Global.pick_ecp_words(level, Global.ECP_PAIR_COUNT)
		var counts := {Word.Level.PRIMARY: 0, Word.Level.INTERMEDIATE: 0, Word.Level.ADVANCED: 0}
		var unique := {}
		for word in words:
			counts[word.level] += 1
			unique[word.English.to_lower()] = true
		print("[systems] %s 抽词：%s" % [Word.LEVEL_NAMES[level], str(counts)])
		_check(words.size() == Global.ECP_PAIR_COUNT, "%s 抽满 30 个" % Word.LEVEL_NAMES[level])
		_check(unique.size() == words.size(), "%s 没有重复词" % Word.LEVEL_NAMES[level])
		match level:
			Word.Level.PRIMARY:
				_check(counts[Word.Level.PRIMARY] == 30, "初级全是初级词")
			Word.Level.INTERMEDIATE:
				_check(counts[Word.Level.INTERMEDIATE] == 15 and counts[Word.Level.PRIMARY] == 15, "中级 15 中 + 15 初")
			Word.Level.ADVANCED:
				_check(counts[Word.Level.ADVANCED] == 15, "高级一半是高级词")
				_check(counts[Word.Level.PRIMARY] + counts[Word.Level.INTERMEDIATE] == 15, "高级剩下一半由初级/中级补")
				_check(abs(counts[Word.Level.PRIMARY] - counts[Word.Level.INTERMEDIATE]) <= 1, "高级补充部分初级中级平均")


func _test_pp_formulas() -> void:
	_check(is_equal_approx(PPSystem.ecp_pp(Word.Level.PRIMARY, 30, 0), 50.0), "初级满盘 50pp")
	_check(is_equal_approx(PPSystem.ecp_pp(Word.Level.INTERMEDIATE, 30, 0), 100.0), "中级满盘 100pp")
	_check(is_equal_approx(PPSystem.ecp_pp(Word.Level.ADVANCED, 30, 0), 300.0), "高级满盘 300pp")
	_check(is_equal_approx(PPSystem.ecp_pp(Word.Level.PRIMARY, 15, 0), 12.5), "初级 15 对 = 12.5pp")
	_check(is_equal_approx(PPSystem.ecp_pp(Word.Level.PRIMARY, 20, 5), 12.5), "错 5 个等于少 5 个词")
	_check(is_equal_approx(PPSystem.ecp_pp(Word.Level.PRIMARY, 5, 20), 0.0), "错太多不会扣成负数")
	_check(is_equal_approx(PPSystem.qqna_pp(60, 0), 200.0), "快问快答 60 题 = 200pp")
	_check(is_equal_approx(PPSystem.qqna_pp(30, 0), 50.0), "答对一半 = 1/4 基础值")
	_check(is_equal_approx(PPSystem.qqna_pp(70, 0), 272.22), "超过 60 题继续按平方增长")
	_check(is_equal_approx(PPSystem.qqna_pp(120, 0), 800.0), "120 题 = 4 倍基础值")
	_check(is_equal_approx(PPSystem.qqna_pp(65, 5), 200.0), "错 5 个等于少 5 题")
	_check(is_equal_approx(PPSystem.qspe_pp(20, 0), 150.0), "快速拼写拼对 20 个 = 150pp")
	_check(is_equal_approx(PPSystem.qspe_pp(10, 0), 37.5), "快速拼写拼对 10 个 = 37.5pp")


func _test_total_pp() -> void:
	var plays: Array = []
	for value in [100.0, 50.0, 10.0]:
		var record := PlayRecord.new()
		record.pp = value
		plays.append(record)
	var expected := 100.0 + 50.0 * 0.95 + 10.0 * 0.95 * 0.95
	_check(is_equal_approx(PPSystem.total_pp(plays), snappedf(expected, 0.01)), "总 pp 按 0.95 权重递减")

	var many: Array = []
	for i in range(120):
		var record := PlayRecord.new()
		record.pp = 1.0
		many.append(record)
	var capped := PPSystem.total_pp(many)
	var manual := 0.0
	for i in range(100):
		manual += pow(0.95, i)
	_check(is_equal_approx(capped, snappedf(manual, 0.01)), "只取最高 100 场")


func _test_save_roundtrip() -> void:
	var account := SingleAccount.new()
	account.id = "测试账号"
	account.score = 0
	account.total_score = 0
	var record := PlayRecord.new()
	record.game_type = Global.GameType.ECP
	record.level = Word.Level.ADVANCED
	record.score = 33
	record.correct = 26
	record.wrong = 2
	record.total = 30
	record.effective = 24
	record.pp = PPSystem.ecp_pp(Word.Level.ADVANCED, 26, 2)
	record.words = [{"en": "apple", "zh": "n.苹果", "result": "correct"}]
	account.settle_play(record)

	var data := account.to_dict()
	var text := JSON.stringify(data)
	var parsed = JSON.parse_string(text)
	var restored := SingleAccount.from_dict(parsed)

	_check(restored.id == "测试账号", "JSON 往返保留账号名")
	_check(restored.plays.size() == 1, "JSON 往返保留游玩记录")
	_check(restored.plays[0].words.size() == 1, "JSON 往返保留逐词明细")
	_check(restored.plays[0].level == Word.Level.ADVANCED, "JSON 往返保留难度")
	_check(is_equal_approx(restored.score, 33), "JSON 往返保留积分")
	_check(is_equal_approx(restored.total_pp, record.pp), "JSON 往返重算总 pp")

	var empty := SingleAccount.from_dict({})
	_check(empty.id == "" and empty.plays.is_empty(), "空字典能安全还原")

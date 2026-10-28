extends Node
## 服务端数据层回归测试（不联网，直接调用 account_server 的方法）。
## 覆盖审查报告里的 F1（伪造 pp）、F3（坏存档回滚）、F5（哈希升级）、F6（背包/体力）。
## godot --headless --path . res://tests/server_data_test.tscn

var failures := 0
var server: Node


func _ready() -> void:
	server = load("res://server/account_server.gd").new()
	var now := Time.get_unix_time_from_system()

	_seed_account(now)
	_test_forged_pp(now)
	_test_bad_records()
	_test_bag_and_stamina(now)
	_test_password_hash()
	_test_legacy_login_upgrade()
	_test_atomic_save(now)

	server.free()
	print("[server_data] %s" % ("ALL PASS" if failures == 0 else "FAILURES: %d" % failures))
	get_tree().quit(0 if failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[server_data] ok   %s" % message)
	else:
		failures += 1
		print("[server_data] FAIL %s" % message)


func _seed_account(now: float) -> void:
	server.accounts = {
		"tester": {
			"name": "tester",
			"salt": "00112233",
			"password_hash": "deadbeef",
			"hash_version": 2,
			"created_unix": now - 3600.0,
			"account": {
				"id": "tester",
				"stamina": 100.0,
				"max_stamina": 240,
				"last_stamina_recovery_unix": now - 3000.0,
				"last_play_unix": 0.0,
				"plays": [],
				"bag": [],
			},
		}
	}


## F1：客户端把 pp/score 改成 999999，服务端必须按 correct/wrong 重算
func _test_forged_pp(now: float) -> void:
	var forged := {
		"id": "tester",
		"plays": [{
			"game": 0,
			"level": 2,
			"mode": "local",
			"unix": now,
			"duration": 60.0,
			"score": 999999,
			"pp": 999999.0,
			"correct": 30,
			"wrong": 0,
			"total": 30,
			"effective": 30,
			"words": [],
		}],
		"bag": [],
		"stamina": 999999.0,
		"max_stamina": 999999,
	}
	var clean: Dictionary = server._sanitize_account(forged, "tester")
	_check(is_equal_approx(clean["total_pp"], 300.0), "伪造 pp 被重算成 300（实际 %.2f）" % clean["total_pp"])
	_check(is_equal_approx(clean["plays"][0]["pp"], 300.0), "单场 pp 由 correct/wrong 重算")
	_check(int(clean["plays"][0]["score"]) == 150, "单场得分按 30×5 重算（实际 %d）" % clean["plays"][0]["score"])
	_check(int(clean["total_score"]) == 150, "总积分不采用客户端数字")
	_check(int(clean["max_stamina"]) == 240, "max_stamina 不采用客户端的 999999")

	# 超量 correct 会被夹到 30，避免一把刷出天文数字
	var huge: Dictionary = server._sanitize_account({
		"id": "tester",
		"plays": [{"game": 0, "level": 2, "correct": 99999, "wrong": 0, "unix": now}],
	}, "tester")
	_check(int(huge["plays"][0]["correct"]) == 30, "correct 超量被夹到 30")
	_check(is_equal_approx(huge["total_pp"], 300.0), "超量 correct 也只能拿 300pp")


## 非法记录直接丢掉，不能让它们混进总分
func _test_bad_records() -> void:
	var bad: Dictionary = server._sanitize_account({
		"id": "tester",
		"plays": [
			{"game": 99, "correct": 30, "wrong": 0},
			{"game": 0, "correct": -5, "wrong": 0},
			{"game": 0, "correct": 0, "wrong": 0},
			{"correct": 10, "wrong": 0},
		],
	}, "tester")
	_check(bad["plays"].is_empty(), "未知玩法/负数/空记录全部被丢弃")
	_check(is_equal_approx(bad["total_pp"], 0.0), "没有有效记录时 pp 为 0")


## F6：背包只认真实存在的道具，体力由服务端自己算
func _test_bag_and_stamina(now: float) -> void:
	var account := {
		"id": "tester",
		"stamina": 999999.0,
		"max_stamina": 240,
		"bag": [
			{"path": "res://assets/items/name_change_card.tres", "count": 60},
			{"path": "res://assets/items/name_change_card.tres", "count": 60},
			{"path": "res://etc/passwd", "count": 1},
			{"path": "res://assets/items/does_not_exist.tres", "count": 1},
		],
		"plays": [{"game": 0, "level": 0, "correct": 1, "wrong": 0, "unix": now}],
	}
	var clean: Dictionary = server._sanitize_account(account, "tester")
	var bag: Array = clean["bag"]
	_check(bag.size() == 1, "背包只保留白名单内真实存在的道具（实际 %d 件）" % bag.size())
	_check(int(bag[0]["count"]) == 99, "道具数量夹在 99（实际 %d）" % bag[0]["count"])

	# 体力：100 + 3000/300 = 110，再扣一局配对 60 → 50
	_check(is_equal_approx(clean["stamina"], 50.0), "体力由服务端按时间恢复并扣费（实际 %.1f）" % clean["stamina"])


## F5：旧版单轮哈希还能验证，新版是迭代哈希
func _test_password_hash() -> void:
	var salt := "salt1234"
	var legacy := {"salt": salt, "password_hash": server._hash_legacy(salt, "pw1234")}
	_check(server._verify_password(legacy, "pw1234"), "旧版单轮哈希仍能登录")
	_check(!server._verify_password(legacy, "wrong"), "旧版哈希拒绝错误密码")

	var modern_hash: String = server._hash(salt, "pw1234")
	var modern := {"salt": salt, "password_hash": modern_hash, "hash_version": 2}
	_check(modern_hash != legacy["password_hash"], "新哈希与旧哈希不同")
	_check(server._verify_password(modern, "pw1234"), "新版迭代哈希能验证")
	_check(!server._verify_password(modern, "pw12345"), "新版哈希拒绝错误密码")


## F5：旧格式账号登录成功后会自动升级哈希，且不会把账号锁死
func _test_legacy_login_upgrade() -> void:
	var path := "user://server/test_login_%d.json" % randi_range(100000, 999999)
	server.data_path = path
	var salt := "legacy_salt"
	server.accounts = {
		"legacy": {
			"name": "legacy",
			"salt": salt,
			"password_hash": server._hash_legacy(salt, "oldpass"),
			"created_unix": Time.get_unix_time_from_system(),
			"account": {
				"id": "legacy", "plays": [], "stamina": 20.0, "max_stamina": 240,
				"last_stamina_recovery_unix": 0.0, "bag": [],
			},
		},
	}

	var response: Dictionary = server._op_login({"name": "legacy", "password": "oldpass"}, "10.0.0.1")
	_check(response.get("ok", false), "旧格式账号能正常登录")
	_check(int(server.accounts["legacy"].get("hash_version", 1)) == 2, "旧哈希登录后升级到新版")

	var again: Dictionary = server._op_login({"name": "legacy", "password": "oldpass"}, "10.0.0.1")
	_check(again.get("ok", false), "升级后原密码仍然有效")

	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))


## F3：主存档写坏时能从 .bak 恢复
func _test_atomic_save(now: float) -> void:
	var path := "user://server/test_atomic_%d.json" % randi_range(100000, 999999)
	server.data_path = path
	server.accounts = {"a": {"account": {"id": "a", "plays": []}}}
	server._save_accounts()

	server.accounts["b"] = {"account": {"id": "b", "plays": []}}
	server._save_accounts()
	_check(FileAccess.file_exists(path + ".bak"), "第二次保存会留一份 .bak")

	# 模拟写到一半断电：主文件变成半截 JSON
	var broken := FileAccess.open(path, FileAccess.WRITE)
	if broken != null:
		broken.store_string("{ this is not json")
		broken.close()

	server.accounts = {}
	server._load_accounts()
	# .bak 是上一次保存的版本，所以恢复到 "a"；最后一次写入的 "b" 丢一局可以接受
	_check(server.accounts.has("a"), "主存档损坏后从 .bak 恢复上一次的数据")
	_check(FileAccess.file_exists(path + ".bak"), "恢复写回时不会覆盖 .bak")

	for suffix in ["", ".bak", ".tmp"]:
		var absolute := ProjectSettings.globalize_path(path + suffix)
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(absolute)

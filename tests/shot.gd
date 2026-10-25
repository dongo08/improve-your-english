extends Node
## 界面截图工具（开发时检查排版用）。
##   godot --path . res://tests/shot.tscn -- --lobby
##   godot --path . res://tests/shot.tscn -- --choose
##   godot --path . res://tests/shot.tscn -- --settings
##   godot --path . res://tests/shot.tscn -- --login
##   godot --path . res://tests/shot.tscn -- --game / --ecp / --qspe
##   godot --path . res://tests/shot.tscn -- --result

var mode := "lobby"
var wait_seconds := 5.0
var scene: Node


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--wait="):
			wait_seconds = arg.trim_prefix("--wait=").to_float()
		elif arg.begins_with("--"):
			mode = arg.trim_prefix("--")

	match mode:
		"lobby":
			_fake_lobby()
		"ecp":
			_fake_match(0)
		"qspe":
			_fake_match(2)
		"choose", "settings", "login":
			pass
		_:
			_fake_match(1)

	var scene_path := "res://scenes/games/answer_area.tscn"
	if mode == "lobby":
		scene_path = "res://scenes/multiplayer/lobby.tscn"
	elif mode == "choose" or mode == "settings":
		scene_path = "res://scenes/choose_scene.tscn"
	elif mode == "login":
		scene_path = "res://scenes/online/login.tscn"

	scene = load(scene_path).instantiate()
	add_child(scene)
	await get_tree().process_frame

	if mode == "settings":
		var settings: GameSettings = scene.get("settings")
		settings.open(Global.GameType.ECP)
		await get_tree().create_timer(0.3).timeout
	elif mode == "result":
		await get_tree().create_timer(5.5).timeout
		await _show_fake_result()
	else:
		await get_tree().create_timer(wait_seconds).timeout

	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var out_dir := "res://tests/out"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var path := "%s/shot_%s.png" % [out_dir, mode]
	var err := image.save_png(path)
	print("[shot] saved %s err=%d" % [path, err])
	get_tree().quit(0 if err == OK else 1)


func _show_fake_result() -> void:
	var record := PlayRecord.new()
	record.game_type = Global.GameType.ECP
	record.level = Word.Level.ADVANCED
	record.score = 142
	record.correct = 27
	record.wrong = 3
	record.total = 30
	record.effective = 24
	record.pp = PPSystem.ecp_pp(Word.Level.ADVANCED, 27, 3)
	scene.set("last_record", record)

	var end_window: Control = scene.get("end_window")
	var words: ItemList = scene.get("last_words_list")
	words.add_item("abandon vt.舍弃；抛弃")
	words.add_item("absorb vt.吸收；吸引")
	words.add_item("accompany vt.陪伴；伴随")
	end_window.visible = true
	var title: Label = end_window.get_node("BoxContainer/Label")
	title.text = "时间到"
	(scene.get("score_label") as Control).visible = false
	(scene.get("time_label") as Control).visible = false
	scene.call("_refresh_summary")
	scene.call("_refresh_end_ranking")
	await get_tree().create_timer(0.3).timeout


func _fake_lobby() -> void:
	NetworkManager.players = {
		1: {"name": "小明", "score": 0, "finished": false},
		1002: {"name": "阿强", "score": 0, "finished": false},
	}
	NetworkManager.is_online = true
	NetworkManager.is_host = true
	NetworkManager.my_name = "小明"


func _fake_match(game_type: int) -> void:
	_fake_lobby()
	NetworkManager.in_match = true
	NetworkManager.match_game_type = game_type
	NetworkManager.match_level = Word.Level.ADVANCED
	NetworkManager.players = {
		1: {"name": "小明", "score": 26, "finished": false},
		1002: {"name": "阿强", "score": 31, "finished": false},
		1003: {"name": "Lily", "score": 12, "finished": true},
	}

extends Node
## 界面截图工具（只用于开发时检查排版）。用法：
##   godot --path . res://tests/shot.tscn -- --lobby
##   godot --path . res://tests/shot.tscn -- --game    (快问快答)
##   godot --path . res://tests/shot.tscn -- --ecp
##   godot --path . res://tests/shot.tscn -- --qspe
##   godot --path . res://tests/shot.tscn -- --result  (结算界面)
##   godot --path . res://tests/shot.tscn -- --choose

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
		"choose":
			pass
		_:
			_fake_match(1)

	var scene_path := "res://scenes/games/answer_area.tscn"
	if mode == "lobby":
		scene_path = "res://scenes/multiplayer/lobby.tscn"
	elif mode == "choose":
		scene_path = "res://scenes/choose_scene.tscn"

	scene = load(scene_path).instantiate()
	add_child(scene)

	if mode == "result":
		await get_tree().create_timer(5.5).timeout
		var words: ItemList = scene.get("last_words_list")
		for i in 6:
			words.add_item("word_%d  n.示例；" % i)
		var end_window: Control = scene.get("end_window")
		end_window.visible = true
		scene.call("_refresh_end_ranking")
		await get_tree().create_timer(0.3).timeout
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
	NetworkManager.players = {
		1: {"name": "小明", "score": 26, "finished": false},
		1002: {"name": "阿强", "score": 31, "finished": false},
		1003: {"name": "Lily", "score": 12, "finished": true},
	}

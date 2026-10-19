extends Control

@export var time_label:Label
@export var score_label:Label
@export var timer:Timer
@export var audio:AudioStreamPlayer
@export var end_window:PanelContainer
@export var black:ColorRect
@export var label2:Label
@export var camera:Camera2D
@export var last_words_list:ItemList
var pre_ecp=preload("res://scenes/games/ECP/EnglishChinese_pairing.tscn")
var pre_qqna=preload("res://scenes/games/QQNA/quickly_qna.tscn")
var pre_qspe=preload("res://scenes/games/QSPE/quickly_spell.tscn")
var answering_area:Node
var score:int=0:
	set(value):
		if value<0:
			value=0
		score=value
var start_time
var multiplayer_mode := false
var match_over := false
var scoreboard: MpScoreboard
var ranking_box: VBoxContainer
var ranking_label: Label
var note_label: Label
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	multiplayer_mode = NetworkManager.in_match
	if multiplayer_mode:
		Global.answer_area_type = NetworkManager.match_game_type
		timer.wait_time = NetworkManager.match_duration
	else:
		var cost = Global.GAME_STAMINA_COST.get(Global.answer_area_type, 5)
		if !(AccountManager.current_account.get_stamina()>cost):
			get_tree().change_scene_to_file("res://scenes/choose_scene.tscn")
			return

	if Global.answer_area_type == Global.GameType.ECP:
		answering_area = pre_ecp.instantiate() as ECP
		answering_area.add_score.connect(add_score)
		answering_area.camera_shake.connect(camera_shake)
		camera.add_sibling(answering_area)

	elif Global.answer_area_type == Global.GameType.QQNA:
		answering_area = pre_qqna.instantiate() as QQNA
		answering_area.add_score.connect(add_score)
		answering_area.camera_shake.connect(camera_shake)
		camera.add_sibling(answering_area)

	elif Global.answer_area_type == Global.GameType.QSPE:
		answering_area = pre_qspe.instantiate() as QSPE
		answering_area.add_score.connect(add_score)
		answering_area.camera_shake.connect(camera_shake)
		camera.add_sibling(answering_area)

	if multiplayer_mode:
		_add_scoreboard()
		_add_end_ranking()
		NetworkManager.network_error.connect(_on_network_error)
		NetworkManager.match_started.connect(_on_new_match)

	start_time = Time.get_unix_time_from_system()
	black.visible=true
	end_window.visible=false
	audio.volume_db=-36
	audio.play()
	var tween=create_tween()
	tween.set_parallel(true)
	tween.tween_property(black,"self_modulate",Color(1,1,1,0),4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_property(audio,"volume_db",-12,4)
	label2.text="3"
	await get_tree().create_timer(1).timeout
	label2.text="2"
	await get_tree().create_timer(1).timeout
	label2.text="1"
	await get_tree().create_timer(1).timeout
	label2.text="开始"
	await get_tree().create_timer(1).timeout
	if answering_area is QSPE:
		answering_area.line_edit.grab_focus()
	black.visible=false
	timer.start()

func add_score(added_score:int):
	score+=added_score
	if multiplayer_mode:
		NetworkManager.report_score(score)
func camera_shake():
	camera.camera_shake_short()
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	time_label.text="剩余时间："+String.num(timer.time_left,2)
	score_label.text="得分"+str(score)


func _on_timer_timeout() -> void:
	if match_over:
		return
	match_over=true
	AccountManager.current_account.settle_game_score(Global.answer_area_type,start_time,score)
	if multiplayer_mode:
		NetworkManager.report_finished(score)
	else:
		AccountManager.current_account.consume_stamina(Global.GAME_STAMINA_COST[Global.answer_area_type])
	end_window.visible=true
	AccountManager.save()
	if multiplayer_mode:
		_refresh_end_ranking()
	var last_words:WordGroup=answering_area.get_last_words()

	for i in last_words.word_group:
		print(i.English)

		var type:EnglishMeaning.Type=-1
		var a:String
		a=""
		for j in i.English_meaning_group:
			if j.type!=type:
				type=j.type
				match type:
					EnglishMeaning.Type.N:
						a+="n."
					EnglishMeaning.Type.V:
						a+="v."
					EnglishMeaning.Type.VI:
						a+="vi."
					EnglishMeaning.Type.VT:
						a+="vt."
					EnglishMeaning.Type.ADJ:
						a+="adj."
					EnglishMeaning.Type.ADV:
						a+="adv."
					EnglishMeaning.Type.PREP:
						a+="prep."
			a+=j.meaning+"；"



		last_words_list.add_item(i.English+" "+a)
	var tween=create_tween()
	tween.tween_property(audio,"volume_db",-50,6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_callback(func():audio.stop())


func _on_confirm_pressed() -> void:
	if multiplayer_mode:
		NetworkManager.end_match()
		if NetworkManager.is_online:
			get_tree().change_scene_to_file("res://scenes/multiplayer/lobby.tscn")
		else:
			get_tree().change_scene_to_file("res://scenes/choose_scene.tscn")
		return
	get_tree().change_scene_to_file("res://scenes/choose_scene.tscn")


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("esc"):
		if match_over:
			return
		timer.stop()
		timer.timeout.emit()


# ---------------------------------------------------------------- 联机界面


func _add_scoreboard() -> void:
	scoreboard = MpScoreboard.new()
	scoreboard.z_index = 10
	add_child(scoreboard)


func _add_end_ranking() -> void:
	var box_container: BoxContainer = end_window.get_node("BoxContainer")
	ranking_box = VBoxContainer.new()
	ranking_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ranking_box.add_theme_constant_override("separation", 2)

	var title := Label.new()
	title.text = "联机排名"
	title.add_theme_font_size_override("font_size", 22)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ranking_box.add_child(title)

	ranking_label = Label.new()
	ranking_label.add_theme_font_size_override("font_size", 24)
	ranking_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ranking_box.add_child(ranking_label)

	note_label = Label.new()
	note_label.add_theme_font_size_override("font_size", 18)
	note_label.add_theme_color_override("font_color", Color(1, 0.55, 0.55))
	note_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note_label.visible = false
	ranking_box.add_child(note_label)

	box_container.add_child(ranking_box)
	box_container.move_child(ranking_box, 1)
	NetworkManager.players_changed.connect(_refresh_end_ranking)


func _refresh_end_ranking() -> void:
	if !ranking_label:
		return
	if NetworkManager.players.is_empty():
		ranking_label.text = ""
		return
	var lines := PackedStringArray()
	var entries := NetworkManager.ranking()
	var my_id := NetworkManager.my_id()
	for i in entries.size():
		var entry: Array = entries[i]
		var me := "（我）" if entry[0] == my_id else ""
		var done := " ✓" if bool(entry[3]) else ""
		lines.append("%d. %s%s  %d%s" % [i + 1, str(entry[1]), me, int(entry[2]), done])
	ranking_label.text = "\n".join(lines)


func _on_network_error(message: String) -> void:
	if !multiplayer_mode or match_over:
		return
	if note_label:
		note_label.text = message
		note_label.visible = true
	timer.stop()
	_on_timer_timeout()


## 房主开了新一局（可能是我们还在结算界面时开的），直接重开这一场
func _on_new_match(_game_type: int, _duration: float) -> void:
	if !is_inside_tree():
		return
	if get_tree().current_scene == self:
		get_tree().reload_current_scene()

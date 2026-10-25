extends Control

@export var time_label: Label
@export var score_label: Label
@export var timer: Timer
@export var audio: AudioStreamPlayer
@export var end_window: PanelContainer
@export var black: ColorRect
@export var label2: Label
@export var camera: Camera2D
@export var last_words_list: ItemList

var pre_ecp = preload("res://scenes/games/ECP/EnglishChinese_pairing.tscn")
var pre_qqna = preload("res://scenes/games/QQNA/quickly_qna.tscn")
var pre_qspe = preload("res://scenes/games/QSPE/quickly_spell.tscn")

var answering_area: Node
var score: int = 0:
	set(value):
		if value < 0:
			value = 0
		score = value

var start_time := 0.0
var multiplayer_mode := false
var session_over := false
var last_record: PlayRecord

var scoreboard: MpScoreboard
var summary_box: VBoxContainer
var summary_label: Label
var ranking_box: VBoxContainer
var ranking_label: Label
var note_label: Label


func _ready() -> void:
	_style_end_window()
	multiplayer_mode = NetworkManager.in_match
	if multiplayer_mode:
		Global.answer_area_type = NetworkManager.match_game_type
		Global.ecp_level = NetworkManager.match_level
		timer.wait_time = NetworkManager.match_duration
	else:
		var cost = Global.GAME_STAMINA_COST.get(Global.answer_area_type, 5)
		if !(AccountManager.current_account.get_stamina() > cost):
			get_tree().change_scene_to_file("res://scenes/choose_scene.tscn")
			return

	_spawn_game()

	if multiplayer_mode:
		_add_scoreboard()
		NetworkManager.network_error.connect(_on_network_error)
		NetworkManager.match_started.connect(_on_new_match)

	_add_summary()
	if multiplayer_mode:
		_add_end_ranking()

	start_time = Time.get_unix_time_from_system()
	black.visible = true
	end_window.visible = false
	audio.volume_db = -36
	audio.play()
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(black, "self_modulate", Color(1, 1, 1, 0), 4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_property(audio, "volume_db", -12, 4)
	label2.text = "3"
	await get_tree().create_timer(1).timeout
	label2.text = "2"
	await get_tree().create_timer(1).timeout
	label2.text = "1"
	await get_tree().create_timer(1).timeout
	label2.text = "开始"
	await get_tree().create_timer(1).timeout
	if answering_area is QSPE:
		answering_area.line_edit.grab_focus()
	black.visible = false
	timer.start()


func _style_end_window() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.11, 1.0)
	end_window.add_theme_stylebox_override("panel", style)


func _spawn_game() -> void:
	if Global.answer_area_type == Global.GameType.ECP:
		answering_area = pre_ecp.instantiate() as ECP
	elif Global.answer_area_type == Global.GameType.QQNA:
		answering_area = pre_qqna.instantiate() as QQNA
	elif Global.answer_area_type == Global.GameType.QSPE:
		answering_area = pre_qspe.instantiate() as QSPE
	if answering_area == null:
		return
	answering_area.add_score.connect(add_score)
	answering_area.camera_shake.connect(camera_shake)
	camera.add_sibling(answering_area)


func add_score(added_score: int):
	score += added_score
	if multiplayer_mode:
		NetworkManager.report_score(score)


func camera_shake():
	camera.camera_shake_short()


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	time_label.text = "剩余时间：" + String.num(timer.time_left, 2)
	score_label.text = "得分" + str(score)


# ---------------------------------------------------------------- 结算


## 场景里 Timer 的 timeout 信号还连着这个方法，保留作为入口
func _on_timer_timeout() -> void:
	_finish_session()


func _finish_session() -> void:
	if session_over:
		return
	session_over = true
	timer.stop()

	var stats := _collect_stats()
	var gained_pp := _calculate_pp(stats)
	var record := PlayRecord.new()
	record.game_type = Global.answer_area_type
	record.level = Global.ecp_level if Global.answer_area_type == Global.GameType.ECP else -1
	record.mode = _play_mode()
	record.unix = start_time
	record.duration = Time.get_unix_time_from_system() - start_time
	record.score = score
	record.correct = int(stats.get("correct", 0))
	record.wrong = int(stats.get("wrong", 0))
	record.total = int(stats.get("total", 0))
	record.effective = maxi(record.correct - record.wrong, 0)
	record.pp = gained_pp
	record.words = _collect_word_results()
	last_record = record

	AccountManager.current_account.settle_play(record)
	if multiplayer_mode:
		NetworkManager.report_finished(score)
	else:
		AccountManager.current_account.consume_stamina(Global.GAME_STAMINA_COST[Global.answer_area_type])
	AccountManager.save()

	var title: Label = end_window.get_node("BoxContainer/Label")
	title.text = "时间到"
	score_label.visible = false
	time_label.visible = false
	end_window.visible = true
	_refresh_summary()

	if multiplayer_mode:
		_refresh_end_ranking()
	_fill_last_words()

	var tween = create_tween()
	tween.tween_property(audio, "volume_db", -50, 6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_callback(func(): audio.stop())


func _play_mode() -> String:
	if multiplayer_mode:
		return PlayRecord.MODE_MULTIPLAYER
	if AccountManager.is_online:
		return PlayRecord.MODE_ONLINE
	return PlayRecord.MODE_LOCAL


func _collect_stats() -> Dictionary:
	if answering_area != null and answering_area.has_method("get_stats"):
		return answering_area.get_stats()
	return {"correct": 0, "wrong": 0, "total": 0, "effective": 0}


func _collect_word_results() -> Array[Dictionary]:
	if answering_area != null and answering_area.has_method("word_results"):
		return answering_area.word_results()
	return [] as Array[Dictionary]


func _calculate_pp(stats: Dictionary) -> float:
	var correct := int(stats.get("correct", 0))
	var wrong := int(stats.get("wrong", 0))
	match Global.answer_area_type:
		Global.GameType.ECP:
			return PPSystem.ecp_pp(Global.ecp_level, correct, wrong)
		Global.GameType.QQNA:
			return PPSystem.qqna_pp(correct, wrong)
		Global.GameType.QSPE:
			return PPSystem.qspe_pp(correct, wrong)
	return 0.0


func _fill_last_words() -> void:
	var last_words: WordGroup = answering_area.get_last_words()
	for word in last_words.word_group:
		last_words_list.add_item(word.English + " " + word.meanings_text())


func _add_summary() -> void:
	var box_container: BoxContainer = end_window.get_node("BoxContainer")
	summary_box = VBoxContainer.new()
	summary_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	summary_label = Label.new()
	summary_label.add_theme_font_size_override("font_size", 24)
	summary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	summary_box.add_child(summary_label)
	box_container.add_child(summary_box)
	box_container.move_child(summary_box, 1)


func _refresh_summary() -> void:
	if summary_label == null or last_record == null:
		return
	var level_text := ""
	if last_record.level >= 0:
		level_text = "（%s）" % Word.LEVEL_NAMES.get(last_record.level, "")
	# 结算里显示的是 pp 的换算基准：配对 30 对，快问快答 60 题，拼写 20 个
	var denominator := last_record.total
	match last_record.game_type:
		Global.GameType.ECP:
			denominator = PPSystem.ECP_TOTAL_PAIRS
		Global.GameType.QQNA:
			denominator = PPSystem.QQNA_REFERENCE
		Global.GameType.QSPE:
			denominator = PPSystem.QSPE_REFERENCE
	summary_label.text = "%s%s｜得分 %d｜pp +%.2f\n正确 %d｜错误 %d｜有效 %d / %d" % [
		last_record.game_name(), level_text, last_record.score, last_record.pp,
		last_record.correct, last_record.wrong, last_record.effective, denominator,
	]


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
		if session_over:
			return
		_finish_session()


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
	var target_index := 1
	if summary_box != null:
		target_index = summary_box.get_index() + 1
	box_container.move_child(ranking_box, target_index)
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
	if !multiplayer_mode or session_over:
		return
	if note_label:
		note_label.text = message
		note_label.visible = true
	_finish_session()


## 房主开了新一局（可能是我们还在结算界面时开的），直接重开这一场
func _on_new_match(_game_type: int, _duration: float) -> void:
	if !is_inside_tree():
		return
	if get_tree().current_scene == self:
		get_tree().reload_current_scene()

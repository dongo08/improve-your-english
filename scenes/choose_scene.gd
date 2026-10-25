extends Control

@export var score_text: Label
@export var group_text: Label
@export var stamina_text: Label
@export var ranking_list: ItemList
@export var ranking_button: Button
@export var ECP_score: Label
@export var ECP_date: Label
@export var ECP_played: Label
@export var ECP_button: Button
@export var QQNA_score: Label
@export var QQNA_date: Label
@export var QQNA_played: Label
@export var QQNA_button: Button
@export var QSPE_score: Label
@export var QSPE_date: Label
@export var QSPE_played: Label
@export var QSPE_button: Button
@export var config_button: Button
@export var config_area: PanelContainer
@export var re_config_button: Button
@export var bag_and_shop: BagUI
@export var camera: Camera2D

var tween: Tween
var settings: GameSettings


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	config_area.visible = false
	ranking_list.visible = false
	bag_and_shop.shopping.connect(shopping)
	AccountManager.account_changed.connect(refresh)

	settings = preload("res://scenes/menu/game_settings.tscn").instantiate()
	settings.started.connect(_on_settings_started)
	add_child(settings)

	refresh()


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func refresh():
	score_text.text = "积分：%d\npp：%.1f" % [AccountManager.current_account.score, AccountManager.current_account.total_pp]
	var online_text := "（在线）" if AccountManager.is_online else ""
	group_text.text = "组名：" + AccountManager.current_account.id + online_text
	_refresh_game_state()
	_refresh_ranking()


func _refresh_ranking() -> void:
	ranking_list.clear()
	var accounts := AccountManager.account_group.account_list.duplicate()
	accounts.sort_custom(func(a, b): return a.total_pp > b.total_pp)
	for account in accounts:
		if AccountManager.current_account.is_formal != account.is_formal:
			continue
		ranking_list.add_item("%s  %.0fpp" % [account.id, account.total_pp])


func _refresh_game_state():
	_refresh_stamina_gate()
	_refresh_latest(Global.GameType.ECP, ECP_score, ECP_date)
	_refresh_latest(Global.GameType.QQNA, QQNA_score, QQNA_date)
	_refresh_latest(Global.GameType.QSPE, QSPE_score, QSPE_date)


func _refresh_latest(game_type: int, score_label: Label, date_label: Label) -> void:
	var play: PlayRecord = AccountManager.current_account.get_latest_play(game_type)
	if play == null:
		score_label.text = "最近没有游玩"
		date_label.text = ""
		return
	score_label.text = "最近得分：%d（+%.1fpp）" % [play.score, play.pp]
	date_label.text = "最近游玩：" + Time.get_datetime_string_from_unix_time(int(play.unix), true)


func _refresh_stamina_gate():
	var stamina = AccountManager.current_account.get_stamina()
	var max_sta = AccountManager.current_account.max_stamina
	var can_play = stamina >= Global.GAME_STAMINA_COST[Global.GameType.ECP]
	ECP_button.disabled = !can_play
	ECP_played.visible = !can_play

	can_play = stamina >= Global.GAME_STAMINA_COST[Global.GameType.QQNA]
	QQNA_button.disabled = !can_play
	QQNA_played.visible = !can_play

	can_play = stamina >= Global.GAME_STAMINA_COST[Global.GameType.QSPE]
	QSPE_button.disabled = !can_play
	QSPE_played.visible = !can_play

	stamina_text.text = "体力：" + str(stamina) + "/" + str(max_sta)


func _on_button_pressed() -> void:
	settings.open(Global.GameType.ECP)


func _on_qqna_pressed() -> void:
	_start_game(Global.GameType.QQNA)


func _on_settings_started(game_type: int) -> void:
	_start_game(game_type)


func _on_qspe_pressed() -> void:
	_start_game(Global.GameType.QSPE)


func _start_game(game_type: int) -> void:
	Global.answer_area_type = game_type
	get_tree().change_scene_to_file("res://scenes/games/answer_area.tscn")


func _on_button_2_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/start.tscn")


func _on_ranking_button_pressed() -> void:
	ranking_list.visible = !ranking_list.visible
	if ranking_list.visible and AccountManager.is_online:
		await _refresh_online_ranking()


func _refresh_online_ranking() -> void:
	var response: Dictionary = await Online.fetch_leaderboard(20)
	if !is_inside_tree() or !response.get("ok", false):
		return
	ranking_list.clear()
	for player in response.get("players", []):
		ranking_list.add_item("%s  %.0fpp" % [str(player.get("name", "")), float(player.get("pp", 0.0))])


func _on_config_button_pressed() -> void:
	config_area.visible = !config_area.visible


func shopping(enter: bool):
	if tween and tween.is_running():
		tween.kill()
	tween = create_tween()
	if enter:
		tween.tween_property(camera, "position:x", 1152 + 1152 / 2, 1).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	else:
		tween.tween_property(camera, "position:x", 1152 / 2, 1).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


func _on_online_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/multiplayer/lobby.tscn")


func _on_check_timer_timeout() -> void:
	_refresh_stamina_gate()


func _on_debugbutton_pressed() -> void:
	AccountManager.current_account.add_stamina(10)
	AccountManager.save()

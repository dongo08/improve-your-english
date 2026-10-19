extends Control
@export var score_text:Label
@export var group_text:Label
@export var stamina_text:Label
@export var ranking_list:ItemList
@export var ranking_button:Button
@export var ECP_score:Label
@export var ECP_date:Label
@export var ECP_played:Label
@export var ECP_button:Button
@export var QQNA_score:Label
@export var QQNA_date:Label
@export var QQNA_played:Label
@export var QQNA_button:Button
@export var QSPE_score:Label
@export var QSPE_date:Label
@export var QSPE_played:Label
@export var QSPE_button:Button
@export var config_button:Button
@export var config_area:PanelContainer
@export var re_config_button:Button
@export var bag_and_shop:BagUI
@export var camera:Camera2D
var tween:Tween
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	AccountManager.sort_account()
	config_area.visible=false
	ranking_list.visible=false
	bag_and_shop.shopping.connect(shopping)
	AccountManager.account_changed.connect(refresh)
	refresh()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func refresh():
	
	score_text.text = "积分：" + str(AccountManager.current_account.score)
	group_text.text = "组名：" + AccountManager.current_account.id
	_refresh_game_state()
	ranking_list.clear()
	for i in AccountManager.account_group.account_list:
		if AccountManager.current_account.is_formal:
			if i.is_formal:
				ranking_list.add_item(i.id + "  " + str(i.score))
		else:
			if !i.is_formal:
				ranking_list.add_item(i.id + "  " + str(i.score))

func _refresh_game_state():
	_refresh_stamina_gate()
	var ECP_history = AccountManager.current_account.get_latest_game_history(Global.GameType.ECP)
	if ECP_history:
		ECP_score.text = "最近得分：" + str(ECP_history.score)
		ECP_date.text = "最近游玩：" + Time.get_datetime_string_from_unix_time(ECP_history.playing_unix, true)
	else:
		ECP_score.text = "最近没有游玩"
		ECP_date.text = ""
	var QQNA_history = AccountManager.current_account.get_latest_game_history(Global.GameType.QQNA)
	if QQNA_history:
		QQNA_score.text = "最近得分：" + str(QQNA_history.score)
		QQNA_date.text = "最近游玩：" + Time.get_datetime_string_from_unix_time(QQNA_history.playing_unix, true)
	else:
		QQNA_score.text = "最近没有游玩"
		QQNA_date.text = ""
	var QSPE_history = AccountManager.current_account.get_latest_game_history(Global.GameType.QSPE)
	if QSPE_history:
		QSPE_score.text = "最近得分：" + str(QSPE_history.score)
		QSPE_date.text = "最近游玩：" + Time.get_datetime_string_from_unix_time(QSPE_history.playing_unix, true)
	else:
		QSPE_score.text = "最近没有游玩"
		QSPE_date.text = ""

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
	
	stamina_text.text="体力：" + str(stamina) + "/" + str(max_sta)
	

func _on_button_pressed() -> void:
	Global.answer_area_type=Global.GameType.ECP
	get_tree().change_scene_to_file("res://scenes/games/answer_area.tscn")

func _on_qqna_pressed() -> void:
	Global.answer_area_type=Global.GameType.QQNA
	get_tree().change_scene_to_file("res://scenes/games/answer_area.tscn")

func _on_button_2_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/start.tscn")


func _on_ranking_button_pressed() -> void:
	ranking_list.visible=!ranking_list.visible


func _on_config_button_pressed() -> void:
	config_area.visible=!config_area.visible
func shopping(enter:bool):
	if tween and tween.is_running():
		tween.kill()
	tween=create_tween()
	if enter:
		tween.tween_property(camera,"position:x",1152+1152/2,1).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	else:
		tween.tween_property(camera,"position:x",1152/2,1).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


func _on_qspe_pressed() -> void:
	Global.answer_area_type=Global.GameType.QSPE
	get_tree().change_scene_to_file("res://scenes/games/answer_area.tscn")


func _on_online_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/multiplayer/lobby.tscn")


func _on_check_timer_timeout() -> void:
	_refresh_stamina_gate()


func _on_debugbutton_pressed() -> void:
	AccountManager.current_account.add_stamina(10)
	AccountManager.save()

extends Resource
class_name SingleAccount

const STAMINA_RECOVERY_PER_SECOND: float = 1.0 / 300

@export var id: String:
	set(a):
		if a != id:
			id = a
			emit_changed()
@export var score: int:
	set(a):
		if a != score:
			score = a
			emit_changed()
@export var playing_history_list: Array[PlayingHistory]

@export var is_formal: bool = false
@export var bag: Array[Item]:
	set(a):
		if a != bag:
			bag = a
			emit_changed()

@export var total_score: int
@export var total_pp: int
@export var score_history_list: Array[ScoreHistory]

@export var max_stamina: int = 240
@export var stamina: float = 20.0
@export var last_stamina_recovery_unix: float = 0.0


func _recover_stamina():
	var now = Time.get_unix_time_from_system()
	if last_stamina_recovery_unix == 0.0:
		last_stamina_recovery_unix = now
		return
	var elapsed = now - last_stamina_recovery_unix
	if elapsed > 0:
		stamina = minf(float(max_stamina), stamina + elapsed * STAMINA_RECOVERY_PER_SECOND)
	last_stamina_recovery_unix = now


func get_stamina() -> int:
	_recover_stamina()
	return int(stamina)


func has_enough_stamina(cost: int) -> bool:
	return get_stamina() >= cost


func consume_stamina(cost: int) -> bool:
	_recover_stamina()
	if stamina < cost:
		return false
	stamina -= cost
	emit_changed()
	return true


func add_stamina(amount: int):
	_recover_stamina()
	stamina = minf(float(max_stamina), stamina + amount)
	emit_changed()

func settle_game_score(type:Global.GameType,unix:float=Time.get_unix_time_from_system(),score1:float=0,pp:float=0):
	score+=score1
	total_score+=score1
	
	if score_history_list.is_empty():
		var score_history=ScoreHistory.new()
		score_history_list.append(score_history)
	var date:Dictionary=Time.get_datetime_dict_from_system()
	var score_history:ScoreHistory=score_history_list.back()
	if score_history_list.back().is_new_day(date):
		score_history=ScoreHistory.new()
		score_history.date=date
		score_history_list.append(score_history)
	score_history.total_score=total_score
	score_history.score=score
	score_history.pp=total_pp
	
	var playing_history:=PlayingHistory.new()
	playing_history.type=type
	playing_history.score=score1
	playing_history.pp=pp
	playing_history.playing_unix=unix
	playing_history_list.append(playing_history)
	
func get_latest_game_history(type:Global.GameType)->PlayingHistory:
	for i in range(playing_history_list.size()-1,-1,-1):
		if playing_history_list[i].type==type:
			return playing_history_list[i]
	return null

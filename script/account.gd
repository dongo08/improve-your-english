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

@export var is_formal: bool = false
@export var bag: Array[Item]:
	set(a):
		if a != bag:
			bag = a
			emit_changed()

@export var total_score: int
## 由 plays 计算出来的实力值
@export var total_pp: float

@export var max_stamina: int = 240
@export var stamina: float = 20.0
@export var last_stamina_recovery_unix: float = 0.0

## 每一次游玩的详细记录（JSON 里持久化）
var plays: Array[PlayRecord] = []

## 旧版 .tres 存档字段，只在迁移时读取，新存档不再写入
@export var playing_history_list: Array[PlayingHistory]
@export var score_history_list: Array[ScoreHistory]


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


## 结算一场游戏：写入详细记录、累加积分、重算总 pp
func settle_play(record: PlayRecord) -> void:
	plays.append(record)
	score += record.score
	total_score += record.score
	total_pp = PPSystem.total_pp(plays)
	emit_changed()


func get_latest_play(type: int) -> PlayRecord:
	for i in range(plays.size() - 1, -1, -1):
		if plays[i].game_type == type:
			return plays[i]
	return null


func get_best_play(type: int) -> PlayRecord:
	var best: PlayRecord = null
	for play in plays:
		if play.game_type != type:
			continue
		if best == null or play.pp > best.pp:
			best = play
	return best


func find_bag_item(item: Item) -> int:
	for i in range(bag.size()):
		if bag[i].resource_path != "" and bag[i].resource_path == item.resource_path:
			return i
	return -1


# ---------------------------------------------------------------- JSON


func to_dict() -> Dictionary:
	var play_dicts: Array = []
	for play in plays:
		play_dicts.append(play.to_dict())
	var bag_dicts: Array = []
	for item in bag:
		bag_dicts.append({"path": item.resource_path, "count": item.count})
	return {
		"id": id,
		"is_formal": is_formal,
		"score": score,
		"total_score": total_score,
		"total_pp": total_pp,
		"stamina": stamina,
		"max_stamina": max_stamina,
		"last_stamina_recovery_unix": last_stamina_recovery_unix,
		"bag": bag_dicts,
		"plays": play_dicts,
	}


static func from_dict(data: Dictionary) -> SingleAccount:
	var account := SingleAccount.new()
	account.id = str(data.get("id", ""))
	account.is_formal = bool(data.get("is_formal", false))
	account.score = int(data.get("score", 0))
	account.total_score = int(data.get("total_score", 0))
	account.stamina = float(data.get("stamina", 20.0))
	account.max_stamina = int(data.get("max_stamina", 240))
	account.last_stamina_recovery_unix = float(data.get("last_stamina_recovery_unix", 0.0))

	for entry in data.get("bag", []):
		var path := str(entry.get("path", ""))
		if path == "" or !ResourceLoader.exists(path):
			continue
		var item: Item = load(path).duplicate()
		item.count = int(entry.get("count", 1))
		account.bag.append(item)

	for entry in data.get("plays", []):
		account.plays.append(PlayRecord.from_dict(entry))

	account.total_pp = PPSystem.total_pp(account.plays)
	return account

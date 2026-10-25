extends RefCounted
class_name PlayRecord

## 一次游玩的完整记录，直接对应玩家存档里 plays 数组的一项。

const MODE_LOCAL := "local"
const MODE_ONLINE := "online"
const MODE_MULTIPLAYER := "multiplayer"

const RESULT_CORRECT := "correct"
const RESULT_WRONG := "wrong"
const RESULT_SKIPPED := "skipped"

var game_type: int = 0
## 英汉配对的难度（Word.Level），其它模式是 -1
var level: int = -1
var mode: String = MODE_LOCAL
var unix: float = 0.0
var duration: float = 0.0
var score: int = 0
var pp: float = 0.0
var correct: int = 0
var wrong: int = 0
var total: int = 0
var effective: int = 0
## [{"en": "apple", "zh": "苹果", "result": "correct"}, ...]
var words: Array[Dictionary] = []


func to_dict() -> Dictionary:
	return {
		"game": game_type,
		"level": level,
		"mode": mode,
		"unix": unix,
		"duration": duration,
		"score": score,
		"pp": pp,
		"correct": correct,
		"wrong": wrong,
		"total": total,
		"effective": effective,
		"words": words,
	}


static func from_dict(data: Dictionary) -> PlayRecord:
	var record := PlayRecord.new()
	record.game_type = int(data.get("game", 0))
	record.level = int(data.get("level", -1))
	record.mode = str(data.get("mode", MODE_LOCAL))
	record.unix = float(data.get("unix", 0.0))
	record.duration = float(data.get("duration", 0.0))
	record.score = int(data.get("score", 0))
	record.pp = float(data.get("pp", 0.0))
	record.correct = int(data.get("correct", 0))
	record.wrong = int(data.get("wrong", 0))
	record.total = int(data.get("total", 0))
	record.effective = int(data.get("effective", 0))
	record.words.assign(data.get("words", []))
	return record


## 旧版存档（PlayingHistory）转过来，只保留时间、类型和分数
static func from_history(history: PlayingHistory) -> PlayRecord:
	var record := PlayRecord.new()
	record.game_type = history.type
	record.unix = history.playing_unix
	record.score = int(history.score)
	record.pp = history.pp
	record.mode = MODE_LOCAL
	return record


func game_name() -> String:
	match game_type:
		Global.GameType.ECP:
			return "英汉配对"
		Global.GameType.QQNA:
			return "快问快答"
		Global.GameType.QSPE:
			return "快速拼写"
	return "未知模式"


func level_name() -> String:
	if level < 0:
		return ""
	return Word.LEVEL_NAMES.get(level, "")


func accuracy() -> float:
	if total <= 0:
		return 0.0
	return float(correct) / float(total)

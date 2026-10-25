extends Resource
class_name Word

## 词汇等级。表格里的“初中”对应初级，“*”对应中级，“**”对应高级。
enum Level {
	PRIMARY,
	INTERMEDIATE,
	ADVANCED,
}

const LEVEL_NAMES := {
	Level.PRIMARY: "初级",
	Level.INTERMEDIATE: "中级",
	Level.ADVANCED: "高级",
}

@export var English: String
@export var Chinese: String
@export var English_meaning_group: Array[EnglishMeaning]
@export var level: Level = Level.ADVANCED
## 括号里的另一种拼写，例如 criticise(criticize)
@export var aliases: PackedStringArray


func level_name() -> String:
	return LEVEL_NAMES.get(level, "高级")


## 把所有词义拼成一行："n.苹果；v.削皮"
func meanings_text() -> String:
	return format_meanings(English_meaning_group)


## 存档里用的精简词义，避免每条记录太长
func short_meanings(max_chars: int = 40) -> String:
	var text := meanings_text()
	if text.length() <= max_chars:
		return text
	return text.substr(0, max_chars) + "…"


## 随机取 count 条词义拼成一行
func get_random_meaning(count: int = 1) -> String:
	if count >= English_meaning_group.size():
		return meanings_text()
	var picked: Array[EnglishMeaning] = []
	var pool := English_meaning_group.duplicate()
	for i in range(count):
		if pool.is_empty():
			break
		var index := randi_range(0, pool.size() - 1)
		picked.append(pool[index])
		pool.remove_at(index)
	return format_meanings(picked)


## 按词性分组拼字符串，相同词性只显示一次前缀
static func format_meanings(meanings: Array) -> String:
	var result := ""
	var last_type := -1
	for meaning in meanings:
		var item := meaning as EnglishMeaning
		if item == null:
			continue
		if item.type != last_type:
			last_type = item.type
			result += item.pos_label()
		result += item.meaning + "；"
	return result.trim_suffix("；")

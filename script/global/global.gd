extends Node

enum GameType {
	ECP,
	QQNA,
	QSPE,
}

const GAME_STAMINA_COST = {
	GameType.ECP: 60,
	GameType.QQNA: 40,
	GameType.QSPE: 60,
}

## 英汉配对棋盘上的词对数
const ECP_PAIR_COUNT := 30

var word_group: WordGroup = load("res://assets/wordbook.res")
var answer_area_type: Global.GameType

## 本局设置：主界面选择，联机时由房主同步
var ecp_level: int = Word.Level.PRIMARY

var _level_pools: Dictionary = {}


# ---------------------------------------------------------------- 词库


func all_words() -> Array[Word]:
	return word_group.word_group


func words_by_level(level: int) -> Array[Word]:
	_ensure_level_pools()
	return _level_pools.get(level, [] as Array[Word])


func _ensure_level_pools() -> void:
	if !_level_pools.is_empty():
		return
	for level in [Word.Level.PRIMARY, Word.Level.INTERMEDIATE, Word.Level.ADVANCED]:
		var pool: Array[Word] = []
		_level_pools[level] = pool
	for word in word_group.word_group:
		var pool: Array[Word] = _level_pools[word.level]
		pool.append(word)


## 从指定等级随机抽 count 个词（不重复）
func sample_level(level: int, count: int) -> Array[Word]:
	var pool: Array[Word] = words_by_level(level).duplicate()
	pool.shuffle()
	if pool.size() > count:
		pool.resize(count)
	return pool


## 英汉配对的等级配比：
##   初级 100% 初级；中级 50% 中级 + 50% 初级；高级 50% 高级 + 25% 初级 + 25% 中级
func ecp_quotas(level: int, total: int) -> Dictionary:
	match level:
		Word.Level.INTERMEDIATE:
			var intermediate := total / 2
			return {Word.Level.INTERMEDIATE: intermediate, Word.Level.PRIMARY: total - intermediate}
		Word.Level.ADVANCED:
			var advanced := total / 2
			var rest := total - advanced
			var primary := rest / 2 + rest % 2
			return {Word.Level.ADVANCED: advanced, Word.Level.PRIMARY: primary, Word.Level.INTERMEDIATE: rest - primary}
	return {Word.Level.PRIMARY: total}


func pick_ecp_words(level: int, total: int = ECP_PAIR_COUNT) -> Array[Word]:
	return sample_by_quotas(ecp_quotas(level, total), total)


## 按 {等级: 数量} 抽词，某个等级不够时用其它词补足
func sample_by_quotas(quotas: Dictionary, total: int) -> Array[Word]:
	_ensure_level_pools()
	var chosen: Array[Word] = []
	var used := {}
	for level in quotas:
		for word in sample_level(level, int(quotas[level])):
			chosen.append(word)
			used[word.English.to_lower()] = true
	if chosen.size() < total:
		var rest: Array[Word] = word_group.word_group.duplicate()
		rest.shuffle()
		for word in rest:
			if chosen.size() >= total:
				break
			if used.has(word.English.to_lower()):
				continue
			chosen.append(word)
			used[word.English.to_lower()] = true
	chosen.shuffle()
	return chosen


## 随机抽 count 个不重复的词，pool 为空时用整个词库
func pick_random_words(count: int, pool: Array[Word] = [] as Array[Word]) -> Array[Word]:
	var source: Array[Word] = pool.duplicate() if !pool.is_empty() else word_group.word_group.duplicate()
	source.shuffle()
	var result: Array[Word] = []
	while result.size() < count and !source.is_empty():
		result.append(source.pop_back())
	return result

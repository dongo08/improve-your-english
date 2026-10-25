extends Node
## 把 assets/wordbook_source.json（xlsx 解析结果）合并进 assets/gaozhong.tres，
## 生成 assets/wordbook.tres。
##
## 规则：
##   - 同一个词（不分大小写、含括号别名）只保留一条，重复的只补新词义；
##   - 表格里的词按“初中 / * / **”设置初级 / 中级 / 高级；
##   - 旧词库里表格没有的词统一算高级。
##
## 跑法：godot --headless --path . res://tools/build_wordbook.tscn

const SOURCE_TRES := "res://assets/gaozhong.tres"
const SOURCE_JSON := "res://assets/wordbook_source.json"
const OUTPUT_TRES := "res://assets/wordbook.tres"

const LEVEL_BY_NAME := {
	"PRIMARY": Word.Level.PRIMARY,
	"INTERMEDIATE": Word.Level.INTERMEDIATE,
	"ADVANCED": Word.Level.ADVANCED,
}

## 规范化后的词 -> Word
var merged: Dictionary = {}
## 别名 -> 规范化后的词
var alias_index: Dictionary = {}

var space_regex := RegEx.create_from_string("\\s+")
var old_entries := 0
var old_merged := 0
var duplicate_meanings := 0
var new_words := 0
var added_meanings := 0


func _ready() -> void:
	var old_group: WordGroup = load(SOURCE_TRES)
	if old_group == null:
		_fail("读不到 %s" % SOURCE_TRES)
		return
	_merge_old(old_group)

	if !FileAccess.file_exists(SOURCE_JSON):
		_fail("读不到 %s，先跑 tools/import_words.py" % SOURCE_JSON)
		return
	_merge_json(SOURCE_JSON)

	var words: Array[Word] = []
	for word in merged.values():
		words.append(word)
	words.sort_custom(func(a: Word, b: Word): return a.English.to_lower() < b.English.to_lower())

	var group := WordGroup.new()
	group.word_group = words
	var err := ResourceSaver.save(group, OUTPUT_TRES)
	if err != OK:
		_fail("保存失败：%s（错误码 %d）" % [OUTPUT_TRES, err])
		return

	_report(words)
	get_tree().quit(0)


func _merge_old(group: WordGroup) -> void:
	for word in group.word_group:
		old_entries += 1
		var key := _key(word.English)
		if key == "":
			continue
		if merged.has(key):
			old_merged += 1
			duplicate_meanings += _merge_meanings(merged[key], word.English_meaning_group)
			_register_aliases(merged[key])
			continue
		# 旧词库里的词先默认高级，表格里出现时再覆盖
		word.level = Word.Level.ADVANCED
		_normalize_meanings(word)
		merged[key] = word
		_register_aliases(word)


func _merge_json(path: String) -> void:
	var text := FileAccess.get_file_as_string(path)
	var data = JSON.parse_string(text)
	if data == null or !(data is Dictionary) or !data.has("words"):
		_fail("JSON 解析失败：%s" % path)
		return

	for entry in data["words"]:
		var english := str(entry.get("english", "")).strip_edges()
		if english == "":
			continue
		var aliases: Array = entry.get("aliases", [])
		var key := _find_key(english, aliases)
		var word: Word
		if merged.has(key):
			word = merged[key]
		else:
			word = Word.new()
			word.English = english
			merged[_key(english)] = word
			new_words += 1
		word.level = LEVEL_BY_NAME.get(str(entry.get("level", "ADVANCED")), Word.Level.ADVANCED)
		for alias in aliases:
			var alias_text := str(alias).strip_edges()
			if alias_text != "" and !word.aliases.has(alias_text):
				word.aliases.append(alias_text)
		_register_aliases(word)
		for meaning in entry.get("meanings", []):
			var item := EnglishMeaning.new()
			item.type = EnglishMeaning.type_from_name(str(meaning.get("type", "NONE")))
			item.meaning = _clean_text(str(meaning.get("meaning", "")))
			if item.meaning == "":
				continue
			if _has_meaning(word, item):
				continue
			word.English_meaning_group.append(item)
			added_meanings += 1


func _find_key(english: String, aliases: Array) -> String:
	var key := _key(english)
	if merged.has(key):
		return key
	if alias_index.has(key):
		return alias_index[key]
	for alias in aliases:
		var alias_key := _key(str(alias))
		if merged.has(alias_key):
			return alias_key
		if alias_index.has(alias_key):
			return alias_index[alias_key]
	return key


func _register_aliases(word: Word) -> void:
	var key := _key(word.English)
	for alias in word.aliases:
		alias_index[_key(alias)] = key


func _normalize_meanings(word: Word) -> void:
	var seen := {}
	var unique: Array[EnglishMeaning] = []
	for meaning in word.English_meaning_group:
		meaning.meaning = _clean_text(meaning.meaning)
		if meaning.meaning == "":
			continue
		var key := "%d|%s" % [meaning.type, meaning.meaning]
		if seen.has(key):
			continue
		seen[key] = true
		unique.append(meaning)
	word.English_meaning_group = unique


func _merge_meanings(target: Word, meanings: Array) -> int:
	var added := 0
	for meaning in meanings:
		meaning.meaning = _clean_text(meaning.meaning)
		if meaning.meaning == "":
			continue
		if _has_meaning(target, meaning):
			continue
		target.English_meaning_group.append(meaning)
		added += 1
	return added


func _has_meaning(word: Word, meaning: EnglishMeaning) -> bool:
	for existing in word.English_meaning_group:
		if existing.same_as(meaning):
			return true
	return false


## 旧词库里的释义常带多余空格（"vt. 达到， 取得"），统一压一压再去重
func _clean_text(text: String) -> String:
	var cleaned := space_regex.sub(text.strip_edges(), " ", true)
	for punct in ["，", "；", "、", ",", ";"]:
		cleaned = cleaned.replace(" " + punct, punct)
		cleaned = cleaned.replace(punct + " ", punct)
	return cleaned.strip_edges()


func _key(text: String) -> String:
	return text.strip_edges().to_lower()


func _report(words: Array[Word]) -> void:
	var level_counts := {}
	var meaning_total := 0
	var empty_words: Array[String] = []
	for word in words:
		level_counts[word.level] = int(level_counts.get(word.level, 0)) + 1
		meaning_total += word.English_meaning_group.size()
		if word.English_meaning_group.is_empty():
			empty_words.append(word.English)
	print("[wordbook] 旧库 %d 条 -> 去重合并 %d 条" % [old_entries, old_merged])
	print("[wordbook] 新增词 %d 条，新增词义 %d 条，去重词义 %d 条" % [new_words, added_meanings, duplicate_meanings])
	print("[wordbook] 合计 %d 词 / %d 词义" % [words.size(), meaning_total])
	print("[wordbook] 等级分布：初级 %d，中级 %d，高级 %d" % [
		level_counts.get(Word.Level.PRIMARY, 0),
		level_counts.get(Word.Level.INTERMEDIATE, 0),
		level_counts.get(Word.Level.ADVANCED, 0),
	])
	if !empty_words.is_empty():
		print("[wordbook] 警告：%d 个词没有词义，例如 %s" % [empty_words.size(), str(empty_words.slice(0, 5))])
	print("[wordbook] 已写入 %s" % OUTPUT_TRES)


func _fail(message: String) -> void:
	push_error("[wordbook] " + message)
	print("[wordbook] 失败：" + message)
	get_tree().quit(1)

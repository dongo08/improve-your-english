extends Node
## 词库自检：godot --headless --path . res://tools/verify_wordbook.tscn

func _ready() -> void:
	var group: WordGroup = load("res://assets/wordbook.tres")
	if group == null:
		print("[verify] 读不到 wordbook.tres")
		get_tree().quit(1)
		return

	var by_key := {}
	var by_level := {Word.Level.PRIMARY: [], Word.Level.INTERMEDIATE: [], Word.Level.ADVANCED: []}
	var empty_words: Array[String] = []
	var meaning_total := 0
	var duplicate_words: Array[String] = []
	for word in group.word_group:
		var key := word.English.strip_edges().to_lower()
		if by_key.has(key):
			duplicate_words.append(word.English)
		by_key[key] = word
		by_level[word.level].append(word)
		meaning_total += word.English_meaning_group.size()
		if word.English_meaning_group.is_empty():
			empty_words.append(word.English)

	print("[verify] 总词数 %d，总词义 %d" % [group.word_group.size(), meaning_total])
	for level in by_level:
		print("[verify] %s：%d 个" % [Word.LEVEL_NAMES[level], by_level[level].size()])
	print("[verify] 重复词 %d，缺词义 %d" % [duplicate_words.size(), empty_words.size()])
	if !duplicate_words.is_empty():
		print("[verify] 重复示例：%s" % str(duplicate_words.slice(0, 5)))

	for level in by_level:
		print("[verify] --- %s 示例 ---" % Word.LEVEL_NAMES[level])
		var pool: Array = by_level[level].duplicate()
		pool.shuffle()
		for i in mini(4, pool.size()):
			var word: Word = pool[i]
			print("[verify]   %s [%s] %s" % [word.English, word.level_name(), word.meanings_text()])

	var ok := duplicate_words.is_empty() and empty_words.is_empty()
	print("[verify] %s" % ("OK" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)

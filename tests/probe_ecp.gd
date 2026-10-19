extends Node
## 回归探针：连续进两局英汉配对，全局词库不应该被消耗。

func _ready() -> void:
	var before := Global.word_group.word_group.size()
	for i in 2:
		var ecp: Node = load("res://scenes/games/ECP/EnglishChinese_pairing.tscn").instantiate()
		add_child(ecp)
		await get_tree().process_frame
		ecp.queue_free()
		await get_tree().process_frame
	var after := Global.word_group.word_group.size()
	print("PROBE before=%d after=%d" % [before, after])
	print("PROBE %s" % ("OK" if before == after else "FAIL"))
	get_tree().quit(0 if before == after else 1)

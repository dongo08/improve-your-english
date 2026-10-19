extends Node
@export var word_group:WordGroup
func _ready() -> void:
	for i in word_group.word_group:
		var a=EnglishMeaning.new()
		a.type=EnglishMeaning.Type.N
		a.meaning=i.Chinese
		i.English_meaning_group.push_back(a)
	ResourceSaver.save(word_group,"res://assets/new.tres")

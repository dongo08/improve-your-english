extends Node
@export var group1:WordGroup
@export var group2:WordGroup
func  _ready() -> void:
	group1.word_group+=group2.word_group
	ResourceSaver.save(group1,"res://assets/new.tres")

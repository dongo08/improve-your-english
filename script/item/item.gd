extends Resource
class_name Item
@export var name:String
@export var count:int=1:
	set(a):
		if count!=a:
			count=a
			emit_changed()
@export var icon:Texture2D
@export_multiline var description:String
@export var cost:int

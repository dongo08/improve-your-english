extends Button
class_name ItemUI
@export var item:Item
@export var count:Label
var is_goods:bool=false
signal check(item:ItemUI)
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	count.text=str(item.count)
	icon=item.icon
	item.changed.connect(refresh)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
func refresh():
	if !is_goods:
		count.text=str(item.count)


#func _on_gui_input(event: InputEvent) -> void:
	#print(event.as_text())
	#if event is InputEventMouseButton and event.pressed and !event.double_click:
		#


func _on_pressed() -> void:
	check.emit(self)

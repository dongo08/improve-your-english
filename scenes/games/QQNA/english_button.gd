extends Button
class_name EnglishButton
@export var word:Word
signal choosed(button:Button,toggled_on:bool)
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	text=word.English


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _on_toggled(toggled_on: bool) -> void:
	choosed.emit(self,toggled_on)

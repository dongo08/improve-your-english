extends Button
class_name ChineseButton
@export var word:Word
signal choosed(button:Button,togglde_on:bool)
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	var a=word.English_meaning_group[randi_range(0,len(word.English_meaning_group)-1)]
	var type:String=""
	match a.type:
		EnglishMeaning.Type.N:
			type="n."
		EnglishMeaning.Type.V:
			type="v."
		EnglishMeaning.Type.VI:
			type="vi."
		EnglishMeaning.Type.VT:
			type="vt."
		EnglishMeaning.Type.ADJ:
			type="adj."
		EnglishMeaning.Type.ADV:
			type="adv."
		EnglishMeaning.Type.PREP:
			type="prep."
	text=type+a.meaning
	


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _on_toggled(toggled_on: bool) -> void:
	choosed.emit(self,toggled_on)

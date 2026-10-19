extends Control
class_name QQNA
var pre_button=preload("res://scenes/games/ECP/c_e_option.tscn")
@export var word_group:Array[Word]=Global.word_group.word_group.duplicate()
@export var English:Label
@export var buttons:Array[CEOption]
@export var button_area:HBoxContainer
@export var current_word:Word
@export var last_word_group:WordGroup=WordGroup.new()
# Called when the node enters the scene tree for the first time.
signal add_score(score:int)
signal camera_shake()
func _ready() -> void:
	_generate_buttons()

func _choose_qna()->Array:
	var correct:Word
	var confused:Array[Word]
	var a=randi_range(0,len(word_group)-1)
	correct=word_group[a]
	for i in range(4):
		var button=pre_button.instantiate() as CEOption
		var b:int
		b=randi_range(0,len(word_group)-1)
		while b==a:
			b=randi_range(0,len(word_group)-1)
		confused.append(word_group[b])
	if word_group.size()>4:
		word_group.pop_at(a)
	return [correct,confused]

func _generate_buttons():
	var chosen_word=_choose_qna()
	current_word=chosen_word[0]
	English.text=current_word.English
	for i in range(4):
		var button=pre_button.instantiate() as CEOption
		button.word=chosen_word[1][i]
		#word_group.word_group.pop_at(b)
		button.choosed.connect(on_choosed)
		buttons.push_back(button)
	var b=randi_range(0,3)
	buttons[b].word=chosen_word[0]
	for i in buttons:
		button_area.add_child(i)

func on_choosed(choosed_button:CEOption):
	if choosed_button.word==current_word:
		choosed_button.text="√"
		add_score.emit(3)
		for i in buttons:
			i.disabled=true
		await get_tree().create_timer(0.5).timeout
		for i in buttons:
			i.queue_free()
		buttons.clear()
	else:
		add_score.emit(-2)
		camera_shake.emit()
		last_word_group.word_group.push_back(current_word)
		for i in buttons:
			i.disabled=true
			if i.word!=current_word:
				i.text="×"
		await get_tree().create_timer(1).timeout
		for i in buttons:
			i.queue_free()
		buttons.clear()
	_generate_buttons()
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
func get_last_words()->WordGroup:
	return last_word_group

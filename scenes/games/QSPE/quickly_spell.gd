extends Control
class_name QSPE

@export var label: Label
@export var line_edit: LineEdit
@export var word_group: Array[Word] = Global.word_group.word_group.duplicate()
@export var tip_label: Label
@onready var tip_timer: Timer = $TipTimer
@export var skip_button: Button

var last_words: WordGroup = WordGroup.new()
var current_word: Word
var correct_count := 0
var wrong_count := 0
var answers: Array[Dictionary] = []

signal add_score(score: int)
signal camera_shake()


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_choose_word()


func _choose_word():
	if word_group.is_empty():
		return
	var i = randi_range(0, word_group.size() - 1)
	current_word = word_group[i]
	if word_group.size() > 5:
		word_group.pop_at(i)
	label.text = current_word.get_random_meaning(2)
	tip_label.text = current_word.English
	tip_label.visible_characters = 0
	skip_button.disabled = false
	tip_timer.stop()
	tip_timer.start()


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func get_last_words():
	if current_word:
		last_words.word_group.append(current_word)
	return last_words


func _on_line_edit_text_changed(new_text: String) -> void:
	if len(new_text) > 50:
		_on_button_pressed()
	if current_word and new_text == current_word.English:
		line_edit.editable = false
		line_edit.text += " √"
		skip_button.disabled = true
		correct_count += 1
		_record(PlayRecord.RESULT_CORRECT)
		current_word = null
		add_score.emit(8)
		tip_timer.stop()
		await get_tree().create_timer(0.5).timeout
		if !is_inside_tree():
			return
		line_edit.clear()
		line_edit.editable = true
		_choose_word()
		line_edit.grab_focus()


func _on_button_pressed() -> void:
	if current_word == null:
		return
	line_edit.text = current_word.English
	last_words.word_group.append(current_word)
	line_edit.editable = false
	skip_button.disabled = true
	wrong_count += 1
	_record(PlayRecord.RESULT_SKIPPED)
	current_word = null
	add_score.emit(-3)
	camera_shake.emit()
	tip_timer.stop()
	await get_tree().create_timer(0.5).timeout
	if !is_inside_tree():
		return
	line_edit.clear()
	line_edit.editable = true
	_choose_word()
	line_edit.grab_focus()


func _record(result: String) -> void:
	answers.append({
		"en": current_word.English,
		"zh": current_word.short_meanings(),
		"result": result,
	})


func get_stats() -> Dictionary:
	return {
		"correct": correct_count,
		"wrong": wrong_count,
		"total": correct_count + wrong_count,
		"effective": maxi(correct_count - wrong_count, 0),
	}


func word_results() -> Array[Dictionary]:
	return answers


func _on_tip_timer_timeout() -> void:
	tip_label.visible_characters = 1

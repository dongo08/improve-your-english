extends Control
class_name QQNA

## 60 秒快问快答：一直出题，直到时间到。答对 +3、答错 -2。
## pp 以 60 题 = 200pp 为基准，超过 60 题继续按平方增长。

var pre_button = preload("res://scenes/games/ECP/c_e_option.tscn")

@export var English: Label
@export var buttons: Array[CEOption]
@export var button_area: HBoxContainer
@export var last_word_group: WordGroup = WordGroup.new()

signal add_score(score: int)
signal camera_shake()

var current_word: Word
## 待出题目的词池，抽完自动重新洗牌
var pool: Array[Word] = []
var correct_count := 0
var wrong_count := 0
var answers: Array[Dictionary] = []


func _ready() -> void:
	_generate_buttons()


func _generate_buttons() -> void:
	current_word = _next_word()
	if current_word == null:
		return
	English.text = current_word.English

	var options := _pick_options(current_word, 4)
	for word in options:
		var button := pre_button.instantiate() as CEOption
		button.word = word
		button.choosed.connect(on_choosed)
		buttons.push_back(button)
	for button in buttons:
		button_area.add_child(button)


func _next_word() -> Word:
	if pool.is_empty():
		pool = Global.all_words().duplicate()
		pool.shuffle()
	if pool.is_empty():
		return null
	return pool.pop_back()


## 4 个选项：1 个正确答案 + 3 个干扰项
func _pick_options(correct: Word, count: int) -> Array[Word]:
	var all_words := Global.all_words()
	var options: Array[Word] = []
	var guard := 0
	while options.size() < count - 1 and guard < 200:
		guard += 1
		var candidate: Word = all_words[randi_range(0, all_words.size() - 1)]
		if candidate == correct or options.has(candidate):
			continue
		options.append(candidate)
	while options.size() < count - 1:
		options.append(correct)
	options.insert(randi_range(0, options.size()), correct)
	return options


func on_choosed(choosed_button: CEOption):
	if choosed_button.word == current_word:
		choosed_button.text = "√"
		correct_count += 1
		add_score.emit(3)
		for button in buttons:
			button.disabled = true
		_record(PlayRecord.RESULT_CORRECT)
		await get_tree().create_timer(0.5).timeout
	else:
		wrong_count += 1
		add_score.emit(-2)
		camera_shake.emit()
		last_word_group.word_group.push_back(current_word)
		for button in buttons:
			button.disabled = true
			if button.word != current_word:
				button.text = "×"
		_record(PlayRecord.RESULT_WRONG)
		await get_tree().create_timer(1).timeout

	if !is_inside_tree():
		return
	_clear_buttons()
	_generate_buttons()


func _record(result: String) -> void:
	answers.append({
		"en": current_word.English,
		"zh": current_word.short_meanings(),
		"result": result,
	})


func _clear_buttons() -> void:
	for button in buttons:
		button.queue_free()
	buttons.clear()


func get_stats() -> Dictionary:
	return {
		"correct": correct_count,
		"wrong": wrong_count,
		"total": correct_count + wrong_count,
		"effective": maxi(correct_count - wrong_count, 0),
	}


func word_results() -> Array[Dictionary]:
	return answers


func get_last_words() -> WordGroup:
	return last_word_group

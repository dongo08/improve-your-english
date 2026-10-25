extends Control
class_name ECP

var pre_english_button = preload("res://scenes/games/QQNA/English_button.tscn")
var pre_chinese_button = preload("res://scenes/games/QQNA/Chinese_button.tscn")

@export var english_area: GridContainer
@export var chinese_area: GridContainer
@export var buttons_english: Array[Button]

signal add_score(score: int)
signal camera_shake()

var words: Array[Word] = []
var correct_count := 0
var wrong_count := 0
var choosed_english_button: EnglishButton
var choosed_chinese_button: ChineseButton


func _ready() -> void:
	words = Global.pick_ecp_words(Global.ecp_level, Global.ECP_PAIR_COUNT)
	_build_board()


func _build_board() -> void:
	for word in words:
		var english_button := pre_english_button.instantiate() as EnglishButton
		english_button.word = word
		english_button.choosed.connect(button_choosed)
		buttons_english.push_back(english_button)
		english_area.add_child(english_button)

	var chinese_words := words.duplicate()
	chinese_words.shuffle()
	for word in chinese_words:
		var chinese_button := pre_chinese_button.instantiate() as ChineseButton
		chinese_button.word = word
		chinese_button.choosed.connect(button_choosed)
		chinese_area.add_child(chinese_button)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func button_choosed(button: Button, toggled_on: bool):
	if toggled_on:
		if button is EnglishButton:
			if choosed_english_button:
				choosed_english_button.button_pressed = false
			choosed_english_button = button
		if button is ChineseButton:
			if choosed_chinese_button:
				choosed_chinese_button.button_pressed = false
			choosed_chinese_button = button
		if choosed_chinese_button and choosed_english_button:
			if choosed_chinese_button.word == choosed_english_button.word:
				choosed_chinese_button.text = "√"
				choosed_chinese_button.disabled = true
				choosed_english_button.text = "√"
				choosed_english_button.disabled = true
				choosed_english_button = null
				choosed_chinese_button = null
				correct_count += 1
				add_score.emit(5)
			else:
				wrong_count += 1
				add_score.emit(-1)
				camera_shake.emit()
	else:
		if button is EnglishButton:
			choosed_english_button = null
		if button is ChineseButton:
			choosed_chinese_button = null


func get_stats() -> Dictionary:
	return {
		"correct": correct_count,
		"wrong": wrong_count,
		"total": words.size(),
		"effective": maxi(correct_count - wrong_count, 0),
	}


func get_last_words() -> WordGroup:
	var group := WordGroup.new()
	for button in buttons_english:
		if button.text != "√":
			group.word_group.push_back(button.word)
	return group


## 每个词的作答结果，写进游玩记录
func word_results() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	for button in buttons_english:
		var word: Word = button.word
		results.append({
			"en": word.English,
			"zh": word.short_meanings(),
			"result": PlayRecord.RESULT_CORRECT if button.text == "√" else PlayRecord.RESULT_SKIPPED,
		})
	return results

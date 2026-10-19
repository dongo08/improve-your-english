extends Control
class_name ECP
var pre_english_button=preload("res://scenes/games/QQNA/English_button.tscn")
var pre_chinese_button=preload("res://scenes/games/QQNA/Chinese_button.tscn")
var choosed_english_button:EnglishButton
var choosed_chinese_button:ChineseButton
@export var word_group:WordGroup=Global.word_group.duplicate()
@export var tmp_word_group:Array[Word]
@export var english_area:GridContainer
@export var chinese_area:GridContainer
@export var buttons_english:Array[Button]
# Called when the node enters the scene tree for the first time.
signal add_score(score:int)
signal camera_shake()
func _ready() -> void:
	# duplicate() 只复制资源本身，数组还是和全局词库共用的；这里单独拷一份，
	# 避免每玩一局就把 Global.word_group 里的词删掉 30 个。
	word_group.word_group = word_group.word_group.duplicate()
	for i in range(30):
		var a=randi_range(0,len(word_group.word_group)-1)
		tmp_word_group.append(word_group.word_group[a])
		word_group.word_group.remove_at(a)
		var english_button=pre_english_button.instantiate()
		english_button.word=tmp_word_group[i]
		english_button.choosed.connect(button_choosed)
		buttons_english.push_back(english_button)
		english_area.add_child(english_button)
	for i in range(30):
		var a=randi_range(0,len(tmp_word_group)-1)
		var chinese_button=pre_chinese_button.instantiate()
		chinese_button.word=tmp_word_group[a]
		tmp_word_group.remove_at(a)
		chinese_button.choosed.connect(button_choosed)
		#buttons.push_back(chinese_button)
		chinese_area.add_child(chinese_button)
		


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
func button_choosed(button:Button,toggled_on:bool):
	if toggled_on:
		if button is EnglishButton:
			if choosed_english_button:
				choosed_english_button.button_pressed=false
			choosed_english_button=button
		if button is ChineseButton:
			if choosed_chinese_button:
				choosed_chinese_button.button_pressed=false
				
			choosed_chinese_button=button
		if choosed_chinese_button and choosed_english_button:
			if choosed_chinese_button.word==choosed_english_button.word:
				choosed_chinese_button.text="√"
				choosed_chinese_button.disabled=true
				choosed_english_button.text="√"
				choosed_english_button.disabled=true
				choosed_english_button=null
				choosed_chinese_button=null
				add_score.emit(5)
			else:
				add_score.emit(-1)
				camera_shake.emit()
	else:
		if button is EnglishButton:
			choosed_english_button=null
		if button is ChineseButton:
			choosed_chinese_button=null
func get_last_words()->WordGroup:
	var a=WordGroup.new()
	for i in buttons_english:
		if i.text!="√":
			a.word_group.push_back(i.word)
	return a

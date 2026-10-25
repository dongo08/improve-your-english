extends Control
@export var input_window:PanelContainer
@export var accept:Button
@export var cancel:Button
@export var start:Button
@export var input_line:LineEdit
@export var formal_button:CheckBox
@export var tip:Label
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	input_window.visible=false


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _on_button_pressed() -> void:
	input_window.visible=true


func _on_accept_pressed() -> void:
	if AccountManager.add_account(input_line.text,formal_button.button_pressed):
		get_tree().change_scene_to_file("res://scenes/choose_scene.tscn")


func _on_online_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/online/login.tscn")


func _on_cancel_pressed() -> void:
	input_window.visible=false
	input_line.text=""


func _on_line_edit_text_changed(new_text: String) -> void:
	if new_text:
		var a=AccountManager.find_account_from_name(new_text)
		if a:
			tip.text="存在该账号"+("，是正式账号" if a.is_formal else "")
			formal_button.disabled=true
		else:
			tip.text="不存在该账号，将创建新账号"
			formal_button.disabled=false
	else:
		tip.text=""
		formal_button.disabled=false

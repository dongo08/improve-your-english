extends PanelContainer
@export var username:LineEdit
@export var buttons:HBoxContainer
@export var remove_area:CenterContainer
@export var warning_window:AcceptDialog
var CNC=preload("res://assets/items/name_change_card.tres")
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	username.text=AccountManager.current_account.id
	buttons.visible=false
	remove_area.visible=false

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _on_usernameinput_text_changed(new_text: String) -> void:
	if new_text!=AccountManager.current_account.id:
		buttons.visible=true
	else:
		buttons.visible=false


func _on_confirm_button_pressed() -> void:
	var a=AccountManager.current_account.bag.find(CNC)
	if a==-1:
		warning_window.dialog_text="你没有改名卡"
		warning_window.visible=true
	else:
		if !AccountManager.has_account_name(username.text):
			AccountManager.current_account.id=username.text

			buttons.visible=false
			if AccountManager.current_account.bag[a].count>1:
				AccountManager.current_account.bag[a].count-=1
			else:
				AccountManager.current_account.bag.pop_at(a)
				get_parent().bag_and_shop.refresh()
			AccountManager.save()
		else:
			warning_window.dialog_text="此账户名已存在"
			warning_window.visible=true


func _on_remove_button_pressed() -> void:
	remove_area.visible=!remove_area.visible


func _on_true_remove_pressed() -> void:
	AccountManager.account_group.account_list.erase(AccountManager.current_account)
	AccountManager.save()
	get_tree().change_scene_to_file("res://scenes/start.tscn")


func _on_cancel_button_pressed() -> void:
	username.text=AccountManager.current_account.id
	buttons.visible=false

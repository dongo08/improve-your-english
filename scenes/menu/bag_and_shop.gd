extends Control
class_name BagUI
@export var appear_button:Button
@export var bag_area:HFlowContainer
@export var shop_area:HFlowContainer
@export var bag_area_item_name:Label
@export var bag_area_item_des:Label
@export var shop_area_item_name:Label
@export var shop_area_item_des:Label
@export var shop_buttons:HBoxContainer
@export var shop_cost:Label
@export var warning_window:AcceptDialog
@export var score:Label
@export var selling_item:Array[Item]
var pre_itemui:PackedScene=preload("res://scenes/menu/item.tscn")
var tween:Tween
var bag_focus:ItemUI:
	set(a):
		bag_area_item_des.text=a.item.description
		bag_area_item_name.text=a.item.name
		bag_focus=a
var shop_focus:ItemUI:
	set(a):
		shop_area_item_des.text=a.item.description
		shop_area_item_name.text=a.item.name
		shop_focus=a
		shop_buttons.visible=true
		shop_cost.text="价格："+str(a.item.cost)

signal shopping(enter:bool)
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	shop_buttons.visible=false
	for i in AccountManager.current_account.bag:
		var a=pre_itemui.instantiate() as ItemUI
		a.item=i
		a.check.connect(check_item)
		bag_area.add_child(a)
	for i in selling_item:
		var a=pre_itemui.instantiate() as ItemUI
		a.is_goods=true
		a.item=i
		a.check.connect(check_item)
		shop_area.add_child(a)
	AccountManager.current_account.changed.connect(refresh)
	bag_area_item_des.text=''
	bag_area_item_name.text=''
	shop_area_item_des.text=''
	shop_area_item_name.text=''
	var stamina = AccountManager.current_account.get_stamina()
	score.text = "积分：" + str(AccountManager.current_account.score) + "  体力：" + str(stamina) + "/" + str(AccountManager.current_account.max_stamina)
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func check_item(item:ItemUI):
	if item.is_goods:
		shop_focus=item
	else:
		bag_focus=item
func refresh():

	for i in bag_area.get_children():
		i.queue_free()
	for i in AccountManager.current_account.bag:
		var a=pre_itemui.instantiate() as ItemUI
		a.item=i
		a.check.connect(check_item)
		bag_area.add_child(a)
	var stamina2 = AccountManager.current_account.get_stamina()
	score.text = "积分：" + str(AccountManager.current_account.score) + "  体力：" + str(stamina2) + "/" + str(AccountManager.current_account.max_stamina)


func _on_buy_pressed() -> void:
	if AccountManager.current_account.score>=shop_focus.item.cost:
		# 存档里的道具是从资源复制出来的，不能按对象身份找，按资源路径找
		var a= AccountManager.current_account.find_bag_item(shop_focus.item)
		if a!=-1:
			AccountManager.current_account.bag[a].count+=1
		else:
			var item:Item=shop_focus.item.duplicate()
			item.count=1
			AccountManager.current_account.bag.push_back(item)
			refresh()
		AccountManager.current_account.score-=shop_focus.item.cost
		AccountManager.save()
	else:
		warning_window.visible=true


func _on_button_toggled(toggled_on: bool) -> void:
	if tween and tween.is_running():
		tween.kill()
	tween=create_tween()
	if toggled_on:
		tween.tween_property(appear_button,"position:x",30,1).as_relative().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		shopping.emit(true)
	else:
		tween.tween_property(appear_button,"position:x",-30,1).as_relative().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		shopping.emit(false)

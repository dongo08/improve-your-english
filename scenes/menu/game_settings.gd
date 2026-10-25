extends Control
class_name GameSettings

## 开局前的小设置面板：英汉配对选难度，快问快答选题数。
## 选中后把设置写进 Global，由主界面切换场景。

signal started(game_type: int)

var mode: int = 0
var title_label: Label
var subtitle_label: Label
var options_box: VBoxContainer
var confirm_button: Button
var option_group := ButtonGroup.new()
var selected_index := 0
var option_texts: Array[String] = []


func _ready() -> void:
	visible = false
	_build_ui()


func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(640, 0)
	center.add_child(panel)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.06, 0.07, 0.11, 0.98)
	panel_style.border_color = Color(1, 1, 1, 0.16)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(12)
	panel.add_theme_stylebox_override("panel", panel_style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_bottom", 30)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	margin.add_child(box)

	title_label = Label.new()
	title_label.add_theme_font_size_override("font_size", 34)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title_label)

	subtitle_label = Label.new()
	subtitle_label.add_theme_font_size_override("font_size", 18)
	subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.65))
	box.add_child(subtitle_label)

	options_box = VBoxContainer.new()
	options_box.add_theme_constant_override("separation", 10)
	box.add_child(options_box)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	box.add_child(buttons)

	var cancel_button := Button.new()
	cancel_button.text = "取消"
	cancel_button.custom_minimum_size = Vector2(0, 44)
	cancel_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel_button.add_theme_font_size_override("font_size", 22)
	cancel_button.pressed.connect(close)
	buttons.add_child(cancel_button)

	confirm_button = Button.new()
	confirm_button.text = "开始"
	confirm_button.custom_minimum_size = Vector2(0, 44)
	confirm_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	confirm_button.add_theme_font_size_override("font_size", 22)
	confirm_button.pressed.connect(_on_confirm_pressed)
	buttons.add_child(confirm_button)


func open(game_type: int) -> void:
	mode = game_type
	_build_options()
	visible = true


func close() -> void:
	visible = false


func _build_options() -> void:
	for child in options_box.get_children():
		options_box.remove_child(child)
		child.queue_free()
	option_texts.clear()

	# 目前只有英汉配对需要选难度（快问快答固定 60 秒，拼写没有选项）
	title_label.text = "英汉配对 · 选择难度"
	subtitle_label.text = "30 对词，按配对数量平方给 pp，配错一个扣一个有效词"
	for level in [Word.Level.PRIMARY, Word.Level.INTERMEDIATE, Word.Level.ADVANCED]:
		_add_option("%s\n满盘 %.0f pp" % [Word.LEVEL_NAMES[level], PPSystem.ecp_base(level)], level)
	select(Global.ecp_level)


func _add_option(text: String, index: int) -> void:
	option_texts.append(text)
	var button := Button.new()
	button.text = text
	button.toggle_mode = true
	button.button_group = option_group
	button.custom_minimum_size = Vector2(0, 64)
	button.add_theme_font_size_override("font_size", 22)
	button.pressed.connect(func(): select(index))
	options_box.add_child(button)


func select(index: int) -> void:
	var buttons := options_box.get_children()
	if index < 0 or index >= buttons.size():
		index = 0
	selected_index = index
	for i in range(buttons.size()):
		var button := buttons[i] as Button
		button.button_pressed = i == index
		if i < option_texts.size():
			button.text = ("✓ " if i == index else "     ") + option_texts[i]


func _on_confirm_pressed() -> void:
	if mode == Global.GameType.ECP:
		Global.ecp_level = selected_index
	visible = false
	started.emit(mode)

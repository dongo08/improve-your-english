extends Control
## 在线模式登录/注册界面。账号和存档都由服务端保存。

const CHOOSE_SCENE := "res://scenes/choose_scene.tscn"
const CONFIG_PATH := "user://online.cfg"

var host_edit: LineEdit
var port_edit: LineEdit
var name_edit: LineEdit
var password_edit: LineEdit
var status_label: Label
var login_button: Button
var register_button: Button
var back_button: Button
var busy := false


func _ready() -> void:
	_build_ui()
	_load_config()


func _build_ui() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(620, 0)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 36)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_right", 36)
	margin.add_theme_constant_override("margin_bottom", 28)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)

	var title := Label.new()
	title.text = "在线模式"
	title.add_theme_font_size_override("font_size", 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "账号、积分和 pp 都存在服务端，换台电脑登录也能接着玩"
	subtitle.add_theme_font_size_override("font_size", 16)
	subtitle.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(subtitle)

	var form := GridContainer.new()
	form.columns = 2
	form.add_theme_constant_override("h_separation", 12)
	form.add_theme_constant_override("v_separation", 10)
	box.add_child(form)

	form.add_child(_form_label("服务器"))
	host_edit = _line_edit("127.0.0.1")
	form.add_child(host_edit)

	form.add_child(_form_label("端口"))
	port_edit = _line_edit(str(Online.DEFAULT_PORT))
	form.add_child(port_edit)

	form.add_child(_form_label("用户名"))
	name_edit = _line_edit("")
	name_edit.max_length = 16
	form.add_child(name_edit)

	form.add_child(_form_label("密码"))
	password_edit = _line_edit("")
	password_edit.secret = true
	form.add_child(password_edit)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	box.add_child(buttons)

	login_button = _make_button("登录")
	login_button.pressed.connect(func(): _submit(false))
	buttons.add_child(login_button)

	register_button = _make_button("注册")
	register_button.pressed.connect(func(): _submit(true))
	buttons.add_child(register_button)

	back_button = _make_button("返回")
	back_button.pressed.connect(_on_back_pressed)
	box.add_child(back_button)

	status_label = Label.new()
	status_label.custom_minimum_size = Vector2(0, 48)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_font_size_override("font_size", 18)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(status_label)

	var hint := Label.new()
	hint.text = "第一次使用先点「注册」。服务端跑起来后，把地址填成服务端所在电脑的 IP。"
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)


func _form_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(80, 0)
	label.add_theme_font_size_override("font_size", 20)
	return label


func _line_edit(default_text: String) -> LineEdit:
	var edit := LineEdit.new()
	edit.text = default_text
	edit.custom_minimum_size = Vector2(300, 40)
	edit.add_theme_font_size_override("font_size", 20)
	return edit


func _make_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 46)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 22)
	return button


func _submit(is_register: bool) -> void:
	if busy:
		return
	var address := host_edit.text.strip_edges()
	var server_port := port_edit.text.strip_edges().to_int()
	var name := name_edit.text.strip_edges()
	var password := password_edit.text
	if address == "":
		_set_status("请填写服务器地址", true)
		return
	if server_port < 1 or server_port > 65535:
		_set_status("端口需要是 1-65535 的数字", true)
		return
	if name == "":
		_set_status("请填写用户名", true)
		return
	if password.length() < Online.MIN_PASSWORD_LENGTH:
		_set_status("密码至少 %d 位" % Online.MIN_PASSWORD_LENGTH, true)
		return

	busy = true
	_set_buttons_enabled(false)
	_set_status("正在连接 %s:%d …" % [address, server_port], false)

	var response: Dictionary
	if is_register:
		response = await Online.register(address, server_port, name, password)
	else:
		response = await Online.login(address, server_port, name, password)

	if !is_inside_tree():
		return
	busy = false
	_set_buttons_enabled(true)
	if !response.get("ok", false):
		_set_status(str(response.get("error", "登录失败")), true)
		return

	_save_config(address, server_port, name)
	var account := SingleAccount.from_dict(response["account"])
	AccountManager.set_online_account(account, "%s:%d" % [address, server_port])
	get_tree().change_scene_to_file(CHOOSE_SCENE)


func _set_status(text: String, is_error: bool) -> void:
	status_label.text = text
	status_label.add_theme_color_override("font_color", Color(1, 0.5, 0.5) if is_error else Color(1, 1, 1, 0.75))


func _set_buttons_enabled(enabled: bool) -> void:
	login_button.disabled = !enabled
	register_button.disabled = !enabled
	back_button.disabled = !enabled


func _on_back_pressed() -> void:
	Online.close_connection()
	get_tree().change_scene_to_file("res://scenes/start.tscn")


# ---------------------------------------------------------------- 上次填过的服务器


func _load_config() -> void:
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) != OK:
		return
	host_edit.text = str(config.get_value("online", "host", host_edit.text))
	port_edit.text = str(config.get_value("online", "port", port_edit.text))
	name_edit.text = str(config.get_value("online", "name", ""))


func _save_config(address: String, server_port: int, name: String) -> void:
	var config := ConfigFile.new()
	config.set_value("online", "host", address)
	config.set_value("online", "port", server_port)
	config.set_value("online", "name", name)
	config.save(CONFIG_PATH)

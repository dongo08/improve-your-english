extends Control
## 联机大厅：创建房间 / 加入房间 / 玩家列表 / 选玩法 / 开始。
## 界面用代码搭建，方便以后在编辑器里改成自己的皮肤。

const CHOOSE_SCENE := "res://scenes/choose_scene.tscn"
const MATCH_SCENE := "res://scenes/games/answer_area.tscn"

const MODE_NAMES := ["英汉配对", "快问快答", "快速拼写"]

var name_edit: LineEdit
var ip_edit: LineEdit
var port_edit: LineEdit
var host_button: Button
var join_button: Button
var leave_button: Button
var start_button: Button
var waiting_label: Label
var mode_option: OptionButton
var player_list: ItemList
var players_title: Label
var status_label: Label
var address_label: Label


func _ready() -> void:
	_build_ui()
	NetworkManager.players_changed.connect(_refresh_players)
	NetworkManager.connection_changed.connect(_refresh_state)
	NetworkManager.network_error.connect(_on_network_error)
	NetworkManager.match_started.connect(_on_match_started)

	name_edit.text = NetworkManager.my_name if NetworkManager.my_name != "" else _default_name()
	_refresh_state()
	_refresh_players()


func _default_name() -> String:
	var account_name: String = AccountManager.current_account.id
	return account_name if account_name != "" else "玩家"


# ---------------------------------------------------------------- 界面


func _build_ui() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(920, 540)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 30)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 30)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 36)
	margin.add_child(columns)

	columns.add_child(_build_left_column())

	var divider := VSeparator.new()
	columns.add_child(divider)

	columns.add_child(_build_right_column())


func _build_left_column() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(380, 0)
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 10)

	var title := Label.new()
	title.text = "联机对战"
	title.add_theme_font_size_override("font_size", 40)
	box.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "各玩各的题目，分数实时同步"
	subtitle.add_theme_font_size_override("font_size", 18)
	subtitle.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	box.add_child(subtitle)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	box.add_child(spacer)

	var form := GridContainer.new()
	form.columns = 2
	form.add_theme_constant_override("h_separation", 12)
	form.add_theme_constant_override("v_separation", 10)
	box.add_child(form)

	form.add_child(_form_label("昵称"))
	name_edit = LineEdit.new()
	name_edit.custom_minimum_size = Vector2(250, 40)
	name_edit.max_length = 16
	name_edit.add_theme_font_size_override("font_size", 20)
	form.add_child(name_edit)

	form.add_child(_form_label("房主地址"))
	ip_edit = LineEdit.new()
	ip_edit.text = "127.0.0.1"
	ip_edit.custom_minimum_size = Vector2(250, 40)
	ip_edit.add_theme_font_size_override("font_size", 20)
	form.add_child(ip_edit)

	form.add_child(_form_label("端口"))
	port_edit = LineEdit.new()
	port_edit.text = str(NetworkManager.DEFAULT_PORT)
	port_edit.custom_minimum_size = Vector2(250, 40)
	port_edit.add_theme_font_size_override("font_size", 20)
	form.add_child(port_edit)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	box.add_child(buttons)

	host_button = _make_button("创建房间", 24)
	host_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host_button.pressed.connect(_on_host_pressed)
	buttons.add_child(host_button)

	join_button = _make_button("加入房间", 24)
	join_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_button.pressed.connect(_on_join_pressed)
	buttons.add_child(join_button)

	leave_button = _make_button("离开房间", 20)
	leave_button.pressed.connect(_on_leave_pressed)
	box.add_child(leave_button)

	status_label = Label.new()
	status_label.custom_minimum_size = Vector2(360, 60)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	status_label.add_theme_font_size_override("font_size", 18)
	box.add_child(status_label)

	address_label = Label.new()
	address_label.custom_minimum_size = Vector2(360, 46)
	address_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	address_label.add_theme_font_size_override("font_size", 16)
	address_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	box.add_child(address_label)

	var hint := Label.new()
	hint.text = "提示：同一局域网直接填对方地址；外网需要房主在路由器上做端口映射。"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
	box.add_child(hint)
	return box


func _build_right_column() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 10)

	players_title = Label.new()
	players_title.text = "房间玩家"
	players_title.add_theme_font_size_override("font_size", 22)
	box.add_child(players_title)

	player_list = ItemList.new()
	player_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	player_list.custom_minimum_size = Vector2(0, 260)
	player_list.add_theme_font_size_override("font_size", 22)
	box.add_child(player_list)

	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 12)
	box.add_child(mode_row)

	var mode_label := _form_label("玩法")
	mode_row.add_child(mode_label)

	mode_option = OptionButton.new()
	mode_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mode_option.custom_minimum_size = Vector2(0, 40)
	mode_option.add_theme_font_size_override("font_size", 20)
	for mode_name in MODE_NAMES:
		mode_option.add_item(mode_name)
	mode_row.add_child(mode_option)

	start_button = _make_button("开始游戏", 28)
	start_button.custom_minimum_size = Vector2(0, 54)
	start_button.pressed.connect(_on_start_pressed)
	box.add_child(start_button)

	waiting_label = Label.new()
	waiting_label.text = "等待房主开始游戏…"
	waiting_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	waiting_label.add_theme_font_size_override("font_size", 20)
	waiting_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	waiting_label.visible = false
	box.add_child(waiting_label)

	var back_button := _make_button("返回主界面", 20)
	back_button.pressed.connect(_on_back_pressed)
	box.add_child(back_button)
	return box


func _form_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(84, 0)
	label.add_theme_font_size_override("font_size", 20)
	return label


func _make_button(text: String, font_size: int) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 44)
	button.add_theme_font_size_override("font_size", font_size)
	return button


# ---------------------------------------------------------------- 状态刷新


func _refresh_state() -> void:
	var online := NetworkManager.is_online
	var host := NetworkManager.is_host
	var busy := NetworkManager.connecting

	name_edit.editable = !online and !busy
	ip_edit.editable = !online and !busy
	port_edit.editable = !online and !busy
	host_button.disabled = online or busy
	join_button.disabled = online or busy
	leave_button.disabled = !online and !busy
	start_button.visible = host
	start_button.disabled = !host
	mode_option.disabled = !host
	waiting_label.visible = online and !host

	if busy:
		status_label.text = "正在连接 %s:%s …" % [ip_edit.text, port_edit.text]
		status_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	elif online and host:
		status_label.text = "房间已创建，把「本机地址」和端口 %s 发给朋友" % port_edit.text
		status_label.add_theme_color_override("font_color", Color(0.6, 1, 0.6, 1))
	elif online:
		status_label.text = "已加入房间，等待房主开始游戏"
		status_label.add_theme_color_override("font_color", Color(0.6, 1, 0.6, 1))
	elif NetworkManager.last_error != "":
		status_label.text = NetworkManager.last_error
		status_label.add_theme_color_override("font_color", Color(1, 0.5, 0.5, 1))
	else:
		status_label.text = "创建房间当房主，或填房主地址加入"
		status_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))

	if online and host:
		var ips := _local_addresses()
		if ips.is_empty():
			address_label.text = "本机地址：没找到局域网地址，请用 127.0.0.1 或手动查 IP"
		else:
			address_label.text = "本机地址：%s" % ", ".join(ips)
	else:
		address_label.text = "对方创建房间后，把他的地址填到「房主地址」再点加入。"


func _refresh_players() -> void:
	player_list.clear()
	players_title.text = "房间玩家（%d/%d）" % [NetworkManager.player_count(), NetworkManager.MAX_CLIENTS + 1]
	var ids := NetworkManager.players.keys()
	ids.sort()
	var my_id := NetworkManager.my_id()
	for id in ids:
		var info: Dictionary = NetworkManager.players[id]
		var tag := ""
		if id == 1:
			tag = "（房主）"
		if id == my_id:
			tag += "（我）"
		player_list.add_item("%s%s" % [str(info.get("name", "玩家")), tag])


func _local_addresses() -> PackedStringArray:
	var result: Array[String] = []
	for address in IP.get_local_addresses():
		if address.contains(":"):
			continue
		if address.begins_with("127.") or address.begins_with("169.254.") or address == "0.0.0.0":
			continue
		result.append(address)
	result.sort_custom(func(a, b): return _address_priority(a) < _address_priority(b))
	return PackedStringArray(result)


func _address_priority(address: String) -> int:
	if address.begins_with("192.168."):
		return 0
	if address.begins_with("10."):
		return 1
	if address.begins_with("172."):
		return 2
	return 3


# ---------------------------------------------------------------- 操作


func _on_host_pressed() -> void:
	var port := _read_port()
	if port <= 0:
		return
	NetworkManager.host_game(port, _nickname())
	_refresh_state()


func _on_join_pressed() -> void:
	var port := _read_port()
	if port <= 0:
		return
	var address := ip_edit.text.strip_edges()
	if address == "":
		status_label.text = "请先填写房主地址"
		status_label.add_theme_color_override("font_color", Color(1, 0.5, 0.5, 1))
		return
	NetworkManager.join_game(address, port, _nickname())
	_refresh_state()


func _on_leave_pressed() -> void:
	NetworkManager.leave_game()
	_refresh_state()
	_refresh_players()


func _on_start_pressed() -> void:
	NetworkManager.start_match(mode_option.selected)


func _on_back_pressed() -> void:
	NetworkManager.leave_game()
	get_tree().change_scene_to_file(CHOOSE_SCENE)


func _on_match_started(_game_type: int, _duration: float) -> void:
	if !is_inside_tree():
		return
	get_tree().change_scene_to_file(MATCH_SCENE)


func _on_network_error(message: String) -> void:
	status_label.text = message
	status_label.add_theme_color_override("font_color", Color(1, 0.5, 0.5, 1))


func _nickname() -> String:
	var nickname := name_edit.text.strip_edges()
	if nickname == "":
		nickname = _default_name()
	name_edit.text = nickname
	return nickname


func _read_port() -> int:
	var port := port_edit.text.strip_edges().to_int()
	if port < 1 or port > 65535:
		status_label.text = "端口需要是 1 到 65535 之间的数字"
		status_label.add_theme_color_override("font_color", Color(1, 0.5, 0.5, 1))
		return -1
	return port

extends PanelContainer
class_name MpScoreboard
## 联机时游戏内的实时排名：左上角一小块，两列显示所有人的分数，不挡题目。

const CELL_SIZE := Vector2(160, 22)
const FONT_SIZE := 18

var grid: GridContainer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	offset_left = 12
	offset_top = 8
	modulate = Color(1, 1, 1, 0.94)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.04, 0.07, 0.66)
	style.border_color = Color(1, 1, 1, 0.16)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(7)
	add_theme_stylebox_override("panel", style)

	grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 2)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(grid)

	NetworkManager.players_changed.connect(_rebuild)
	_rebuild()


func _rebuild() -> void:
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()

	var entries := NetworkManager.ranking()
	visible = !entries.is_empty()
	var my_id := NetworkManager.my_id()
	for i in entries.size():
		var entry: Array = entries[i]
		var is_me: bool = entry[0] == my_id
		grid.add_child(_make_cell(i + 1, str(entry[1]), int(entry[2]), is_me, bool(entry[3])))

	reset_size()


func _make_cell(rank: int, player_name: String, score: int, is_me: bool, finished: bool) -> HBoxContainer:
	var cell := HBoxContainer.new()
	cell.custom_minimum_size = CELL_SIZE
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_theme_constant_override("separation", 4)

	var rank_label := Label.new()
	rank_label.text = str(rank)
	rank_label.custom_minimum_size = Vector2(20, 0)
	rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rank_label.add_theme_font_size_override("font_size", FONT_SIZE)
	rank_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	rank_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(rank_label)

	var name_label := Label.new()
	name_label.text = player_name + (" ✓" if finished else "")
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.add_theme_font_size_override("font_size", FONT_SIZE)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(name_label)

	var score_label := Label.new()
	score_label.text = str(score)
	score_label.custom_minimum_size = Vector2(38, 0)
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score_label.add_theme_font_size_override("font_size", FONT_SIZE)
	score_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(score_label)

	if is_me:
		cell.modulate = Color(1.0, 0.86, 0.35)
	return cell

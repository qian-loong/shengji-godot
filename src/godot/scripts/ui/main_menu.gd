## Main menu — entry point for choosing game mode.
extends Control


func _ready() -> void:
	_build_ui()


func _unhandled_input(event: InputEvent) -> void:
	if not _is_back_input(event):
		return
	get_tree().quit()
	get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		get_tree().quit()
		get_viewport().set_input_as_handled()


func _is_back_input(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_cancel"):
		return true
	return event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_BACK


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.08, 0.12)
	bg.set_anchors_preset(PRESET_FULL_RECT)
	add_child(bg)

	var center := VBoxContainer.new()
	center.set_anchors_preset(PRESET_CENTER)
	center.set_anchor_and_offset(SIDE_LEFT, 0.5, -200)
	center.set_anchor_and_offset(SIDE_RIGHT, 0.5, 200)
	center.set_anchor_and_offset(SIDE_TOP, 0.5, -160)
	center.set_anchor_and_offset(SIDE_BOTTOM, 0.5, 160)
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_theme_constant_override("separation", 20)
	add_child(center)

	# Title
	var title := Label.new()
	title.text = "双升对局"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color(0.95, 0.88, 0.65))
	center.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "竞技型单机双升卡牌游戏"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 16)
	subtitle.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	center.add_child(subtitle)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
	center.add_child(spacer)

	# GUI mode button (primary)
	var gui_btn := _make_menu_button("开始对局", Color(0.15, 0.50, 0.25))
	gui_btn.pressed.connect(func() -> void:
		get_tree().change_scene_to_file("res://scenes/main/gui_game.tscn")
	)
	center.add_child(gui_btn)

	# TUI mode button (secondary)
	var tui_btn := _make_menu_button("终端模式 (TUI)", Color(0.3, 0.3, 0.35))
	tui_btn.pressed.connect(func() -> void:
		get_tree().change_scene_to_file("res://scenes/main/tui_game.tscn")
	)
	center.add_child(tui_btn)

	# Version
	var version := Label.new()
	version.text = "v0.6.0-dev"
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	version.add_theme_font_size_override("font_size", 12)
	version.add_theme_color_override("font_color", Color(0.35, 0.35, 0.35))
	center.add_child(version)


func _make_menu_button(text: String, color: Color) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(280, 50)
	btn.add_theme_font_size_override("font_size", 20)

	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	btn.add_theme_stylebox_override("normal", style)

	var hover := style.duplicate()
	hover.bg_color = color.lightened(0.15)
	btn.add_theme_stylebox_override("hover", hover)

	var pressed := style.duplicate()
	pressed.bg_color = color.lightened(0.25)
	btn.add_theme_stylebox_override("pressed", pressed)

	btn.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	return btn

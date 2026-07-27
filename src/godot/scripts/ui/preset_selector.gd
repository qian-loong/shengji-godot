## Preset Selector — 预设模式选择界面
## S4-02: 在主菜单显示三种预设（经典/竞技/快速）供玩家选择
extends Control

signal preset_selected(preset: RuleConfig.ConfigSource)

const RuleConfig = preload("res://scripts/core/rule_config.gd")
const ConfigStore = preload("res://scripts/core/config_store.gd")

# 预设卡片配置
const PRESET_CARDS := [
	{
		"source": RuleConfig.ConfigSource.PRESET_CLASSIC,
		"title": "经典模式",
		"subtitle": "标准规则，平衡体验",
		"icon": "📋",
		"color": Color(0.15, 0.50, 0.25),
		"features": [
			"2 副牌，80 分升级",
			"允许甩牌，严格跟牌",
			"王须匹配花色定主",
			"不可跳过 5/10/K"
		]
	},
	{
		"source": RuleConfig.ConfigSource.PRESET_COMPETITIVE,
		"title": "竞技模式",
		"subtitle": "高手对决，严格规则",
		"icon": "🏆",
		"color": Color(0.60, 0.25, 0.10),
		"features": [
			"2 副牌，100 分升级",
			"级牌可定主",
			"王不须匹配花色",
			"不可跳过 10/K"
		]
	},
	{
		"source": RuleConfig.ConfigSource.PRESET_QUICK,
		"title": "快速模式",
		"subtitle": "休闲速战，轻松上手",
		"icon": "⚡",
		"color": Color(0.25, 0.40, 0.65),
		"features": [
			"1 副牌，80 分升级",
			"从 5 开始，升 2 级",
			"禁用甩牌，宽松跟牌",
			"可跳过所有等级"
		]
	}
]


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	# 背景
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.08, 0.12)
	bg.set_anchors_preset(PRESET_FULL_RECT)
	add_child(bg)

	# 主容器
	var main := VBoxContainer.new()
	main.set_anchors_preset(PRESET_FULL_RECT)
	main.set_anchor_and_offset(SIDE_LEFT, 0.0, 40)
	main.set_anchor_and_offset(SIDE_TOP, 0.0, 40)
	main.set_anchor_and_offset(SIDE_RIGHT, 1.0, -40)
	main.set_anchor_and_offset(SIDE_BOTTOM, 1.0, -40)
	main.add_theme_constant_override("separation", 30)
	add_child(main)

	# 标题区域
	var header := VBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	main.add_child(header)

	var title := Label.new()
	title.text = "选择规则预设"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(0.95, 0.88, 0.65))
	header.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "选择一种预设模式开始游戏，或在游戏中自定义规则"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	header.add_child(subtitle)

	# 卡片容器（水平排列）
	var cards_container := HBoxContainer.new()
	cards_container.size_flags_vertical = SIZE_EXPAND_FILL
	cards_container.alignment = BoxContainer.ALIGNMENT_CENTER
	cards_container.add_theme_constant_override("separation", 20)
	main.add_child(cards_container)

	# 创建三个预设卡片
	for preset_data in PRESET_CARDS:
		var card := _create_preset_card(preset_data)
		cards_container.add_child(card)

	# 返回按钮
	var back_btn := Button.new()
	back_btn.text = "返回主菜单"
	back_btn.custom_minimum_size = Vector2(200, 44)
	back_btn.size_flags_horizontal = SIZE_SHRINK_CENTER
	back_btn.add_theme_font_size_override("font_size", 16)
	back_btn.pressed.connect(_on_back_pressed)
	main.add_child(back_btn)


func _create_preset_card(data: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(280, 360)
	card.size_flags_horizontal = SIZE_EXPAND_FILL
	card.mouse_filter = Control.MOUSE_FILTER_PASS

	# 卡片样式
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.14, 0.18)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = data.color
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 20
	style.content_margin_bottom = 20
	card.add_theme_stylebox_override("panel", style)

	# 卡片内容
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 16)
	card.add_child(content)

	# 图标
	var icon := Label.new()
	icon.text = data.icon
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.add_theme_font_size_override("font_size", 48)
	content.add_child(icon)

	# 标题
	var title := Label.new()
	title.text = data.title
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", data.color)
	content.add_child(title)

	# 副标题
	var subtitle := Label.new()
	subtitle.text = data.subtitle
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 13)
	subtitle.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	content.add_child(subtitle)

	# 分隔线
	var separator := HSeparator.new()
	separator.add_theme_constant_override("separation", 1)
	content.add_child(separator)

	# 特性列表
	var features_label := Label.new()
	var features_text := ""
	for feature in data.features:
		features_text += "• " + feature + "\n"
	features_label.text = features_text.strip_edges()
	features_label.add_theme_font_size_override("font_size", 13)
	features_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	features_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(features_label)

	# 弹性空间
	var spacer := Control.new()
	spacer.size_flags_vertical = SIZE_EXPAND_FILL
	content.add_child(spacer)

	# 按钮容器（垂直排列两个按钮）
	var btn_container := VBoxContainer.new()
	btn_container.add_theme_constant_override("separation", 8)
	content.add_child(btn_container)

	# 选择按钮
	var btn := Button.new()
	btn.text = "选择此模式"
	btn.custom_minimum_size = Vector2(0, 46)
	btn.add_theme_font_size_override("font_size", 16)

	var btn_style := StyleBoxFlat.new()
	btn_style.bg_color = data.color
	btn_style.corner_radius_top_left = 8
	btn_style.corner_radius_top_right = 8
	btn_style.corner_radius_bottom_left = 8
	btn_style.corner_radius_bottom_right = 8
	btn.add_theme_stylebox_override("normal", btn_style)

	var btn_hover := btn_style.duplicate()
	btn_hover.bg_color = data.color.lightened(0.15)
	btn.add_theme_stylebox_override("hover", btn_hover)

	var btn_pressed := btn_style.duplicate()
	btn_pressed.bg_color = data.color.lightened(0.25)
	btn.add_theme_stylebox_override("pressed", btn_pressed)

	btn.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	btn.pressed.connect(_on_preset_button_pressed.bind(data.source))
	btn_container.add_child(btn)

	# 规则调整按钮
	var adjust_btn := Button.new()
	adjust_btn.text = "自定义规则"
	adjust_btn.custom_minimum_size = Vector2(0, 38)
	adjust_btn.add_theme_font_size_override("font_size", 14)

	var adjust_style := StyleBoxFlat.new()
	adjust_style.bg_color = Color(0.2, 0.22, 0.26)
	adjust_style.border_width_left = 2
	adjust_style.border_width_top = 2
	adjust_style.border_width_right = 2
	adjust_style.border_width_bottom = 2
	adjust_style.border_color = data.color.darkened(0.3)
	adjust_style.corner_radius_top_left = 8
	adjust_style.corner_radius_top_right = 8
	adjust_style.corner_radius_bottom_left = 8
	adjust_style.corner_radius_bottom_right = 8
	adjust_btn.add_theme_stylebox_override("normal", adjust_style)

	var adjust_hover := adjust_style.duplicate()
	adjust_hover.bg_color = Color(0.25, 0.27, 0.31)
	adjust_btn.add_theme_stylebox_override("hover", adjust_hover)

	var adjust_pressed := adjust_style.duplicate()
	adjust_pressed.bg_color = Color(0.3, 0.32, 0.36)
	adjust_btn.add_theme_stylebox_override("pressed", adjust_pressed)

	adjust_btn.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	adjust_btn.pressed.connect(_on_adjust_button_pressed.bind(data.source))
	btn_container.add_child(adjust_btn)

	return card


func _on_preset_button_pressed(source: RuleConfig.ConfigSource) -> void:
	# 直接开预设：写入内存，开局不读 JSON
	ConfigStore.commit_preset(source)
	get_tree().change_scene_to_file("res://scenes/main/gui_game.tscn")


func _on_adjust_button_pressed(source: RuleConfig.ConfigSource) -> void:
	# 仅传预设 id；自定义页用 ConfigStore.resolve_for_edit
	ProjectSettings.set_setting("game/selected_preset", int(source))
	get_tree().change_scene_to_file("res://scenes/main/room_config.tscn")


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main/main_menu.tscn")

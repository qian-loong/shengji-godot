## Preset Selector — 预设模式选择界面
## S4-02: 在主菜单显示三种预设（经典/竞技/快速）供玩家选择
extends Control

signal preset_selected(preset: RuleConfig.ConfigSource)

const RuleConfig = preload("res://scripts/core/rule_config.gd")
const ConfigStore = preload("res://scripts/core/config_store.gd")
const BackNavigation = preload("res://scripts/ui/back_navigation.gd")

## 自定义标注统一用色（徽章、边框、被改的规则行）
const ACCENT_CUSTOM := Color(0.95, 0.78, 0.35)

# 预设卡片配置
#
# 只放展示用的标题/图标/配色。规则要点**不硬编码**——一律由 _describe_config()
# 从 RuleConfig 实时生成。此前这里写死的文案已与实现漂移出 3 处错误
# （快速写"80 分升级"实为 60、写"从 5 开始"实为 2，竞技写"不可跳过 10/K"实为 5/10/K）。
const PRESET_CARDS := [
	{
		"source": RuleConfig.ConfigSource.PRESET_CLASSIC,
		"title": "经典模式",
		"subtitle": "标准规则，平衡体验",
		"icon": "📋",
		"color": Color(0.15, 0.50, 0.25),
	},
	{
		"source": RuleConfig.ConfigSource.PRESET_COMPETITIVE,
		"title": "竞技模式",
		"subtitle": "高手对决，严格规则",
		"icon": "🏆",
		"color": Color(0.60, 0.25, 0.10),
	},
	{
		"source": RuleConfig.ConfigSource.PRESET_QUICK,
		"title": "快速模式",
		"subtitle": "休闲速战，轻松上手",
		"icon": "⚡",
		"color": Color(0.25, 0.40, 0.65),
	}
]

## 卡片上展示的规则要点。每项 { field, text }——field 用于判断是否被自定义。
## 返回值随配置实时变化，改了配置文案自然跟着变。
static func _describe_config(config: RuleConfig) -> Array:
	var rows: Array = []

	rows.append({
		"field": "deck_count",
		"text": "%d 副牌，%d 分升级" % [config.deck_count, config.upgrade_threshold],
	})

	var step_text := "每次升 %d 级" % config.upgrade_step
	if config.current_rank != Card.Rank.TWO:
		step_text = "从 %s 起，%s" % [Card.rank_symbol(config.current_rank), step_text]
	rows.append({ "field": "upgrade_step", "text": step_text })

	rows.append({
		"field": "allow_dump",
		"text": "%s，%s" % [
			"允许甩牌" if config.allow_dump else "禁用甩牌",
			"严格跟牌" if config.strict_follow_structure else "宽松跟牌",
		],
	})

	rows.append({
		"field": "bid_requires_joker",
		"text": "%s，%s" % [
			"需持王定主" if config.bid_requires_joker else "级牌可定主",
			"王色须匹配" if config.trump_joker_color_match else "王色不限",
		],
	})

	var skip_text := "可跳过所有等级"
	if config.no_skip_enabled and not config.no_skip_ranks.is_empty():
		var names := PackedStringArray()
		for r: int in config.no_skip_ranks:
			names.append(Card.rank_symbol(r))
		skip_text = "不可跳过 %s" % "/".join(names)
	rows.append({ "field": "no_skip_enabled", "text": skip_text })

	return rows


func _ready() -> void:
	_build_ui()
	_install_back_navigation()


## 系统返回键 / Esc / 边缘侧滑都退回主菜单。
## 这里的卡片是纵向静态布局，没有滚动，侧滑不会和别的手势冲突。
func _install_back_navigation() -> void:
	var back := BackNavigation.new()
	back.back_requested.connect(_on_back_pressed)
	add_child(back)


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
	# 该预设是否有已保存的自定义——决定卡片显示原版还是自定义后的规则
	var custom_info := ConfigStore.describe_custom_for_preset(data.source)
	var config: RuleConfig = custom_info["config"]
	var changed_fields: PackedStringArray = custom_info["fields"]
	var has_custom: bool = int(custom_info["count"]) > 0

	var card := PanelContainer.new()
	# 横屏 1280 逻辑宽：3 张卡 + 间距 40 + 边距 80，每张可占 386
	card.custom_minimum_size = Vector2(380, 420)
	card.size_flags_horizontal = SIZE_EXPAND_FILL
	card.mouse_filter = Control.MOUSE_FILTER_PASS

	# 卡片样式（有自定义时边框加粗并转为金色，一眼可辨）
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.14, 0.18)
	var border := 3 if has_custom else 2
	style.border_width_left = border
	style.border_width_top = border
	style.border_width_right = border
	style.border_width_bottom = border
	style.border_color = ACCENT_CUSTOM if has_custom else data.color
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 18
	style.content_margin_bottom = 18
	card.add_theme_stylebox_override("panel", style)

	# 卡片内容
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	card.add_child(content)

	# 顶部徽章行：无自定义时占位保持三张卡对齐
	var badge := Label.new()
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.add_theme_font_size_override("font_size", 15)
	if has_custom:
		badge.text = "✎ 已自定义 %d 项" % custom_info["count"]
		badge.add_theme_color_override("font_color", ACCENT_CUSTOM)
	else:
		badge.text = " "
		badge.add_theme_color_override("font_color", Color(0, 0, 0, 0))
	content.add_child(badge)

	# 图标
	var icon := Label.new()
	icon.text = data.icon
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.add_theme_font_size_override("font_size", 44)
	content.add_child(icon)

	# 标题
	var title := Label.new()
	title.text = data.title
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", data.color)
	content.add_child(title)

	# 副标题
	var subtitle := Label.new()
	subtitle.text = data.subtitle
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 16)
	subtitle.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	content.add_child(subtitle)

	# 分隔线
	var separator := HSeparator.new()
	separator.add_theme_constant_override("separation", 1)
	content.add_child(separator)

	# 规则要点：逐行渲染，被自定义的行标金色 ✎
	var features := VBoxContainer.new()
	features.add_theme_constant_override("separation", 6)
	content.add_child(features)
	for row: Dictionary in _describe_config(config):
		var is_changed: bool = changed_fields.has(row["field"])
		var line := Label.new()
		line.text = "%s %s%s" % [
			"✎" if is_changed else "•",
			row["text"],
			" (原 %s)" % _original_text(data.source, row["field"]) if is_changed else "",
		]
		line.add_theme_font_size_override("font_size", 18)
		line.add_theme_color_override("font_color",
			ACCENT_CUSTOM if is_changed else Color(0.85, 0.85, 0.85))
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		features.add_child(line)

	_finish_card(data, card, content)
	return card


## 取某字段在原版预设下的展示文案，用于「(原 X)」对照
static func _original_text(preset: RuleConfig.ConfigSource, field: String) -> String:
	var pristine := RuleConfig.from_preset(preset)
	for row: Dictionary in _describe_config(pristine):
		if row["field"] == field:
			return row["text"]
	return ""


## 卡片下半部分：弹性空间 + 两个操作按钮
func _finish_card(data: Dictionary, card: PanelContainer, content: VBoxContainer) -> void:
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
	btn.custom_minimum_size = Vector2(0, 56)
	btn.add_theme_font_size_override("font_size", 20)

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
	adjust_btn.custom_minimum_size = Vector2(0, 52)
	adjust_btn.add_theme_font_size_override("font_size", 18)

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

## Room Config — 房间配置界面
## S4-03: 允许房主调整规则细节（副牌数、升级分、甩牌等）
extends Control

signal config_confirmed(config: RuleConfig)
signal config_cancelled()

const RuleConfig = preload("res://scripts/core/rule_config.gd")
const Card = preload("res://scripts/core/card.gd")

# 当前编辑的配置
var _config: RuleConfig = null

# UI 节点引用
var _deck_count_option: OptionButton
var _upgrade_threshold_spin: SpinBox
var _upgrade_step_spin: SpinBox
var _allow_dump_check: CheckBox
var _strict_follow_check: CheckBox
var _four_same_tractor_check: CheckBox
var _tractor_rank_card_check: CheckBox
var _joker_always_trump_check: CheckBox
var _trump_joker_color_check: CheckBox
var _bid_requires_joker_check: CheckBox
var _no_skip_enabled_check: CheckBox
var _preset_label: Label


func _ready() -> void:
	_build_ui()


## 加载配置（从预设或自定义）
func load_config(config: RuleConfig) -> void:
	_config = config.duplicate_editable() if config.is_locked() else config
	_update_ui_from_config()


## 从预设初始化
func load_preset(source: RuleConfig.ConfigSource) -> void:
	_config = RuleConfig.from_preset(source)
	_update_ui_from_config()


func _build_ui() -> void:
	# 背景
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.08, 0.12)
	bg.set_anchors_preset(PRESET_FULL_RECT)
	add_child(bg)

	# 主滚动容器
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(PRESET_FULL_RECT)
	scroll.set_anchor_and_offset(SIDE_LEFT, 0.0, 40)
	scroll.set_anchor_and_offset(SIDE_TOP, 0.0, 40)
	scroll.set_anchor_and_offset(SIDE_RIGHT, 1.0, -40)
	scroll.set_anchor_and_offset(SIDE_BOTTOM, 1.0, -40)
	add_child(scroll)

	# 内容容器
	var main := VBoxContainer.new()
	main.size_flags_horizontal = SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 24)
	scroll.add_child(main)

	# 标题区域
	var header := VBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	main.add_child(header)

	var title := Label.new()
	title.text = "房间规则配置"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(0.95, 0.88, 0.65))
	header.add_child(title)

	_preset_label = Label.new()
	_preset_label.text = "基于：自定义配置"
	_preset_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_preset_label.add_theme_font_size_override("font_size", 14)
	_preset_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	header.add_child(_preset_label)

	# === 牌组配置 ===
	var deck_section := _create_section("牌组配置", Color(0.15, 0.50, 0.25))
	main.add_child(deck_section)

	_deck_count_option = _add_option_row(deck_section, "副牌数", ["1 副牌", "2 副牌"])
	_add_info_label(deck_section, "• 1 副牌：12 张手牌，6 张底牌\n• 2 副牌：25 张手牌，8 张底牌")

	# === 升级规则 ===
	var upgrade_section := _create_section("升级规则", Color(0.60, 0.25, 0.10))
	main.add_child(upgrade_section)

	_upgrade_threshold_spin = _add_spin_row(upgrade_section, "升级分数", 40, 200, 10)
	_upgrade_step_spin = _add_spin_row(upgrade_section, "升级步数", 1, 3, 1)
	_no_skip_enabled_check = _add_check_row(upgrade_section, "启用必打等级")
	_add_info_label(upgrade_section, "• 80 分：标准模式\n• 100 分：竞技模式\n• 必打等级：5/10/K 不可跳过")

	# === 出牌规则 ===
	var play_section := _create_section("出牌规则", Color(0.25, 0.40, 0.65))
	main.add_child(play_section)

	_allow_dump_check = _add_check_row(play_section, "允许甩牌")
	_strict_follow_check = _add_check_row(play_section, "严格跟牌结构")
	_four_same_tractor_check = _add_check_row(play_section, "四张相同算拖拉机")
	_tractor_rank_card_check = _add_check_row(play_section, "拖拉机允许级牌")
	_add_info_label(play_section, "• 甩牌：一次打出多张牌\n• 严格跟牌：必须跟相同结构（对子、拖拉机）\n• 拖拉机：连续对子")

	# === 定主规则 ===
	var trump_section := _create_section("定主规则", Color(0.50, 0.30, 0.50))
	main.add_child(trump_section)

	_joker_always_trump_check = _add_check_row(trump_section, "王始终算主牌")
	_trump_joker_color_check = _add_check_row(trump_section, "王须匹配花色定主")
	_bid_requires_joker_check = _add_check_row(trump_section, "亮主必须有王")
	_add_info_label(trump_section, "• 王须匹配花色：红桃定主需红王\n• 亮主必须有王：首局亮主规则")

	# 底部按钮
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	main.add_child(buttons)

	var cancel_btn := _create_button("取消", Color(0.4, 0.4, 0.4))
	cancel_btn.custom_minimum_size = Vector2(160, 48)
	cancel_btn.pressed.connect(_on_cancel_pressed)
	buttons.add_child(cancel_btn)

	var confirm_btn := _create_button("确认配置", Color(0.15, 0.50, 0.25))
	confirm_btn.custom_minimum_size = Vector2(200, 48)
	confirm_btn.pressed.connect(_on_confirm_pressed)
	buttons.add_child(confirm_btn)

	var reset_btn := _create_button("恢复默认", Color(0.60, 0.25, 0.10))
	reset_btn.custom_minimum_size = Vector2(160, 48)
	reset_btn.pressed.connect(_on_reset_pressed)
	buttons.add_child(reset_btn)


## 创建分区
func _create_section(title_text: String, color: Color) -> PanelContainer:
	var panel := PanelContainer.new()

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.14, 0.18)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = color
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", style)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	panel.add_child(content)

	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", color)
	content.add_child(title)

	var separator := HSeparator.new()
	content.add_child(separator)

	return panel


## 添加选项行
func _add_option_row(parent: PanelContainer, label_text: String, options: PackedStringArray) -> OptionButton:
	var container := parent.get_child(0) as VBoxContainer

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	container.add_child(row)

	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	row.add_child(label)

	var option := OptionButton.new()
	option.custom_minimum_size = Vector2(160, 36)
	for opt in options:
		option.add_item(opt)
	row.add_child(option)

	return option


## 添加数值调节行
func _add_spin_row(parent: PanelContainer, label_text: String, min_val: float, max_val: float, step: float) -> SpinBox:
	var container := parent.get_child(0) as VBoxContainer

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	container.add_child(row)

	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	row.add_child(label)

	var spin := SpinBox.new()
	spin.custom_minimum_size = Vector2(120, 36)
	spin.min_value = min_val
	spin.max_value = max_val
	spin.step = step
	spin.value = min_val
	row.add_child(spin)

	return spin


## 添加复选框行
func _add_check_row(parent: PanelContainer, label_text: String) -> CheckBox:
	var container := parent.get_child(0) as VBoxContainer

	var check := CheckBox.new()
	check.text = label_text
	check.add_theme_font_size_override("font_size", 15)
	check.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	container.add_child(check)

	return check


## 添加信息标签
func _add_info_label(parent: PanelContainer, info_text: String) -> void:
	var container := parent.get_child(0) as VBoxContainer

	var label := Label.new()
	label.text = info_text
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	container.add_child(label)


## 创建按钮
func _create_button(text: String, color: Color) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 16)

	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	btn.add_theme_stylebox_override("normal", style)

	var hover := style.duplicate()
	hover.bg_color = color.lightened(0.15)
	btn.add_theme_stylebox_override("hover", hover)

	var pressed := style.duplicate()
	pressed.bg_color = color.lightened(0.25)
	btn.add_theme_stylebox_override("pressed", pressed)

	btn.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))

	return btn


## 从配置更新 UI
func _update_ui_from_config() -> void:
	if not _config:
		return

	# 更新预设标签
	var preset_name := ""
	match _config.source:
		RuleConfig.ConfigSource.PRESET_CLASSIC:
			preset_name = "经典模式"
		RuleConfig.ConfigSource.PRESET_COMPETITIVE:
			preset_name = "竞技模式"
		RuleConfig.ConfigSource.PRESET_QUICK:
			preset_name = "快速模式"
		_:
			preset_name = "自定义配置"

	_preset_label.text = "基于：" + preset_name
	if _config.modified_fields.size() > 0:
		_preset_label.text += " (已修改)"

	# 更新控件值
	_deck_count_option.selected = _config.deck_count - 1
	_upgrade_threshold_spin.value = _config.upgrade_threshold
	_upgrade_step_spin.value = _config.upgrade_step
	_allow_dump_check.button_pressed = _config.allow_dump
	_strict_follow_check.button_pressed = _config.strict_follow_structure
	_four_same_tractor_check.button_pressed = _config.four_same_is_tractor
	_tractor_rank_card_check.button_pressed = _config.tractor_allow_rank_card
	_joker_always_trump_check.button_pressed = _config.joker_always_trump
	_trump_joker_color_check.button_pressed = _config.trump_joker_color_match
	_bid_requires_joker_check.button_pressed = _config.bid_requires_joker
	_no_skip_enabled_check.button_pressed = _config.no_skip_enabled


## 从 UI 更新配置
func _update_config_from_ui() -> void:
	if not _config:
		return

	_config.deck_count = _deck_count_option.selected + 1
	_config.upgrade_threshold = int(_upgrade_threshold_spin.value)
	_config.upgrade_step = int(_upgrade_step_spin.value)
	_config.allow_dump = _allow_dump_check.button_pressed
	_config.strict_follow_structure = _strict_follow_check.button_pressed
	_config.four_same_is_tractor = _four_same_tractor_check.button_pressed
	_config.tractor_allow_rank_card = _tractor_rank_card_check.button_pressed
	_config.joker_always_trump = _joker_always_trump_check.button_pressed
	_config.trump_joker_color_match = _trump_joker_color_check.button_pressed
	_config.bid_requires_joker = _bid_requires_joker_check.button_pressed
	_config.no_skip_enabled = _no_skip_enabled_check.button_pressed


func _on_confirm_pressed() -> void:
	_update_config_from_ui()

	# 验证配置
	var errors := _config.validate()
	if errors.size() > 0:
		push_error("配置验证失败: " + str(errors))
		# TODO: 显示错误提示对话框
		return

	# 保存配置并跳转到游戏场景
	ProjectSettings.set_setting("game/selected_preset", int(_config.source))
	ProjectSettings.set_setting("game/custom_config", _config)
	get_tree().change_scene_to_file("res://scenes/main/gui_game.tscn")


func _on_cancel_pressed() -> void:
	# 返回主菜单
	get_tree().change_scene_to_file("res://scenes/main/main_menu.tscn")


func _on_reset_pressed() -> void:
	if _config and _config.source != RuleConfig.ConfigSource.CUSTOM:
		# 恢复到原始预设
		_config = RuleConfig.from_preset(_config.source)
		_update_ui_from_config()
	else:
		# 恢复到经典模式
		_config = RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_CLASSIC)
		_update_ui_from_config()

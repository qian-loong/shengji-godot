## Room Config — 房间配置界面
## S4-03: 允许房主调整规则细节（副牌数、升级分、甩牌等）
## 确认后：内存 ConfigStore.current + 磁盘 user://custom_rule_config.json
## 开局只读内存，不在进游戏时再读 JSON
extends Control

signal config_confirmed(config: RuleConfig)
signal config_cancelled()

const RuleConfig = preload("res://scripts/core/rule_config.gd")
const ConfigStore = preload("res://scripts/core/config_store.gd")
const Card = preload("res://scripts/core/card.gd")
const BackNavigation = preload("res://scripts/ui/back_navigation.gd")

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
	_connect_change_signals()
	_install_back_navigation()

	# 从预设选择界面：内存同预设 → 磁盘同预设 → 预设默认
	var preset_id: int = int(ProjectSettings.get_setting("game/selected_preset", -1))
	ProjectSettings.set_setting("game/selected_preset", -1)

	if preset_id >= 0 and preset_id <= int(RuleConfig.ConfigSource.PRESET_QUICK):
		load_config(ConfigStore.resolve_for_edit(preset_id as RuleConfig.ConfigSource))
	else:
		# 主菜单的「自定义规则」直接跳到这里，不带预设 id。此前这种情况下
		# 压根不加载配置，页面显示的是控件出厂值（1 副牌 / 门槛 40 / 开关全关），
		# 既不对应任何预设，点确认还会在 _config.validate() 上空引用崩溃。
		load_config(_default_config_for_edit())


## 未指定预设时的编辑初值：优先沿用内存里正在生效的配置，冷启动则以经典预设为底
static func _default_config_for_edit() -> RuleConfig:
	if ConfigStore.current != null:
		return ConfigStore.current.duplicate_editable()
	return ConfigStore.resolve_for_edit(RuleConfig.ConfigSource.PRESET_CLASSIC)


## 系统返回键 / Esc / 边缘侧滑都等同于「取消」——丢弃未确认的改动回预设页。
## 与"取消"按钮走同一条路径，语义一致。
func _install_back_navigation() -> void:
	var back := BackNavigation.new()
	back.back_requested.connect(_on_cancel_pressed)
	add_child(back)


## 任一控件变化都实时刷新 ✎ 标记与顶部摘要
func _connect_change_signals() -> void:
	_deck_count_option.item_selected.connect(func(_i: int) -> void: _refresh_change_marks())
	_upgrade_threshold_spin.value_changed.connect(func(_v: float) -> void: _refresh_change_marks())
	_upgrade_step_spin.value_changed.connect(func(_v: float) -> void: _refresh_change_marks())
	for check: CheckBox in [
		_allow_dump_check, _strict_follow_check, _four_same_tractor_check,
		_tractor_rank_card_check, _joker_always_trump_check,
		_trump_joker_color_check, _bid_requires_joker_check, _no_skip_enabled_check,
	]:
		check.toggled.connect(func(_on: bool) -> void: _refresh_change_marks())


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

	# 主容器（横屏两栏布局，内容一屏放得下，无需滚动）
	var main := VBoxContainer.new()
	main.set_anchors_preset(PRESET_FULL_RECT)
	main.set_anchor_and_offset(SIDE_LEFT, 0.0, 40)
	main.set_anchor_and_offset(SIDE_TOP, 0.0, 24)
	main.set_anchor_and_offset(SIDE_RIGHT, 1.0, -40)
	main.set_anchor_and_offset(SIDE_BOTTOM, 1.0, -24)
	main.add_theme_constant_override("separation", 16)
	add_child(main)

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

	# 两栏并排放进滚动区。11 个配置项撑出约 644 逻辑px，加上标题与按钮行
	# 需要 797px，而视口只有 720px——不滚动的话右栏底部和按钮行都会被挤出屏幕。
	#
	# 按钮行**留在滚动区外**：确认/取消必须始终可见，否则用户得先滚到底才能提交。
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.follow_focus = true
	# 手指移动超过这个距离才判定为滚动，之内仍算点击，避免点开关时轻微抖动被吞掉
	scroll.scroll_deadzone = 24
	main.add_child(scroll)

	var columns := HBoxContainer.new()
	columns.size_flags_horizontal = SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 24)
	scroll.add_child(columns)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = SIZE_EXPAND_FILL
	left.size_flags_vertical = SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 16)
	columns.add_child(left)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = SIZE_EXPAND_FILL
	right.size_flags_vertical = SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 16)
	columns.add_child(right)

	# === 左栏：牌组与计分 ===
	var deck_section := _create_section("牌组与计分", Color(0.15, 0.50, 0.25))
	left.add_child(deck_section)

	_deck_count_option = _add_option_row(
		deck_section, "副牌数", ["1 副牌", "2 副牌"], "deck_count")
	_upgrade_threshold_spin = _add_spin_row(
		deck_section, "升级门槛", 40, 250, 10, "upgrade_threshold")
	_upgrade_step_spin = _add_spin_row(
		deck_section, "升级步数", 1, 3, 1, "upgrade_step")

	# === 左栏：必打级 ===
	var skip_section := _create_section("必打等级", Color(0.60, 0.25, 0.10))
	left.add_child(skip_section)

	_no_skip_enabled_check = _add_check_row(
		skip_section, "启用必打等级（5/10/K）", "no_skip_enabled")
	_add_info_label(skip_section, "开启后多级升级不可跨越 5/10/K")

	# === 右栏：出牌规则 ===
	var play_section := _create_section("出牌规则", Color(0.25, 0.40, 0.65))
	right.add_child(play_section)

	_allow_dump_check = _add_check_row(play_section, "允许甩牌", "allow_dump")
	_strict_follow_check = _add_check_row(
		play_section, "严格跟牌结构", "strict_follow_structure")
	_four_same_tractor_check = _add_check_row(
		play_section, "四张同点算拖拉机", "four_same_is_tractor")
	_tractor_rank_card_check = _add_check_row(
		play_section, "级牌可参与拖拉机", "tractor_allow_rank_card")

	# === 右栏：定主规则 ===
	var trump_section := _create_section("定主规则", Color(0.50, 0.30, 0.50))
	right.add_child(trump_section)

	_joker_always_trump_check = _add_check_row(
		trump_section, "王始终算主牌", "joker_always_trump")
	_trump_joker_color_check = _add_check_row(
		trump_section, "王色须匹配级牌花色", "trump_joker_color_match")
	_bid_requires_joker_check = _add_check_row(
		trump_section, "亮主必须持有王", "bid_requires_joker")

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


## 配置行的统一高度。横屏 1280×720 逻辑分辨率在手机上放大 1.5~1.9 倍，
## 56 逻辑px ≈ 84~105 物理px，明显高于 48dp 可点区域下限。
const ROW_HEIGHT := 56

## 自定义标注用色，与预设卡片保持一致
const ACCENT_CUSTOM := Color(0.95, 0.78, 0.35)

## 记录每个字段对应的标记 Label，供 _refresh_change_marks() 更新
var _change_marks: Dictionary = {}

## 正在用配置回填控件。期间控件发出的 value_changed / toggled 是程序赋值的回声，
## 不是用户操作，必须忽略——SpinBox 在代码赋值时同样会发 value_changed，而那一刻
## 后面的 CheckBox 还停在默认 false，回调会把这些默认值当成用户输入写回 _config，
## 一次性抹掉预设里 8 个为 true 的开关。
var _loading: bool = false


## 造一个统一规格的配置行：左侧标签（含自定义标记位）+ 右侧控件
##
## 行的外层是一个 Control 壳子而不是直接用 HBoxContainer——BoxContainer 会强制
## 排布所有子节点，锚点在它里面不生效，覆盖整行的命中按钮必须多包一层才放得住。
func _make_row(parent: PanelContainer, label_text: String, field: String) -> HBoxContainer:
	var container := parent.get_child(0) as VBoxContainer

	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(wrap)

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(row)

	# 自定义标记位：始终占位，避免改动时行宽跳动
	var mark := Label.new()
	mark.custom_minimum_size = Vector2(20, 0)
	mark.add_theme_font_size_override("font_size", 18)
	mark.add_theme_color_override("font_color", ACCENT_CUSTOM)
	mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(mark)
	if not field.is_empty():
		_change_marks[field] = mark

	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(0.88, 0.88, 0.88))
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)

	return row


## 取配置行的外层壳子，用于叠加覆盖整行的命中按钮
static func _row_wrap(row: HBoxContainer) -> Control:
	return row.get_parent() as Control


## 添加选项行
func _add_option_row(parent: PanelContainer, label_text: String, options: PackedStringArray, field: String = "") -> OptionButton:
	var row := _make_row(parent, label_text, field)

	var option := OptionButton.new()
	option.custom_minimum_size = Vector2(150, ROW_HEIGHT - 8)
	option.add_theme_font_size_override("font_size", 18)
	option.mouse_filter = Control.MOUSE_FILTER_PASS
	for opt in options:
		option.add_item(opt)
	row.add_child(option)

	return option


## 添加数值调节行
func _add_spin_row(parent: PanelContainer, label_text: String, min_val: float, max_val: float, step: float, field: String = "") -> SpinBox:
	var row := _make_row(parent, label_text, field)

	var spin := SpinBox.new()
	spin.custom_minimum_size = Vector2(130, ROW_HEIGHT - 8)
	spin.add_theme_font_size_override("font_size", 18)
	spin.mouse_filter = Control.MOUSE_FILTER_PASS
	spin.min_value = min_val
	spin.max_value = max_val
	spin.step = step
	spin.value = min_val
	row.add_child(spin)

	return spin


## 添加开关行。
##
## CheckBox 本身只有那个小方框能点，所以在整行底下垫一个透明按钮，
## 点标签文字同样能切换开关，把可点区域扩到整行宽度。
func _add_check_row(parent: PanelContainer, label_text: String, field: String = "") -> CheckBox:
	var row := _make_row(parent, label_text, field)

	var check := CheckBox.new()
	check.custom_minimum_size = Vector2(64, ROW_HEIGHT - 8)
	check.add_theme_font_size_override("font_size", 18)
	check.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(check)

	var hit := Button.new()
	hit.flat = true
	hit.set_anchors_preset(Control.PRESET_FULL_RECT)
	hit.mouse_filter = Control.MOUSE_FILTER_PASS
	hit.focus_mode = Control.FOCUS_NONE
	hit.pressed.connect(func() -> void: check.button_pressed = not check.button_pressed)

	# 垫在 row 下层：row 与其中的 Label 都是 IGNORE，点击会穿透到这里；
	# 只有 CheckBox 自己会拦下落在方框上的点击。
	var wrap := _row_wrap(row)
	wrap.add_child(hit)
	wrap.move_child(hit, 0)

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

	_loading = true

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

	_loading = false

	# 顶部摘要由 _refresh_change_marks() 统一渲染（含"已改 N 项"）
	_refresh_change_marks()


## 从 UI 更新配置
func _update_config_from_ui() -> void:
	if not _config:
		return

	_config.deck_count = _deck_count_option.selected + 1

	# 门槛必须与升级表同步改，否则两者失配会造出矛盾配置
	# （门槛 100 配 80 分表时，攻方 86 分会被表判"赢"、被门槛判"没下庄"）
	var new_threshold := int(_upgrade_threshold_spin.value)
	if new_threshold != _config.upgrade_threshold:
		_config.set_upgrade_threshold(new_threshold)

	_config.upgrade_step = int(_upgrade_step_spin.value)
	_config.allow_dump = _allow_dump_check.button_pressed
	_config.strict_follow_structure = _strict_follow_check.button_pressed
	_config.four_same_is_tractor = _four_same_tractor_check.button_pressed
	_config.tractor_allow_rank_card = _tractor_rank_card_check.button_pressed
	_config.joker_always_trump = _joker_always_trump_check.button_pressed
	_config.trump_joker_color_match = _trump_joker_color_check.button_pressed
	_config.bid_requires_joker = _bid_requires_joker_check.button_pressed
	_config.no_skip_enabled = _no_skip_enabled_check.button_pressed
	# 必打级列表跟随开关，避免"开启了但列表为空"的无效状态
	if _config.no_skip_enabled and _config.no_skip_ranks.is_empty():
		_config.no_skip_ranks = [Card.Rank.FIVE, Card.Rank.TEN, Card.Rank.KING]


## 刷新每行的自定义标记与顶部摘要
func _refresh_change_marks() -> void:
	if _loading or not _config:
		return

	_update_config_from_ui()

	var changed := 0
	for field: String in _change_marks:
		var is_changed := ConfigStore.is_field_customized(_config, field)
		var mark := _change_marks[field] as Label
		mark.text = "✎" if is_changed else ""
		if is_changed:
			changed += 1

	if _preset_label:
		var base_name := _preset_display_name(_config.base_preset)
		if changed > 0:
			_preset_label.text = "基于：%s  ·  ✎ 已改 %d 项" % [base_name, changed]
			_preset_label.add_theme_color_override("font_color", ACCENT_CUSTOM)
		else:
			_preset_label.text = "基于：%s（原版）" % base_name
			_preset_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))


static func _preset_display_name(preset: int) -> String:
	match preset:
		RuleConfig.ConfigSource.PRESET_CLASSIC: return "经典模式"
		RuleConfig.ConfigSource.PRESET_COMPETITIVE: return "竞技模式"
		RuleConfig.ConfigSource.PRESET_QUICK: return "快速模式"
		_: return "自定义"


func _on_confirm_pressed() -> void:
	_update_config_from_ui()

	# 验证配置
	var errors := _config.validate()
	if errors.size() > 0:
		push_error("配置验证失败: " + str(errors))
		# TODO: 显示错误提示对话框
		return

	# 内存 + 磁盘；开局只读 ConfigStore.current
	if not ConfigStore.commit_custom(_config):
		push_error("保存自定义配置失败")
		# TODO: 显示错误提示对话框
		return

	get_tree().change_scene_to_file("res://scenes/main/gui_game.tscn")


func _on_cancel_pressed() -> void:
	# 返回预设选择页（用户是从那里进来的），而非跳回最顶层主菜单
	get_tree().change_scene_to_file("res://scenes/main/preset_selector.tscn")


func _on_reset_pressed() -> void:
	var base := _config.base_preset if _config else RuleConfig.ConfigSource.PRESET_CLASSIC
	if base == RuleConfig.ConfigSource.CUSTOM:
		base = RuleConfig.ConfigSource.PRESET_CLASSIC
	_config = RuleConfig.from_preset(base)
	_update_ui_from_config()
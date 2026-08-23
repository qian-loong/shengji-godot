## RoomConfig 自定义页的加载与布局回归
##
## 回归的 bug（2026-07-30）：进入自定义页时，_update_ui_from_config() 给 SpinBox
## 赋值会同步触发 value_changed，而那一刻后面的 CheckBox 还停在默认 false，
## 回调把这些默认值当成用户输入写回 _config，一次性抹掉经典预设里 8 个为 true
## 的开关。表现为预设卡片说「已自定义 1 项」、进去却显示「已改 8 项」，
## 且此时点确认会把走样的规则存盘并开局。
extends GutTest

const RoomConfig = preload("res://scripts/ui/room_config.gd")
const RuleConfig = preload("res://scripts/core/rule_config.gd")
const ConfigStore = preload("res://scripts/core/config_store.gd")

## 逻辑分辨率，与 project.godot 的 viewport 尺寸一致
const VIEWPORT_SIZE := Vector2(1280, 720)

var _disk_backup: String = ""
var _had_backup: bool = false


func before_all() -> void:
	# 测试会写 user:// 下的真实存档，先备份，跑完还原，避免吃掉玩家配置
	if FileAccess.file_exists(ConfigStore.SAVE_PATH):
		_disk_backup = FileAccess.get_file_as_string(ConfigStore.SAVE_PATH)
		_had_backup = true


func after_all() -> void:
	ConfigStore.current = null
	if _had_backup:
		var file := FileAccess.open(ConfigStore.SAVE_PATH, FileAccess.WRITE)
		file.store_string(_disk_backup)
		file.close()
	elif FileAccess.file_exists(ConfigStore.SAVE_PATH):
		DirAccess.remove_absolute(ConfigStore.SAVE_PATH)


func before_each() -> void:
	ConfigStore.current = null
	if FileAccess.file_exists(ConfigStore.SAVE_PATH):
		DirAccess.remove_absolute(ConfigStore.SAVE_PATH)


## 按「从预设卡片点自定义规则」的路径打开配置页
func _open_page(preset: RuleConfig.ConfigSource) -> Control:
	ProjectSettings.set_setting("game/selected_preset", int(preset))
	var page := RoomConfig.new()
	page.size = VIEWPORT_SIZE
	add_child_autofree(page)
	await wait_frames(2)
	return page


# ============================================================
# 加载不得篡改配置
# ============================================================

func test_opening_classic_preserves_all_switches() -> void:
	var page := await _open_page(RuleConfig.ConfigSource.PRESET_CLASSIC)

	var base := RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_CLASSIC)
	var live: RuleConfig = page._config

	for field: String in ConfigStore.TRACKED_FIELDS:
		assert_eq(live.get(field), base.get(field),
			"字段 %s 在加载后被篡改" % field)


func test_opening_each_preset_reports_zero_changes() -> void:
	for preset: int in [
		RuleConfig.ConfigSource.PRESET_CLASSIC,
		RuleConfig.ConfigSource.PRESET_COMPETITIVE,
		RuleConfig.ConfigSource.PRESET_QUICK,
	]:
		ConfigStore.current = null
		var page := await _open_page(preset as RuleConfig.ConfigSource)

		var changed := 0
		for field: String in page._change_marks:
			if ConfigStore.is_field_customized(page._config, field):
				changed += 1

		assert_eq(changed, 0,
			"刚打开的原版预设 %d 不应有任何改动标记" % preset)
		assert_string_contains(page._preset_label.text, "原版")

		page.queue_free()
		await wait_frames(1)


func test_switch_states_match_preset_after_load() -> void:
	var page := await _open_page(RuleConfig.ConfigSource.PRESET_CLASSIC)
	var base := RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_CLASSIC)

	# 经典预设这 8 项全为 true，正是当初被集体重置为 false 的那批
	assert_eq(page._allow_dump_check.button_pressed, base.allow_dump)
	assert_eq(page._strict_follow_check.button_pressed, base.strict_follow_structure)
	assert_eq(page._four_same_tractor_check.button_pressed, base.four_same_is_tractor)
	assert_eq(page._tractor_rank_card_check.button_pressed, base.tractor_allow_rank_card)
	assert_eq(page._joker_always_trump_check.button_pressed, base.joker_always_trump)
	assert_eq(page._trump_joker_color_check.button_pressed, base.trump_joker_color_match)
	assert_eq(page._bid_requires_joker_check.button_pressed, base.bid_requires_joker)
	assert_eq(page._no_skip_enabled_check.button_pressed, base.no_skip_enabled)


func test_saved_custom_survives_reopen() -> void:
	# 存一份「经典 + 升级步数 2」，重开配置页时该值不能被打回预设默认
	var saved := RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_CLASSIC)
	saved.upgrade_step = 2
	ConfigStore.commit_custom(saved)
	ConfigStore.current = null

	var page := await _open_page(RuleConfig.ConfigSource.PRESET_CLASSIC)

	assert_eq(page._config.upgrade_step, 2, "已保存的自定义值不应被加载过程重置")
	assert_eq(int(page._upgrade_step_spin.value), 2, "控件也应显示已保存的值")


func test_reopen_reports_same_change_count_as_card() -> void:
	# 卡片说几项，进去就该显示几项——两处计数曾经一个说 1、一个说 8
	var saved := RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_CLASSIC)
	saved.upgrade_step = 2
	ConfigStore.commit_custom(saved)
	ConfigStore.current = null

	var card_count: int = ConfigStore.describe_custom_for_preset(
		RuleConfig.ConfigSource.PRESET_CLASSIC)["count"]

	var page := await _open_page(RuleConfig.ConfigSource.PRESET_CLASSIC)
	var page_count := 0
	for field: String in page._change_marks:
		if ConfigStore.is_field_customized(page._config, field):
			page_count += 1

	assert_eq(page_count, card_count,
		"预设卡片与自定义页对「改了几项」的判断必须一致")


func test_user_edit_is_still_tracked() -> void:
	# 守卫不能把真实的用户操作也一并屏蔽掉
	var page := await _open_page(RuleConfig.ConfigSource.PRESET_CLASSIC)

	page._allow_dump_check.button_pressed = false
	await wait_frames(1)

	assert_false(page._config.allow_dump, "用户关掉开关应写入配置")
	assert_eq(page._change_marks["allow_dump"].text, "✎", "该行应标记为已改")
	assert_string_contains(page._preset_label.text, "已改 1 项")


# ============================================================
# 布局：内容可滚动，操作按钮常驻可见
# ============================================================

func test_action_buttons_stay_within_viewport() -> void:
	# 原先四个分区撑出 797px 高，把按钮行顶到了屏幕外，
	# 手机上既滚不动也点不到确认/取消
	var page := await _open_page(RuleConfig.ConfigSource.PRESET_CLASSIC)

	var buttons := _find_action_row(page)
	assert_not_null(buttons, "应存在底部按钮行")

	var bottom: float = buttons.global_position.y + buttons.size.y
	assert_lte(bottom, VIEWPORT_SIZE.y,
		"按钮行底部 %.0f 超出了视口高度 %.0f" % [bottom, VIEWPORT_SIZE.y])
	assert_gte(buttons.global_position.y, 0.0, "按钮行不应被顶出屏幕上方")


func test_config_area_is_scrollable() -> void:
	var page := await _open_page(RuleConfig.ConfigSource.PRESET_CLASSIC)

	var scroll := _find_scroll(page)
	assert_not_null(scroll, "配置区应放在 ScrollContainer 里")
	assert_eq(scroll.horizontal_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED,
		"横向滚动须关闭，否则会和侧滑返回抢手势")

	var content := scroll.get_child(0) as Control
	assert_gt(content.get_combined_minimum_size().y, scroll.size.y,
		"内容确实高于可视区，滚动才有意义")


func test_action_buttons_are_outside_scroll_area() -> void:
	# 按钮跟着滚动的话，用户得先滚到底才能提交
	var page := await _open_page(RuleConfig.ConfigSource.PRESET_CLASSIC)

	var scroll := _find_scroll(page)
	var buttons := _find_action_row(page)
	assert_false(scroll.is_ancestor_of(buttons),
		"确认/取消按钮不能放在滚动区内")


func test_interactive_controls_let_touch_reach_scroll() -> void:
	# CheckBox 默认 mouse_filter=STOP 会截断触摸事件冒泡，
	# ScrollContainer 收不到 ScreenTouch 就无法开始拖拽滚动
	var page := await _open_page(RuleConfig.ConfigSource.PRESET_CLASSIC)

	var blocking: Array[String] = []
	for node in _walk(_find_scroll(page)):
		if node is CheckBox or node is SpinBox or node is OptionButton:
			var ctrl := node as Control
			if ctrl.mouse_filter == Control.MOUSE_FILTER_STOP:
				blocking.append(ctrl.get_class())

	assert_eq(blocking.size(), 0,
		"这些控件会挡住滚动手势: %s" % ", ".join(blocking))


func test_switch_rows_are_clickable_across_full_width() -> void:
	# 只有 64px 宽的小方框在手机上太难点，整行都应可点
	var page := await _open_page(RuleConfig.ConfigSource.PRESET_CLASSIC)

	var rows := 0
	for node in _walk(page):
		if not (node is CheckBox):
			continue
		var wrap := (node as CheckBox).get_parent().get_parent() as Control
		assert_not_null(wrap, "开关行应有外层壳子承载命中按钮")

		var hit: Button = null
		for child in wrap.get_children():
			if child is Button:
				hit = child as Button
				break
		assert_not_null(hit, "开关行缺少覆盖整行的命中按钮")
		assert_almost_eq(hit.size.x, wrap.size.x, 1.0, "命中按钮未铺满行宽")
		assert_almost_eq(hit.size.y, wrap.size.y, 1.0, "命中按钮未铺满行高")
		rows += 1

	assert_eq(rows, 8, "应有 8 个开关行")


func test_row_hit_button_toggles_the_switch() -> void:
	var page := await _open_page(RuleConfig.ConfigSource.PRESET_CLASSIC)

	var check := page._allow_dump_check as CheckBox
	var wrap := check.get_parent().get_parent() as Control
	var hit: Button = null
	for child in wrap.get_children():
		if child is Button:
			hit = child as Button
			break

	var before := check.button_pressed
	hit.pressed.emit()
	await wait_frames(1)

	assert_ne(check.button_pressed, before, "点整行应切换开关")


# ============================================================
# 返回导航
# ============================================================

func test_page_installs_back_navigation() -> void:
	# quit_on_go_back=false，界面不自己处理返回键就会把玩家困死在这一屏
	var page := await _open_page(RuleConfig.ConfigSource.PRESET_CLASSIC)

	var found := false
	for child in page.get_children():
		if child.get_script() == preload("res://scripts/ui/back_navigation.gd"):
			found = true
			break
	assert_true(found, "配置页应挂载 BackNavigation")


# ============================================================
# 无预设上下文时的兜底
# ============================================================

func test_page_without_preset_id_still_has_config() -> void:
	# 主菜单曾有个「自定义规则」按钮直通本页且不带预设 id，
	# 结果 _config 为 null、界面显示控件出厂值、点确认直接空引用崩溃。
	# 入口已移除，但这里仍须兜底，不能靠"没人这么进"来保证不崩。
	ConfigStore.current = null
	ProjectSettings.set_setting("game/selected_preset", -1)

	var page := RoomConfig.new()
	page.size = VIEWPORT_SIZE
	add_child_autofree(page)
	await wait_frames(2)

	assert_not_null(page._config, "没有预设 id 也必须有一份可编辑配置")
	assert_eq(page._config.base_preset, RuleConfig.ConfigSource.PRESET_CLASSIC,
		"冷启动无上下文时以经典预设为底")


func test_page_without_preset_id_follows_current_config() -> void:
	# 已经选过快速模式再进配置页，应接着改快速模式而不是跳回经典
	ConfigStore.commit_preset(RuleConfig.ConfigSource.PRESET_QUICK)
	ProjectSettings.set_setting("game/selected_preset", -1)

	var page := RoomConfig.new()
	page.size = VIEWPORT_SIZE
	add_child_autofree(page)
	await wait_frames(2)

	assert_eq(page._config.base_preset, RuleConfig.ConfigSource.PRESET_QUICK,
		"应沿用内存里正在生效的配置")


func test_page_without_preset_id_does_not_alias_current() -> void:
	# 兜底不能直接引用 ConfigStore.current，否则编辑页的改动会
	# 在用户点确认之前就泄漏进正在生效的配置
	ConfigStore.commit_preset(RuleConfig.ConfigSource.PRESET_CLASSIC)
	ProjectSettings.set_setting("game/selected_preset", -1)

	var page := RoomConfig.new()
	page.size = VIEWPORT_SIZE
	add_child_autofree(page)
	await wait_frames(2)

	page._allow_dump_check.button_pressed = false
	await wait_frames(1)

	assert_false(page._config.allow_dump, "编辑副本应记录改动")
	assert_true(ConfigStore.current.allow_dump,
		"未确认前不应改动内存中正在生效的配置")


# ============================================================
# Helpers
# ============================================================

func _find_scroll(page: Control) -> ScrollContainer:
	for node in _walk(page):
		if node is ScrollContainer:
			return node as ScrollContainer
	return null


## 底部操作行 = 直接装着「确认配置」按钮的那个 HBoxContainer
func _find_action_row(page: Control) -> HBoxContainer:
	for node in _walk(page):
		if not (node is HBoxContainer):
			continue
		for child in node.get_children():
			if child is Button and (child as Button).text == "确认配置":
				return node as HBoxContainer
	return null


func _walk(node: Node) -> Array[Node]:
	var out: Array[Node] = []
	if node == null:
		return out
	for child in node.get_children():
		out.append(child)
		out.append_array(_walk(child))
	return out

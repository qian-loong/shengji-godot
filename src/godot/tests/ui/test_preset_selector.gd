extends GutTest

## PresetSelector UI 测试
##
## 测试预设选择界面的创建、显示、交互

const PresetSelector = preload("res://scripts/ui/preset_selector.gd")
const BackNavigation = preload("res://scripts/ui/back_navigation.gd")
const RuleConfig = preload("res://scripts/core/rule_config.gd")
const ConfigStore = preload("res://scripts/core/config_store.gd")

var _disk_backup: String = ""
var _had_backup: bool = false


func before_all() -> void:
	# 用例会读写 user:// 下的真实存档，先备份再还原，别吃掉玩家配置
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


func _open_selector() -> Control:
	var selector := PresetSelector.new()
	add_child_autofree(selector)
	await wait_frames(2)
	return selector


func test_preset_selector_creates_three_cards():
	var selector := await _open_selector()

	# 每张卡两个按钮（选择此模式 / 自定义规则），外加底部返回主菜单
	var buttons := _find_all_buttons(selector)
	assert_eq(buttons.size(), 7, "应该有 3 张卡 × 2 个按钮 + 1 个返回按钮")

	assert_eq(_find_buttons_with_text(selector, "选择此模式").size(), 3)
	assert_eq(_find_buttons_with_text(selector, "自定义规则").size(), 3)


func test_preset_selector_has_back_button():
	var selector := await _open_selector()

	var back_buttons := _find_buttons_with_text(selector, "返回主菜单")
	assert_eq(back_buttons.size(), 1, "应该有一个返回按钮")


func test_adjust_button_passes_preset_to_config_page():
	# 「自定义规则」只传预设 id，配置页再用 resolve_for_edit 决定初值
	var selector := await _open_selector()
	ProjectSettings.set_setting("game/selected_preset", -1)

	selector._on_adjust_button_pressed(RuleConfig.ConfigSource.PRESET_COMPETITIVE)

	assert_eq(
		int(ProjectSettings.get_setting("game/selected_preset", -1)),
		int(RuleConfig.ConfigSource.PRESET_COMPETITIVE),
		"应该把待编辑的预设写入项目设置")


func test_selecting_preset_commits_it_to_config_store():
	# 「选择此模式」直接开局，配置进内存而不经 ProjectSettings
	var selector := await _open_selector()

	selector._on_preset_button_pressed(RuleConfig.ConfigSource.PRESET_QUICK)

	assert_not_null(ConfigStore.current, "选择预设后内存里应有生效配置")
	assert_eq(ConfigStore.current.base_preset, RuleConfig.ConfigSource.PRESET_QUICK)


func test_preset_cards_display_correct_info():
	var selector := await _open_selector()

	var labels := _find_all_labels(selector)
	var titles := labels.map(func(l: Label) -> String: return l.text)

	assert_true(titles.has("经典模式"), "应该显示经典模式标题")
	assert_true(titles.has("竞技模式"), "应该显示竞技模式标题")
	assert_true(titles.has("快速模式"), "应该显示快速模式标题")


func test_card_badge_reflects_saved_custom():
	# 卡片上的「已自定义 N 项」必须和配置页的计数对得上
	var saved := RuleConfig.from_preset(RuleConfig.ConfigSource.PRESET_CLASSIC)
	saved.upgrade_step = 2
	ConfigStore.commit_custom(saved)
	ConfigStore.current = null

	var selector := await _open_selector()

	var texts := _find_all_labels(selector).map(func(l: Label) -> String: return l.text)
	var badges := texts.filter(func(t: String) -> bool: return t.contains("已自定义"))
	assert_eq(badges.size(), 1, "只有经典模式那张卡该带徽章")
	assert_true(badges[0].contains("1 项"), "徽章文案应为 1 项，实际：%s" % badges[0])


func test_selector_installs_back_navigation():
	# quit_on_go_back=false，界面不自己处理返回键就会把玩家困在这一屏
	var selector := await _open_selector()

	var found := false
	for child in selector.get_children():
		if child.get_script() == BackNavigation:
			found = true
			break
	assert_true(found, "预设选择页应挂载 BackNavigation")


# ============================================================
# Helper Methods
# ============================================================

func _find_all_buttons(node: Node) -> Array[Button]:
	var buttons: Array[Button] = []
	if node is Button:
		buttons.append(node)
	for child in node.get_children():
		buttons.append_array(_find_all_buttons(child))
	return buttons


func _find_buttons_with_text(node: Node, text: String) -> Array[Button]:
	var all_buttons := _find_all_buttons(node)
	return all_buttons.filter(func(b: Button) -> bool: return b.text == text)


func _find_all_labels(node: Node) -> Array[Label]:
	var labels: Array[Label] = []
	if node is Label:
		labels.append(node)
	for child in node.get_children():
		labels.append_array(_find_all_labels(child))
	return labels

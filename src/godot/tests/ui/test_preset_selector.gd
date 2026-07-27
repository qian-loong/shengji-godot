extends GutTest

## PresetSelector UI 测试
##
## 测试预设选择界面的创建、显示、交互

const PresetSelector = preload("res://scripts/ui/preset_selector.gd")
const RuleConfig = preload("res://scripts/core/rule_config.gd")


func test_preset_selector_creates_three_cards():
	# Arrange
	var selector := PresetSelector.new()
	add_child_autofree(selector)

	# Act - _ready() is called automatically
	await wait_frames(2)

	# Assert
	var buttons := _find_all_buttons(selector)
	assert_eq(buttons.size(), 4, "应该有 3 个预设按钮 + 1 个返回按钮")


func test_preset_selector_has_back_button():
	# Arrange
	var selector := PresetSelector.new()
	add_child_autofree(selector)

	# Act
	await wait_frames(2)

	# Assert
	var back_buttons := _find_buttons_with_text(selector, "返回主菜单")
	assert_eq(back_buttons.size(), 1, "应该有一个返回按钮")


func test_clicking_preset_button_saves_to_project_settings():
	# Arrange
	var selector := PresetSelector.new()
	add_child_autofree(selector)
	await wait_frames(2)

	# Act - 模拟点击经典模式按钮（通过直接调用方法）
	selector._on_preset_button_pressed(RuleConfig.ConfigSource.PRESET_CLASSIC)

	# Assert
	var saved_preset: int = ProjectSettings.get_setting("game/selected_preset", -1)
	assert_eq(saved_preset, int(RuleConfig.ConfigSource.PRESET_CLASSIC), "应该保存经典模式到项目设置")


func test_preset_cards_display_correct_info():
	# Arrange
	var selector := PresetSelector.new()
	add_child_autofree(selector)

	# Act
	await wait_frames(2)

	# Assert - 检查是否显示了预设标题
	var labels := _find_all_labels(selector)
	var titles := labels.map(func(l: Label) -> String: return l.text)

	assert_true(titles.has("经典模式"), "应该显示经典模式标题")
	assert_true(titles.has("竞技模式"), "应该显示竞技模式标题")
	assert_true(titles.has("快速模式"), "应该显示快速模式标题")


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

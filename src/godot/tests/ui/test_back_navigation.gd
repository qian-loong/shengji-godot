## BackNavigation 手势与信号
##
## project.godot 设了 config/quit_on_go_back=false，引擎不会替界面兜底处理
## Android 返回键。preset_selector 与 room_config 此前都没有任何返回处理，
## 手机上进去就出不来（叠加按钮被顶出屏幕后，只能杀进程）。
extends GutTest

const BackNavigation = preload("res://scripts/ui/back_navigation.gd")

## 判定用的参考屏宽，与逻辑分辨率一致
const WIDTH := 1280.0


# ============================================================
# 手势判定（纯函数，不依赖场景树）
# ============================================================

func test_left_edge_swipe_right_triggers_back() -> void:
	assert_true(BackNavigation.is_back_swipe(
		Vector2(300, 10), WIDTH, true, false),
		"从左边缘向右推应触发返回")


func test_right_edge_swipe_left_triggers_back() -> void:
	assert_true(BackNavigation.is_back_swipe(
		Vector2(-300, 10), WIDTH, false, true),
		"从右边缘向左推应触发返回")


func test_swipe_from_middle_does_not_trigger() -> void:
	# 限定边缘起手，避免和界面内部的横向拖拽抢手势
	assert_false(BackNavigation.is_back_swipe(
		Vector2(400, 0), WIDTH, false, false),
		"非边缘起手不应触发返回")


func test_wrong_direction_does_not_trigger() -> void:
	assert_false(BackNavigation.is_back_swipe(
		Vector2(-300, 0), WIDTH, true, false),
		"从左边缘往左推不是返回手势")
	assert_false(BackNavigation.is_back_swipe(
		Vector2(300, 0), WIDTH, false, true),
		"从右边缘往右推不是返回手势")


func test_short_swipe_does_not_trigger() -> void:
	# 阈值 15% 屏宽 = 192px
	assert_false(BackNavigation.is_back_swipe(
		Vector2(100, 0), WIDTH, true, false),
		"位移不足阈值不应触发返回")


func test_vertical_drag_does_not_trigger() -> void:
	# 这条最关键：配置页的滚动就是从边缘起手的垂直拖拽
	assert_false(BackNavigation.is_back_swipe(
		Vector2(200, 400), WIDTH, true, false),
		"纵向占主导时应判为滚动而非返回")


func test_diagonal_favoring_horizontal_triggers() -> void:
	assert_true(BackNavigation.is_back_swipe(
		Vector2(400, 100), WIDTH, true, false),
		"横向明显占优的斜滑仍应视为返回")


func test_threshold_scales_with_screen_width() -> void:
	# 同样 200px 位移，窄屏够、宽屏不够
	assert_true(BackNavigation.is_back_swipe(Vector2(200, 0), 800.0, true, false))
	assert_false(BackNavigation.is_back_swipe(Vector2(200, 0), 2400.0, true, false))


# ============================================================
# 信号与去重
# ============================================================

func test_emits_back_requested_on_go_back_notification() -> void:
	var nav := BackNavigation.new()
	add_child_autofree(nav)
	watch_signals(nav)

	nav.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)

	assert_signal_emitted(nav, "back_requested")


func test_same_frame_duplicate_is_collapsed() -> void:
	# Android 把一次返回键同时投递为 WM_GO_BACK_REQUEST 和 KEY_BACK 输入事件，
	# 不去重就会一次按下连退两屏
	var nav := BackNavigation.new()
	add_child_autofree(nav)
	watch_signals(nav)

	nav.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	nav.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)

	assert_signal_emit_count(nav, "back_requested", 1,
		"同一帧内的重复返回请求应只算一次")


func test_next_frame_back_is_accepted_again() -> void:
	var nav := BackNavigation.new()
	add_child_autofree(nav)
	watch_signals(nav)

	nav.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await wait_frames(2)
	nav.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)

	assert_signal_emit_count(nav, "back_requested", 2,
		"跨帧的两次返回是两次真实操作")


func test_escape_key_triggers_back() -> void:
	var nav := BackNavigation.new()
	add_child_autofree(nav)
	watch_signals(nav)

	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.physical_keycode = KEY_ESCAPE
	event.pressed = true
	nav._input(event)

	assert_signal_emitted(nav, "back_requested", "Esc 应触发返回")


func test_key_echo_is_ignored() -> void:
	var nav := BackNavigation.new()
	add_child_autofree(nav)
	watch_signals(nav)

	var event := InputEventKey.new()
	event.keycode = KEY_BACK
	event.physical_keycode = KEY_BACK
	event.pressed = true
	event.echo = true
	nav._input(event)

	assert_signal_not_emitted(nav, "back_requested", "长按重复事件不应反复触发返回")


func test_swipe_can_be_disabled() -> void:
	var nav := BackNavigation.new()
	nav.swipe_enabled = false
	add_child_autofree(nav)

	assert_false(nav.swipe_enabled, "滚动密集的界面可以只保留返回键")

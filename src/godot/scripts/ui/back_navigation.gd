## 返回导航 — 把「返回上一屏」的三种触发方式收敛到一个信号
##
## 挂在界面 Control 下即可，连接 back_requested 处理返回逻辑：
##
##     var back := BackNavigation.new()
##     back.back_requested.connect(_on_back)
##     add_child(back)
##
## 覆盖的触发方式：
##   1. Android 系统返回键（NOTIFICATION_WM_GO_BACK_REQUEST）
##   2. Esc / KEY_BACK（ui_cancel）
##   3. 屏幕左右边缘的横向滑动手势
##
## project.godot 设了 config/quit_on_go_back=false，引擎不会兜底处理返回键，
## 每个界面都必须自己响应，否则手机上会卡在该界面出不去。
class_name BackNavigation
extends Node

signal back_requested

## 起手点须落在屏幕左右多宽的范围内才算边缘滑动（占视口宽的比例）。
## 限定边缘起手是为了不和界面内部的横向拖拽抢手势。
const EDGE_RATIO := 0.12

## 触发返回所需的最小横向位移（占视口宽的比例）
const TRIGGER_RATIO := 0.15

## 横向位移须达到纵向位移的这个倍数，避免和垂直滚动抢手势
const DIRECTION_RATIO := 1.5

## 是否启用边缘滑动手势。垂直滚动密集的界面可关掉只留返回键。
var swipe_enabled: bool = true

var _touch_index: int = -1
var _touch_start := Vector2.ZERO
var _touch_last := Vector2.ZERO
var _from_left_edge := false
var _from_right_edge := false

## Android 把一次返回键同时投递为 NOTIFICATION_WM_GO_BACK_REQUEST 和
## KEY_BACK 输入事件。不去重的话一次按下会被当成两次，连退两屏。
var _consumed_frame: int = -1


func _input(event: InputEvent) -> void:
	if _handle_back_key(event):
		return
	if swipe_enabled:
		_track_swipe(event)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_emit_back()


## Esc / KEY_BACK。返回 true 表示事件已消费。
func _handle_back_key(event: InputEvent) -> bool:
	var is_back := event.is_action_pressed("ui_cancel")
	if not is_back and event is InputEventKey:
		var key := event as InputEventKey
		is_back = key.pressed and not key.echo and key.keycode == KEY_BACK
	if not is_back:
		return false

	# 先消费再处理：处理逻辑通常会 change_scene_to_file()，
	# 之后本节点已离开场景树，get_viewport() 会变成 null。
	var vp := get_viewport()
	if vp:
		vp.set_input_as_handled()
	_emit_back()
	return true


## 边缘横滑。只观察不消费，让垂直滚动和控件点击照常工作；
## 仅在确认命中返回手势时才消费抬手事件。
func _track_swipe(event: InputEvent) -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var width := vp.get_visible_rect().size.x
	if width <= 0.0:
		return

	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_begin_touch(touch, width)
		else:
			_end_touch(touch, width)
		return

	if event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == _touch_index:
			_touch_last = drag.position


func _begin_touch(touch: InputEventScreenTouch, width: float) -> void:
	# 多指时只跟踪第一根，避免双指缩放之类的操作被误判成返回
	if _touch_index != -1:
		return
	_touch_index = touch.index
	_touch_start = touch.position
	_touch_last = touch.position
	var edge := width * EDGE_RATIO
	_from_left_edge = touch.position.x <= edge
	_from_right_edge = touch.position.x >= width - edge


func _end_touch(touch: InputEventScreenTouch, width: float) -> void:
	if touch.index != _touch_index:
		return
	var end_pos := touch.position
	_touch_index = -1

	if not (_from_left_edge or _from_right_edge):
		return

	var delta := end_pos - _touch_start
	if not is_back_swipe(delta, width, _from_left_edge, _from_right_edge):
		return

	var vp := get_viewport()
	if vp:
		vp.set_input_as_handled()
	_emit_back()


## 手势判定，抽成静态函数以便脱离场景树测试。
static func is_back_swipe(
	delta: Vector2, width: float, from_left: bool, from_right: bool
) -> bool:
	if not (from_left or from_right):
		return false
	var horizontal := absf(delta.x)
	if horizontal < width * TRIGGER_RATIO:
		return false
	# 纵向占主导时判为滚动而非返回
	if horizontal < absf(delta.y) * DIRECTION_RATIO:
		return false
	# 左边缘向右推、右边缘向左推，方向反了不算
	if from_left and delta.x > 0.0:
		return true
	if from_right and delta.x < 0.0:
		return true
	return false


func _emit_back() -> void:
	var frame := Engine.get_process_frames()
	if _consumed_frame == frame:
		return
	_consumed_frame = frame
	back_requested.emit()

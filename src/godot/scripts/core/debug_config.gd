## 调试配置
## 全局调试选项，可在开发期间控制日志详细程度
extends Node

## 是否启用详细日志输出
## 设为 true 时会输出更多调试信息（如卡牌动画、网络细节等）
## 发布版本应设为 false
const VERBOSE_LOG: bool = false

## 是否启用网络调试日志
const NETWORK_DEBUG: bool = false

## 是否启用UI事件调试日志
const UI_DEBUG: bool = false

## 是否启用游戏逻辑调试日志
const GAME_LOGIC_DEBUG: bool = false

## 便捷的日志函数
static func log_verbose(message: String, category: String = "VERBOSE") -> void:
	if VERBOSE_LOG:
		print("[%s] %s" % [category, message])

static func log_network(message: String) -> void:
	if NETWORK_DEBUG:
		print("[NETWORK] %s" % message)

static func log_ui(message: String) -> void:
	if UI_DEBUG:
		print("[UI] %s" % message)

static func log_game(message: String) -> void:
	if GAME_LOGIC_DEBUG:
		print("[GAME] %s" % message)

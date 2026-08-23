## 对局日志的落盘位置。
##
## PC 上写仓库根的 logs/，`tools/validate_game_log.py` 等脚本直接读那里。
## 但这套路径是从 res:// 往上两级推出来的，只在「从源码目录运行」时成立：
## 移动端 res:// 指向 APK 内部，上两级是不可写的安装目录，建目录必然失败，
## 日志会被静默丢弃——真机跑了整局却一条日志都没有就是这么来的。
##
## 所以移动端一律走 user://logs/（Android 上是 /data/data/<pkg>/files/logs/，
## 可用 `adb shell run-as <pkg> ls files/logs` 取出）。导出版 PC 的 res:// 指向
## .pck、仓库布局同样不存在，靠建目录失败回退兜住。
class_name LogPaths
extends RefCounted


## 日志目录下某个文件的可写绝对路径（目录会被自动创建）
static func resolve(filename: String) -> String:
	var dir := log_dir()
	DirAccess.make_dir_recursive_absolute(dir)
	return "%s/%s" % [dir, filename]


## 当前平台该往哪写日志
static func log_dir() -> String:
	if is_mobile():
		return ProjectSettings.globalize_path("user://logs")

	var project_root := ProjectSettings.globalize_path("res://").trim_suffix("/")
	var repo_dir := "%s/logs" % project_root.get_base_dir().get_base_dir()
	if DirAccess.make_dir_recursive_absolute(repo_dir) == OK \
			or DirAccess.dir_exists_absolute(repo_dir):
		return repo_dir

	return ProjectSettings.globalize_path("user://logs")


static func is_mobile() -> bool:
	return OS.has_feature("mobile") or OS.get_name() in ["Android", "iOS"]

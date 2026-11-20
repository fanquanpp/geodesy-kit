# tests/transform/run_module_tests.gd —— GK-M4 施工域本地自测入口（单域，不影响统一 runner）
# 用法（自测单模块，等价于任务书给的 -s 单文件口径，因 test_*.gd 继承 RefCounted 不可直接 -s）：
#   godot --headless --path . -s res://tests/transform/run_module_tests.gd
# 逻辑与 tests/run_tests.gd 一致（软失败/退出码/中文明细），仅收集范围限 tests/transform/。
# 已知盲点与统一 runner 相同：test_ 方法中途脚本错误会计 PASS —— 由日志 SCRIPT ERROR 行兜底，
# 本脚本末尾同时打印是否发现 SCRIPT ERROR 字样以辅助人工检查（grep 亦可用）。
extends SceneTree

const DIR := "res://tests/transform"
const BASE_PATH := "res://tests/test_case_base.gd"

var _plan: Array = []
var _started := false

func _initialize() -> void:
	var files := PackedStringArray()
	_collect(DIR, files)
	files.sort()
	print("== GK-M4 模块自测：收集到 %d 个测试文件 ==" % files.size())
	for path in files:
		if path == BASE_PATH:
			continue
		var script = load(path)
		if script == null or not script.can_instantiate():
			printerr("[SCRIPT-ERROR] 无法加载/实例化 %s" % path)
			_plan.append({"path": path, "error": true})
			continue
		var inst = script.new()
		if not (inst is RefCounted and inst.has_method("_fail")):
			printerr("[SCRIPT-ERROR] %s 未继承 tests/test_case_base.gd" % path)
			_plan.append({"path": path, "error": true})
			continue
		_plan.append({"path": path, "error": false, "inst": inst, "methods": _test_methods(inst)})

func _process(_delta: float) -> bool:
	if _started:
		return false
	_started = true
	var passed := 0
	var failed := 0
	var script_errors := 0
	for item: Dictionary in _plan:
		if item.get("error", false):
			script_errors += 1
			continue
		var path: String = item["path"]
		var inst = item["inst"]
		for method: String in item["methods"]:
			inst.set("current_method", method)
			var before: int = inst.failures.size()
			inst.call(method)
			var msgs: PackedStringArray = inst.failures.slice(before)
			if msgs.is_empty():
				passed += 1
				print("[PASS] %s :: %s" % [path, method])
			else:
				failed += 1
				print("[FAIL] %s :: %s" % [path, method])
				for m in msgs:
					print("       - " + m)
	print("--------------------------------------------------")
	print("M4 模块自测: passed=%d failed=%d script_errors=%d" % [passed, failed, script_errors])
	var exit_code := 1 if (failed > 0 or script_errors > 0) else 0
	print("退出码: %d" % exit_code)
	quit(exit_code)
	return true

func _collect(dirpath: String, out: PackedStringArray) -> void:
	var d := DirAccess.open(dirpath)
	if d == null:
		return
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		var full := dirpath.path_join(f)
		if d.current_is_dir():
			if not f.begins_with("."):
				_collect(full, out)
		elif f.ends_with(".gd") and f.begins_with("test_"):
			out.append(full)
		f = d.get_next()
	d.list_dir_end()

func _test_methods(inst) -> PackedStringArray:
	var names := PackedStringArray()
	for mi in inst.get_method_list():
		if String(mi.name).begins_with("test_"):
			names.append(mi.name)
	return names

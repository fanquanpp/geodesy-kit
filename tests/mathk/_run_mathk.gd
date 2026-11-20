# tests/mathk/_run_mathk.gd —— GK-M1 域单模块自测驱动（施工期工具，非正式测试用例）
#
# 为什么存在：正式测试文件 tests/mathk/test_*.gd 继承 RefCounted，直接
# `godot -s res://tests/mathk/test_xxx.gd` 不会作为 MainLoop 运行（本机实测进程挂起
# 不退出）——单模块自测需要一个 SceneTree 驱动。本文件镜像 tests/run_tests.gd 的
# 收集/断言/退出码逻辑，仅把收集范围限定在 tests/mathk/，供 M1 施工自测；
# 全量回归仍以 res://tests/run_tests.gd 为准（本文件不进正式计数流程）。
# 文件名不以 test_ 开头，统一 runner 不会收集本文件。
#
# 用法：
#   godot --headless --path . -s res://tests/mathk/_run_mathk.gd
# 退出码：0=全过；1=有断言失败或脚本错误（与 run_tests.gd 同口径）。
extends SceneTree

const DIR := "res://tests/mathk"

var _plan: Array = []          # [{path, script, inst, methods}] / [{path, error}]
var _started := false

func _initialize() -> void:
	var files := PackedStringArray()
	_collect(DIR, files)
	files.sort()
	print("== GK-M1 mathk 单模块自测: 收集到 %d 个测试文件 ==" % files.size())
	for path in files:
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
		return false  # 已结束等待 quit 生效
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
	print("mathk 自测汇总: passed=%d failed=%d script_errors=%d" % [passed, failed, script_errors])
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

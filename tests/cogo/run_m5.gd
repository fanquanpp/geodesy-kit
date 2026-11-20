# tests/cogo/run_m5.gd —— GK-M5 模块级自测入口（仅收集 tests/cogo/test_*.gd，不跑全工程）
# 背景：tests/test_*.gd 均继承 RefCounted（tests/test_case_base.gd），不能以
#   `godot -s res://tests/<test文件>` 单文件运行（非 MainLoop 脚本会挂起）；
#   故按 tests/run_tests.gd 的同款机制做本模块作用域的运行器。
# 用法：
#   godot --headless --path . --script res://tests/cogo/run_m5.gd
# 退出码：失败>0 或脚本错误>0 → 1，否则 0（与统一 runner 同口径）。
# 已知盲点（继承自统一 runner）：test_ 方法中途脚本错误会计 PASS —— 需人工核对日志
#   中的 SCRIPT ERROR 行；本运行器把 stdout/stderr 原样输出便于 grep。
extends SceneTree

const DOMAIN_DIR := "res://tests/cogo"

var _plan: Array = []
var _started := false

func _initialize() -> void:
	var files := PackedStringArray()
	_collect(DOMAIN_DIR, files)
	files.sort()
	print("== GK-M5 模块测试 runner: 收集到 %d 个测试文件 ==" % files.size())
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
	print("总计: passed=%d failed=%d script_errors=%d" % [passed, failed, script_errors])
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

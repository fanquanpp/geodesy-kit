# tests/ellipsoid/run_m2.gd —— GK-M2 单模块自测入口（不叫 test_*，不会被统一 runner 收集）
# 用法（与 run_tests.gd 同构，只收集本域）：
#   godot --headless --path . --script res://tests/ellipsoid/run_m2.gd
# 执行时机（沿用 run_tests.gd 实测教训）：_initialize 阶段 root 尚未入树，
# 涉树的测试（UI 冒烟）会失效 —— 收集在 _initialize，执行统一推迟到 _process 首轮。
# 退出码：失败>0 或脚本错误>0 → 1，否则 0。
extends SceneTree

const DIR := "res://tests/ellipsoid"
const BASE := "res://tests/test_case_base.gd"

var _plan: Array = []
var _started := false

func _initialize() -> void:
	var files := PackedStringArray()
	var d := DirAccess.open(DIR)
	d.list_dir_begin()
	var fn := d.get_next()
	while fn != "":
		if not d.current_is_dir() and fn.begins_with("test_") and fn.ends_with(".gd"):
			files.append(DIR.path_join(fn))
		fn = d.get_next()
	d.list_dir_end()
	files.sort()
	print("== GK-M2 单模块 runner：收集到 %d 个测试文件 ==" % files.size())
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
		var methods := PackedStringArray()
		for mi in inst.get_method_list():
			if String(mi.name).begins_with("test_"):
				methods.append(String(mi.name))
		_plan.append({"path": path, "error": false, "inst": inst, "methods": methods})

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
		for mname: String in item["methods"]:
			inst.set("current_method", mname)
			var before: int = inst.failures.size()
			inst.call(mname)
			var msgs: PackedStringArray = inst.failures.slice(before)
			if msgs.is_empty():
				passed += 1
				print("[PASS] %s :: %s" % [path.get_file(), mname])
			else:
				failed += 1
				print("[FAIL] %s :: %s" % [path.get_file(), mname])
				for msg in msgs:
					print("       - " + msg)
	print("--------------------------------------------------")
	print("GK-M2 总计: passed=%d failed=%d script_errors=%d" % [passed, failed, script_errors])
	quit(1 if (failed > 0 or script_errors > 0) else 0)
	return true

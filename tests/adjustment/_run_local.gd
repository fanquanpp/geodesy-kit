# tests/adjustment/_run_local.gd —— M6 本地单模块自测入口（施工期用，不进 runner 收集）
# 用法：
#   "C:/Atian/STEAM/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe" \
#     --headless --path . -s res://tests/adjustment/_run_local.gd
# 只收集 res://tests/adjustment/test_*.gd，逻辑与 tests/run_tests.gd 一致（软失败 + 退出码）。
# 文件名不带 test_ 前缀，全量 runner 不会收集本文件。
extends SceneTree

const DIR := "res://tests/adjustment"

var _plan: Array = []
var _started := false

func _initialize() -> void:
	var files := PackedStringArray()
	_collect(DIR, files)
	files.sort()
	print("== M6 本地自测: 收集到 %d 个测试文件 ==" % files.size())
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
				methods.append(mi.name)
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
	print("M6 本地总计: passed=%d failed=%d script_errors=%d" % [passed, failed, script_errors])
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
		if not d.current_is_dir() and f.begins_with("test_") and f.ends_with(".gd"):
			out.append(dirpath.path_join(f))
		f = d.get_next()
	d.list_dir_end()

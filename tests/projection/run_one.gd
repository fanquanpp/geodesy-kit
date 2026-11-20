# tests/projection/run_one.gd —— M3 施工自测入口（单域运行，不进统一 runner 收集）
# 用法：
#   godot --headless --path . --script res://tests/projection/run_one.gd
# 行为同 tests/run_tests.gd，但只收集 res://tests/projection/test_*.gd。
# 注意：这是施工期脚手架；统一验收仍以 res://tests/run_tests.gd 全量为准。
extends SceneTree

var _plan: Array = []
var _started := false

func _initialize() -> void:
	var files := PackedStringArray()
	_collect("res://tests/projection", files)
	files.sort()
	print("== GeodesyKit M3 自测: 收集到 %d 个测试文件 ==" % files.size())
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
	print("M3 自测: passed=%d failed=%d script_errors=%d" % [passed, failed, script_errors])
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

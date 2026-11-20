# tests/astro/_driver_m8.gd —— GK-M8 单模块自测驱动（仅收集 tests/astro 与 tests/topics）
# 用法：
#   godot --headless --path . --script res://tests/astro/_driver_m8.gd
# 说明：正式全量入口是 tests/run_tests.gd（自动收集所有 test_*.gd）；本驱动仅供
# M8 施工域本地自测，文件名不带 test_ 前缀，全量 runner 不会收集本文件。
# 与 run_tests.gd 同款统计口径：软失败累计、退出码 0/1。
# 已知盲点（继承自架构师实现，见 run_tests.gd 头注）：test_ 方法中途脚本错误会中断
# 该方法且计 PASS——需人工查看日志中的 SCRIPT ERROR 行兜底。
extends SceneTree

var _plan: Array = []
var _started := false

func _initialize() -> void:
	var files := PackedStringArray()
	_collect("res://tests/astro", files)
	_collect("res://tests/topics", files)
	files.sort()
	print("== GK-M8 单模块驱动: 收集到 %d 个测试文件 ==" % files.size())
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
	print("M8 总计: passed=%d failed=%d script_errors=%d" % [passed, failed, script_errors])
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

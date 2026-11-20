# tests/route/_run_single.gd —— M7 单模块自测入口（施工期自用，不进统一 runner）
#
# 背景：tests/run_tests.gd 是整套统一入口（架构 §7.1，由集成脚本统一跑）；
#   而单文件 test_*.gd 继承 RefCounted 断言基类，不能直接 `-s` 当 MainLoop 跑。
#   本文件是 SceneTree 包装器：只收集/运行 GK-M7 自己的测试（tests/route/ 与
#   tests/earthwork/），供单模块自测，不触碰共享文件。
# 用法：
#   godot --headless --path . -s res://tests/route/_run_single.gd
#   godot --headless --path . -s res://tests/route/_run_single.gd -- test_spiral test_alignment_el
#   （传参为文件名过滤关键字；不传则跑两个目录全部 test_*.gd）
# 说明：文件名不匹配 test_*.gd，故统一 runner 不会收集本文件；逻辑镜像 run_tests.gd
#   （软断言累计、[PASS]/[FAIL] 打印、退出码 0/1），已知盲点同源：test_ 方法中途
#   脚本错误会计 PASS，需人工看日志 SCRIPT ERROR 行。
extends SceneTree

var _plan: Array = []
var _started := false

func _initialize() -> void:
	var filters := []
	var args := OS.get_cmdline_user_args()
	for a: String in args:
		filters.append(a.strip_edges())
	var files := PackedStringArray()
	_collect("res://tests/route", files)
	_collect("res://tests/earthwork", files)
	files.sort()
	for path: String in files:
		var matched := filters.is_empty()
		for f: String in filters:
			if path.contains(f):
				matched = true
				break
		if not matched:
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
		var methods := PackedStringArray()
		for mi in inst.get_method_list():
			if String(mi.name).begins_with("test_"):
				methods.append(mi.name)
		_plan.append({"path": path, "error": false, "inst": inst, "methods": methods})
	print("== GK-M7 单模块自测：收集到 %d 个测试文件 ==" % _plan.size())

func _process(_delta: float) -> bool:
	if _started:
		return false
	_started = true
	_run_all()
	return true

func _run_all() -> void:
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
	print("M7 自测总计: passed=%d failed=%d script_errors=%d" % [passed, failed, script_errors])
	var exit_code := 1 if (failed > 0 or script_errors > 0) else 0
	print("退出码: %d" % exit_code)
	quit(exit_code)

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

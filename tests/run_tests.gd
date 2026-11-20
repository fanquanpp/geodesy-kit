# GeodesyKit 统一测试入口（CI/本地共用）
# 用法：
#   godot --headless --path <工程根> --script res://tests/run_tests.gd
# 行为：
#   1) 递归收集 res://tests/**/test_*.gd（跳过本文件与断言基类，忽略点开头目录）；
#   2) 逐脚本实例化，按声明顺序执行所有 test_ 开头的方法；
#   3) 每条软断言失败计入 failures；脚本加载/实例化失败计 script_errors；
#   4) 打印逐用例 [PASS]/[FAIL] 与汇总行；
#   5) quit(失败>0 或脚本错误>0 ? 1 : 0)。
#
# ⚠ 执行时机（本会话实测教训）：SceneTree 脚本模式下 _initialize 阶段 root 尚未入树，
#   此时 add_child 的子节点 in_tree=false、_ready 不触发 —— 凡涉树的测试（导航壳冒烟等）
#   会静默失效。故收集在 _initialize，执行统一推迟到主循环首轮 _process（此时树已就绪）。
# 已知盲点（如实声明）：GDScript 无异常机制，test_ 方法中途脚本错误（空引用等）会中断
#   该方法且不产生失败记录，runner 会计其为 PASS —— 由日志中的 SCRIPT ERROR 行人工兜底。
extends SceneTree

const SELF_PATH := "res://tests/run_tests.gd"
const BASE_PATH := "res://tests/test_case_base.gd"

var _plan: Array = []          # [{path, script, inst, methods}]
var _started := false

func _initialize() -> void:
	var files := PackedStringArray()
	_collect("res://tests", files)
	files.sort()
	print("== GeodesyKit test runner: 收集到 %d 个测试文件 ==" % files.size())
	for path in files:
		if path == SELF_PATH or path == BASE_PATH:
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

# tests/route/_ui_smoke.gd —— M7 UI 冒烟（长期保留的 UI 回归入口，不进统一 runner）
# 单跑：godot --headless --path . -s res://tests/route/_ui_smoke.gd
# 检查：1) 15 个计算器场景可实例化且 _ready 不崩；2) 空输入 run() 返回中文错误不崩溃；
#       3) manifest 示例一键填充后 run() 全部 ok=true（端到端）；4) 目录挂载 15 条目。
# 说明：UI 视觉/触控验收仍属三端手工清单（架构 §7.3 口径），本脚本只做 headless 功能冒烟。
extends SceneTree

var _started := false

func _process(_delta: float) -> bool:
	if _started:
		return false
	_started = true
	var fails := 0
	# —— 挂载检查 ——
	var catalog := GKModuleCatalog.new()
	var order: Array = catalog.load_all()
	var by_domain: Dictionary = catalog.by_domain()
	var route_dom: Dictionary = by_domain.get("route", {})
	var route_entries: Array = route_dom.get("entries", [])
	print("== 挂载检查：route 域条目 = %d（全局 %d）==" % [route_entries.size(), catalog.count()])
	if route_entries.size() != 15:
		print("[SMOKE-FAIL] route 域条目数 != 15")
		fails += 1
	# —— 场景实例化 + 空输入 + 示例端到端 ——
	for entry: Dictionary in route_entries:
		var scene_path := String(entry["scene"])
		var packed = load(scene_path)
		if packed == null:
			print("[SMOKE-FAIL] 场景加载失败：%s" % scene_path)
			fails += 1
			continue
		var inst: Node = packed.instantiate()
		if not (inst is GKCalculatorBase):
			print("[SMOKE-FAIL] 根脚本未继承 GKCalculatorBase：%s" % scene_path)
			fails += 1
			inst.free()
			continue
		root.add_child(inst)  # 触发 _ready
		var calc := inst as GKCalculatorBase
		# 空输入：应 ok=false 且 error 中文（不崩溃）
		var empty_res: Dictionary = calc.run()
		if bool(empty_res.get("ok", true)):
			print("[SMOKE-FAIL] 空输入意外成功：%s" % entry["id"])
			fails += 1
		elif String(empty_res.get("error", "")).is_empty():
			print("[SMOKE-FAIL] 空输入错误消息为空：%s" % entry["id"])
			fails += 1
		# 示例输入：应 ok=true
		calc.set_example(entry.get("example", {}))
		calc.call("_on_example")
		var ex_res: Dictionary = calc.run()
		if not bool(ex_res.get("ok", false)):
			print("[SMOKE-FAIL] 示例输入计算失败：%s → %s" % [entry["id"], str(ex_res.get("error", ""))])
			fails += 1
		else:
			print("[SMOKE-OK] %s（%s）示例端到端通过" % [entry["id"], String(entry["name"])])
		# get_inputs / set_inputs 回放往返
		var snap: Dictionary = calc.get_inputs()
		if snap.is_empty():
			print("[SMOKE-FAIL] get_inputs 为空：%s" % entry["id"])
			fails += 1
		root.remove_child(inst)
		inst.free()
	print("== UI 冒烟总计：%s ==" % ("全部通过" if fails == 0 else "%d 项失败" % fails))
	quit(1 if fails > 0 else 0)
	return true

# scenes/calculators/adjustment/_smoke_local.gd —— M6 场景冒烟（施工期用，不进 runner）
# 用法：godot --headless --path . -s res://scenes/calculators/adjustment/_smoke_local.gd
# 检查：manifest 解析 → 逐场景实例化（入树触发 _ready）→ 填示例输入 → run() → ok 通路。
extends SceneTree

var _items: Array = []
var _started := false
var _idx := 0
var _passed := 0
var _failed := 0
var _fail_msgs := PackedStringArray()

func _initialize() -> void:
	var catalog_script = load("res://app/module_catalog.gd")
	var catalog = catalog_script.new()
	var entries: Array = catalog.load_manifest_file("res://scenes/calculators/adjustment/manifest.json")
	print("== M6 场景冒烟: manifest 条目 %d 个 ==" % entries.size())
	for e: Dictionary in entries:
		_items.append(e)

func _process(_delta: float) -> bool:
	if _started:
		return false
	_started = true
	# ⚠ SceneTree._process 返回 true 会退出主循环：全部条目须在本帧一次处理完
	for e: Dictionary in _items:
		var scene_path: String = String(e["scene"])
		var packed = load(scene_path)
		if packed == null:
			_failed += 1
			_fail_msgs.append("%s 场景加载失败" % scene_path)
			continue
		var inst = packed.instantiate()
		if inst == null:
			_failed += 1
			_fail_msgs.append("%s 实例化失败" % scene_path)
			continue
		root.add_child(inst)
		# 入树后 _ready 已触发；填示例并运行
		var title: String = String(e["name"])
		inst.set_inputs(e.get("example", {}))
		var res: Dictionary = inst.run()
		if bool(res.get("ok", false)):
			_passed += 1
			print("[SMOKE-PASS] %s (%s)" % [title, String(e["id"])])
		else:
			_failed += 1
			var msg := "%s (%s) run 失败：%s" % [title, String(e["id"]), String(res.get("error", ""))]
			_fail_msgs.append(msg)
			print("[SMOKE-FAIL] " + msg)
		root.remove_child(inst)
		inst.free()
	print("--------------------------------------------------")
	print("M6 场景冒烟总计: passed=%d failed=%d" % [_passed, _failed])
	for m in _fail_msgs:
		print("       - " + m)
	var exit_code := 1 if _failed > 0 else 0
	print("退出码: %d" % exit_code)
	quit(exit_code)
	return true

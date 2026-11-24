# scenes/calculators/projection/utm_inverse.gd —— a7_utm_inv UTM 反算（A7）
# 计算器契约：继承 GKCalculatorBase（经 proj_calc_base），run() 返回 §5 协议。
# 标签域 "utm"：core/projection/utm.gd 输出 n_m/e_m 为平面坐标，经域子表覆盖
# 通用表 n_m=「卯酉圈曲率半径」的撞名词条。
extends "res://scenes/calculators/projection/proj_calc_base.gd"

const _UT := preload("res://core/projection/utm.gd")

## 面板自带示例（manifest example 仅经 main 导航路径注入；直接挂载该场景时
## 无输入可算——基类 _ready 的 set_inputs(_example_inputs) 依赖此默认值；
## 数值与 core/projection/utm.gd 19N 权威向量同源）
func _init() -> void:
	_example_inputs = {"zone": "19", "hemisphere": "N",
			"e_m": "399002.5708", "n_m": "4832935.3412", "datum": "WGS84"}

func get_title() -> String:
	return "UTM 反算（A7）"

func get_description() -> String:
	return "UTM 网格坐标 → B/L（需带号与半球）。"

func get_label_domain() -> String:
	return "utm"

func _setup() -> void:
	_add_row("带号", "zone", "1..60", true)
	_add_row("半球", "hemisphere", "N / S（或 北/南）", true, LineEdit.KEYBOARD_TYPE_DEFAULT)
	_add_row("东坐标 E（m）", "e_m", "如 399002.5708", true)
	_add_row("北坐标 N（m）", "n_m", "如 4832935.3412", true)
	_add_row("基准", "datum", "WGS84 / 其他", false, LineEdit.KEYBOARD_TYPE_DEFAULT)

func run() -> Dictionary:
	var p := _fail_or(_params())
	if bool(p.get("ok", true)) == false and p.has("error"):
		return p
	return _UT.inverse(p)

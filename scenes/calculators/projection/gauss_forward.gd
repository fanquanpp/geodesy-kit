# scenes/calculators/projection/gauss_forward.gd —— a3_gauss_fwd 高斯投影正算（A3）
# 计算器契约：继承 GKCalculatorBase（经 proj_calc_base），run() 返回 §5 协议。
extends "res://scenes/calculators/projection/proj_calc_base.gd"

const _GK := preload("res://core/projection/gauss_kruger.gd")

func get_title() -> String:
	return "高斯投影正算（A3）"

func get_description() -> String:
	return "B/L → 高斯平面坐标（x 北、y 东，含 500km 假东）。支持十进制度或度分秒输入。"

func _setup() -> void:
	# P9.4 坐标输入形式：B|L 坐标对双列（stacked 标签 + ° 后缀）
	_add_coord_pair("纬度 B", "lat_deg", "经度 L", "lon_deg", true, "°", "°")
	# 角度档 keyboard_angle=true：L0 可输度分秒（如 117 00 00，键盘须含空格 → DEFAULT）
	_add_row("中央子午线 L0", "l0_deg", "3°带 L0=3n，6°带 L0=6n−3", true,
			LineEdit.KEYBOARD_TYPE_NUMBER_DECIMAL, "°", true)
	_add_row("基准", "datum", "CGCS2000 / 北京54 / 西安80 / WGS84", false, LineEdit.KEYBOARD_TYPE_DEFAULT)

func run() -> Dictionary:
	var p := _fail_or(_params())
	if bool(p.get("ok", true)) == false and p.has("error"):
		return p
	return _GK.forward(p)

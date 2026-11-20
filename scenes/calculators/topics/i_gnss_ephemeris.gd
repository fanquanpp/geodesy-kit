# scenes/calculators/topics/i_gnss_ephemeris.gd —— I-GNSS 广播星历开普勒→ECEF
extends "res://scenes/calculators/topics/topics_calc_base.gd"

const CORE := preload("res://core/topics/gnss.gd")

func _init() -> void:
	_entry_id = "i_gnss_ephemeris"
	_example_inputs = {
		"sqrt_a": "5153.793876", "e": "0.005", "i0": "0.9599310859",
		"omega": "1.2", "omega0": "-0.5", "omega_dot": "-5.2e-9",
		"m0": "1.5", "delta_n": "4.5e-9",
		"cuc": "-8.7e-7", "cus": "1.1e-6", "crc": "180", "crs": "-45",
		"cic": "5.8e-8", "cis": "1.2e-7", "idot": "3.2e-11",
		"toe": "400000", "t_gps": "400000",
	}

func get_title() -> String:
	return "GNSS 广播星历（开普勒→ECEF）（I）"

func get_description() -> String:
	return "IS-GPS-200 广播星历 16 参数开普勒算法：平均角速度 n、半周滚转归算 tk、开普勒方程迭代解偏近点角、摄动改正（Cuc/Cus/Crc/Crs/Cic/Cis）与地球自转修正，输出卫星 ECEF 坐标。角度参数一律弧度（与 RINEX 一致）；√a 单位 m^0.5（GPS 约 5153.79），toe/t_gps 为 GPS 周内秒。"

func _build_rows() -> void:
	add_input_row("√a（m^0.5）", "sqrt_a", "5153.793876")
	add_input_row("偏心率 e", "e", "0.005")
	add_input_row("i₀（rad）", "i0", "0.9599310859")
	add_input_row("ω 近地点角距（rad）", "omega", "1.2")
	add_input_row("Ω₀（rad）", "omega0", "-0.5")
	add_input_row("Ω̇（rad/s）", "omega_dot", "-5.2e-9")
	add_input_row("M₀（rad）", "m0", "1.5")
	add_input_row("Δn（rad/s）", "delta_n", "4.5e-9")
	add_input_row("Cuc（rad）", "cuc", "-8.7e-7")
	add_input_row("Cus（rad）", "cus", "1.1e-6")
	add_input_row("Crc（m）", "crc", "180")
	add_input_row("Crs（m）", "crs", "-45")
	add_input_row("Cic（rad）", "cic", "5.8e-8")
	add_input_row("Cis（rad）", "cis", "1.2e-7")
	add_input_row("İ（rad/s）", "idot", "3.2e-11")
	add_input_row("toe 星历参考时刻（s）", "toe", "400000")
	add_input_row("t_gps 计算时刻（s）", "t_gps", "400000")

func run() -> Dictionary:
	var bad := []
	var p := {}
	for key in ["sqrt_a", "e", "i0", "omega", "omega0", "omega_dot", "m0", "delta_n",
			"cuc", "cus", "crc", "crs", "cic", "cis", "idot", "toe", "t_gps"]:
		var v := num_field(_fields[key], _fields[key].placeholder_text, bad)
		if not bad.is_empty():
			return fail_input(bad)
		p[key] = v
	if not bad.is_empty():
		return fail_input(bad)
	return CORE.ephemeris_to_ecef(p)

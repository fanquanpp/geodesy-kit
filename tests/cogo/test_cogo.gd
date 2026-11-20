# tests/cogo/test_cogo.gd —— GK-M5 坐标正反算（M5-1，向量来源：ARCHITECTURE.md §4 GK-M5【构造·自洽检核】）
# 权威向量：A1/A2 (1000,1000) az45° d500→(1353.553390593,1353.553390593) 反算回收 45.000000/500.000000
extends "res://tests/test_case_base.gd"

const C := preload("res://core/cogo/cogo.gd")

func test_forward_authoritative_vector() -> void:
	var r := C.forward({"x0_m": 1000.0, "y0_m": 1000.0, "az_deg": 45.0, "dist_m": 500.0})
	assert_true(bool(r.get("ok", false)), "A1 权威向量计算成功")
	if not bool(r.get("ok", false)):
		return
	var v: Dictionary = r["value"]
	assert_almost_eq(float(v["x_m"]), 1353.553390593, 1e-9, "A1 x_m（向量 1353.553390593）")
	assert_almost_eq(float(v["y_m"]), 1353.553390593, 1e-9, "A1 y_m")
	assert_almost_eq(float(v["dx_m"]), 353.553390593274, 1e-9, "Δx = d·sin45°")
	assert_almost_eq(float(v["dy_m"]), 353.553390593274, 1e-9, "Δy = d·cos45°")

func test_inverse_authoritative_vector() -> void:
	var r := C.inverse({"x0_m": 1000.0, "y0_m": 1000.0, "x_m": 1353.553390593, "y_m": 1353.553390593})
	assert_true(bool(r.get("ok", false)), "A2 反算成功")
	if not bool(r.get("ok", false)):
		return
	var v: Dictionary = r["value"]
	# 输入坐标为向量截断值（12 位），回收断言用 1e-9 容差
	assert_almost_eq(float(v["dist_m"]), 500.0, 1e-9, "回收 d = 500.000000")
	assert_almost_eq(float(v["az_deg"]), 45.0, 1e-9, "回收 az = 45.000000")
	assert_almost_eq(float(v["az_back_deg"]), 225.0, 1e-9, "反方位角 225°")
	# 纯原语全精度往返
	var p := C.inv(1000.0, 1000.0, 1000.0 + 500.0 * sin(deg_to_rad(45.0)), 1000.0 + 500.0 * cos(deg_to_rad(45.0)))
	assert_almost_eq(float(p["d"]), 500.0, 1e-12, "纯 inv 全精度 d")
	assert_almost_eq(float(p["az_deg"]), 45.0, 1e-12, "纯 inv 全精度 az")

func test_forward_inverse_roundtrip_edges() -> void:
	var cases := [0.0, 45.0, 90.0, 135.0, 180.0, 225.0, 270.0, 315.0, 359.999, 400.5, -90.0]
	for az: float in cases:
		var d := 123.456789
		var f := C.fwd(500.0, -800.0, az, d)
		assert_false(f.is_empty(), "正算原语合法 az=%s" % str(az))
		if f.is_empty():
			continue
		var inv := C.inv(500.0, -800.0, float(f["x"]), float(f["y"]))
		assert_false(inv.is_empty(), "反算原语合法 az=%s" % str(az))
		if inv.is_empty():
			continue
		assert_almost_eq(float(inv["d"]), d, 1e-12, "往返边长 az=%s" % str(az))
		assert_almost_eq(float(inv["az_deg"]), GKAngles.normalize_deg(az), 1e-12, "往返方位 az=%s" % str(az))

func test_forward_protocol_contract() -> void:
	var r := C.forward({"x0_m": 1000.0, "y0_m": 1000.0, "az_deg": 45.0, "dist_m": 500.0})
	assert_true(r.has("ok") and r.has("value") and r.has("steps") and r.has("formula") and r.has("error"), "§5 协议字段齐备")
	var steps: Array = r["steps"]
	assert_int_eq(steps.size(), 2, "正算两步")
	for st: Dictionary in steps:
		assert_true(st.has("title") and st.has("formula") and st.has("substitution") and st.has("result"), "步骤四字段")
		assert_true(String(st["title"]).length() > 0, "title 非空")
	var v: Dictionary = r["value"]
	assert_true(v.has("x_m") and v.has("y_m") and v.has("az_dms"), "value 键带单位后缀")
	assert_true(String(v["az_dms"]).contains("°"), "az_dms 为度分秒文本")

func test_forward_error_paths_chinese() -> void:
	var r1 := C.forward({"x0_m": 1000.0, "y0_m": 1000.0, "az_deg": 45.0, "dist_m": -1.0})
	assert_false(bool(r1.get("ok", true)), "负距离应失败")
	assert_true(String(r1.get("error", "")).contains("距离"), "负距离中文错误")
	var r2 := C.forward({"x0_m": 1000.0, "y0_m": 1000.0, "az_deg": "abc", "dist_m": 500.0})
	assert_false(bool(r2.get("ok", true)), "非法角度应失败")
	assert_true(String(r2.get("error", "")).length() > 0, "非法输入有中文错误")
	var r3 := C.forward({"x0_m": 1000.0, "y0_m": 1000.0})
	assert_false(bool(r3.get("ok", true)), "缺输入应失败")
	assert_true(String(r3.get("error", "")).contains("方位角"), "缺项中文提示")
	var r4 := C.inverse({"x0_m": 5.0, "y0_m": 5.0, "x_m": 5.0, "y_m": 5.0})
	assert_false(bool(r4.get("ok", true)), "两点重合应失败")
	assert_true(String(r4.get("error", "")).contains("重合"), "重合中文错误")

func test_3d_forward_vector_self_consistent() -> void:
	# 构造向量：S=500、v=10°、i=1.5、t=1.8、H0=100、az=30° → D=492.403877、Δh=86.524089
	var r := C.forward_3d({
		"x0_m": 1000.0, "y0_m": 1000.0, "h0_m": 100.0,
		"az_deg": 30.0, "dist_m": 500.0, "v_deg": 10.0,
		"hi_m": 1.5, "ht_m": 1.8, "dist_mode": "slope",
	})
	assert_true(bool(r.get("ok", false)), "三维正算成功")
	if not bool(r.get("ok", false)):
		return
	var v: Dictionary = r["value"]
	assert_almost_eq(float(v["d_horiz_m"]), 492.403876506104, 1e-9, "D = S·cos v")
	assert_almost_eq(float(v["dh_m"]), 86.524088833465, 1e-9, "Δh = S·sin v + i − t")
	assert_almost_eq(float(v["x_m"]), 1246.201938253052, 1e-9, "x = x0 + D·sin α")
	assert_almost_eq(float(v["y_m"]), 426.434265976222 + 1000.0, 1e-9, "y = y0 + D·cos α")
	assert_almost_eq(float(v["h_m"]), 186.524088833465, 1e-9, "H = H0 + Δh")
	assert_almost_eq(float(v["slope_m"]), 500.0, 1e-9, "到棱镜中心斜距 = √(D²+Δh_镜²) = S")

func test_3d_inverse_roundtrip() -> void:
	var fwd := C.forward_3d({
		"x0_m": 1000.0, "y0_m": 1000.0, "h0_m": 100.0,
		"az_deg": 30.0, "dist_m": 500.0, "v_deg": 10.0,
		"hi_m": 1.5, "ht_m": 1.8, "dist_mode": "slope",
	})
	if not bool(fwd.get("ok", false)):
		assert_true(false, "三维正算失败，无法往返")
		return
	var fv: Dictionary = fwd["value"]
	var inv := C.inverse_3d({
		"x0_m": 1000.0, "y0_m": 1000.0, "h0_m": 100.0,
		"x_m": float(fv["x_m"]), "y_m": float(fv["y_m"]), "h_m": float(fv["h_m"]),
		"hi_m": 1.5, "ht_m": 1.8,
	})
	assert_true(bool(inv.get("ok", false)), "三维反算成功")
	if not bool(inv.get("ok", false)):
		return
	var iv: Dictionary = inv["value"]
	assert_almost_eq(float(iv["d_horiz_m"]), 492.403876506104, 1e-9, "反算平距")
	assert_almost_eq(float(iv["slope_m"]), 500.0, 1e-9, "反算斜距 = S")
	assert_almost_eq(float(iv["v_deg"]), 10.0, 1e-9, "反算竖直角 = 10°（指向棱镜中心）")
	assert_almost_eq(float(iv["az_deg"]), 30.0, 1e-9, "反算方位角 = 30°")

func test_3d_forward_horiz_mode() -> void:
	var r := C.forward_3d({
		"x0_m": 0.0, "y0_m": 0.0, "h0_m": 50.0,
		"az_deg": 0.0, "dist_m": 500.0, "v_deg": 10.0,
		"hi_m": 1.5, "ht_m": 1.8, "dist_mode": "horiz",
	})
	assert_true(bool(r.get("ok", false)), "平距模式成功")
	if not bool(r.get("ok", false)):
		return
	var v: Dictionary = r["value"]
	assert_almost_eq(float(v["d_horiz_m"]), 500.0, 1e-12, "平距模式 D = 输入值")
	var dh := 500.0 * tan(deg_to_rad(10.0)) - 0.3
	assert_almost_eq(float(v["dh_m"]), dh, 1e-12, "平距模式 Δh = D·tan v + i − t")
	# slope_m = 到棱镜中心的三维斜距 = √(D² + (D·tan v)²) = D/cos v（与 inv_3d 同口径）
	assert_almost_eq(float(v["slope_m"]), 500.0 / cos(deg_to_rad(10.0)), 1e-12, "斜距（到棱镜中心）= D/cos v")
	assert_almost_eq(float(v["y_m"]), 500.0, 1e-12, "az=0 沿北前进")

func test_3d_error_paths() -> void:
	var r1 := C.forward_3d({
		"x0_m": 0.0, "y0_m": 0.0, "h0_m": 0.0,
		"az_deg": 0.0, "dist_m": 100.0, "v_deg": 90.0,
		"hi_m": 0.0, "ht_m": 0.0,
	})
	assert_false(bool(r1.get("ok", true)), "竖直角 90° 应失败")
	assert_true(String(r1.get("error", "")).contains("竖直角"), "竖直角越界中文错误")
	var r2 := C.forward_3d({
		"x0_m": 0.0, "y0_m": 0.0, "h0_m": 0.0,
		"az_deg": 0.0, "dist_m": 100.0, "v_deg": 10.0,
		"hi_m": 0.0, "ht_m": 0.0, "dist_mode": "斜线",
	})
	assert_false(bool(r2.get("ok", true)), "非法 dist_mode 应失败")
	var r3 := C.inverse_3d({
		"x0_m": 1.0, "y0_m": 2.0, "h0_m": 0.0,
		"x_m": 1.0, "y_m": 2.0, "h_m": 5.0,
		"hi_m": 0.0, "ht_m": 0.0,
	})
	assert_false(bool(r3.get("ok", true)), "平面重合应失败")

func test_azimuth_accepts_dms_string() -> void:
	var r := C.forward({"x0_m": 0.0, "y0_m": 0.0, "az_deg": "30 30 00", "dist_m": 100.0})
	assert_true(bool(r.get("ok", false)), "度分秒文本可解析")
	if bool(r.get("ok", false)):
		var v: Dictionary = r["value"]
		assert_almost_eq(float(v["az_deg"]), 30.5, 1e-12, "30 30 00 → 30.5°")
	var r2 := C.forward({"x0_m": 0.0, "y0_m": 0.0, "az_deg": "45°30′00″", "dist_m": 100.0})
	assert_true(bool(r2.get("ok", false)), "全角度分秒符号可解析")

func test_b5_angle_vector_30p5deg() -> void:
	# B5 权威向量：30.5° = 30°30′00″（经 M1 GKAngles 换算，M5-3 angle_tools 封装输出）
	# 注：M1 deg_to_dms_str(deg, 0) 的秒宽度按 3+0 位格式化会输出 "000″"（地基已知格式怪癖，
	# M1 API 冻结不改，本测试按组件 + 1 位秒口径断言；0 位秒口径已如实上报集成者）。
	var AT := preload("res://core/cogo/angle_tools.gd")
	var d: Dictionary = GKAngles.deg_to_dms(30.5)
	assert_int_eq(int(d["d"]), 30, "B5 度 = 30")
	assert_int_eq(int(d["m"]), 30, "B5 分 = 30")
	assert_almost_eq(float(d["s"]), 0.0, 1e-9, "B5 秒 = 00")
	assert_eq(GKAngles.deg_to_dms_str(30.5), "30°30′00.0″", "B5 度分秒文本（默认 1 位秒）")
	var r := AT.convert({"deg": 30.5})
	assert_true(bool(r.get("ok", false)), "B5 换算成功")
	if bool(r.get("ok", false)):
		var v: Dictionary = r["value"]
		assert_almost_eq(float(v["deg"]), 30.5, 1e-12, "B5 十进制度")
		assert_almost_eq(float(v["gon"]), 33.888888888888886, 1e-12, "B5 gon = 30.5×10/9（按定义式断言，架构向量表 33.913345 有误已注明）")
		assert_almost_eq(float(v["rad"]), 30.5 * PI / 180.0, 1e-12, "B5 弧度")
		assert_eq(String(v["quadrant_text"]), "北东30°30′00.0″", "B5 象限角文本")

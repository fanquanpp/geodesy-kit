# tests/route/test_alignment_jd.gd —— D1 交点法正反算（构造自洽向量：几何闭合 + 往返回收）
# 自洽检核口径：ZH/HZ 坐标闭合于切线几何、QZ 落于圆曲线（|QZ−圆心|=R）、
# 反算 JD 得桩号=QZ 桩号且偏距=−E、断点里程往返一致（架构 §4 GK-M7【构造·判据明确】）
extends "res://tests/test_case_base.gd"

const Jd := preload("res://core/route/alignment_jd.gd")
const Cur := preload("res://core/route/curve_elements.gd")

# 构造路线：起点(1000,2000) 方位30°；JD1 距起点 400；JD2 在方位 55° 方向 600 m 处
# → JD1 处右转 25°，R=300，l0=60
const SX := 1000.0
const SY := 2000.0
const AZ0 := 30.0
const D1 := 400.0
const D2 := 600.0
const AZ1 := 55.0
const R := 300.0
const L0 := 60.0

static func _jds() -> Array:
	var jd1 := [SX + D1 * sin(deg_to_rad(AZ0)), SY + D1 * cos(deg_to_rad(AZ0))]
	var jd2 := [jd1[0] + D2 * sin(deg_to_rad(AZ1)), jd1[1] + D2 * cos(deg_to_rad(AZ1))]
	return [
		{"x_m": jd1[0], "y_m": jd1[1], "r_m": R, "l0_m": L0},
		{"x_m": jd2[0], "y_m": jd2[1], "r_m": R, "l0_m": L0},
	]

static func _p(end_bearing: bool) -> Dictionary:
	var d := {"start": {"x_m": SX, "y_m": SY, "bearing_deg": AZ0, "chain_m": 0.0}, "jds": _jds()}
	if end_bearing:
		d["end_bearing_deg"] = AZ1 + 25.0  # JD2 转 25°（与 JD1 相同；l0=60,R=300 需 2β0=11.46°<α）
	return d

## 装配正算：要素与主点里程闭合
func test_forward_elements_and_main_points() -> void:
	var res: Dictionary = Jd.forward(_p(true))
	assert_true(bool(res.get("ok", false)), "交点法装配成功：" + String(res.get("error", "")))
	if not bool(res.get("ok", false)):
		return
	var v: Dictionary = res["value"]
	var curves: Array = v["curves"]
	assert_int_eq(curves.size(), 2, "两个交点各设曲线")
	var c1: Dictionary = curves[0]
	var el1: Dictionary = Cur.elements(R, L0, deg_to_rad(25.0))
	assert_almost_eq(c1["chain_jd_m"], D1, 1e-9, "chain(JD1)=400")
	assert_almost_eq(c1["t_m"], el1["t_m"], 1e-9, "T 与 B3 要素一致")
	assert_almost_eq(c1["chain_zh_m"], D1 - float(el1["t_m"]), 1e-9, "ZH=JD−T")
	assert_almost_eq(c1["chain_hz_m"], D1 - float(el1["t_m"]) + float(el1["l_m"]), 1e-9, "HZ=ZH+L")
	assert_almost_eq(c1["alpha_deg"], 25.0, 1e-9, "JD1 右转 25°")
	assert_eq(c1["dir_cn"], "右转", "转向判定")
	# chain(JD2) = chain(HZ1) + D(JD1,JD2) − T1（HZ1 落在 JD1→JD2 连线上距 JD1 为 T1）
	var c2: Dictionary = curves[1]
	assert_almost_eq(c2["chain_jd_m"], float(c1["chain_hz_m"]) + D2 - float(c1["t_m"]), 1e-9, "chain(JD2)=HZ1+D−T1")
	# 主点坐标闭合：ZH = 起点 + (400−T)·u(30°)；HZ = JD1 + T·u(55°)
	var th0 := deg_to_rad(AZ0)
	var th1 := deg_to_rad(AZ1)
	var zh_x := SX + (D1 - float(el1["t_m"])) * sin(th0)
	var zh_y := SY + (D1 - float(el1["t_m"])) * cos(th0)
	var jd1: Dictionary = _jds()[0]
	var hz_x := float(jd1["x_m"]) + float(el1["t_m"]) * sin(th1)
	var hz_y := float(jd1["y_m"]) + float(el1["t_m"]) * cos(th1)
	var main_pts: Array = v["main_points"]
	assert_almost_eq(main_pts[0]["x_m"], zh_x, 1e-8, "ZH 坐标闭合 X")
	assert_almost_eq(main_pts[0]["y_m"], zh_y, 1e-8, "ZH 坐标闭合 Y")
	# HZ 闭合容差 1e-4：引擎按真回旋线（曲率线性、数值积分）定位，检验值按布告式
	# 级数要素 T 构造——两者存在级数截断级差异（本会话 Python 复核 ~5e-6 m 量级）
	assert_almost_eq(main_pts[4]["x_m"], hz_x, 1e-4, "HZ 坐标闭合 X（容差=级数截断量级）")
	assert_almost_eq(main_pts[4]["y_m"], hz_y, 1e-4, "HZ 坐标闭合 Y（容差=级数截断量级）")
	assert_almost_eq(main_pts[4]["chain_m"], c1["chain_hz_m"], 1e-9, "HZ 里程一致")

## 曲线段检核：HZ 切线方位 = 出切线方位；QZ 到圆心距离 = R
func test_curve_geometry_checks() -> void:
	var res: Dictionary = Jd.forward(_p(true))
	assert_true(bool(res.get("ok", false)), "装配成功")
	if not bool(res.get("ok", false)):
		return
	var pa: Dictionary = Jd.point_at({"start": _p(true)["start"], "jds": _jds(),
		"end_bearing_deg": _p(true)["end_bearing_deg"], "chain_m": float(res["value"]["curves"][0]["chain_hz_m"])})
	assert_almost_eq(pa["value"]["bearing_deg"], AZ1, 1e-6, "HZ 切线方位 = 出切线 55°")
	# QZ 落在圆曲线上：圆心 = HY + R·右法线(HY 方位)，|QZ−圆心|=R
	var c1: Dictionary = res["value"]["curves"][0]
	var chain_hy: float = float(c1["chain_zh_m"]) + L0
	var chain_qz: float = float(c1["chain_zh_m"]) + float(c1["l_m"]) / 2.0
	var p_hy: Dictionary = Jd.point_at({"start": _p(true)["start"], "jds": _jds(),
		"end_bearing_deg": _p(true)["end_bearing_deg"], "chain_m": chain_hy})
	var p_qz: Dictionary = Jd.point_at({"start": _p(true)["start"], "jds": _jds(),
		"end_bearing_deg": _p(true)["end_bearing_deg"], "chain_m": chain_qz})
	var th_hy := deg_to_rad(float(p_hy["value"]["bearing_deg"]))
	var cx: float = float(p_hy["value"]["x_m"]) + R * cos(th_hy)
	var cy: float = float(p_hy["value"]["y_m"]) - R * sin(th_hy)
	var dq := sqrt(pow(float(p_qz["value"]["x_m"]) - cx, 2.0) + pow(float(p_qz["value"]["y_m"]) - cy, 2.0))
	assert_almost_eq(dq, R, 1e-6, "|QZ−圆心| = R")
	assert_almost_eq(float(p_qz["value"]["radius_m"]), R, 1e-9, "QZ 半径 = R")

## 反算：JD 坐标 → 桩号=QZ 桩号、偏距=−E（最近点对称性）
func test_inverse_jd_lands_on_qz_with_offset_neg_e() -> void:
	var res: Dictionary = Jd.forward(_p(true))
	assert_true(bool(res.get("ok", false)), "装配成功")
	if not bool(res.get("ok", false)):
		return
	var c1: Dictionary = res["value"]["curves"][0]
	var jd1: Dictionary = _jds()[0]
	var inv: Dictionary = Jd.inverse({"start": _p(true)["start"], "jds": _jds(),
		"end_bearing_deg": _p(true)["end_bearing_deg"],
		"x_m": float(jd1["x_m"]), "y_m": float(jd1["y_m"])})
	assert_true(bool(inv.get("ok", false)), "反算成功")
	if bool(inv.get("ok", false)):
		assert_almost_eq(inv["value"]["chain_m"], float(c1["chain_zh_m"]) + float(c1["l_m"]) / 2.0, 1e-4, "JD1 反算桩号 = QZ 桩号")
		var el1: Dictionary = Cur.elements(R, L0, deg_to_rad(25.0))
		assert_almost_eq(inv["value"]["offset_m"], -float(el1["e_m"]), 1e-4, "JD1 偏距 = −E（外侧）")

## 反算往返：桩号→坐标→桩号
func test_point_inverse_roundtrip() -> void:
	var inp := _p(true)
	var chains := [50.0, 150.0, 300.0, 450.0, 600.0, 900.0, 1050.0]
	for ch: float in chains:
		var pt: Dictionary = Jd.point_at({"start": inp["start"], "jds": inp["jds"],
			"end_bearing_deg": inp["end_bearing_deg"], "chain_m": ch})
		assert_true(bool(pt.get("ok", false)), "正算 %s 成功" % str(ch))
		if not bool(pt.get("ok", false)):
			continue
		var inv: Dictionary = Jd.inverse({"start": inp["start"], "jds": inp["jds"],
			"end_bearing_deg": inp["end_bearing_deg"],
			"x_m": pt["value"]["x_m"], "y_m": pt["value"]["y_m"]})
		assert_almost_eq(inv["value"]["chain_m"], ch, 1e-5, "往返回收 桩号 %s" % str(ch))
		assert_almost_eq(inv["value"]["offset_m"], 0.0, 1e-6, "中桩偏距 0（桩号 %s）" % str(ch))

## 无 end_bearing：末交点不设曲线，路线以直线收尾
func test_no_end_bearing_straight_tail() -> void:
	var res: Dictionary = Jd.forward(_p(false))
	assert_true(bool(res.get("ok", false)), "无 end_bearing 装配成功")
	if bool(res.get("ok", false)):
		var curves: Array = res["value"]["curves"]
		assert_int_eq(curves.size(), 1, "仅 JD1 设曲线")
		var jd2: Dictionary = _jds()[1]
		var inv: Dictionary = Jd.inverse({"start": _p(false)["start"], "jds": _jds(),
			"x_m": float(jd2["x_m"]), "y_m": float(jd2["y_m"])})
		# 容差 1e-4：路线终点里程按级数要素 T 推算、JD2 坐标反算按积分几何定位，
		# 两者存在级数截断级差异（~5e-6 m，本会话 Python 复核）
		assert_almost_eq(inv["value"]["chain_m"], float(res["value"]["total_len_m"]), 1e-4, "路线终点即 JD2")
		assert_almost_eq(inv["value"]["min_dist_m"], 0.0, 1e-4, "JD2 在路线上")

## l0=0 纯圆曲线交点法：主点 ZY/QZ/YZ
func test_circular_only_jd() -> void:
	var jds := [{"x_m": SX + D1 * sin(deg_to_rad(AZ0)), "y_m": SY + D1 * cos(deg_to_rad(AZ0)), "r_m": R, "l0_m": 0.0}]
	var p := {"start": {"x_m": SX, "y_m": SY, "bearing_deg": AZ0}, "jds": jds, "end_bearing_deg": AZ1 + 20.0}
	var res: Dictionary = Jd.forward(p)
	assert_true(bool(res.get("ok", false)), "纯圆曲线装配成功：" + String(res.get("error", "")))
	if bool(res.get("ok", false)):
		var names := PackedStringArray()
		for mp: Dictionary in res["value"]["main_points"]:
			names.append(String(mp["name"]))
		assert_eq("，".join(names), "ZY，QZ，YZ", "纯圆曲线主点命名")

## 错误路径
func test_error_paths() -> void:
	# 曲线伸入起点之前
	var short_p := {"start": {"x_m": SX, "y_m": SY, "bearing_deg": AZ0},
		"jds": [{"x_m": SX + 50.0 * sin(deg_to_rad(AZ0)), "y_m": SY + 50.0 * cos(deg_to_rad(AZ0)), "r_m": R, "l0_m": L0}],
		"end_bearing_deg": AZ0 + 20.0}
	var r1: Dictionary = Jd.forward(short_p)
	assert_false(bool(r1.get("ok", true)), "切线长大于段距应拒绝")
	assert_true(String(r1.get("error", "")).contains("伸入"), "中文提示曲线伸入")
	# 转角恰为 180°（normalize 后 Δ=180）走线元法
	var back_p := {"start": {"x_m": SX, "y_m": SY, "bearing_deg": AZ0},
		"jds": [{"x_m": SX + 400.0 * sin(deg_to_rad(AZ0)), "y_m": SY + 400.0 * cos(deg_to_rad(AZ0)), "r_m": R, "l0_m": L0}],
		"end_bearing_deg": AZ0 + 180.0}  # Δ = normalize(180) = 180 → 拒绝
	var r2: Dictionary = Jd.forward(back_p)
	assert_false(bool(r2.get("ok", true)), "|α|≥180° 应拒绝并指引 D2/D6")
	assert_true(String(r2.get("error", "")).contains("线元法"), "提示改用线元法")
	# 缺交点
	var r3: Dictionary = Jd.forward({"start": {"x_m": SX, "y_m": SY, "bearing_deg": AZ0}, "jds": []})
	assert_false(bool(r3.get("ok", true)), "空交点列表拒绝")
	# 半径非法
	var r4: Dictionary = Jd.forward({"start": {"x_m": SX, "y_m": SY, "bearing_deg": AZ0},
		"jds": [{"x_m": SX + 400.0, "y_m": SY, "r_m": 0.0}]})
	assert_false(bool(r4.get("ok", true)), "r_m=0 拒绝")
	# start 与 JD1 重合且无方位
	var r5: Dictionary = Jd.forward({"start": {"x_m": SX, "y_m": SY}, "jds": [{"x_m": SX, "y_m": SY, "r_m": R}]})
	assert_false(bool(r5.get("ok", true)), "重合且无方位拒绝")

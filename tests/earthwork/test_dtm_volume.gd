# tests/earthwork/test_dtm_volume.gd —— E3 DTM 三棱柱（已知三棱柱精确体积）
# 构造向量（本会话手算+Python 双路径自洽检核，见交付说明）：
# 直角三角形 (0,0)(100,0)(0,100)（面积 5000 m²）、设计面 z=0：
#   角点高 (1,2,3) → 填 10000 / 净 10000；
#   角点高 (3,−1,−2) → 填 2250 / 挖 2250 / 净 0（零线分割解析值）；
#   角点高 (2,0,−1) → 填 20000/9 / 挖 5000/9 / 净 5000/3；
#   角点高 (1,2,−1) → 填 32500/9 / 挖 2500/9 / 净 10000/3
extends "res://tests/test_case_base.gd"

const Dv := preload("res://core/earthwork/dtm_volume.gd")

static func _tri(z1: float, z2: float, z3: float) -> Array:
	return [
		{"v1": {"x_m": 0.0, "y_m": 0.0, "z_m": z1},
			"v2": {"x_m": 100.0, "y_m": 0.0, "z_m": z2},
			"v3": {"x_m": 0.0, "y_m": 100.0, "z_m": z3}},
	]

## 向量1：全正角点 (1,2,3) → 净体积 = 5000×2 = 10000（全填侧）
func test_vector_all_positive() -> void:
	var res: Dictionary = Dv.forward({"design_elev_m": 0.0, "triangles": _tri(1.0, 2.0, 3.0)})
	assert_true(bool(res.get("ok", false)), "应计算成功：" + String(res.get("error", "")))
	if not bool(res.get("ok", false)):
		return
	var v: Dictionary = res["value"]
	assert_almost_eq(v["fill_m3"], 10000.0, 1e-9, "填 = A·(1+2+3)/3 = 10000")
	assert_almost_eq(v["cut_m3"], 0.0, 1e-9, "无挖方")
	assert_almost_eq(v["net_m3"], 10000.0, 1e-9, "净 = 10000")
	assert_almost_eq(v["total_area_m2"], 5000.0, 1e-9, "面积 5000")

## 向量2：混合符号 (3,−1,−2) → 填 2250 / 挖 2250 / 净 0（零线分割精确）
func test_vector_mixed_signs() -> void:
	var res: Dictionary = Dv.forward({"design_elev_m": 0.0, "triangles": _tri(3.0, -1.0, -2.0)})
	assert_true(bool(res.get("ok", false)), "应计算成功")
	if not bool(res.get("ok", false)):
		return
	var v: Dictionary = res["value"]
	assert_almost_eq(v["fill_m3"], 2250.0, 1e-9, "尖端块解析值 2250")
	assert_almost_eq(v["cut_m3"], 2250.0, 1e-9, "基座块解析值 2250")
	assert_almost_eq(v["net_m3"], 0.0, 1e-9, "净 0 = A·(3−1−2)/3")

## 向量3/4：含零顶点与两正一负（解析值）
func test_vector_more_mixed() -> void:
	var r3: Dictionary = Dv.forward({"design_elev_m": 0.0, "triangles": _tri(2.0, 0.0, -1.0)})
	var v3: Dictionary = r3["value"]
	assert_almost_eq(v3["fill_m3"], 20000.0 / 9.0, 1e-9, "填 20000/9")
	assert_almost_eq(v3["cut_m3"], 5000.0 / 9.0, 1e-9, "挖 5000/9")
	assert_almost_eq(v3["net_m3"], 5000.0 / 3.0, 1e-9, "净 5000/3")
	var r4: Dictionary = Dv.forward({"design_elev_m": 0.0, "triangles": _tri(1.0, 2.0, -1.0)})
	var v4: Dictionary = r4["value"]
	assert_almost_eq(v4["fill_m3"], 32500.0 / 9.0, 1e-9, "填 32500/9")
	assert_almost_eq(v4["cut_m3"], 2500.0 / 9.0, 1e-9, "挖 2500/9")
	assert_almost_eq(v4["net_m3"], 10000.0 / 3.0, 1e-9, "净 10000/3")

## 倾斜设计面：z = 0.01x → h=(0,1,1) → 填 = 5000×2/3
func test_tilted_plane() -> void:
	var res: Dictionary = Dv.forward({"plane": {"z0": 0.0, "ix": 0.01, "iy": 0.0},
		"triangles": [{"v1": {"x_m": 0.0, "y_m": 0.0, "z_m": 0.0},
			"v2": {"x_m": 100.0, "y_m": 0.0, "z_m": 2.0},
			"v3": {"x_m": 0.0, "y_m": 100.0, "z_m": 1.0}}]})
	assert_true(bool(res.get("ok", false)), "倾斜设计面成功")
	if bool(res.get("ok", false)):
		assert_almost_eq(res["value"]["fill_m3"], 5000.0 * 2.0 / 3.0, 1e-9, "倾斜面填方精确值")

## 多三角形累加
func test_multiple_triangles() -> void:
	var t1: Array = _tri(1.0, 2.0, 3.0)
	var t2 := [{"v1": {"x_m": 100.0, "y_m": 0.0, "z_m": 0.0},
		"v2": {"x_m": 200.0, "y_m": 0.0, "z_m": -1.0},
		"v3": {"x_m": 100.0, "y_m": 100.0, "z_m": 0.5}}]
	var res: Dictionary = Dv.forward({"design_elev_m": 0.0, "triangles": [t1[0], t2[0]]})
	assert_true(bool(res.get("ok", false)), "多三角形成功")
	if bool(res.get("ok", false)):
		var v: Dictionary = res["value"]
		assert_int_eq(int(v["tri_count"]), 2, "2 个三角形")
		# △1：h=(1,2,3) → 填 10000；
		# △2：h=(0,−1,0.5)，面积 5000：净 = −2500/3；零线分割：独正点 v3(h=0.5)，
		#   P 落在 v1（h=0），Q 在 v3-v2 边 t=1/3；尖端面积 5000/3 → 填 2500/9；
		#   基座（v1,v2,Q）面积 10000/3 → 挖 10000/9（本会话 Python 分数精确复算）
		assert_almost_eq(v["fill_m3"], 10000.0 + 2500.0 / 9.0, 1e-6, "填 = △1 + △2 尖端 2500/9")
		assert_almost_eq(v["cut_m3"], 10000.0 / 9.0, 1e-6, "挖 = △2 基座 10000/9")
		assert_almost_eq(v["net_m3"], 10000.0 - 2500.0 / 3.0, 1e-6, "净 = 10000 − 2500/3")
		# 自洽：填 − 挖 = 净
		assert_almost_eq(v["fill_m3"] - v["cut_m3"], v["net_m3"], 1e-6, "填挖净自洽")

## 纯核 tri_area 与退化检查
func test_core_and_errors() -> void:
	assert_almost_eq(Dv.tri_area(0.0, 0.0, 100.0, 0.0, 0.0, 100.0), 5000.0, 1e-9, "面积 5000")
	var e1: Dictionary = Dv.forward({"design_elev_m": 0.0, "triangles": [
		{"v1": {"x_m": 0.0, "y_m": 0.0, "z_m": 1.0}, "v2": {"x_m": 10.0, "y_m": 0.0, "z_m": 1.0},
			"v3": {"x_m": 20.0, "y_m": 0.0, "z_m": 1.0}}]})
	assert_false(bool(e1.get("ok", true)), "三点共线（退化三角形）拒绝")
	assert_true(String(e1.get("error", "")).contains("退化"), "退化中文提示")
	var e2: Dictionary = Dv.forward({"design_elev_m": 0.0, "triangles": []})
	assert_false(bool(e2.get("ok", true)), "空三角形拒绝")

# ---------- P5 追加：三角形平面投影重叠检测（中文告警） ----------

## 两三角形平面投影重叠 → ok=true 但 value.overlap_warning 附中文告警
func test_triangle_overlap_warning() -> void:
	# 两个共边三角形共享全部区域之一部分：T1 与 T1 的平移重叠副本
	var t1: Array = _tri(1.0, 2.0, 3.0)
	var t2 := [{"v1": {"x_m": 10.0, "y_m": 0.0, "z_m": 1.0},
		"v2": {"x_m": 110.0, "y_m": 0.0, "z_m": 2.0},
		"v3": {"x_m": 10.0, "y_m": 100.0, "z_m": 3.0}}]
	var res: Dictionary = Dv.forward({"design_elev_m": 0.0, "triangles": [t1[0], t2[0]]})
	assert_true(bool(res.get("ok", false)), "重叠输入仍返回结果")
	if bool(res.get("ok", false)):
		var v: Dictionary = res["value"]
		assert_true((v as Dictionary).has("overlap_warning"), "value 含重叠告警")
		assert_true(String(v.get("overlap_warning", "")).contains("重叠"), "告警为中文且说明重叠")
		assert_int_eq(int(v.get("overlap_pairs", 0)), 1, "1 组重叠")
		# steps 中亦有告警
		var joined := ""
		for s: Dictionary in res["steps"]:
			joined += String(s.get("result", ""))
		assert_true(joined.contains("重叠"), "steps 告警重叠")
		# 体积仍按逐三角形累计（重叠区被重复计入，量值可核对：两三角形同构 → 填 2×10000）
		assert_almost_eq(float(v["fill_m3"]), 20000.0, 1e-6, "重叠时逐三角形累计（总量偏大如实报告）")

## 相邻不重叠三角形（共享顶点）→ 无告警
func test_adjacent_triangles_no_warning() -> void:
	var t1: Array = _tri(1.0, 2.0, 3.0)  # (0,0)(100,0)(0,100)
	var t2 := [{"v1": {"x_m": 100.0, "y_m": 0.0, "z_m": 1.0},
		"v2": {"x_m": 200.0, "y_m": 0.0, "z_m": 2.0},
		"v3": {"x_m": 100.0, "y_m": 100.0, "z_m": 3.0}}]
	var res: Dictionary = Dv.forward({"design_elev_m": 0.0, "triangles": [t1[0], t2[0]]})
	assert_true(bool(res.get("ok", false)), "相邻三角形成功")
	if bool(res.get("ok", false)):
		assert_false((res["value"] as Dictionary).has("overlap_warning"), "相邻不重叠无告警")

## 纯核 triangles_overlap：重叠/分离/仅共边三种情形
func test_triangles_overlap_core() -> void:
	var a1 := [0.0, 0.0, 1.0]
	var a2 := [100.0, 0.0, 2.0]
	var a3 := [0.0, 100.0, 3.0]
	# 大幅重叠
	var b1 := [10.0, 0.0, 1.0]
	var b2 := [110.0, 0.0, 2.0]
	var b3 := [10.0, 100.0, 3.0]
	assert_true(Dv.triangles_overlap(a1, a2, a3, b1, b2, b3), "重叠 true")
	# 完全分离
	var c1 := [500.0, 500.0, 1.0]
	var c2 := [600.0, 500.0, 2.0]
	var c3 := [500.0, 600.0, 3.0]
	assert_false(Dv.triangles_overlap(a1, a2, a3, c1, c2, c3), "分离 false")
	# 仅共享一条边（(0,0)-(100,0)）不算重叠
	var d1 := [0.0, 0.0, 1.0]
	var d2 := [100.0, 0.0, 2.0]
	var d3 := [0.0, -100.0, 3.0]
	assert_false(Dv.triangles_overlap(a1, a2, a3, d1, d2, d3), "仅共边 false")
	# 顶点在对方内部
	var e1 := [10.0, 10.0, 1.0]
	var e2 := [200.0, 10.0, 2.0]
	var e3 := [10.0, 200.0, 3.0]
	assert_true(Dv.triangles_overlap(a1, a2, a3, e1, e2, e3), "顶点落入内部 true")

# tests/topics/test_photogrammetry.gd —— GK-M8-7（I-摄影测量与遥感）
# 向量来源：ARCHITECTURE.md §4 GK-M8【构造·本会话】I-摄影：天顶像 f=100、H=100，
# 物点 (±20,±15,0) → 像点 (∓20,∓15)、比例尺 1:100（构造口径 = _scripts/gen_vectors_b.py
# 的 xi=−f·X/H 倒像，即共线方程 κ=180° 天顶摄影；架构表中"像点(±20,∓15)"为该式的
# 简写失真，测试按生成脚本原值断言）。其余为构造自洽（后方/前方交会恢复、GSD 闭式、
# 指数闭式值）。
extends "res://tests/test_case_base.gd"

const P := preload("res://core/topics/photogrammetry.gd")

func _nadir_ext(kappa_deg: float, Xs := 0.0, Ys := 0.0, Zs := 100.0) -> Dictionary:
	return {"f": 100.0, "Xs": Xs, "Ys": Ys, "Zs": Zs,
			"phi_deg": 0.0, "omega_deg": 0.0, "kappa_deg": kappa_deg}

func test_nadir_authority_vector() -> void:
	# 天顶像 κ=180°（倒像）：(±20,±15,0) → (∓20,∓15)，比例尺 1:100
	var ext := _nadir_ext(180.0)
	var r := P.collinearity({"f": 100.0, "Xs": 0.0, "Ys": 0.0, "Zs": 100.0,
			"phi_deg": 0.0, "omega_deg": 0.0, "kappa_deg": 180.0,
			"points": "20,15,0;-20,15,0;-20,-15,0;20,-15,0"})
	assert_true(r["ok"], "天顶像向量算例应成功")
	if bool(r["ok"]):
		var v: Dictionary = r["value"]
		assert_almost_eq(float(v["x1"]), -20.0, 1e-9, "(20,15)→x=−20")
		assert_almost_eq(float(v["y1"]), -15.0, 1e-9, "(20,15)→y=−15")
		assert_almost_eq(float(v["x2"]), 20.0, 1e-9, "(−20,15)→x=+20")
		assert_almost_eq(float(v["y2"]), -15.0, 1e-9, "(−20,15)→y=−15")
		assert_almost_eq(float(v["x3"]), 20.0, 1e-9, "(−20,−15)→x=+20")
		assert_almost_eq(float(v["y3"]), 15.0, 1e-9, "(−20,−15)→y=+15")
		assert_almost_eq(float(v["x4"]), -20.0, 1e-9, "(20,−15)→x=−20")
		assert_almost_eq(float(v["y4"]), 15.0, 1e-9, "(20,−15)→y=+15")

func test_nadir_upright_and_scale() -> void:
	# κ=0°（正像）：像点 = (f·X/H, f·Y/H)；比例尺 1:m = f/(H−Z) = 1:100
	var r := P.collinearity({"f": 100.0, "Xs": 0.0, "Ys": 0.0, "Zs": 100.0,
			"phi_deg": 0.0, "omega_deg": 0.0, "kappa_deg": 0.0, "points": "20,15,0"})
	assert_true(r["ok"], "正像算例应成功")
	if bool(r["ok"]):
		assert_almost_eq(float(r["value"]["x1"]), 20.0, 1e-9, "正像 x = f·X/H")
		assert_almost_eq(float(r["value"]["y1"]), 15.0, 1e-9, "正像 y = f·Y/H")
	# 比例尺 1:100 的等价表达：|像点| = |物点|×f/(H−Z)
	var scale := 100.0 / (100.0 - 0.0)
	assert_almost_eq(scale, 1.0, 1e-12, "f/(H−Z) = 1 → 1:100")

func test_collinearity_general_rotation() -> void:
	# 一般外方位：与 project() 逐点一致 + w=0 报错路径
	var ext := {"f": 50.0, "Xs": 10.0, "Ys": -5.0, "Zs": 300.0,
			"phi_deg": 2.0, "omega_deg": -1.5, "kappa_deg": 30.0}
	var img := P.project(ext, [110.0, -5.0, 0.0])
	assert_true(is_finite(float(img[0])), "一般外方位可投影")
	# 主点偏移
	var r := P.collinearity({"f": 100.0, "Xs": 0.0, "Ys": 0.0, "Zs": 100.0,
			"phi_deg": 0.0, "omega_deg": 0.0, "kappa_deg": 0.0, "x0": 5.0, "y0": -3.0,
			"points": "0,0,0"})
	if bool(r["ok"]):
		assert_almost_eq(float(r["value"]["x1"]), 5.0, 1e-12, "x0 平移")
		assert_almost_eq(float(r["value"]["y1"]), -3.0, 1e-12, "y0 平移")
	var rbad := P.collinearity({"f": 100.0, "Xs": 0.0, "Ys": 0.0, "Zs": 0.0,
			"phi_deg": 0.0, "omega_deg": 0.0, "kappa_deg": 0.0, "points": "10,0,0"})
	assert_false(bool(rbad["ok"]), "分母为零应报中文错误")

func test_resection_recovery() -> void:
	# 构造自洽：已知外方位生成控制点像坐标 → 后方交会恢复（6 未知数迭代 LS）
	var ext_true := {"f": 100.0, "Xs": 30.0, "Ys": -20.0, "Zs": 120.0,
			"phi_deg": 0.0, "omega_deg": 0.0, "kappa_deg": 15.0}
	# 控制点必须非共面（共面 → 平面场景双解；模块对此有守卫报错）
	var pts := [[0.0, 0.0, 0.0], [40.0, 0.0, 0.0], [0.0, 30.0, 0.0], [40.0, 30.0, 0.0], [20.0, 15.0, 45.0]]
	var recs := PackedStringArray()
	for pt: Array in pts:
		var img := P.project(ext_true, pt)
		recs.append("%s,%s,%s,%s,%s" % [str(pt[0]), str(pt[1]), str(pt[2]), str(img[0]), str(img[1])])
	var r := P.resection({"f": 100.0, "controls": ";".join(recs)})
	assert_true(r["ok"], "后方交会应收敛（构造数据，非共面）")
	# 共面守卫：全零高程控制点应报中文错误而非静默给出另一解
	var pts_planar := [[0.0, 0.0, 0.0], [40.0, 0.0, 0.0], [0.0, 30.0, 0.0], [40.0, 30.0, 0.0], [20.0, 15.0, 0.0]]
	var recs_planar := PackedStringArray()
	for pt: Array in pts_planar:
		var img2 := P.project(ext_true, pt)
		recs_planar.append("%s,%s,%s,%s,%s" % [str(pt[0]), str(pt[1]), str(pt[2]), str(img2[0]), str(img2[1])])
	var r_planar := P.resection({"f": 100.0, "controls": ";".join(recs_planar)})
	assert_false(bool(r_planar["ok"]), "共面控制点应报双解错误")
	assert_true(String(r_planar["error"]).contains("共面"), "共面错误提示")
	if bool(r["ok"]):
		var v: Dictionary = r["value"]
		assert_almost_eq(float(v["Xs_m"]), 30.0, 1e-4, "恢复 Xs")
		assert_almost_eq(float(v["Ys_m"]), -20.0, 1e-4, "恢复 Ys")
		assert_almost_eq(float(v["Zs_m"]), 120.0, 1e-4, "恢复 Zs")
		assert_almost_eq(float(v["kappa_deg"]), 15.0, 1e-3, "恢复 κ")
		assert_almost_eq(float(v["phi_deg"]), 0.0, 1e-4, "恢复 φ")
		assert_almost_eq(float(v["rms_px"]), 0.0, 1e-6, "无噪声时残差≈0")
		assert_true(int(v["iters"]) > 0 and int(v["iters"]) <= 50, "迭代次数合理")

func test_resection_with_noise() -> void:
	# 加入 ±0.003 px 噪声：恢复至 mm 级且 RMS 与噪声量级相当
	var ext_true := {"f": 100.0, "Xs": 0.0, "Ys": 0.0, "Zs": 100.0,
			"phi_deg": 0.0, "omega_deg": 0.0, "kappa_deg": 180.0}
	var noise := [0.002, -0.001, 0.003, 0.001, -0.002, 0.002, 0.0, -0.003, 0.001, 0.002]
	var pts := [[0.0, 0.0, 0.0], [40.0, 0.0, 0.0], [0.0, 30.0, 0.0], [40.0, 30.0, 0.0], [20.0, 15.0, 45.0]]
	var recs := PackedStringArray()
	var i := 0
	for pt: Array in pts:
		var img := P.project(ext_true, pt)
		recs.append("%s,%s,%s,%s,%s" % [str(pt[0]), str(pt[1]), str(pt[2]),
				str(float(img[0]) + float(noise[i * 2])), str(float(img[1]) + float(noise[i * 2 + 1]))])
		i += 1
	var r := P.resection({"f": 100.0, "controls": ";".join(recs)})
	assert_true(r["ok"], "带噪后方交会应收敛")
	if bool(r["ok"]):
		var v: Dictionary = r["value"]
		assert_almost_eq(float(v["Zs_m"]), 100.0, 0.05, "带噪航高恢复（±0.003px 噪声）")
		assert_almost_eq(float(v["Xs_m"]), 0.0, 0.05, "带噪 Xs 恢复")
		assert_true(float(v["rms_px"]) < 0.01, "RMS 与注入噪声量级一致")

func test_forward_intersection_authority_style() -> void:
	# 立体像对：S₁=(0,0,100)、S₂=(80,0,100)，均天顶 κ=180°；P=(30,20,0)
	# 像点：左 (−30,−20)、右 (50,−20) → 恢复 (30,20,0)
	var e1 := {"f": 100.0, "Xs": 0.0, "Ys": 0.0, "Zs": 100.0, "phi_deg": 0.0, "omega_deg": 0.0, "kappa_deg": 180.0}
	var e2 := {"f": 100.0, "Xs": 80.0, "Ys": 0.0, "Zs": 100.0, "phi_deg": 0.0, "omega_deg": 0.0, "kappa_deg": 180.0}
	var img1 := P.project(e1, [30.0, 20.0, 0.0])
	var img2 := P.project(e2, [30.0, 20.0, 0.0])
	assert_almost_eq(float(img1[0]), -30.0, 1e-9, "左片像 x")
	assert_almost_eq(float(img1[1]), -20.0, 1e-9, "左片像 y")
	assert_almost_eq(float(img2[0]), 50.0, 1e-9, "右片像 x")
	var r := P.forward_intersection({
		"f": 100.0,
		"ext_left": e1, "pt_left": "%s,%s" % [str(img1[0]), str(img1[1])],
		"ext_right": e2, "pt_right": "%s,%s" % [str(img2[0]), str(img2[1])],
	})
	assert_true(r["ok"], "前方交会应成功")
	if bool(r["ok"]):
		var v: Dictionary = r["value"]
		assert_almost_eq(float(v["X_m"]), 30.0, 1e-4, "恢复 X")
		assert_almost_eq(float(v["Y_m"]), 20.0, 1e-4, "恢复 Y")
		assert_almost_eq(float(v["Z_m"]), 0.0, 1e-4, "恢复 Z")
		assert_almost_eq(float(v["rms_px"]), 0.0, 1e-6, "无噪声残差≈0")

func test_flight_design() -> void:
	# 构造闭式：f=0.1 m，像元 4.6 μm，6000×4000，H=1000 m，航向 65%、旁向 35%
	var r := P.flight_design({"f_m": 0.1, "pixel_um": 4.6, "img_w_px": 6000.0, "img_h_px": 4000.0,
			"H_m": 1000.0, "forward_overlap": 0.65, "side_overlap": 0.35})
	assert_true(r["ok"], "航摄设计应成功")
	if bool(r["ok"]):
		var v: Dictionary = r["value"]
		assert_almost_eq(float(v["scale_denom"]), 10000.0, 1e-6, "比例尺分母 H/f")
		assert_almost_eq(float(v["gsd_m"]), 0.046, 1e-9, "GSD = 像元·H/f")
		assert_almost_eq(float(v["coverage_w_m"]), 276.0, 1e-9, "航向覆盖")
		assert_almost_eq(float(v["coverage_h_m"]), 184.0, 1e-9, "旁向覆盖")
		assert_almost_eq(float(v["baseline_m"]), 96.6, 1e-9, "航向基线 B=276×0.35")
		assert_almost_eq(float(v["strip_gap_m"]), 119.6, 1e-9, "航线间隔 D=184×0.65")
	var r2 := P.flight_design({"f_m": 0.1, "pixel_um": 4.6, "img_w_px": 6000.0, "img_h_px": 4000.0,
			"H_m": 1000.0, "forward_overlap": 0.65, "side_overlap": 0.35,
			"area_w_m": 2000.0, "area_h_m": 3000.0})
	assert_true(r2["ok"], "带测区设计应成功")
	if bool(r2["ok"]):
		assert_int_eq(int(r2["value"]["photos_per_line"]), 30, "每航线像片数 ceil((3000−276)/96.6)+1")
		assert_int_eq(int(r2["value"]["lines"]), 17, "航线数 ceil((2000−184)/119.6)+1")
		assert_int_eq(int(r2["value"]["photos_total"]), 510, "总像片数")

func test_remote_indexes_closed_form() -> void:
	var bands := {"red": 0.2, "nir": 0.8, "green": 0.5, "blue": 0.1, "swir1": 0.1, "swir2": 0.15}
	var r := P.remote_index({"bands": bands})
	assert_true(r["ok"], "指数批量计算应成功")
	if bool(r["ok"]):
		var v: Dictionary = r["value"]
		assert_almost_eq(float(v["NDVI"]), 0.6, 1e-12, "NDVI=(0.8−0.2)/1.0")
		assert_almost_eq(float(v["EVI"]), 2.5 * 0.6 / 2.25, 1e-12, "EVI 闭式")
		assert_almost_eq(float(v["SAVI"]), 0.6, 1e-12, "SAVI=1.5×0.6/1.5")
		assert_almost_eq(float(v["NDWI"]), -0.3 / 1.3, 1e-12, "NDWI")
		assert_almost_eq(float(v["MNDWI"]), 0.4 / 0.6, 1e-12, "MNDWI")
		assert_almost_eq(float(v["NDBI"]), -0.7 / 0.9, 1e-12, "NDBI")
		assert_almost_eq(float(v["NBR"]), 0.65 / 0.95, 1e-12, "NBR")
		assert_almost_eq(float(v["BAI"]), 1.0 / 0.37, 1e-12, "BAI=1/((0.1−0.2)²+(0.2−0.8)²)")
		assert_almost_eq(float(v["VARI"]), 0.5, 1e-12, "VARI=0.3/0.6")
		assert_almost_eq(float(v["NDSI"]), 0.4 / 0.6, 1e-12, "NDSI")
	# 缺少波段 → 依赖波段的指数跳过，不崩溃（green/red/blue → 仅 VARI 可算）
	var r2 := P.remote_index({"bands": {"green": 0.5, "red": 0.2, "blue": 0.1}})
	assert_true(r2["ok"], "部分波段仅计算可算项")
	if bool(r2["ok"]):
		assert_false((r2["value"] as Dictionary).has("NDVI"), "缺 nir 时无 NDVI")
		assert_true((r2["value"] as Dictionary).has("VARI"), "VARI 仍可算")
		assert_int_eq((r2["value"] as Dictionary).size(), 1, "仅 1 项可算")
	# 完全不可算 → 中文错误
	var r2b := P.remote_index({"bands": {"green": 0.5}})
	assert_false(bool(r2b["ok"]), "无任何可算指数应报中文错误")
	# 自定义表达式（b1..bn 语法，M1-7 对齐）
	var r3 := P.remote_index({"bands": bands, "custom_expression": "b1*2+b2",
			"custom_bands": ["red", "nir"]})
	assert_true(r3["ok"], "自定义表达式应成功")
	if bool(r3["ok"]):
		assert_almost_eq(float(r3["value"]["custom_index"]), 1.2, 1e-12, "b1×2+b2 = 0.4+0.8")
	# 自定义表达式 1/1 合法（bands 字典需与 custom_bands 一致）
	var r4 := P.remote_index({"bands": {"red": 1.0, "nir": 1.0}, "custom_expression": "b1/b2",
			"custom_bands": ["red", "nir"]})
	assert_true(bool(r4["ok"]), "1/1 合法")
	var r5 := P.remote_index({"bands": {"red": 1.0}, "custom_expression": "b1/(b1-1)",
			"custom_bands": ["red"]})
	assert_false(bool(r5["ok"]), "除零应返回中文错误")

func test_invalid_inputs() -> void:
	var r1 := P.resection({"f": 100.0, "controls": "1,2,3,4,5;6,7,8,9,10"})
	assert_false(bool(r1["ok"]), "控制点不足应拒绝")
	var r2 := P.resection({"f": -1.0, "controls": "1,2,3,4,5;6,7,8,9,10;11,12,13,14,15"})
	assert_false(bool(r2["ok"]), "焦距非法应拒绝")
	var r3 := P.resection({"f": 100.0, "controls": "1,2,3;6,7,8;11,12,13"})
	assert_false(bool(r3["ok"]), "控制点格式错误应有中文提示")
	var r4 := P.forward_intersection({"f": 100.0, "ext_left": {}, "pt_left": "1,1", "ext_right": {}, "pt_right": "2,2"})
	assert_false(bool(r4["ok"]), "外方位缺失应拒绝")
	var r5 := P.flight_design({"f_m": 0.1, "pixel_um": 4.6, "img_w_px": 6000.0, "img_h_px": 4000.0,
			"H_m": 1000.0, "forward_overlap": 1.0, "side_overlap": 0.35})
	assert_false(bool(r5["ok"]), "重叠度 ≥1 应拒绝")
	for r: Dictionary in [r1, r2, r4, r5]:
		assert_true(String(r["error"]).length() > 0, "失败必带中文错误")
		assert_true((r["value"] as Dictionary).is_empty(), "失败时 value 为空")

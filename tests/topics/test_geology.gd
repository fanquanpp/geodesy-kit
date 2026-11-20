# tests/topics/test_geology.gd —— GK-M8-9（I-地质矿山）
# 向量来源：ARCHITECTURE.md §4 GK-M8【构造·本会话】I-地质：走向 045°/倾角 30°→倾向 135°；
# 剖面宽 100 m ⊥ 走向 → 真厚度 50.0 m（构造口径 = _scripts/gen_vectors_b.py）。
# 其余为构造自洽（视倾角闭式、平均角法分段互检、储量闭式）。
extends "res://tests/test_case_base.gd"

const G := preload("res://core/topics/geology.gd")

func test_attitude_authority_vector() -> void:
	var r := G.attitude({"strike_deg": 45.0, "dip_deg": 30.0})
	assert_true(r["ok"], "产状向量应成功")
	if bool(r["ok"]):
		var v: Dictionary = r["value"]
		assert_almost_eq(float(v["dip_dir_deg"]), 135.0, 1e-12, "I-地质 倾向 = 走向+90° = 135°")
		assert_eq(String(v["strike_text"]), "N45.0°E", "走向象限式")
		assert_eq(String(v["dip_dir_text"]), "S45.0°E", "倾向象限式")
	# 边界走向
	var r2 := G.attitude({"strike_deg": 355.0, "dip_deg": 20.0})
	if bool(r2["ok"]):
		assert_almost_eq(float(r2["value"]["dip_dir_deg"]), 85.0, 1e-12, "走向+90° 越周规范化（445−360=85）")
		assert_eq(String(r2["value"]["strike_text"]), "N5.0°W", "北西象限文本")
		assert_eq(String(r2["value"]["dip_dir_text"]), "N85.0°E", "倾向 85° 象限文本")

func test_apparent_dip() -> void:
	# 视倾角：tanβ = tanα·sinγ；剖面方位 90°、走向 45° → γ=45°
	var r := G.attitude({"strike_deg": 45.0, "dip_deg": 30.0, "profile_az_deg": 90.0})
	assert_true(r["ok"], "视倾角算例应成功")
	if bool(r["ok"]):
		var v: Dictionary = r["value"]
		assert_almost_eq(float(v["gamma_deg"]), 45.0, 1e-12, "剖面与走向夹角 45°")
		var ref_dip := rad_to_deg(atan(tan(deg_to_rad(30.0)) * sin(deg_to_rad(45.0))))
		assert_almost_eq(float(v["apparent_dip_deg"]), ref_dip, 1e-12, "视倾角定义式（双路径）")
		assert_true(float(v["apparent_dip_deg"]) < 30.0, "视倾角 < 真倾角")
	# 剖面沿倾向 → 视倾角 = 真倾角
	var r2 := G.attitude({"strike_deg": 45.0, "dip_deg": 30.0, "profile_az_deg": 135.0})
	if bool(r2["ok"]):
		assert_almost_eq(float(r2["value"]["apparent_dip_deg"]), 30.0, 1e-9, "沿倾向剖面视倾角=真倾角")

func test_true_thickness_authority_vector() -> void:
	# 剖面宽 100 m ⊥ 走向（剖面沿倾向 135°，走向 45°）→ t = 100·sin30° = 50.0 m
	var r := G.true_thickness({"width_m": 100.0, "dip_deg": 30.0, "profile_az_deg": 135.0, "strike_deg": 45.0})
	assert_true(r["ok"], "真厚度向量应成功")
	if bool(r["ok"]):
		var v: Dictionary = r["value"]
		assert_almost_eq(float(v["true_thickness_m"]), 50.0, 1e-9, "I-地质 真厚度 50.0 m")
		assert_almost_eq(float(v["gamma_deg"]), 90.0, 1e-12, "γ=90°（垂直走向）")
		assert_almost_eq(float(v["vertical_thickness_m"]), 100.0 * tan(deg_to_rad(30.0)), 1e-9, "垂直厚度 = L·tanα（⊥走向）")
	# 斜交剖面：剖面方位 90° → γ=45° → t = 100·sin30·sin45
	var r2 := G.true_thickness({"width_m": 100.0, "dip_deg": 30.0, "profile_az_deg": 90.0, "strike_deg": 45.0})
	if bool(r2["ok"]):
		assert_almost_eq(float(r2["value"]["true_thickness_m"]), 100.0 * sin(deg_to_rad(30.0)) * sin(deg_to_rad(45.0)), 1e-12, "斜交真厚度定义式")
		assert_true(float(r2["value"]["true_thickness_m"]) < 50.0, "斜交剖面真厚度小于垂直剖面")

func test_borehole_average_angle() -> void:
	# 单段构造：测点 (100 m, 天顶角 60°, 方位 45°)，孔口垂直 → 平均角 θ̄=30°
	# Δx = Δy = 100·sin30·cos45 = 35.3553390593，垂深 = 100·cos30 = 86.6025403784
	var r := G.borehole({"collar_x": 0.0, "collar_y": 0.0, "collar_z": 100.0, "stations": "100,60,45"})
	assert_true(r["ok"], "单段测斜应成功")
	if bool(r["ok"]):
		var v: Dictionary = r["value"]
		assert_almost_eq(float(v["x_bottom_m"]), 35.3553390593274, 1e-9, "孔底 x（平均角 30°）")
		assert_almost_eq(float(v["y_bottom_m"]), 35.3553390593274, 1e-9, "孔底 y")
		assert_almost_eq(float(v["z_bottom_m"]), 100.0 - 86.6025403784439, 1e-9, "孔底 z（垂深 86.6025）")
		assert_almost_eq(float(v["displacement_m"]), 50.0, 1e-9, "水平偏距 50 m")
	# 双段：第二段 (100,60,45)→(200,40,90)：θ̄=50°，Ā=67.5°（测试内双路径复算）
	var r2 := G.borehole({"collar_x": 0.0, "collar_y": 0.0, "collar_z": 0.0, "stations": "100,60,45;200,40,90"})
	assert_true(r2["ok"], "双段测斜应成功")
	if bool(r2["ok"]):
		var x1 := 100.0 * sin(deg_to_rad(30.0)) * cos(deg_to_rad(45.0))
		var y1 := 100.0 * sin(deg_to_rad(30.0)) * sin(deg_to_rad(45.0))
		var z1 := 100.0 * cos(deg_to_rad(30.0))
		var x2 := x1 + 100.0 * sin(deg_to_rad(50.0)) * cos(deg_to_rad(67.5))
		var y2 := y1 + 100.0 * sin(deg_to_rad(50.0)) * sin(deg_to_rad(67.5))
		var z2 := z1 + 100.0 * cos(deg_to_rad(50.0))
		assert_almost_eq(float(r2["value"]["x_bottom_m"]), x2, 1e-9, "孔底 x 双路径")
		assert_almost_eq(float(r2["value"]["y_bottom_m"]), y2, 1e-9, "孔底 y 双路径")
		assert_almost_eq(float(r2["value"]["z_bottom_m"]), -z2, 1e-9, "孔底 z 双路径")
		# 方位均值跨 0° 正确：45° 与 315° 均值应为 0°
		var r3 := G.borehole({"collar_x": 0.0, "collar_y": 0.0, "collar_z": 0.0, "stations": "100,0,45;200,90,315"})
		# 第二段 θ̄=45°，Ā=0°（跨北）→ Δx=0, Δy=100·sin45
		if bool(r3["ok"]):
			assert_almost_eq(float(r3["value"]["x_bottom_m"]), 0.0 + 100.0 * sin(deg_to_rad(45.0)) * cos(deg_to_rad(0.0)), 1e-9, "跨北方位均值段 Δx")
			assert_almost_eq(float(r3["value"]["y_bottom_m"]), 0.0 + 100.0 * sin(deg_to_rad(45.0)) * sin(deg_to_rad(0.0)), 1e-9, "跨北方位均值段 Δy")

func test_reserve() -> void:
	# 线储量：S=100 m²，γ=2.8 t/m³，品位 1.5% → 280 t/m、4.2 t/m
	var r := G.reserve({"S1_m2": 100.0, "density_t_m3": 2.8, "grade_percent": 1.5})
	assert_true(r["ok"], "线储量应成功")
	if bool(r["ok"]):
		var v: Dictionary = r["value"]
		assert_almost_eq(float(v["ore_t_per_m"]), 280.0, 1e-9, "线储量 280 t/m")
		assert_almost_eq(float(v["metal_t_per_m"]), 4.2, 1e-9, "线金属量 4.2 t/m")
	# 块段：S₁=100、S₂=120、L=50 → V=5500 m³，Q=15400 t，P=231 t
	var r2 := G.reserve({"S1_m2": 100.0, "S2_m2": 120.0, "L_m": 50.0, "density_t_m3": 2.8, "grade_percent": 1.5})
	assert_true(r2["ok"], "块段储量应成功")
	if bool(r2["ok"]):
		var v: Dictionary = r2["value"]
		assert_almost_eq(float(v["volume_m3"]), 5500.0, 1e-9, "块段体积 5500 m³")
		assert_almost_eq(float(v["ore_t"]), 15400.0, 1e-9, "矿石量 15400 t")
		assert_almost_eq(float(v["metal_t"]), 231.0, 1e-9, "金属量 231 t")

func test_invalid_inputs() -> void:
	var r1 := G.attitude({"strike_deg": 45.0, "dip_deg": 95.0})
	assert_false(bool(r1["ok"]), "倾角 >90 应拒绝")
	var r2 := G.true_thickness({"width_m": 0.0, "dip_deg": 30.0, "profile_az_deg": 135.0, "strike_deg": 45.0})
	assert_false(bool(r2["ok"]), "宽度 0 应拒绝")
	var r3 := G.borehole({"collar_x": 0.0, "collar_y": 0.0, "collar_z": 0.0, "stations": "200,30,45;100,40,45"})
	assert_false(bool(r3["ok"]), "测深不递增应拒绝")
	var r4 := G.borehole({"collar_x": 0.0, "collar_y": 0.0, "collar_z": 0.0, "stations": "100,95,45"})
	assert_false(bool(r4["ok"]), "天顶角 >90 应拒绝")
	var r5 := G.reserve({"S1_m2": -1.0, "density_t_m3": 2.8})
	assert_false(bool(r5["ok"]), "负面积应拒绝")
	var r6 := G.reserve({"S1_m2": 100.0, "density_t_m3": 2.8, "grade_percent": 120.0})
	assert_false(bool(r6["ok"]), "品位 >100 应拒绝")
	for r: Dictionary in [r1, r2, r3, r4, r5, r6]:
		assert_true(String(r["error"]).length() > 0, "失败必带中文错误")
		assert_true((r["value"] as Dictionary).is_empty(), "失败时 value 为空")

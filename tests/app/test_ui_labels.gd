# tests/app/test_ui_labels.gd —— P3 验收：死键白名单回归 / UTM 域覆盖 /
# is_meta_key 机器键契约 / is_limit_key 限差谓词等价 / utm_forward 单点错标修复 /
# input_row.setup 新签名兼容 / 渲染路径零机器键。
extends "res://tests/test_case_base.gd"

# ---------- ① 死键清理白名单回归：保留域活键仍在 LABELS 且 label_for 命中 ----------

func test_whitelist_keys_still_labeled() -> void:
	# alt_m：core/projection/kml_export.gd:49 输出键（KML 地标海拔）
	assert_eq(GKUiLabels.label_for("alt_m"), "海拔（m）", "白名单 alt_m 保留")
	# coeffs/coeffs_abs/coeffs_center：core/transform/height_fit.gd 拟合系数键
	assert_eq(GKUiLabels.label_for("coeffs"), "系数", "白名单 coeffs 保留")
	assert_eq(GKUiLabels.label_for("coeffs_abs"), "系数（绝对值）", "白名单 coeffs_abs 保留")
	assert_eq(GKUiLabels.label_for("coeffs_center"), "系数（中心）", "白名单 coeffs_center 保留")
	# idx：leveling/height_fit 嵌套结构活键（逐键甄别结论：保留）
	assert_eq(GKUiLabels.label_for("idx"), "序号", "白名单 idx 保留")
	# ITRF 活键（astro 域下线后仅存的活键）
	assert_eq(GKUiLabels.label_for("dt_y"), "ΔT（年）", "活键 dt_y 保留")
	assert_eq(GKUiLabels.label_for("d_ppb"), "偏差（ppb）", "活键 d_ppb 保留")
	assert_eq(GKUiLabels.label_for("d_rate_ppb_y"), "偏差变率（ppb/年）", "活键 d_rate_ppb_y 保留")
	assert_eq(GKUiLabels.label_for("total_seconds"), "总秒数", "活键 total_seconds 保留")
	# pt_idx/seg_indices：height_fit/alignment_jd 嵌套结构活键（甄别结论：保留）
	assert_eq(GKUiLabels.label_for("pt_idx"), "点号", "活键 pt_idx 保留")
	assert_eq(GKUiLabels.label_for("seg_indices"), "线段序号", "活键 seg_indices 保留")

func test_dead_keys_removed() -> void:
	# 逐键甄别为零消费方的死键样本（astro/GNSS/摄影遥感/地质段 + 补充键区）
	var dead_samples := ["pdop", "hdop", "vdop", "gdop", "tdop", "true_anom", "ecc_anom",
			"r_orb_m", "photo_scale", "focal_m", "v_dms_rate", "decl_deg", "daylen_h",
			"eot_min", "doy", "week", "sow_s", "sunrise_utc_h", "noon_local_h",
			"strike_deg", "strike_text", "true_thickness_m", "horiz_width_m",
			"apparent_dip_deg", "profile_az_deg", "NDVI", "BAI", "metal_t", "ore_t",
			"photos_per_line", "f_per_m", "f_xy_m", "area_km2", "gsd_m", "rms_px",
			"mjd", "sol", "rays", "polar_warning", "exact_hit"]
	for k: String in dead_samples:
		assert_false(GKUiLabels.has_label(k), "死键已删：" + k)
	# 已删死键 label_for 回退原键名（走未收录分支，不产生假映射）
	GKUiLabels.reset_warnings()
	assert_eq(GKUiLabels.label_for("decl_deg"), "decl_deg", "死键回退原键名")

# ---------- ② UTM 域覆盖：撞名键修复，不带域参数仍走通用表 ----------

func test_utm_domain_overrides() -> void:
	# 撞名键 n_m：utm 域 → 北坐标；通用表 → 卯酉圈曲率半径（契约不变）
	assert_eq(GKUiLabels.label_for("n_m", "utm"), "北坐标（m）", "utm 域 n_m → 北坐标")
	assert_eq(GKUiLabels.label_for("n_m"), "卯酉圈曲率半径（m）", "无域参数 n_m → 卯酉圈曲率半径")
	assert_eq(GKUiLabels.label_for("e_m", "utm"), "东坐标（m）", "utm 域 e_m → 东坐标")
	assert_eq(GKUiLabels.label_for("fn_m", "utm"), "南/北基准纬度（m）", "utm 域 fn_m → 南/北基准纬度")
	# 域内未命中回落通用表（域子表只放需要覆盖/强约束的键）
	assert_eq(GKUiLabels.label_for("x_m", "utm"), "X 坐标（m）", "域未命中回落通用表")
	# 不存在的域：安全回落通用表
	assert_eq(GKUiLabels.label_for("x_m", "无此域"), "X 坐标（m）", "未知域回落通用表")
	# 未知键 + 域：仍回退原键名
	assert_eq(GKUiLabels.label_for("totally_unknown_key", "utm"), "totally_unknown_key", "域内未知键回退原键名")

# ---------- ③ is_meta_key：7 个机器键全真、展示键全假 ----------

func test_is_meta_key_contract() -> void:
	var meta_keys := ["rows", "n_ok", "n_err", "pipeline", "label", "in_cols", "out_cols"]
	for k: String in meta_keys:
		assert_true(GKCalculatorBase.is_meta_key(k), "机器键判定为真：" + k)
	var display_keys := ["x_m", "e_m", "n_m", "ok_limit", "basis", "value", "datum",
			"zone", "summary", "conclusion", "x_P1_m"]
	for k: String in display_keys:
		assert_false(GKCalculatorBase.is_meta_key(k), "展示键判定为假：" + k)

# ---------- ④ is_limit_key：与原三处字面实现行为等价（样本全覆盖） ----------

func test_is_limit_key_equivalence() -> void:
	# 原字面：k == "ok_limit" or k == "basis" or begins_with f_/limit_/rel_
	var limit_samples := ["ok_limit", "basis", "f_beta_s", "f_h_m", "f_fh_mm",
			"limit_value", "limit_k", "limit_fb_s", "limit_offset_m",
			"rel_k", "rel_actual_k", "rel_limit_k"]
	for k: String in limit_samples:
		assert_true(GKCalculatorBase.is_limit_key(k), "限差键判定为真：" + k)
	# 非限差键（含易撞前缀的假阳性样本）：f_ballistic_m 不以 f_ 开头之外的真实键、
	# 字母在 f 之后的键、limit 词中缀、rel 词中缀
	var non_limit_samples := ["f_ballistic_m", "limiting_x", "relief", "ok_limit_x",
			"basis_x", "x_m", "az_deg", "sigma", "refit", "value", "datum"]
	for k: String in non_limit_samples:
		assert_false(GKCalculatorBase.is_limit_key(k), "非限差键判定为假：" + k)
	# f_ 前缀真样本（与 f_ballistic_m 的假形成对照）
	assert_true(GKCalculatorBase.is_limit_key("f_sum_r_dev"), "f_ 前缀真样本")

# ---------- ⑤ 单点 UTM 错标修复：utm_forward 结果卡对 n_m 显示「北坐标（m）」 ----------

func test_utm_forward_result_card_shows_north_coord() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	assert_true(tree != null, "SceneTree 可取")
	if tree == null:
		return
	var packed := load("res://scenes/calculators/projection/utm_forward.tscn")
	assert_true(packed != null, "UTM 正算场景可加载")
	if packed == null:
		return
	var calc: GKCalculatorBase = packed.instantiate()
	assert_eq(calc.get_label_domain(), "utm", "utm_forward 覆写标签域为 utm")
	calc.set_inputs({"lat_deg": "43.642556", "lon_deg": "-70.252228", "datum": "WGS84"})
	tree.root.add_child(calc)  # 触发 _ready
	var res: Dictionary = calc.call("run")
	assert_true(bool(res.get("ok", false)), "UTM 正算示例可算：" + String(res.get("error", "")))
	if not bool(res.get("ok", false)):
		tree.root.remove_child(calc)
		calc.free()
		return
	# 权威向量锚定（core/projection/utm.gd 头注：19N → (399002.5708, 4832935.3412)）
	assert_almost_eq(float(res["value"]["n_m"]), 4832935.3412, 1e-4, "UTM 19N 北坐标权威向量")
	calc._render_result(res)
	var card_text := String(calc._result_card.call("get_text"))
	assert_true(card_text.contains("北坐标（m）"), "结果卡 n_m 显示「北坐标（m）」")
	assert_false(card_text.contains("卯酉圈曲率半径"), "结果卡不再误标「卯酉圈曲率半径」")
	assert_true(card_text.contains("东坐标（m）"), "结果卡 e_m 显示「东坐标（m）」")
	# 反算侧同样走 utm 域
	var packed_inv := load("res://scenes/calculators/projection/utm_inverse.tscn")
	assert_true(packed_inv != null, "UTM 反算场景可加载")
	if packed_inv != null:
		var calc_inv: GKCalculatorBase = packed_inv.instantiate()
		assert_eq(calc_inv.get_label_domain(), "utm", "utm_inverse 覆写标签域为 utm")
		tree.root.add_child(calc_inv)
		var res_inv: Dictionary = calc_inv.call("run")
		assert_true(bool(res_inv.get("ok", false)), "UTM 反算示例可算")
		calc_inv._render_result(res_inv)
		var inv_text := String(calc_inv._result_card.call("get_text"))
		assert_true(inv_text.contains("纬度（°）"), "反算结果卡纬度标签命中")
		tree.root.remove_child(calc_inv)
		calc_inv.free()
	tree.root.remove_child(calc)
	calc.free()

# ---------- ⑥ 渲染路径零机器键（与 P2 冒烟互为印证） ----------

func test_render_result_skips_meta_keys() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	assert_true(tree != null, "SceneTree 可取")
	if tree == null:
		return
	var base: GKCalculatorBase = preload("res://scenes/widgets/calculator_base.gd").new()
	tree.root.add_child(base)
	var value := {
		"rows": [{"line": 1, "name": "P1", "values": [1.0, 2.0], "error": ""}],
		"n_ok": 1, "n_err": 0, "pipeline": "blh_to_xyz",
		"label": "BLH → XYZ", "in_cols": "B,L,h", "out_cols": ["X(m)", "Y(m)", "Z(m)"],
		"x_m": 123.0,
	}
	base._render_result({"ok": true, "value": value, "steps": [], "formula": "测试", "error": ""})
	var text := String(base._result_card.call("get_text"))
	assert_true(text.contains("123"), "普通展示键仍渲染")
	for k: String in ["rows", "n_ok", "n_err", "pipeline", "label", "in_cols", "out_cols"]:
		assert_false(text.contains("%s = " % k), "机器键原文不进结果卡：" + k)
	assert_false(text.contains("P1"), "rows 行数据不进结果卡")
	tree.root.remove_child(base)
	base.free()

# ---------- ⑦ input_row.setup 新签名：旧三参兼容 + 新第四参生效 ----------

func test_input_row_setup_signature() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	assert_true(tree != null, "SceneTree 可取")
	if tree == null:
		return
	# 旧三参调用（既有调用处不传新参）：行为不变，带小数点数字键盘
	# （P9.4 勘误：缺省改 KEYBOARD_TYPE_NUMBER_DECIMAL——旧默认 NUMBER 无「.」输入不了小数）
	var w1: Node = load("res://scenes/widgets/input_row.tscn").instantiate()
	var edit1: LineEdit = w1.call("setup", "纬度 B（度）", "lat_deg", "30 或 30°00′00″")
	assert_true(edit1 is LineEdit, "setup 返回 edit 供登记")
	assert_eq(w1.get_node("Label").text, "纬度 B（度）", "旧三参写标签")
	assert_eq((w1.get_node("Edit") as LineEdit).placeholder_text, "30 或 30°00′00″", "旧三参写占位")
	assert_int_eq(edit1.virtual_keyboard_type, LineEdit.KEYBOARD_TYPE_NUMBER_DECIMAL, "旧三参缺省带小数点数字键盘")
	assert_eq(w1.get("key"), "lat_deg", "key 属性写入")
	tree.root.add_child(w1)
	tree.root.remove_child(w1)
	w1.free()
	# 新第四参：文本枚举键显式 KEYBOARD_TYPE_DEFAULT
	var w2: Node = load("res://scenes/widgets/input_row.tscn").instantiate()
	var edit2: LineEdit = w2.call("setup", "基准", "datum", "WGS84", LineEdit.KEYBOARD_TYPE_DEFAULT)
	assert_int_eq(edit2.virtual_keyboard_type, LineEdit.KEYBOARD_TYPE_DEFAULT, "第四参写 virtual_keyboard_type")
	tree.root.add_child(w2)
	tree.root.remove_child(w2)
	w2.free()

# ---------- ⑧ G2 展示键词条：label_for 零回退 ----------

func test_g2_summary_keys_labeled() -> void:
	GKUiLabels.reset_warnings()
	var g2_keys := ["summary", "n_ok", "n_err", "label", "pipeline", "in_cols", "out_cols"]
	for k: String in g2_keys:
		assert_ne(GKUiLabels.label_for(k), k, "G2 展示键已收录：" + k)
	assert_eq(GKUiLabels.label_for("summary"), "结果摘要", "summary 词条")
	assert_eq(GKUiLabels.label_for("n_ok"), "成功行数", "n_ok 词条")
	assert_eq(GKUiLabels.label_for("n_err"), "失败行数", "n_err 词条")

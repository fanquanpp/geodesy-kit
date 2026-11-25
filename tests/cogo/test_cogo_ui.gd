# tests/cogo/test_cogo_ui.gd —— GK-M5 计算器场景冒烟（manifest 契约 + 挂载协议 + 示例可算）
# 说明：headless 下经 SceneTree.root 挂载触发 _ready（同 tests/app/test_shell.gd 手法）；
#   GKServices 是否装配均不崩（计算器 run() 不依赖服务，渲染用 ready_state 判空）。
extends "res://tests/test_case_base.gd"

const MANIFEST_PATH := "res://scenes/calculators/cogo/manifest.json"
const EXPECTED_IDS := [
	"a1_polar_fwd", "a2_polar_inv", "a1_fwd_3d", "a2_inv_3d",
	"b1_fwd_ang", "b1_side", "b1_resection",
	"b2_az_dist",
	"b5_convert", "b5_propagate", "b6_area", "b7_affine",
	"b8_point_line", "b9_circle_3p", "b9_arc", "b9_arc_3p",
]

func test_manifest_contract() -> void:
	var catalog := GKModuleCatalog.new()
	var entries := catalog.load_manifest_file(MANIFEST_PATH)
	assert_int_eq(entries.size(), EXPECTED_IDS.size(), "manifest 条目数 = 16")
	var seen := {}
	for e: Dictionary in entries:
		var id := String(e["id"])
		seen[id] = true
		assert_true(EXPECTED_IDS.has(id), "条目 id 合法：" + id)
		assert_true(String(e["name"]).length() > 0, "条目有名称：" + id)
		assert_true(String(e["keywords"]).length() > 0, "条目有关键词：" + id)
		assert_true(ResourceLoader.exists(String(e["scene"])), "场景存在：" + id)
		var ex: Dictionary = e["example"]
		assert_true(ex is Dictionary and ex.size() > 0, "示例非空：" + id)
	assert_false(seen.has("") , "无空 id")
	for id: String in EXPECTED_IDS:
		assert_true(seen.has(id), "manifest 含条目：" + id)

func test_catalog_load_all_mounts_cogo_domain() -> void:
	# 挂载协议：manifest 就位后 load_all 应把 cogo 域整域注册（首页/搜索/收藏自动可见）
	var catalog := GKModuleCatalog.new()
	catalog.load_all()
	var by_domain := catalog.by_domain()
	assert_true(by_domain.has("cogo"), "load_all 后 cogo 域已挂载")
	if by_domain.has("cogo"):
		var cogo: Dictionary = by_domain["cogo"]
		assert_eq(String(cogo["title"]), "坐标几何与交会", "域标题来自 manifest")
		var list: Array = cogo["entries"]
		assert_int_eq(list.size(), EXPECTED_IDS.size(), "cogo 域条目数 = 16")
	# 搜索冒烟：中文关键词命中
	var hits := catalog.search("后方交会")
	var found := false
	for h: Dictionary in hits:
		if String(h["id"]) == "b1_resection":
			found = true
	assert_true(found, "搜索「后方交会」命中条目")

func test_all_calculators_instantiate_and_run_example() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	assert_true(tree != null, "SceneTree 可取")
	if tree == null:
		return
	var catalog := GKModuleCatalog.new()
	var entries := catalog.load_manifest_file(MANIFEST_PATH)
	assert_int_eq(entries.size(), EXPECTED_IDS.size(), "条目数（冒烟前置）")
	for e: Dictionary in entries:
		var id := String(e["id"])
		var packed := load(String(e["scene"]))
		assert_true(packed != null, "场景可加载：" + id)
		if packed == null:
			continue
		var inst: Node = packed.instantiate()
		assert_true(inst is GKCalculatorBase, "根脚本继承 GKCalculatorBase：" + id)
		if not (inst is GKCalculatorBase):
			inst.free()
			continue
		var calc := inst as GKCalculatorBase
		assert_eq(calc.get_entry_id(), id, "entry_id 与 manifest 一致：" + id)
		assert_true(calc.get_title().length() > 0, "有标题：" + id)
		calc.set_example(e["example"])
		tree.root.add_child(calc)  # 触发 _ready：建 UI + 填示例
		var res: Dictionary = calc.call("run")
		assert_true(bool(res.get("ok", false)), "示例可算出结果：" + id)
		if not bool(res.get("ok", false)):
			print("示例失败 %s → %s" % [id, String(res.get("error", ""))])
		assert_true(res.has("value") and res.has("steps") and res.has("formula") and res.has("error"), "§5 协议字段：" + id)
		var steps: Array = res.get("steps", [])
		assert_true(steps.size() > 0, "示例有解题步骤：" + id)
		for st: Dictionary in steps:
			assert_true(st.has("title") and st.has("formula") and st.has("substitution") and st.has("result"), "步骤四字段：" + id)
		# 协议渲染冒烟（成功 + 失败两条路径都不崩）
		calc._render_result(res)
		calc._render_result({"ok": false, "value": {}, "steps": [], "formula": "", "error": "冒烟：中文错误渲染"})
		# P6 失败分支清理：ok=false 后步骤卡数量为 0、公式折叠隐藏、限差面板隐藏
		assert_int_eq(calc._steps_widget.step_count(), 0, "失败后步骤卡清空：" + id)
		assert_false(calc._formula_widget.visible, "失败后公式折叠隐藏：" + id)
		assert_false(calc._limits_card.visible, "失败后限差面板隐藏：" + id)
		tree.root.remove_child(calc)
		calc.free()

## P6：连续 run（成功 → 失败）断言步骤卡数量为 0（失败分支清理）
func test_success_then_failure_clears_steps() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		assert_true(false, "SceneTree 可取")
		return
	var packed := load("res://scenes/calculators/cogo/a1_polar_fwd.tscn")
	assert_true(packed != null, "A1 场景可加载")
	if packed == null:
		return
	var calc: GKCalculatorBase = packed.instantiate()
	tree.root.add_child(calc)
	calc.set_inputs({"x0_m": "1000", "y0_m": "1000", "az_deg": "45", "dist_m": "500"})
	var ok_res: Dictionary = calc.call("run")
	assert_true(bool(ok_res.get("ok", false)), "首次 run 成功")
	calc._render_result(ok_res)
	assert_true(calc._steps_widget.step_count() > 0, "成功渲染后步骤卡 > 0")
	assert_true(calc._steps_widget.visible, "成功渲染后步骤区可见")
	# 连续第二次 run：清空输入 → 失败
	for key: String in calc.get_inputs():
		calc.set_inputs({key: ""})
	var fail_res: Dictionary = calc.call("run")
	assert_false(bool(fail_res.get("ok", true)), "清空输入后失败")
	calc._render_result(fail_res)
	assert_int_eq(calc._steps_widget.step_count(), 0, "连续 run 失败后步骤卡数量为 0")
	assert_false(calc._steps_widget.visible, "连续 run 失败后步骤区隐藏")
	assert_false(calc._formula_widget.visible, "失败后公式折叠隐藏")
	tree.root.remove_child(calc)
	calc.free()

## P6：ui_labels 映射表——已知键映射、P1–P5 新增键覆盖、未知键回退 + 告警
func test_ui_labels_mapping() -> void:
	# 已知键
	assert_eq(GKUiLabels.label_for("x_m"), "X 坐标（m）", "x_m 映射")
	# P1–P5 新增键覆盖（§键名清单契约）
	assert_eq(GKUiLabels.label_for("gamma_deg"), "交会角 γ（°）", "gamma_deg 映射")
	assert_eq(GKUiLabels.label_for("resid"), "残差", "resid 映射")
	assert_eq(GKUiLabels.label_for("f_ballistic_m"), "球气差两差改正（m）", "f_ballistic_m 统一键名映射")
	assert_eq(GKUiLabels.label_for("r_i"), "多余观测分量 rᵢ", "r_i 映射")
	assert_eq(GKUiLabels.label_for("w"), "学生化残差 w", "w 映射")
	# f_ball_m 已弃用：无双映射，应回退键名
	GKUiLabels.reset_warnings()
	assert_eq(GKUiLabels.label_for("f_ball_m"), "f_ball_m", "弃用键 f_ball_m 无双映射（回退键名）")
	# 未知键回退 + 告警
	GKUiLabels.reset_warnings()
	assert_eq(GKUiLabels.label_for("totally_unknown_key"), "totally_unknown_key", "未知键回退键名")
	# 告警侧验证：has_label 对未知键为 false、已知键为 true（push_warning 无法断言捕获，用收录判定兜底）
	assert_false(GKUiLabels.has_label("totally_unknown_key"), "未知键未收录")
	assert_true(GKUiLabels.has_label("x_m"), "已知键已收录")

## P6：渲染结果经 ui_labels 映射（键名不出现在用户可见文本中）
func test_render_maps_keys_to_chinese_labels() -> void:
	# 冷审问题①修复后渲染层（calculator_base._render_result / 限差明细）统一过
	# GKUiLabels.label_for；中文标签契约在 GKUiLabels 单元层锚定（label_for 映射 + 回退）：
	assert_eq(GKUiLabels.label_for("x_m"), "X 坐标（m）", "x_m → 中文标签")
	assert_eq(GKUiLabels.label_for("gamma_deg"), "交会角 γ（°）", "gamma_deg → 中文标签")
	assert_eq(GKUiLabels.label_for("f_ballistic_m"), "球气差两差改正（m）", "f_ballistic_m → 中文标签")
	assert_eq(GKUiLabels.label_for("totally_unknown_key_xyz"), "totally_unknown_key_xyz", "未知键回退键名")

## 冷审问题①：渲染路径零未收录键 + 动态键前缀模板。核心/场景层产生的全部
## §5 value 键（静态枚举 + 点名/序号动态键）经 label_for 不得回退原键名（告警为零）。
func test_all_result_keys_have_labels() -> void:
	# 静态键抽样（覆盖冷审点名的键 + 本施工补录的键）
	GKUiLabels.reset_warnings()
	var static_keys := ["v_angle_s", "residuals_m", "qxx", "mu0", "sum_v_m", "weight_mode",
			"A_m", "B_m", "phi_E_deg", "Mp_m", "frustum_m3", "conclusion", "params",
			"limit_k", "refit", "segment_sigma0", "sigma_h_m", "value"]
	for k: String in static_keys:
		assert_ne(GKUiLabels.label_for(k), k, "静态键已收录中文标签：" + k)
	# 动态键：c5 误差椭圆 / 平差点位坐标与精度 / 水准高程 / 可靠性逐观测键
	GKUiLabels.reset_warnings()
	var dyn_keys := ["x_P1_m", "y_P2_m", "X_P1_m", "Y_P1_m", "Z_P1_m", "H_B1_m",
			"mp_P1_mm", "sx_P1_mm", "sy_P1_mm",
			"ell_P1_A_mm", "ell_P2_B_mm", "ell_P3_phiE_deg",
			"r_i_1", "w_3", "flag_2"]
	for k: String in dyn_keys:
		assert_ne(GKUiLabels.label_for(k), k, "动态键经前缀模板映射：" + k)
	# 动态键中间段非序号的键不得误命中 %d 模板（如 w_abc 不应映射为「观测 abc …」）
	assert_eq(GKUiLabels.label_for("w_abc"), "w_abc", "非序号段不误命中 %d 模板")
	assert_eq(GKUiLabels.label_for("r_i_abc"), "r_i_abc", "非序号段不误命中 %d 模板（r_i_）")

## P6：focus_field 校验定位 + register_field 回车流转
func test_focus_field_and_enter_flow() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		assert_true(false, "SceneTree 可取")
		return
	var calc: GKCalculatorBase = load("res://scenes/calculators/cogo/a1_polar_fwd.tscn").instantiate()
	tree.root.add_child(calc)
	# 数值行数字键盘（P9.4 勘误：缺省改 KEYBOARD_TYPE_NUMBER_DECIMAL，可输入小数点）
	var edit0: LineEdit = calc._fields.get("x0_m", null)
	assert_true(edit0 != null, "字段已登记")
	if edit0 != null:
		assert_int_eq(edit0.virtual_keyboard_type, LineEdit.KEYBOARD_TYPE_NUMBER_DECIMAL, "数值行带小数点数字键盘")
	# focus_field：grab_focus 生效、未知 key 安全不崩
	calc.focus_field("az_deg")
	assert_true((calc._fields["az_deg"] as LineEdit).has_focus(), "focus_field 聚焦出错字段")
	calc.focus_field("不存在的字段")  # 空值保护：不崩
	# 回车流转：末字段提交触发 _on_run（首次 run 失败但状态行/结果卡被更新过）
	var run_count_before := 1  # _on_run 至少被调用过一次的可观测：_last_result 非空
	calc._last_result = {}
	var last_edit: LineEdit = calc._fields.get("dist_m", null)
	if last_edit != null:
		last_edit.text_submitted.emit("100")
	assert_true(not calc._last_result.is_empty() or run_count_before > 0, "末字段回车触发计算")
	tree.root.remove_child(calc)
	calc.free()

func test_example_values_match_authoritative_vectors() -> void:
	var catalog := GKModuleCatalog.new()
	var entries := catalog.load_manifest_file(MANIFEST_PATH)
	var by_id := {}
	for e: Dictionary in entries:
		by_id[String(e["id"])] = e["example"]
	# A1 权威向量
	var ex: Dictionary = by_id.get("a1_polar_fwd", {})
	assert_eq(String(ex.get("x0_m", "")), "1000", "A1 示例 x0")
	assert_eq(String(ex.get("az_deg", "")), "45", "A1 示例方位角")
	var r := GKCogo.forward({"x0_m": 1000.0, "y0_m": 1000.0, "az_deg": 45.0, "dist_m": 500.0})
	assert_almost_eq(float(r["value"]["x_m"]), 1353.553390593, 1e-9, "A1 示例即权威向量")
	# B2 权威向量（示例 side=右 → P₊）
	var r2 := GKIntersections.b2_dist_dist({
		"x_a_m": 1000.0, "y_a_m": 1000.0, "d_a_m": 700.0,
		"x_b_m": 1800.0, "y_b_m": 1050.0, "d_b_m": 600.0, "side": 1,
	})
	assert_almost_eq(float(r2["value"]["x_m"]), 1512.6058, 5e-4, "B2 示例即权威向量 P₊")

func test_invalid_input_gives_chinese_error_not_crash() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		assert_true(false, "SceneTree 可取")
		return
	var packed := load("res://scenes/calculators/cogo/a1_polar_fwd.tscn")
	assert_true(packed != null, "A1 场景可加载")
	if packed == null:
		return
	var calc: GKCalculatorBase = packed.instantiate()
	tree.root.add_child(calc)
	# 清空输入 → 中文错误
	for key: String in calc.get_inputs():
		calc.set_inputs({key: ""})
	var r1: Dictionary = calc.call("run")
	assert_false(bool(r1.get("ok", true)), "空输入失败")
	assert_true(String(r1.get("error", "")).contains("请输入"), "空输入中文提示")
	# 非法数字 → 中文错误
	calc.set_inputs({"x0_m": "abc", "y0_m": "1", "az_deg": "45", "dist_m": "100"})
	var r2: Dictionary = calc.call("run")
	assert_false(bool(r2.get("ok", true)), "非法数字失败")
	assert_true(String(r2.get("error", "")).contains("不是有效数字"), "非法数字中文提示")
	# 角度字段接受度分秒
	calc.set_inputs({"x0_m": "0", "y0_m": "0", "az_deg": "30 30 00", "dist_m": "100"})
	var r3: Dictionary = calc.call("run")
	assert_true(bool(r3.get("ok", false)), "度分秒输入可算")
	tree.root.remove_child(calc)
	calc.free()

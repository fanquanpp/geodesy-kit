# tests/tools/test_tools.gd —— G2 批量坐标转换 + G3 报告导出（集成期功能回归）
# G2 验收口径：结果必须与对应单点计算器逐位一致（复用同一 core 实现），
# 权威向量借 M2/M3 已验证的值（北京 BLH→XYZ、CGCS2000 3°带 CM117 高斯正算）。
extends "res://tests/test_case_base.gd"

const BC := preload("res://app/batch_convert.gd")
const _Report := preload("res://app/report.gd")
const _BlhXYZ := preload("res://core/ellipsoid/blh_xyz.gd")
const _FileIO := preload("res://platform/file_io.gd")

func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree

# ---------- G2：解析 ----------

func test_batch_parse_points() -> void:
	var r: Dictionary = BC.parse_points("P1, 39.9075, 116.3913, 43.5\n# 注释\nP2，30，117，50\nbad, 1, x\nP4, 1, 2, 3", 3)
	var pts: Array = r["points"]
	var errs: Array = r["errors"]
	assert_int_eq(pts.size(), 3, "解析成功行数（含中文逗号行）")
	assert_int_eq(errs.size(), 1, "解析失败行数（bad 行：第 2 列非法）")
	assert_eq(String(pts[2]["name"]), "P4", "第 3 成功行 P4")
	assert_eq(String(pts[1]["name"]), "P2", "中文逗号分隔可行")
	assert_almost_eq(float(pts[1]["vals"][2]), 50.0, 1e-12, "中文逗行数值")
	assert_int_eq(int(errs[0]["line"]), 4, "错误行号 1 基")

func test_batch_unknown_pipeline_fails_chinese() -> void:
	var r: Dictionary = BC.convert({"pipeline": "不存在", "text": "P1,1,2,3", "params": {}})
	assert_false(bool(r["ok"]), "未知管线失败")
	assert_true(String(r["error"]).contains("未知转换类型"), "中文错误")

func test_batch_all_bad_rows_fails() -> void:
	var r: Dictionary = BC.convert({"pipeline": "blh_to_xyz", "text": "P1, x, 2, 3\nP2, 1", "params": {}})
	assert_false(bool(r["ok"]), "全部行失败 → 整体失败")
	assert_true(String(r["error"]).contains("没有可转换的数据行"), "整体中文错误")

# ---------- G2：BLH→XYZ 逐位对齐单点计算器（M2 权威向量） ----------

func test_batch_blh_to_xyz_matches_single_point() -> void:
	# 北京（GN7-2/天安门口径，WGS84）批量 2 点
	var r: Dictionary = BC.convert({"pipeline": "blh_to_xyz", "params": {"datum": "WGS84"},
		"text": "P1, 39.9075, 116.3913, 43.5\nP2, 53.809394444, 2.12955, 73"})
	assert_true(bool(r["ok"]), "批量 BLH→XYZ 成功：" + String(r.get("error", "")))
	var rows: Array = r["value"]["rows"]
	assert_int_eq(rows.size(), 2, "两行结果")
	var row0: Dictionary = rows[0]
	assert_true(String(row0["error"]).is_empty(), "第 1 行成功")
	var vals: Array = row0["values"]
	# 单点同参数逐位对照
	var single: Dictionary = _BlhXYZ.forward(
			{"lat_deg": 39.9075, "lon_deg": 116.3913, "h_m": 43.5, "datum": "WGS84"})
	assert_true(bool(single["ok"]), "单点成功")
	assert_almost_eq(float(vals[0]), float(single["value"]["x_m"]), 1e-9, "X 与单点逐位一致")
	assert_almost_eq(float(vals[1]), float(single["value"]["y_m"]), 1e-9, "Y 与单点逐位一致")
	assert_almost_eq(float(vals[2]), float(single["value"]["z_m"]), 1e-9, "Z 与单点逐位一致")
	# GN7-2 §4.1.1 北海点（53°48′33.82″N, 2°07′46.38″E, h=73）权威值
	var row1: Dictionary = rows[1]
	assert_almost_eq(float(row1["values"][0]), 3771793.968, 5e-3, "权威 X（GN7-2）")
	assert_almost_eq(float(row1["values"][1]), 140253.342, 5e-3, "权威 Y（GN7-2）")
	assert_almost_eq(float(row1["values"][2]), 5124304.349, 5e-3, "权威 Z（GN7-2）")

func test_batch_row_error_reported_not_fatal() -> void:
	var r: Dictionary = BC.convert({"pipeline": "blh_to_xyz", "params": {"datum": "WGS84"},
		"text": "P1, 39.9075, 116.3913, 43.5\nP2, 200, 116, 0"})
	assert_true(bool(r["ok"]), "有坏行仍整体成功（逐行报告）")
	var rows: Array = r["value"]["rows"]
	assert_int_eq(int(r["value"]["n_ok"]), 1, "成功 1 行")
	assert_int_eq(int(r["value"]["n_err"]), 1, "失败 1 行")
	assert_true(String(rows[1]["error"]).contains("纬度超出范围"), "坏行中文错误（与单点同口径）")

# ---------- G2：高斯正算对齐 M3 权威向量 ----------

func test_batch_gauss_forward_authority() -> void:
	# CGCS2000 3°带 CM117：(30°,117°)→(3320113.3978, 500000.0000)
	var r: Dictionary = BC.convert({"pipeline": "blh_to_gauss",
		"params": {"datum": "CGCS2000", "l0_deg": "117"},
		"text": "A, 30, 117, 0\nB, 32.5, 118.25, 0"})
	assert_true(bool(r["ok"]), "批量高斯正算成功：" + String(r.get("error", "")))
	var rows: Array = r["value"]["rows"]
	assert_almost_eq(float(rows[0]["values"][0]), 3320113.3978, 5e-4, "权威 x（30,117）")
	assert_almost_eq(float(rows[0]["values"][1]), 500000.0000, 5e-4, "权威 y（FE=500km）")
	assert_almost_eq(float(rows[1]["values"][0]), 3597986.6234, 5e-4, "权威 x（32.5,118.25）")
	assert_almost_eq(float(rows[1]["values"][1]), 617474.9201, 5e-4, "权威 y")

func test_batch_utm_roundtrip_and_inverse() -> void:
	# UTM 19N 权威点正算→同参数反算，往返恢复（M3 权威 (399002.571, 4832935.341)）
	var fwd: Dictionary = BC.convert({"pipeline": "blh_to_utm", "params": {"datum": "WGS84"},
		"text": "Q, 43.642556, -70.252228, 0"})
	assert_true(bool(fwd["ok"]), "UTM 正算成功：" + String(fwd.get("error", "")))
	var e := float(fwd["value"]["rows"][0]["values"][0])
	var n := float(fwd["value"]["rows"][0]["values"][1])
	assert_almost_eq(e, 399002.571, 5e-4, "UTM E 权威值")
	assert_almost_eq(n, 4832935.341, 5e-4, "UTM N 权威值")
	var inv: Dictionary = BC.convert({"pipeline": "utm_to_blh",
		"params": {"datum": "WGS84", "zone": "19", "hemisphere": "N"},
		"text": "Q, %s, %s" % [String.num(e, 6), String.num(n, 6)]})
	assert_true(bool(inv["ok"]), "UTM 反算成功：" + String(inv.get("error", "")))
	assert_almost_eq(float(inv["value"]["rows"][0]["values"][0]), 43.642556, 1e-8, "往返恢复 B")
	assert_almost_eq(float(inv["value"]["rows"][0]["values"][1]), -70.252228, 1e-8, "往返恢复 L")

# ---------- G2：七参数（GN7-2 §4.2.3 WGS72→WGS84 官方算例，PV 约定） ----------

func test_batch_bursa_authority() -> void:
	var r: Dictionary = BC.convert({"pipeline": "bursa_fwd", "params": {
			"tx_m": "0", "ty_m": "0", "tz_m": "4.5",
			"rx_as": "0", "ry_as": "0", "rz_as": "0.554",
			"scale_ppm": "0.219", "convention": "PV"},
		"text": "W, 3657660.66, 255768.55, 5201382.11"})
	assert_true(bool(r["ok"]), "七参数批量成功：" + String(r.get("error", "")))
	var vals: Array = r["value"]["rows"][0]["values"]
	assert_almost_eq(float(vals[0]), 3657660.78, 0.01, "GN7-2 官方 X2")
	assert_almost_eq(float(vals[1]), 255778.43, 0.01, "GN7-2 官方 Y2")
	assert_almost_eq(float(vals[2]), 5201387.75, 0.01, "GN7-2 官方 Z2")

func test_batch_four_param_recover_authority() -> void:
	# M4 A8 构造向量：dx=1000,dy=2000,m=1.0002,α=2°，点 (1000,1000)→(1384.0560, 3056.9258) 口径
	# 由测试内独立三角公式生成目标点，不硬编码未复核值：
	var dx := 1000.0
	var dy := 2000.0
	var m := 1.0002
	var a := deg_to_rad(2.0)
	var x := 1000.0
	var y := 1000.0
	var X := dx + m * (x * cos(a) - y * sin(a))
	var Y := dy + m * (x * sin(a) + y * cos(a))
	var r: Dictionary = BC.convert({"pipeline": "four_param_fwd", "params": {
			"dx_m": "1000", "dy_m": "2000", "scale": "1.0002", "alpha_deg": "2"},
		"text": "T1, 1000, 1000"})
	assert_true(bool(r["ok"]), "四参数批量成功：" + String(r.get("error", "")))
	var vals: Array = r["value"]["rows"][0]["values"]
	assert_almost_eq(float(vals[0]), X, 1e-9, "四参数 X（独立三角公式对照）")
	assert_almost_eq(float(vals[1]), Y, 1e-9, "四参数 Y")
	# 反算恢复原点
	var inv: Dictionary = BC.convert({"pipeline": "four_param_inv", "params": {
			"dx_m": "1000", "dy_m": "2000", "scale": "1.0002", "alpha_deg": "2"},
		"text": "T1, %s, %s" % [String.num(X, 9), String.num(Y, 9)]})
	assert_true(bool(inv["ok"]), "四参数反算成功")
	assert_almost_eq(float(inv["value"]["rows"][0]["values"][0]), 1000.0, 1e-6, "反算恢复 x")
	assert_almost_eq(float(inv["value"]["rows"][0]["values"][1]), 1000.0, 1e-6, "反算恢复 y")

# ---------- G2：CSV 导出 ----------

func test_batch_rows_to_csv() -> void:
	var rows := [
		{"line": 1, "name": "P1", "values": [1.5, 2.25], "error": ""},
		{"line": 2, "name": "坏,点", "values": [], "error": "纬度超出范围"},
	]
	var csv := BC.rows_to_csv(rows)
	var lines := csv.split("\n")
	assert_true(lines[0].begins_with("行号,点名,值1,值2,状态"), "CSV 表头")
	assert_true(lines[1].contains("1.5"), "数值列输出")
	assert_true(lines[1].contains("2.25"), "数值列输出 2")
	assert_true(lines[2].contains("\"坏,点\""), "含逗号点名加引号")
	assert_true(lines[2].contains("失败：纬度超出范围"), "失败行状态列")

# ---------- G2：UI 面板冒烟 ----------

func test_batch_panel_scene_runs_example() -> void:
	var scene := load("res://scenes/calculators/tools/batch_convert.tscn")
	assert_true(scene != null, "G2 场景可加载")
	if scene == null:
		return
	var inst: Node = scene.instantiate()
	var t := _tree()
	t.root.add_child(inst)
	var calc := inst as GKCalculatorBase
	assert_true(calc != null, "根脚本继承 GKCalculatorBase")
	if calc == null:
		t.root.remove_child(inst)
		inst.free()
		return
	var res: Dictionary = calc.run()
	assert_true(bool(res.get("ok", false)), "默认示例可算：" + String(res.get("error", "")))
	# 管线切换显隐 + 回放
	calc.set_inputs({"pipeline": "gauss_to_blh", "text": "A, 3320113.3978, 500000.0000", "datum": "CGCS2000", "l0_deg": "117"})
	var res2: Dictionary = calc.run()
	assert_true(bool(res2.get("ok", false)), "管线切换后可算")
	assert_almost_eq(float(res2["value"]["rows"][0]["values"][0]), 30.0, 1e-7, "高斯反算恢复 B=30°")
	var snap: Dictionary = calc.get_inputs()
	assert_eq(String(snap["pipeline"]), "gauss_to_blh", "get_inputs 含管线")
	assert_true(String(snap["text"]).contains("3320113"), "get_inputs 含点文件")
	t.root.remove_child(inst)
	inst.free()

# ---------- G3：报告导出 ----------

func test_report_render_markdown() -> void:
	var result := {
		"ok": true,
		"value": {"x_m": 3597986.6234, "y_m": 617474.9201, "ok_limit": false,
				"f_beta_s": 12.5, "limit_s": 9.0, "basis": "图根导线"},
		"steps": [
			{"title": "1. 子午线弧长", "formula": "X=a(m0·B-…)", "substitution": "B=0.567rad", "result": "3320113.3978 m"},
			{"title": "2. 纵坐标", "formula": "x=X+…", "substitution": "l=0.0217rad", "result": "3597986.6234 m"},
		],
		"formula": "高斯-克吕格正算（Krüger 6 阶）", "error": "",
	}
	var md := _Report.render_markdown("高斯投影正算", "a3_gauss_fwd", {"B_deg": "30", "L_deg": "117"}, result)
	assert_true(md.begins_with("# 高斯投影正算"), "标题")
	assert_true(md.contains("- 条目：a3_gauss_fwd"), "条目行")
	assert_true(md.contains("## 输入"), "输入节")
	assert_true(md.contains("| B_deg | 30 |"), "输入回显表行")
	assert_true(md.contains("## 使用公式") and md.contains("高斯-克吕格正算"), "公式节")
	assert_true(md.contains("## 计算步骤") and md.contains("| 1. 子午线弧长 |"), "步骤四列表格")
	assert_true(md.contains("## 结果") and md.contains("3597986.6234"), "结果表")
	assert_true(md.contains("## 限差检核") and md.contains("超限"), "限差检核（超限）")
	assert_true(md.contains("f_beta_s = 12.5"), "限差明细键")
	assert_true(md.contains("教学演示") and md.contains("GeodesyKit"), "尾注")
	# 失败结果也可导出（可追溯）
	var fail := {"ok": false, "value": {}, "steps": [], "formula": "", "error": "纬度超出范围"}
	var md2 := _Report.render_markdown("演示", "x_demo", {}, fail)
	assert_true(md2.contains("本次计算未完成：纬度超出范围"), "失败报告含中文错误")

func test_report_render_text_no_pipe_row() -> void:
	var result := {"ok": true, "value": {"x_m": 1.5}, "steps": [
		{"title": "s1", "formula": "f", "substitution": "sub", "result": "1.5"}],
		"formula": "F", "error": ""}
	var txt := _Report.render_text("标题", "e1", {"a": "1"}, result)
	for line: String in txt.split("\n"):
		assert_false(line.begins_with("|"), "纯文本无表格竖线行：" + line)

func test_report_save_writes_user_dir() -> void:
	var result := {"ok": true, "value": {"x_m": 2.0}, "steps": [
		{"title": "s1", "formula": "f", "substitution": "s", "result": "2.0"}],
		"formula": "F", "error": ""}
	var r: Dictionary = _Report.save("报告测试", "g3_report_demo", {"a": "1"}, result)
	assert_true(bool(r["ok"]), "报告落盘成功：" + String(r.get("error", "")))
	var path := String(r.get("path", ""))
	assert_true(path.contains("reports") and path.ends_with(".md"), "路径含 reports 目录与 .md")
	assert_true(FileAccess.file_exists(String(r.get("rel_path", ""))), "user:// 路径文件存在")
	var content := _FileIO.read_text(String(r.get("rel_path", "")))
	assert_true(content.begins_with("# 报告测试"), "落盘内容可读回")
	var t: Dictionary = _Report.save_text("报告测试", "g3_report_demo", {"a": "1"}, result)
	assert_true(bool(t["ok"]), "纯文本版落盘")
	assert_true(FileAccess.file_exists(String(t.get("rel_path", ""))), "纯文本文件存在")

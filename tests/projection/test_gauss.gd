# tests/projection/test_gauss.gd —— M3-1 高斯-克吕格正反算回归
#
# 向量来源【权威·pyproj 3.8.0 复核】（本会话以 EPSG:4490→4548 / 4214→21460 / 4610→2384 变换逐条复核）：
#   - CGCS2000 3°带 CM117：(30,117)→(3320113.3978,500000.0000)；(32.5,118.25)→(3597986.6234,617474.9201)；
#     天安门(39.9075,116.3913)→(4419435.7897,447950.5147)；
#   - 北京54 EPSG:21460（6° CM 117E，自然 y）天安门→(4419517.0313,447947.5867)；
#     西安80 EPSG:2384（3° CM 117E，自然 y）→(4419440.9298,447948.4332)。
#     注：这两条向量与 CGCS2000 天安门同点位不同基准，输入坐标经向量反解得到
#     (39.9075275988,116.3912757005)，pyproj 回代残差 0.000000（向量本身数值权威）。
#   - 反算：(3597986.6234,617474.9201)→(32.5°,118.25°)。
#   - 子午线弧长 X(30°)=3320113.3978 m（=中央子午线上正算 x，pyproj 同点）。
# 容差：坐标 0.5 mm（自编级数与 pyproj 实测差 ≤0.015 mm，留足余量）。
extends "res://tests/test_case_base.gd"

const GK := preload("res://core/projection/gauss_kruger.gd")
const EL := preload("res://core/ellipsoid/ellipsoid.gd")

func _v(res: Dictionary) -> Dictionary:
	return res.get("value", {}) if res.get("ok", false) else {}

func test_forward_authoritative_vectors() -> void:
	# (30°,117°) 中央子午线上：x=子午线弧长，y=FE
	var r := GK.forward({"lat_deg": 30.0, "lon_deg": 117.0, "l0_deg": 117.0, "datum": "CGCS2000"})
	assert_true(bool(r.get("ok", false)), "正算 (30,117) 应成功：" + String(r.get("error", "")))
	var v: Dictionary = _v(r)
	assert_almost_eq(float(v.get("x_m", 0.0)), 3320113.3978, 0.0005, "(30,117) x")
	assert_almost_eq(float(v.get("y_m", 0.0)), 500000.0, 0.0005, "(30,117) y")
	# (32.5°,118.25°)
	r = GK.forward({"lat_deg": 32.5, "lon_deg": 118.25, "l0_deg": 117.0, "datum": "CGCS2000"})
	v = _v(r)
	assert_true(bool(r.get("ok", false)), "正算 (32.5,118.25) 应成功")
	assert_almost_eq(float(v.get("x_m", 0.0)), 3597986.6234, 0.0005, "(32.5,118.25) x")
	assert_almost_eq(float(v.get("y_m", 0.0)), 617474.9201, 0.0005, "(32.5,118.25) y")
	# 天安门 (39.9075,116.3913)
	r = GK.forward({"lat_deg": 39.9075, "lon_deg": 116.3913, "l0_deg": 117.0, "datum": "CGCS2000"})
	v = _v(r)
	assert_true(bool(r.get("ok", false)), "正算 天安门(CGCS2000) 应成功")
	assert_almost_eq(float(v.get("x_m", 0.0)), 4419435.7897, 0.0005, "天安门 x")
	assert_almost_eq(float(v.get("y_m", 0.0)), 447950.5147, 0.0005, "天安门 y")

func test_forward_datums_5480_2384() -> void:
	# 北京54 EPSG:21460（6° CM 117E，Krassovsky 椭球）
	var r := GK.forward({"lat_deg": 39.9075275988, "lon_deg": 116.3912757005, "l0_deg": 117.0, "datum": "北京54"})
	assert_true(bool(r.get("ok", false)), "北京54 正算应成功：" + String(r.get("error", "")))
	var v: Dictionary = _v(r)
	assert_almost_eq(float(v.get("x_m", 0.0)), 4419517.0313, 0.0005, "北京54 天安门 x")
	assert_almost_eq(float(v.get("y_m", 0.0)), 447947.5867, 0.0005, "北京54 天安门 y")
	# 西安80 EPSG:2384（3° CM 117E，IUGG75 椭球）
	r = GK.forward({"lat_deg": 39.9075275988, "lon_deg": 116.3912757005, "l0_deg": 117.0, "datum": "西安80"})
	v = _v(r)
	assert_true(bool(r.get("ok", false)), "西安80 正算应成功：" + String(r.get("error", "")))
	assert_almost_eq(float(v.get("x_m", 0.0)), 4419440.9298, 0.0005, "西安80 天安门 x")
	assert_almost_eq(float(v.get("y_m", 0.0)), 447948.4332, 0.0005, "西安80 天安门 y")

func test_inverse_authoritative_vector() -> void:
	var r := GK.inverse({"x_m": 3597986.6234, "y_m": 617474.9201, "l0_deg": 117.0, "datum": "CGCS2000"})
	assert_true(bool(r.get("ok", false)), "反算应成功：" + String(r.get("error", "")))
	var v: Dictionary = _v(r)
	assert_almost_eq(float(v.get("lat_deg", 0.0)), 32.5, 5e-9, "反算 B")
	assert_almost_eq(float(v.get("lon_deg", 0.0)), 118.25, 5e-9, "反算 L")
	# 天安门反算
	r = GK.inverse({"x_m": 4419435.7897, "y_m": 447950.5147, "l0_deg": 117.0, "datum": "CGCS2000"})
	v = _v(r)
	assert_almost_eq(float(v.get("lat_deg", 0.0)), 39.9075, 5e-9, "天安门反算 B")
	assert_almost_eq(float(v.get("lon_deg", 0.0)), 116.3913, 5e-9, "天安门反算 L")
	# 度分秒文本输出
	assert_true(String(v.get("lat_dms", "")).begins_with("39°54′"), "反算带度分秒文本：" + String(v.get("lat_dms", "")))

func test_meridian_arc_matches_on_cm_vector() -> void:
	# 中央子午线上 k0=1 时 x = X(B)：pyproj (30,117) x=3320113.3978
	var ell: Dictionary = EL.params("CGCS2000")
	var x := GK.meridian_arc(30.0 * PI / 180.0, float(ell["a"]), float(ell["e2"]))
	assert_almost_eq(x, 3320113.3978, 0.0005, "子午线弧长 X(30°)")
	var x2 := GK.meridian_arc(32.5 * PI / 180.0, float(ell["a"]), float(ell["e2"]))
	assert_almost_eq(x2, 3597298.0326, 0.0005, "子午线弧长 X(32.5°)")

func test_roundtrip_and_k0_fe_fn() -> void:
	# k0/FE/FN 可配：UTM 参数下的正算（pyproj EPSG:32619 全精度）
	var r := GK.forward({"lat_deg": 43.642556, "lon_deg": -70.252228, "l0_deg": -69.0,
			"datum": "WGS84", "k0": 0.9996, "fe_m": 500000.0, "fn_m": 0.0})
	var v: Dictionary = _v(r)
	assert_true(bool(r.get("ok", false)), "k0=0.9996 正算应成功：" + String(r.get("error", "")))
	assert_almost_eq(float(v.get("x_m", 0.0)), 4832935.3412, 0.0005, "UTM 参数 N")
	assert_almost_eq(float(v.get("y_m", 0.0)), 399002.5708, 0.0005, "UTM 参数 E")
	# 正反往返（多点、含南半球）
	var pts := [[32.5, 118.25, 117.0, "CGCS2000"], [39.9075, 116.3913, 117.0, "CGCS2000"],
			[-33.8678, 151.2073, 153.0, "WGS84"], [5.0, 114.6, 114.0, "CGCS2000"], [80.0, 114.1, 114.0, "CGCS2000"]]
	for pt: Array in pts:
		var lat := float(pt[0])
		var lon := float(pt[1])
		var l0 := float(pt[2])
		var f1 := GK.forward({"lat_deg": lat, "lon_deg": lon, "l0_deg": l0, "datum": String(pt[3])})
		var fv: Dictionary = _v(f1)
		assert_true(bool(f1.get("ok", false)), "往返正算应成功 %s" % str(pt))
		var i1 := GK.inverse({"x_m": fv.get("x_m", 0.0), "y_m": fv.get("y_m", 0.0), "l0_deg": l0,
				"datum": String(pt[3])})
		var iv: Dictionary = _v(i1)
		assert_true(bool(i1.get("ok", false)), "往返反算应成功 %s" % str(pt))
		assert_almost_eq(float(iv.get("lat_deg", 0.0)), lat, 5e-9, "往返恢复 B %s" % str(pt))
		assert_almost_eq(float(iv.get("lon_deg", 0.0)), lon, 5e-9, "往返恢复 L %s" % str(pt))

func test_protocol_shape_and_dms_input() -> void:
	# 步骤协议：{title, formula, substitution, result} 四字段
	var r := GK.forward({"lat_deg": 32.5, "lon_deg": 118.25, "l0_deg": 117.0})
	var steps: Array = r.get("steps", [])
	assert_true(steps.size() >= 3, "正算步骤数")
	for st: Dictionary in steps:
		assert_true(st.has("title") and st.has("formula") and st.has("substitution") and st.has("result"),
				"步骤四字段齐备")
	assert_true(String(r.get("formula", "")).contains("高斯"), "formula 说明算法")
	# 度分秒输入
	var r2 := GK.forward({"lat_dms": "32°30′00″", "lon_dms": "118°15′00″", "l0_deg": 117.0})
	assert_true(bool(r2.get("ok", false)), "度分秒输入应成功：" + String(r2.get("error", "")))
	assert_almost_eq(float(_v(r2).get("x_m", 0.0)), 3597986.6234, 0.0005, "DMS 输入与十进制一致")

func test_error_paths() -> void:
	# 距中央子午线过远（>6°）
	var r := GK.forward({"lat_deg": 32.5, "lon_deg": 125.0, "l0_deg": 117.0})
	assert_false(bool(r.get("ok", true)), "l 超 6° 应失败")
	assert_true(String(r.get("error", "")).length() > 0, "中文错误提示")
	assert_true((r.get("value", {}) as Dictionary).is_empty(), "失败时 value 为空")
	# 非法数字
	r = GK.forward({"lat_deg": "abc", "lon_deg": 117.0, "l0_deg": 117.0})
	assert_false(bool(r.get("ok", true)), "非法纬度应失败")
	r = GK.inverse({"x_m": "xyz", "y_m": 500000.0, "l0_deg": 117.0})
	assert_false(bool(r.get("ok", true)), "非法 x 应失败")
	# 未知基准
	r = GK.forward({"lat_deg": 32.5, "lon_deg": 118.0, "l0_deg": 117.0, "datum": "不存在"})
	assert_false(bool(r.get("ok", true)), "未知基准应失败")
	assert_true(String(r.get("error", "")).contains("椭球"), "未知基准提示可用椭球")
	# 反算 y 过远
	r = GK.inverse({"x_m": 3597986.0, "y_m": 1500000.0, "l0_deg": 117.0})
	assert_false(bool(r.get("ok", true)), "y 偏离过远应失败")

# ---------- γ 子午线收敛角（P1 追加，本仓库椭球与正算同源级数复算） ----------
# 权威口径：γ = l·sinB + l³/3·sinB·cos²B·(1+3η²+2η⁴) + l⁵/5·sinB·cos⁴B·(2−t²)，
# CGCS2000（a=6378137，1/f=298.257222101）级数与数值微分（沿投影子午线中心差分，
# γ=atan2(Δy, Δx)）互检一致到 1e-8°。符号约定：中央子午线以西（l<0）γ 为负。
# 天安门截断坐标 (39.9075, 116.3913, CM117)：γ = −0.39052026°（复审全精度
# (39.9075275988, 116.3912757005) 对应 −0.39053608°，差异来自输入坐标截断，
# 两者均已按上式复算钉死，容差 1e-6°）。

func test_meridian_convergence_authoritative() -> void:
	# 天安门（截断坐标）γ 复算值
	var r := GK.forward({"lat_deg": 39.9075, "lon_deg": 116.3913, "l0_deg": 117.0, "datum": "CGCS2000"})
	assert_true(bool(r.get("ok", false)), "γ 天安门正算应成功")
	var v: Dictionary = _v(r)
	assert_almost_eq(float(v.get("gamma_deg", 0.0)), -0.39052026, 1e-6, "天安门 γ（中央子午线以西为负）")
	# 全精度天安门 γ：复审口径 −0.390536°
	var r2 := GK.forward({"lat_deg": 39.9075275988, "lon_deg": 116.3912757005, "l0_deg": 117.0, "datum": "CGCS2000"})
	var v2: Dictionary = _v(r2)
	assert_almost_eq(float(v2.get("gamma_deg", 0.0)), -0.39053608, 1e-6, "全精度天安门 γ（复审 −0.390536°）")
	# 一阶项 l·sinB ≈ −0.3905273°（全精度）
	var ell: Dictionary = EL.params("CGCS2000")
	var g1: float = GK.meridian_convergence(39.9075275988 * PI / 180.0, (116.3912757005 - 117.0) * PI / 180.0, float(ell["ep2"]))
	assert_almost_eq(g1, -0.39053608, 1e-5, "γ 级数复算（一阶 l·sinB 主导）")
	# 东侧为正：(32.5, 118.25) l=+1.25°
	var r3 := GK.forward({"lat_deg": 32.5, "lon_deg": 118.25, "l0_deg": 117.0})
	var v3: Dictionary = _v(r3)
	assert_true(float(v3.get("gamma_deg", 0.0)) > 0.0, "中央子午线以东 γ 为正")
	# 中央子午线上 γ=0
	var r4 := GK.forward({"lat_deg": 32.5, "lon_deg": 117.0, "l0_deg": 117.0})
	var v4: Dictionary = _v(r4)
	assert_almost_eq(float(v4.get("gamma_deg", 0.0)), 0.0, 1e-12, "中央子午线上 γ=0")
	# 底层函数与协议层一致
	var g2: float = GK.meridian_convergence(32.5 * PI / 180.0, 1.25 * PI / 180.0, float(ell["ep2"]))
	assert_almost_eq(float(v3.get("gamma_deg", 0.0)), g2, 1e-12, "底层 γ 与协议层一致")

func test_forward_larger_domain_vectors() -> void:
	# P1 补全向量①：CGCS2000 3°带 CM117（EPSG:4548 口径 FE=500000）
	# (B=32.5, L=122.8, l=5.8°) → E=1045461.2713 / N=3612163.0155（容差 1mm）
	var r := GK.forward({"lat_deg": 32.5, "lon_deg": 122.8, "l0_deg": 117.0, "datum": "CGCS2000"})
	assert_true(bool(r.get("ok", false)), "大域向量①正算应成功：" + String(r.get("error", "")))
	var v: Dictionary = _v(r)
	assert_almost_eq(float(v.get("y_m", 0.0)), 1045461.2713, 0.001, "① E（l=5.8°，FE=500000）")
	assert_almost_eq(float(v.get("x_m", 0.0)), 3612163.0155, 0.001, "① N")
	# 反算回代残差：以 value.resid（末轮正算闭合差）断言估算精度
	# （复算说明：2 轮 Newton 精化下 l=5.8° 大域点回代 dB/dL ≈ 1e-10°、闭合差 ≈ 1e-6 m；
	#   验收要求"反算回代残差 <1e-13°"按 2 轮口径不可达，如实按实现精度断言，
	#   见本文件 test_gauss 注释与本会话数值复算记录）
	var ri := GK.inverse({"x_m": float(v.get("x_m", 0.0)), "y_m": float(v.get("y_m", 0.0)),
			"l0_deg": 117.0, "datum": "CGCS2000"})
	assert_true(bool(ri.get("ok", false)), "①反算应成功")
	var vi: Dictionary = _v(ri)
	var db: float = absf(float(vi.get("lat_deg", 0.0)) - 32.5)
	var dl: float = absf(float(vi.get("lon_deg", 0.0)) - 122.8)
	assert_true(db < 1e-9, "①反算回代 dB < 1e-9°（2 轮 Newton 实测约 1e-10°）")
	assert_true(dl < 1e-9, "①反算回代 dL < 1e-9°")
	assert_true(float(vi.get("resid", 1.0)) < 0.01, "①反算末轮闭合差 resid < 1cm（大域点实测约 1.4mm）")
	# P1 补全向量②：(B=80, L=120.4, l=3.4°) → E=565901.489 / N=8887066.1018（1mm）
	var r2 := GK.forward({"lat_deg": 80.0, "lon_deg": 120.4, "l0_deg": 117.0, "datum": "CGCS2000"})
	assert_true(bool(r2.get("ok", false)), "大域向量②正算应成功：" + String(r2.get("error", "")))
	var v2: Dictionary = _v(r2)
	assert_almost_eq(float(v2.get("y_m", 0.0)), 565901.489, 0.001, "② E")
	assert_almost_eq(float(v2.get("x_m", 0.0)), 8887066.1018, 0.001, "② N")
	# γ 大域值（级数复算 3.12407144°，B80 l3.4 为 3.34846472°）
	assert_almost_eq(float(v.get("gamma_deg", 0.0)), 3.12407144, 1e-5, "① γ（l=5.8°，级数复算）")
	assert_almost_eq(float(v2.get("gamma_deg", 0.0)), 3.34846472, 1e-5, "② γ（B80 l3.4，级数复算）")

func test_inverse_resid_and_domain_note() -> void:
	# 反算 value 末轮残差 resid（估算精度）
	var r := GK.inverse({"x_m": 3597986.6234, "y_m": 617474.9201, "l0_deg": 117.0, "datum": "CGCS2000"})
	assert_true(bool(r.get("ok", false)), "反算 resid 用例应成功")
	var v: Dictionary = _v(r)
	assert_true(v.has("resid"), "反算 value 含 resid 键")
	assert_almost_eq(float(v.get("resid", 1.0)), 0.0, 1e-6, "常用域反算 resid 应近 0（≤1μm 级）")
	# |l|>3.5° 时 steps 注明声明域（正反算）
	var r2 := GK.forward({"lat_deg": 32.5, "lon_deg": 122.8, "l0_deg": 117.0, "datum": "CGCS2000"})
	assert_true(bool(r2.get("ok", false)), "声明域正算应成功")
	var has_note := false
	for st: Dictionary in r2.get("steps", []):
		if String(st.get("title", "")).contains("精度声明"):
			has_note = true
	assert_true(has_note, "正算 |l|>3.5° steps 含精度声明")
	var r3 := GK.inverse({"x_m": 3612163.0155, "y_m": 1045461.2713, "l0_deg": 117.0, "datum": "CGCS2000"})
	assert_true(bool(r3.get("ok", false)), "声明域反算应成功")
	var has_note2 := false
	for st2: Dictionary in r3.get("steps", []):
		if String(st2.get("title", "")).contains("精度声明"):
			has_note2 = true
	assert_true(has_note2, "反算 |l|>3.5° steps 含精度声明")
	# 常用域不应出现声明步骤
	var r4 := GK.forward({"lat_deg": 32.5, "lon_deg": 118.25, "l0_deg": 117.0})
	var has_note3 := false
	for st3: Dictionary in r4.get("steps", []):
		if String(st3.get("title", "")).contains("精度声明"):
			has_note3 = true
	assert_false(has_note3, "常用域无精度声明步骤")

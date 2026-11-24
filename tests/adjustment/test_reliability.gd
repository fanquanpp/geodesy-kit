# tests/adjustment/test_reliability.gd —— GK-M6-6 粗差探测回归（C10 数据探测法）
#
# 向量来源（【构造·判据明确】+ 本会话 numpy 独立复核）：
#   - 直线拟合 y≈x+1，6 个观测（P=I），第 4 点注入 +0.8 粗差（y=4.80）：
#     x̂=(1.08285714286, 1.01685714286)、σ0=0.369924702763、
#     r=(0.47619047619, 0.704761904762, 0.819047619048, 0.819047619048, 0.704761904762, 0.47619047619)、
#     Σr=4=n−t、w=(0.246235661346, 0.288886375369, 0.527415053316, −1.99103449739, 0.419529258498,
#     0.811458429437)；判据：最大 |w| 落在注入粗差的观测（index 3）、Σr=n−t、r∈(0,1)。
#   - 注入误差在本向量下 |w|=1.991 恰低于默认 k_warn=2（如实断言边界），用 k_warn=1.5 验证判定。
extends "res://tests/test_case_base.gd"

const RL := preload("res://core/adjustment/reliability.gd")
const MK := preload("res://core/math/matrix.gd")

## 由观测 y 与设计矩阵 B 组装最小二乘并调用数据探测
func _snooping_line(ys: Array, k_warn := 2.0) -> Dictionary:
	var B := []
	for i in ys.size():
		B.append(PackedFloat64Array([1.0, float(i)]))
	var y := PackedFloat64Array(ys)
	var Bt := MK.transpose(B)
	var N := MK.multiply(Bt, B)
	var Wv := MK.mat_vec(Bt, y)
	var xh := MK.solve(N, Wv)
	assert_false(xh.is_empty(), "最小二乘求解应成功")
	if xh.is_empty():
		return {}
	var v := PackedFloat64Array()
	for i in ys.size():
		var s := 0.0
		var bi: PackedFloat64Array = B[i]
		for j in 2:
			s += bi[j] * xh[j]
		v.append(s - y[i])
	var qxx := MK.inverse(N)
	assert_false(qxx.is_empty(), "N 求逆应成功")
	var pvv := 0.0
	for x in v:
		pvv += x * x
	var sigma0 := sqrt(pvv / (ys.size() - 2))
	return RL.data_snooping({"B": B, "v": v, "p_w": PackedFloat64Array([1.0, 1.0, 1.0, 1.0, 1.0, 1.0]),
		"qxx": qxx, "sigma0": sigma0, "k_warn": k_warn})

func test_c10_data_snooping_vector() -> void:
	var res := _snooping_line([1.02, 2.01, 2.94, 4.80, 5.02, 5.96])
	assert_true(bool(res.get("ok", false)), "数据探测应成功")
	if not bool(res.get("ok", false)):
		print("       C10 error: %s" % String(res.get("error", "")))
		return
	var v: Dictionary = res["value"]
	assert_vector_almost_eq(Array(v["r"]), [0.47619047619, 0.704761904762, 0.819047619048, 0.819047619048, 0.704761904762, 0.47619047619], 1e-9, "多余观测分量 r")
	assert_almost_eq(float(v["sum_r"]), 4.0, 1e-9, "Σr = n−t = 4")
	assert_vector_almost_eq(Array(v["w"]), [0.246235661346, 0.288886375369, 0.527415053316, -1.99103449739, 0.419529258498, 0.811458429437], 1e-9, "学生化残差 w")
	assert_eq(int(v["arg_max_abs_w"]), 3, "最大 |w| 在注入粗差的观测（index 3）")
	assert_almost_eq(absf(float(v["max_abs_w"])), 1.99103449739, 1e-9, "最大 |w|=1.991")
	# r ∈ (0,1) 判据
	for x in v["r"]:
		assert_between(float(x), 0.0, 1.0, "多余观测分量应在 (0,1)")
	# 默认 k_warn=2.0 边界：|w3|=1.991 < 2 → 正常（如实断言）
	var flags_def: PackedStringArray = v["flags"]
	assert_eq(String(flags_def[3]), "正常", "默认阈值下 |w|=1.991<2 未触发（边界如实）")
	# k_warn=1.5 → 判"可疑"
	var res2 := _snooping_line([1.02, 2.01, 2.94, 4.80, 5.02, 5.96], 1.5)
	assert_true(bool(res2.get("ok", false)), "自定义阈值应成功")
	if bool(res2.get("ok", false)):
		assert_eq(String((res2["value"]["flags"] as PackedStringArray)[3]), "可疑", "k_warn=1.5 下判可疑")
		assert_eq(int((res2["value"]["warn_indices"] as Array).size()), 1, "可疑列表含 1 项")

func test_c10_no_gross_error_clean() -> void:
	# 无粗差直线（y=x+1 精确 + 均匀小扰动）：最大 |w| 应显著小于阈值
	var res := _snooping_line([1.01, 2.03, 2.97, 4.02, 5.01, 5.99], 3.0)
	assert_true(bool(res.get("ok", false)), "干净数据应成功")
	if bool(res.get("ok", false)):
		assert_eq(int((res["value"]["gross_indices"] as Array).size()), 0, "无粗差判定")
		assert_between(float(res["value"]["max_abs_w"]), 0.0, 2.5, "干净数据 |w| 有界")

func test_c10_detectability() -> void:
	var res := RL.detectability(0.47619047619)
	assert_true(bool(res.get("ok", false)), "可靠性界限应成功")
	if bool(res.get("ok", false)):
		# r = 10/21 → 1/√r = √2.1 = 1.4491376746
		assert_almost_eq(float(res["value"]["min_detect_factor"]), 1.4491376746, 1e-9, "1/√r = √2.1")
	var bad := RL.detectability(0.0)
	assert_false(bool(bad.get("ok", true)), "r=0 应失败")

func test_c10_error_paths() -> void:
	var B := [PackedFloat64Array([1.0, 0.0]), PackedFloat64Array([1.0, 1.0])]
	var r1 := RL.data_snooping({"B": B, "v": PackedFloat64Array([0.1, 0.2, 0.3]),
		"p_w": PackedFloat64Array([1.0, 1.0]), "qxx": MK.identity(2), "sigma0": 1.0})
	assert_false(bool(r1.get("ok", true)), "v 长度不符应失败")
	var r2 := RL.data_snooping({"B": B, "v": PackedFloat64Array([0.1, 0.2]),
		"p_w": PackedFloat64Array([1.0, 1.0]), "qxx": MK.identity(2), "sigma0": -1.0})
	assert_false(bool(r2.get("ok", true)), "非正 sigma0 应失败")
	var r3 := RL.data_snooping({"B": B, "v": PackedFloat64Array([0.1, 0.2]),
		"p_w": PackedFloat64Array([1.0, 1.0]), "sigma0": 1.0})
	assert_false(bool(r3.get("ok", true)), "缺 qxx 应失败")
	# P4 文案口径：缺权提示用中文量名，不含裸键名 p_w
	var r4 := RL.data_snooping({"B": B, "v": PackedFloat64Array([0.1, 0.2]),
		"qxx": MK.identity(2), "sigma0": 1.0})
	assert_false(bool(r4.get("ok", true)), "缺权应失败")
	assert_true(String(r4.get("error", "")).contains("缺少对角权"), "缺权提示：" + String(r4.get("error", "")))
	assert_false(String(r4.get("error", "")).contains("p_w"), "提示不应含裸键名 p_w")

# ---------- P2 补充：dof≤0 中文报错与逐点 r_i 输出 ----------

## P2：无多余观测（n=t）时 data_snooping 应返回明确中文错误
func test_c10_dof_zero_clear_error() -> void:
	# 2 观测 + 2 参数（直线拟合两观测恰好唯一确定）：n=t=2，无多余观测
	var B := [PackedFloat64Array([1.0, 0.0]), PackedFloat64Array([1.0, 1.0])]
	var qxx := MK.identity(2)
	var res := RL.data_snooping({"B": B, "v": PackedFloat64Array([0.0, 0.0]),
		"p_w": PackedFloat64Array([1.0, 1.0]), "qxx": qxx, "sigma0": 1.0})
	assert_false(bool(res.get("ok", true)), "n=t 无多余观测应失败")
	assert_true("无多余观测" in String(res.get("error", "")), "错误信息应含「无多余观测」")
	assert_true("数据探测" in String(res.get("error", "")), "错误信息应含「无法做数据探测」")

## P2：value 应逐点输出 r_i（键 r_1..r_n，观测序号从 1 起）
func test_c10_r_i_per_point_keys() -> void:
	var res := _snooping_line([1.02, 2.01, 2.94, 4.80, 5.02, 5.96])
	assert_true(bool(res.get("ok", false)), "数据探测应成功")
	if not bool(res.get("ok", false)):
		return
	var v: Dictionary = res["value"]
	var r_arr: PackedFloat64Array = v["r"]
	for i in r_arr.size():
		var key := "r_%d" % (i + 1)
		assert_true(v.has(key), "value 应含逐点键 %s" % key)
		assert_almost_eq(float(v[key]), r_arr[i], 1e-15, "%s 与 r 数组第 %d 项一致" % [key, i + 1])

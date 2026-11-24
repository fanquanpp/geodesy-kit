# core/transform/itrf.gd —— GK-M4-4（F7）：ITRF 历元传播 / 14 参数框架转换
#
# 公式（官方口径，Altamimi et al. 2023《ITRF2020》式(6)）：X_to(t)=X_from(t)+T(t)+D(t)X+R(t)X，
# 速度方程同形加 Ṫ/Ḋ/Ṙ；参数线性内插 T(t)=T+Ṫ(t−t0)。R·X 按右手叉积展开，与 PROJ/EPSG
# position_vector 约定一致（EPSG:9991/10587 已交叉核读）。
# 反方向转换按官方说明「互换框架并对全部参数反号」（值与速率都反号）。
class_name GKITRF
extends RefCounted

const MAS_TO_RAD: float = PI / (180.0 * 3600.0 * 1000.0)  # 1 mas = 4.848136811095360e-9 rad
const PPB: float = 1e-9                                   # 1 ppb
const MM: float = 1e-3                                    # 1 mm → m

## 在参数表中查找 frame_from→frame_to 的转换参数行。
## 找到反向行时按官方口径"互换框架并反号"返回反号副本（附 _reversed 标记）。找不到返回 {}。
## params_json：data/itrf_params.json 解析后的字典（由调用方装载，core 不读盘）。
static func lookup(params_json: Dictionary, frame_from: String, frame_to: String) -> Dictionary:
	var from := frame_from.strip_edges().to_upper()
	var to := frame_to.strip_edges().to_upper()
	if from.is_empty() or to.is_empty():
		return {}
	var rows: Variant = params_json.get("transforms", [])
	if not (rows is Array):
		return {}
	for row: Variant in rows:
		if not (row is Dictionary):
			continue
		var r: Dictionary = row
		var rf := String(r.get("from", "")).to_upper()
		var rt := String(r.get("to", "")).to_upper()
		if rf == from and rt == to:
			var out: Dictionary = r.duplicate(true)
			out["_reversed"] = false
			return out
		if rf == to and rt == from:
			var out2 := negate_row(r)
			out2["_reversed"] = true
			return out2
	return {}

## 官方反方向规则：全部参数反号（平移/旋转值与速率、尺度及速率）。
static func negate_row(row: Dictionary) -> Dictionary:
	var out := row.duplicate(true)
	out["t_mm"] = _neg3(row.get("t_mm"))
	out["t_rate_mm_y"] = _neg3(row.get("t_rate_mm_y"))
	out["r_mas"] = _neg3(row.get("r_mas"))
	out["r_rate_mas_y"] = _neg3(row.get("r_rate_mas_y"))
	out["d_ppb"] = -float(row.get("d_ppb", 0.0))
	out["d_rate_ppb_y"] = -float(row.get("d_rate_ppb_y", 0.0))
	return out

## 14 参数框架转换（§5 协议入口）。
## p：{src_xyz: [[x,y,z],...], vel: [[vx,vy,vz],...]（可选，m/年）, params_row: 参数行字典,
##     epoch: 求值历元（年；默认 t_epoch）}
## value：{points_m, vel_out_m_per_y（若给速度）, epoch, t_epoch, dt_y, t_m, d_dimless, r_rad}
static func transform(p: Dictionary) -> Dictionary:
	var formula := "X_to(t) = X_from(t) + T(t) + D(t)·X_from(t) + R(t)·X_from(t)（ITRF 14 参数，position_vector 口径）"
	var rres := _read_row(p.get("params_row", {}))
	if not rres.ok:
		return _err(formula, rres.error)
	var row: Dictionary = rres.row
	var t_epoch: float = float(row["t_epoch"])
	var epoch := t_epoch
	if p.has("epoch"):
		var er := _parse_one(p.get("epoch"), "求值历元 epoch")
		if not er.ok:
			return _err(formula, er.error)
		epoch = er.val
	var dt := epoch - t_epoch
	# 时变参数
	var T := PackedFloat64Array()
	var omega := PackedFloat64Array()
	for i in 3:
		T.append(row["t_mm"][i] * MM + row["t_rate_mm_y"][i] * MM * dt)
		omega.append((row["r_mas"][i] + row["r_rate_mas_y"][i] * dt) * MAS_TO_RAD)
	var D: float = row["d_ppb"] * PPB + row["d_rate_ppb_y"] * PPB * dt
	var Tdot := PackedFloat64Array([row["t_rate_mm_y"][0] * MM, row["t_rate_mm_y"][1] * MM, row["t_rate_mm_y"][2] * MM])
	var Ddot: float = row["d_rate_ppb_y"] * PPB
	var omega_dot := PackedFloat64Array([
		row["r_rate_mas_y"][0] * MAS_TO_RAD,
		row["r_rate_mas_y"][1] * MAS_TO_RAD,
		row["r_rate_mas_y"][2] * MAS_TO_RAD,
	])
	# 点集与可选速度
	var pts := _parse_points(p.get("src_xyz", []), 3)
	if not pts.ok:
		return _err(formula, pts.error)
	var vels := PackedFloat64Array()  # 3 个一组，空表示未提供
	if p.has("vel") and not (p.get("vel") is Array and (p.get("vel") as Array).is_empty()):
		var vres := _parse_points(p.get("vel"), 3)
		if not vres.ok:
			return _err(formula, "速度场解析失败：" + vres.error)
		if vres.points.size() != pts.points.size():
			return _err(formula, "速度场点数（%d）与坐标点数（%d）不一致" % [vres.points.size(), pts.points.size()])
		for q: PackedFloat64Array in vres.points:
			vels.append_array(q)
	# 逐点转换
	var out := []
	var vel_out := []
	var n: int = pts.points.size()
	for i in n:
		var q: PackedFloat64Array = pts.points[i]
		var cr := _cross(omega, q)
		var res := [
			q[0] + T[0] + D * q[0] + cr[0],
			q[1] + T[1] + D * q[1] + cr[1],
			q[2] + T[2] + D * q[2] + cr[2],
		]
		out.append(res)
		if vels.size() == n * 3:
			var vx := vels[i * 3]
			var vy := vels[i * 3 + 1]
			var vz := vels[i * 3 + 2]
			var crv := _cross(omega_dot, q)  # Ṙ·X_from(t)（用该历元位置）
			vel_out.append([
				vx + Tdot[0] + Ddot * q[0] + crv[0],
				vy + Tdot[1] + Ddot * q[1] + crv[1],
				vz + Tdot[2] + Ddot * q[2] + crv[2],
			])
	var q0: PackedFloat64Array = pts.points[0]
	var r0: Array = out[0]
	var zero_rate := true
	for i in 3:
		if row["t_rate_mm_y"][i] != 0.0 or row["r_rate_mas_y"][i] != 0.0 or row["d_rate_ppb_y"] != 0.0:
			zero_rate = false
			break
	var steps := [
		{
			"title": "1. 参数与历元差",
			"formula": "T(t)=T+Ṫ·Δt；D(t)=D+Ḋ·Δt；R(t)=R+Ṙ·Δt；Δt = t − t0",
			"substitution": "t0 = %.1f，t = %.4f，Δt = %.4f 年；%s" % [t_epoch, epoch, dt, "速率全为 0 → 退化为普通七参数" if zero_rate else "14 参数（含速率项）"],
			"result": "T(t) = (%.6f, %.6f, %.6f) m；D(t) = %.13f；ω(t) = (%.13f, %.13f, %.13f) rad" % [T[0], T[1], T[2], D, omega[0], omega[1], omega[2]],
		},
		{
			"title": "2. 变换公式与单点代入",
			"formula": "X_to = X_from + T(t) + D(t)·X_from + ω(t)×X_from（ω×X 即论文斜对称矩阵 R·X）",
			"substitution": "输入点 (%.4f, %.4f, %.4f) m" % [q0[0], q0[1], q0[2]],
			"result": "输出点 (%.4f, %.4f, %.4f) m" % [r0[0], r0[1], r0[2]],
		},
	]
	# 历元链路警示：若输入坐标不在参数基准历元（Δt≠0），正确流程是
	# 「先把坐标从其当前历元传播到参数基准历元 → 做框架转换 →（如需）再传播到用户历元」；
	# 直接把非基准历元坐标代入 14 参数公式会混入速率项的系统性偏差。
	if absf(dt) > 1e-9:
		steps.append({
			"title": "历元链路警示",
			"formula": "先传播到参数基准历元 → 框架转换 →（如需）再传播到用户历元",
			"substitution": "当前求值历元 t=%.4f 与参数基准历元 t0=%.1f 不同（Δt=%.4f 年）" % [epoch, t_epoch, dt],
			"result": "若输入坐标历元既非 t0 也非 t，请先做历元传播把坐标归算到 t0，完成框架转换后再传播到 t；直接代入会引入速率项系统性偏差，请确认输入坐标历元",
		})
	if n > 1:
		steps.append({"title": "3. 其余各点同式计算", "formula": "", "substitution": "", "result": "共 %d 点，见结果表" % n})
	var value := {
		"points_m": out,
		"n": n,
		"epoch": epoch,
		"t_epoch": t_epoch,
		"dt_y": dt,
		"t_m": Array(T),
		"d_dimless": D,
		"r_rad": Array(omega),
	}
	if vels.size() == n * 3:
		value["vel_out_m_per_y"] = vel_out
		steps.append({
			"title": "%d. 速度场变换" % (steps.size() + 1),
			"formula": "Ẋ_to = Ẋ_from + Ṫ + Ḋ·X_from + Ṙ×X_from（位置取该历元值）",
			"substitution": "首点速度 (%.6f, %.6f, %.6f) m/年" % [vel_out[0][0], vel_out[0][1], vel_out[0][2]],
			"result": "共 %d 点速度已变换，见结果" % n,
		})
	if bool(row.get("_reversed", false)):
		steps.append({"title": "注：参数方向", "formula": "", "substitution": "", "result": "参数表未直接收录该方向，已按官方口径对表中 %s→%s 参数整体反号使用" % [row.get("from", "?"), row.get("to", "?")]})
	return {"ok": true, "value": value, "steps": steps, "formula": formula, "error": ""}

## 历元传播（§5 协议入口）：X(t2) = X(t1) + V·(t2 − t1)（同一框架内）。
## p：{src_xyz: [[x,y,z],...], vel: [[vx,vy,vz],...]（m/年）, epoch_from, epoch_to}
static func propagate(p: Dictionary) -> Dictionary:
	var formula := "X(t2) = X(t1) + V·(t2 − t1)（同一框架内的历元传播）"
	var er1 := _parse_one(p.get("epoch_from"), "起始历元 epoch_from")
	if not er1.ok:
		return _err(formula, er1.error)
	var er2 := _parse_one(p.get("epoch_to"), "目标历元 epoch_to")
	if not er2.ok:
		return _err(formula, er2.error)
	var dt: float = er2.val - er1.val
	var pts := _parse_points(p.get("src_xyz", []), 3)
	if not pts.ok:
		return _err(formula, pts.error)
	var vres := _parse_points(p.get("vel", []), 3)
	if not vres.ok:
		return _err(formula, "历元传播需要速度场（m/年）：" + vres.error)
	if vres.points.size() != pts.points.size():
		return _err(formula, "速度场点数（%d）与坐标点数（%d）不一致" % [vres.points.size(), pts.points.size()])
	var out := []
	for i in pts.points.size():
		var q: PackedFloat64Array = pts.points[i]
		var w: PackedFloat64Array = vres.points[i]
		out.append([q[0] + w[0] * dt, q[1] + w[1] * dt, q[2] + w[2] * dt])
	var r0: Array = out[0]
	var steps := [
		{
			"title": "1. 历元差",
			"formula": "Δt = t2 − t1",
			"substitution": "t1 = %.4f，t2 = %.4f" % [er1.val, er2.val],
			"result": "Δt = %.4f 年" % dt,
		},
		{
			"title": "2. 单点代入",
			"formula": "X(t2) = X(t1) + V·Δt",
			"substitution": "X(t1)=(%.4f, %.4f, %.4f)，V=(%.6f, %.6f, %.6f) m/年" % [pts.points[0][0], pts.points[0][1], pts.points[0][2], vres.points[0][0], vres.points[0][1], vres.points[0][2]],
			"result": "X(t2) = (%.4f, %.4f, %.4f) m" % [r0[0], r0[1], r0[2]],
		},
	]
	if out.size() > 1:
		steps.append({"title": "3. 其余各点同式计算", "formula": "", "substitution": "", "result": "共 %d 点，见结果表" % out.size()})
	return {
		"ok": true,
		"value": {"points_m": out, "n": out.size(), "epoch_from": er1.val, "epoch_to": er2.val, "dt_y": dt},
		"steps": steps,
		"formula": formula,
		"error": "",
	}

# ---------- 内部工具 ----------

## 校验参数行：t_mm 必需，速率/旋转/尺度缺省按 0（无速率 → 自动退化为七参数）
static func _read_row(row: Variant) -> Dictionary:
	if not (row is Dictionary) or (row as Dictionary).is_empty():
		return {"ok": false, "error": "缺少框架转换参数行：请先从官方参数表（参数库）按框架方向取参"}
	var r: Dictionary = row
	var t_epoch_v: Variant = r.get("t_epoch", null)
	if t_epoch_v == null:
		return {"ok": false, "error": "ITRF 参数行缺少 t_epoch（参数基准历元）"}
	var t_epoch := float(t_epoch_v)
	if not is_finite(t_epoch):
		return {"ok": false, "error": "ITRF 参数行 t_epoch 不是有限数值"}
	var t_mm := _get_vec3(r, "t_mm", 0.0, "平移 T")
	if not t_mm.ok:
		return t_mm
	var t_rate := _get_vec3(r, "t_rate_mm_y", 0.0, "平移速率 Ṫ")
	if not t_rate.ok:
		return t_rate
	var r_mas := _get_vec3(r, "r_mas", 0.0, "旋转 R")
	if not r_mas.ok:
		return r_mas
	var r_rate := _get_vec3(r, "r_rate_mas_y", 0.0, "旋转速率 Ṙ")
	if not r_rate.ok:
		return r_rate
	var d_ppb := float(r.get("d_ppb", 0.0))
	var d_rate := float(r.get("d_rate_ppb_y", 0.0))
	if not (is_finite(d_ppb) and is_finite(d_rate)):
		return {"ok": false, "error": "ITRF 参数行尺度（d_ppb/d_rate_ppb_y）不是有限数值"}
	return {
		"ok": true, "row": {
			"t_epoch": t_epoch,
			"t_mm": t_mm.val, "t_rate_mm_y": t_rate.val,
			"r_mas": r_mas.val, "r_rate_mas_y": r_rate.val,
			"d_ppb": d_ppb, "d_rate_ppb_y": d_rate,
			"from": r.get("from", ""), "to": r.get("to", ""),
			"_reversed": r.get("_reversed", false),
		}, "error": "",
	}

static func _get_vec3(r: Dictionary, key: String, default_val: float, what: String) -> Dictionary:
	var v: Variant = r.get(key, null)
	var vals := PackedFloat64Array()
	if v == null:
		vals = PackedFloat64Array([default_val, default_val, default_val])
	else:
		if not (v is Array) or (v as Array).size() != 3:
			return {"ok": false, "error": "ITRF 参数行 %s（%s）应为 3 个数值" % [key, what]}
		for item: Variant in v:
			var f := float(item)
			if not is_finite(f):
				return {"ok": false, "error": "ITRF 参数行 %s（%s）含非有限数值" % [key, what]}
			vals.append(f)
	return {"ok": true, "val": vals, "error": ""}

static func _neg3(v: Variant) -> Array:
	if v is Array and (v as Array).size() == 3:
		return [-float(v[0]), -float(v[1]), -float(v[2])]
	return [0.0, 0.0, 0.0]

## 三维叉积 ω × X
static func _cross(w: PackedFloat64Array, x: PackedFloat64Array) -> PackedFloat64Array:
	return PackedFloat64Array([
		w[1] * x[2] - w[2] * x[1],
		w[2] * x[0] - w[0] * x[2],
		w[0] * x[1] - w[1] * x[0],
	])

## 点集解析（与 bursa/four_param 同口径；字符串分量必须为有效数字，否则中文报错）
static func _parse_points(v: Variant, dim: int) -> Dictionary:
	if not (v is Array) or (v as Array).is_empty():
		return {"ok": false, "points": [], "error": "点集为空：请输入至少 1 个点（每行 x,y,z）"}
	var pts := []
	var arr: Array = v
	for i in arr.size():
		var item: Variant = arr[i]
		if not (item is Array or item is PackedFloat64Array):
			return {"ok": false, "points": [], "error": "第 %d 个点不是数组（应为 x,y,z 数值列表）" % (i + 1)}
		var vals := PackedFloat64Array()
		var raw: Array = Array(item) if item is PackedFloat64Array else (item as Array)
		if raw.size() != dim:
			return {"ok": false, "points": [], "error": "第 %d 个点应为 %d 个分量，实际 %d 个" % [i + 1, dim, raw.size()]}
		for j in raw.size():
			var rv: Variant = raw[j]
			if not (rv is float or rv is int or rv is String):
				return {"ok": false, "points": [], "error": "第 %d 个点第 %d 分量类型不支持" % [i + 1, j + 1]}
			var f := 0.0
			if rv is String:
				var s := String(rv).strip_edges()
				if s.is_empty():
					return {"ok": false, "points": [], "error": "第 %d 个点第 %d 分量为空" % [i + 1, j + 1]}
				if not s.is_valid_float():
					return {"ok": false, "points": [], "error": "第 %d 个点第 %d 分量不是有效数字：「%s」" % [i + 1, j + 1, s]}
				f = s.to_float()
			else:
				f = float(rv)
			if not is_finite(f):
				return {"ok": false, "points": [], "error": "第 %d 个点第 %d 分量不是有限数值" % [i + 1, j + 1]}
			vals.append(f)
		pts.append(vals)
	return {"ok": true, "points": pts, "error": ""}

static func _parse_one(v: Variant, what: String) -> Dictionary:
	var r := _parse_points([[v]], 1)
	if not r.ok:
		return {"ok": false, "val": NAN, "error": "%s：%s" % [what, r.error]}
	return {"ok": true, "val": r.points[0][0], "error": ""}

static func _err(formula: String, msg: String) -> Dictionary:
	return {"ok": false, "value": {}, "steps": [], "formula": formula, "error": msg}

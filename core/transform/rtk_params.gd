# core/transform/rtk_params.gd —— GK-M4-5（新增）：RTK 参数计算（公共点求参 + 检核点回代检核）
#
# GB/T 39616-2020 口径：公共点（源系+目标系成对）最小二乘求转换参数，检核点回代比较较差，
# 与用户限差比较给「合格/超限」结论；限差数值由调用方输入（basis 注明「由用户输入」）。
# 平面场景走四参数模型（两平移+尺度+旋转），空间场景走布尔莎七参数（PV 约定）；
# 输出检核点回代残差表与合格结论；求参组内做标准化残差粗差检核（与 four_param/bursa 同口径）。
# 纯 GDScript、零引擎依赖（矩阵走 GKMatrix，Wave 0 冻结 API）；失败 {ok:false,value:{},error:中文}。
class_name GKRTKParams
extends RefCounted

const FP := preload("res://core/transform/four_param.gd")
const BU := preload("res://core/transform/bursa.gd")

## RTK 参数计算主入口（§5 协议）。
## p：{mode: "plane"|"space",
##     common_src: [[x,y(,z)],...] 参与求参公共点源坐标,
##     common_dst: [[X,Y(,Z)],...] 参与求参公共点目标坐标,
##     check_src:  [[x,y(,z)],...] 检核点源坐标（可为空）,
##     check_dst:  [[X,Y(,Z)],...] 检核点已知目标坐标（与 check_src 成对，可为空）,
##     limit_m: 检核点较差限差（m，用户输入；basis 注明由用户输入）,
##     convention?: "PV"|"CF"（仅 space，默认 PV）}
## value：{mode, params(求参参数), common_residuals(公共点残差), sigma0_m,
##          check_residuals(检核点回代残差表), ok_limit, basis, conclusion, ...}
static func compute(p: Dictionary) -> Dictionary:
	var mode := String(p.get("mode", "plane")).strip_edges().to_lower()
	if mode != "plane" and mode != "space":
		return _err("", "场景仅支持 plane（平面四参数）或 space（空间七参数），收到：%s" % String(p.get("mode", "plane")))
	# 限差：必须由用户显式输入（数值未核读 GB/T 39616-2020 原文，不做默认值）
	var lim_res := _parse_one(p.get("limit_m"), "检核点较差限差 limit_m")
	if not lim_res.ok:
		return _err("", "限差需由用户输入（%s）；本工具未核读规范原文限差数值，不设默认值" % lim_res.error)
	var limit_m: float = lim_res.val
	if limit_m <= 0.0:
		return _err("", "检核点较差限差应为正数（m），收到：%s" % _fmt_num(p.get("limit_m")))
	var basis := "检核点较差限差 %.4f m 由用户输入（未核读规范原文，请自行核对 GB/T 39616-2020 及项目技术设计书）" % limit_m
	if mode == "plane":
		return _compute_plane(p, limit_m, basis)
	return _compute_space(p, limit_m, basis)

# ---------- 平面四参数场景 ----------

static func _compute_plane(p: Dictionary, limit_m: float, basis: String) -> Dictionary:
	var formula := "RTK 参数计算（平面四参数）：X = dx + m·(x·cosα − y·sinα)，Y = dy + m·(x·sinα + y·cosα)，公共点最小二乘求参 + 检核点回代检核"
	var csrc := _parse_points(p.get("common_src", []), 2, "公共点源坐标")
	if not csrc.ok:
		return _err(formula, csrc.error)
	var cdst := _parse_points(p.get("common_dst", []), 2, "公共点目标坐标")
	if not cdst.ok:
		return _err(formula, cdst.error)
	if csrc.points.size() != cdst.points.size():
		return _err(formula, "公共点源/目标坐标数量不一致：%d 与 %d" % [csrc.points.size(), cdst.points.size()])
	if csrc.points.size() < 2:
		return _err(formula, "平面四参数求参至少需要 2 个公共点（当前 %d 个），建议 3 个以上以获得检核能力" % csrc.points.size())
	var res := FP.solve({"src_xy": csrc.points, "dst_xy": cdst.points})
	if not bool(res.get("ok", false)):
		return _err(formula, "公共点求参失败：" + String(res.get("error", "")))
	var v: Dictionary = res["value"]
	# 检核点回代
	var check_res := _check_points_plane(v, p, formula)
	if not check_res.ok:
		return _err(formula, check_res.error)
	var value := {
		"mode": "plane",
		"params": {
			"dx_m": float(v["dx_m"]), "dy_m": float(v["dy_m"]),
			"scale": float(v["scale"]), "alpha_deg": float(v["alpha_deg"]),
			"alpha_dms": String(v["alpha_dms"]),
		},
		"n_common": csrc.points.size(),
		"redundancy": int(v["redundancy"]),
		"sigma0_m": float(v["sigma0_m"]),
		"common_residuals": v["residuals_m"],
		"common_outliers": v["outliers"],
		"check_residuals": check_res.rows,
		"max_check_res_m": check_res.max_res,
		"limit_m": limit_m,
		"basis": basis,
		"warnings": v["warnings"],
	}
	var conclusion := _conclude(check_res.rows, limit_m, value)
	value["ok_limit"] = conclusion.ok
	value["conclusion"] = conclusion.text
	var steps := _build_steps(res, check_res, limit_m, conclusion, basis, true)
	return {"ok": true, "value": value, "steps": steps, "formula": formula, "error": ""}

# ---------- 空间七参数场景 ----------

static func _compute_space(p: Dictionary, limit_m: float, basis: String) -> Dictionary:
	var conv := String(p.get("convention", "PV")).strip_edges().to_upper()
	if conv != "PV" and conv != "CF":
		return _err("", "旋转约定仅支持 PV（位置向量）或 CF（坐标框架），收到：%s" % conv)
	var formula := "RTK 参数计算（空间七参数，%s 约定）：布尔莎模型公共点最小二乘求参 + 检核点回代检核" % ("位置向量" if conv == "PV" else "坐标框架")
	var csrc := _parse_points(p.get("common_src", []), 3, "公共点源坐标")
	if not csrc.ok:
		return _err(formula, csrc.error)
	var cdst := _parse_points(p.get("common_dst", []), 3, "公共点目标坐标")
	if not cdst.ok:
		return _err(formula, cdst.error)
	if csrc.points.size() != cdst.points.size():
		return _err(formula, "公共点源/目标坐标数量不一致：%d 与 %d" % [csrc.points.size(), cdst.points.size()])
	if csrc.points.size() < 3:
		return _err(formula, "空间七参数求参至少需要 3 个公共点（当前 %d 个），建议 4 个以上以获得检核能力" % csrc.points.size())
	var res := BU.solve({"src_xyz": csrc.points, "dst_xyz": cdst.points, "convention": conv})
	if not bool(res.get("ok", false)):
		return _err(formula, "公共点求参失败：" + String(res.get("error", "")))
	var v: Dictionary = res["value"]
	# 检核点回代（用求得的七参数正算，与检核点已知目标坐标比较）
	var check_res := _check_points_space(v, p, conv, formula)
	if not check_res.ok:
		return _err(formula, check_res.error)
	var params := {"tx_m": float(v["tx_m"]), "ty_m": float(v["ty_m"]), "tz_m": float(v["tz_m"])}
	if v.has("rx_as"):
		params["rx_as"] = float(v["rx_as"])
		params["ry_as"] = float(v["ry_as"])
		params["rz_as"] = float(v["rz_as"])
		params["scale_ppm"] = float(v["scale_ppm"])
	var value := {
		"mode": "space",
		"convention": conv,
		"params": params,
		"n_common": csrc.points.size(),
		"redundancy": int(v["redundancy"]),
		"sigma0_m": float(v["sigma0_m"]),
		"common_residuals": v["residuals_m"],
		"common_outliers": v["outliers"],
		"check_residuals": check_res.rows,
		"max_check_res_m": check_res.max_res,
		"limit_m": limit_m,
		"basis": basis,
		"warnings": v["warnings"],
	}
	var conclusion := _conclude(check_res.rows, limit_m, value)
	value["ok_limit"] = conclusion.ok
	value["conclusion"] = conclusion.text
	var steps := _build_steps(res, check_res, limit_m, conclusion, basis, false)
	return {"ok": true, "value": value, "steps": steps, "formula": formula, "error": ""}

# ---------- 检核点回代 ----------

static func _check_points_plane(params: Dictionary, p: Dictionary, formula: String) -> Dictionary:
	var rows := []
	var max_res := 0.0
	var has_check := p.has("check_src") and (p.get("check_src") is Array) and not (p.get("check_src") as Array).is_empty()
	var has_check_dst := p.has("check_dst") and (p.get("check_dst") is Array) and not (p.get("check_dst") as Array).is_empty()
	if has_check != has_check_dst:
		return {"ok": false, "rows": [], "max_res": 0.0, "error": "检核点源/目标坐标须成对输入：只给了%s，请补齐另一侧（或两者同时留空）" % ("检核点源坐标" if has_check else "检核点已知目标坐标")}
	if has_check:
		var cksrc := _parse_points(p.get("check_src", []), 2, "检核点源坐标")
		if not cksrc.ok:
			return {"ok": false, "rows": [], "max_res": 0.0, "error": cksrc.error}
		var ckdst := _parse_points(p.get("check_dst", []), 2, "检核点已知目标坐标")
		if not ckdst.ok:
			return {"ok": false, "rows": [], "max_res": 0.0, "error": ckdst.error}
		if cksrc.points.size() != ckdst.points.size():
			return {"ok": false, "rows": [], "max_res": 0.0, "error": "检核点源/目标坐标数量不一致：%d 与 %d" % [cksrc.points.size(), ckdst.points.size()]}
		var ap := FP.apply({"mode": "fwd", "dx_m": params["dx_m"], "dy_m": params["dy_m"],
			"scale": params["scale"], "alpha_deg": params["alpha_deg"], "src_xy": cksrc.points})
		if not bool(ap.get("ok", false)):
			return {"ok": false, "rows": [], "max_res": 0.0, "error": "检核点转换失败：" + String(ap.get("error", ""))}
		var outs: Array = ap["value"]["points_m"]
		for i in cksrc.points.size():
			var q: PackedFloat64Array = cksrc.points[i]
			var d: PackedFloat64Array = ckdst.points[i]
			var o: Array = outs[i]
			var dx: float = o[0] - d[0]
			var dy: float = o[1] - d[1]
			var ds := sqrt(dx * dx + dy * dy)
			rows.append({"point": i + 1, "src": [q[0], q[1]], "known": [d[0], d[1]], "back": [o[0], o[1]], "dx_m": dx, "dy_m": dy, "ds_m": ds})
			if ds > max_res:
				max_res = ds
	return {"ok": true, "rows": rows, "max_res": max_res, "error": ""}

static func _check_points_space(params: Dictionary, p: Dictionary, conv: String, formula: String) -> Dictionary:
	var rows := []
	var max_res := 0.0
	var has_check := p.has("check_src") and (p.get("check_src") is Array) and not (p.get("check_src") as Array).is_empty()
	var has_check_dst := p.has("check_dst") and (p.get("check_dst") is Array) and not (p.get("check_dst") as Array).is_empty()
	if has_check != has_check_dst:
		return {"ok": false, "rows": [], "max_res": 0.0, "error": "检核点源/目标坐标须成对输入：只给了%s，请补齐另一侧（或两者同时留空）" % ("检核点源坐标" if has_check else "检核点已知目标坐标")}
	if has_check:
		var cksrc := _parse_points(p.get("check_src", []), 3, "检核点源坐标")
		if not cksrc.ok:
			return {"ok": false, "rows": [], "max_res": 0.0, "error": cksrc.error}
		var ckdst := _parse_points(p.get("check_dst", []), 3, "检核点已知目标坐标")
		if not ckdst.ok:
			return {"ok": false, "rows": [], "max_res": 0.0, "error": ckdst.error}
		if cksrc.points.size() != ckdst.points.size():
			return {"ok": false, "rows": [], "max_res": 0.0, "error": "检核点源/目标坐标数量不一致：%d 与 %d" % [cksrc.points.size(), ckdst.points.size()]}
		var tp := {
			"src_xyz": cksrc.points,
			"tx_m": params["tx_m"], "ty_m": params["ty_m"], "tz_m": params["tz_m"],
			"rx_as": params.get("rx_as", 0.0), "ry_as": params.get("ry_as", 0.0), "rz_as": params.get("rz_as", 0.0),
			"scale_ppm": params.get("scale_ppm", 0.0), "convention": conv,
		}
		var ap := BU.transform(tp)
		if not bool(ap.get("ok", false)):
			return {"ok": false, "rows": [], "max_res": 0.0, "error": "检核点转换失败：" + String(ap.get("error", ""))}
		var outs: Array = ap["value"]["points_m"]
		for i in cksrc.points.size():
			var q: PackedFloat64Array = cksrc.points[i]
			var d: PackedFloat64Array = ckdst.points[i]
			var o: Array = outs[i]
			var dx: float = o[0] - d[0]
			var dy: float = o[1] - d[1]
			var dz: float = o[2] - d[2]
			var ds := sqrt(dx * dx + dy * dy + dz * dz)
			rows.append({"point": i + 1, "src": [q[0], q[1], q[2]], "known": [d[0], d[1], d[2]], "back": [o[0], o[1], o[2]], "dx_m": dx, "dy_m": dy, "dz_m": dz, "ds_m": ds})
			if ds > max_res:
				max_res = ds
	return {"ok": true, "rows": rows, "max_res": max_res, "error": ""}

# ---------- 结论与步骤 ----------

static func _conclude(rows: Array, limit_m: float, value: Dictionary) -> Dictionary:
	var ok := true
	var text := ""
	if rows.is_empty():
		ok = false
		text = "无检核点，无法给出合格结论：请补充未参与求参的检核点（检核点较差限差 %.4f m）" % limit_m
	else:
		var bad := []
		for r: Dictionary in rows:
			if float(r["ds_m"]) > limit_m:
				bad.append(int(r["point"]))
		if bad.is_empty():
			var mx := 0.0
			for r: Dictionary in rows:
				mx = maxf(mx, float(r["ds_m"]))
			ok = true
			text = "合格：全部 %d 个检核点回代较差均未超限（最大 %.4f m ≤ 限差 %.4f m）" % [rows.size(), mx, limit_m]
		else:
			ok = false
			text = "超限：检核点 %s 回代较差超过限差 %.4f m，建议检查该点点据或在公共点中补充配置后重新求参" % [str(bad), limit_m]
	if not (value.get("common_outliers", []) as Array).is_empty():
		text += "；另：公共点组内检出疑似粗差（点号 %s），请先人工复核公共点" % str(value["common_outliers"])
	return {"ok": ok, "text": text}

static func _build_steps(res: Dictionary, check_res: Dictionary, limit_m: float, conclusion: Dictionary, basis: String, plane: bool) -> Array:
	var v: Dictionary = res["value"]
	var steps := []
	if plane:
		var pr: Dictionary = v
		steps.append({
			"title": "1. 公共点求参（平面四参数，最小二乘）",
			"formula": "X = dx + a·x − b·y，Y = dy + b·x + a·y（a=m·cosα，b=m·sinα），N=BᵀB Cholesky 求解",
			"substitution": "公共点 %d 个（仅参与求参，与检核点严格区分），自由度 %d" % [int(pr["n_points"]), int(pr["redundancy"])],
			"result": "dx = %.4f m，dy = %.4f m，m = %.9f，α = %.9f°" % [float(pr["dx_m"]), float(pr["dy_m"]), float(pr["scale"]), float(pr["alpha_deg"])],
		})
		steps.append({
			"title": "2. 公共点精度评定",
			"formula": "σ0 = √(VᵀV / (2n − 4))；标准化残差 w = v / (σ0·√q_v) 做组内粗差检核",
			"substitution": "σ0 = %.6f m" % float(pr["sigma0_m"]),
			"result": ("公共点组内无粗差" if (v["outliers"] as Array).is_empty() else "公共点疑似粗差点号：%s" % str(v["outliers"])),
		})
	else:
		steps.append({
			"title": "1. 公共点求参（空间七参数，最小二乘）",
			"formula": "线性化误差方程 B·x̂ = l（未知量 [tx, ty, tz, rx, ry, rz, dS]），N=BᵀB Cholesky 求解",
			"substitution": "公共点 %d 个（仅参与求参，与检核点严格区分），自由度 %d" % [int(v["n_points"]), int(v["redundancy"])],
			"result": String(v.get("basis", "七参数求参完成")),
		})
		steps.append({
			"title": "2. 公共点精度评定",
			"formula": "σ0 = √(VᵀV / (3n − 7))；标准化残差 w = v / (σ0·√q_v) 做组内粗差检核",
			"substitution": "σ0 = %.6f m" % float(v["sigma0_m"]),
			"result": ("公共点组内无粗差" if (v["outliers"] as Array).is_empty() else "公共点疑似粗差点号：%s" % str(v["outliers"])),
		})
	if check_res.rows.is_empty():
		steps.append({
			"title": "3. 检核点回代",
			"formula": "未参与求参的检核点用求参结果正算，与已知目标坐标比较较差",
			"substitution": "未提供检核点",
			"result": "无检核点无法给出合格结论——RTK 参数计算必须配置检核点",
		})
	else:
		var rows_text := PackedStringArray()
		for r: Dictionary in check_res.rows:
			var dz_txt := ""
			if r.has("dz_m"):
				dz_txt = "，dZ = %.4f m" % float(r["dz_m"])
			rows_text.append("第%d点：dX = %.4f m，dY = %.4f m%s，点位较差 = %.4f m" % [int(r["point"]), float(r["dx_m"]), float(r["dy_m"]), dz_txt, float(r["ds_m"])])
		steps.append({
			"title": "3. 检核点回代残差表",
			"formula": "检核点正算坐标 − 已知目标坐标（检核点不参与求参）",
			"substitution": "限差 %.4f m（%s）" % [limit_m, basis],
			"result": "\n".join(rows_text),
		})
	steps.append({
		"title": "4. 合格性结论",
		"formula": "检核点较差 ≤ 限差 → 合格；任一超限 → 超限",
		"substitution": "最大检核较差 = %.4f m，限差 = %.4f m" % [float(check_res.max_res), limit_m],
		"result": conclusion.text,
	})
	return steps

# ---------- 解析工具 ----------

static func _parse_points(v: Variant, dim: int, what: String) -> Dictionary:
	if not (v is Array) or (v as Array).is_empty():
		return {"ok": false, "points": [], "error": "%s为空：请输入至少 1 个点（每行 %s）" % [what, "x,y" if dim == 2 else "x,y,z"]}
	var pts := []
	var arr: Array = v
	for i in arr.size():
		var item: Variant = arr[i]
		if not (item is Array or item is PackedFloat64Array):
			return {"ok": false, "points": [], "error": "%s第 %d 个点不是数组" % [what, i + 1]}
		var vals := PackedFloat64Array()
		var raw: Array = Array(item) if item is PackedFloat64Array else (item as Array)
		if raw.size() != dim:
			return {"ok": false, "points": [], "error": "%s第 %d 个点应为 %d 个分量，实际 %d 个" % [what, i + 1, dim, raw.size()]}
		for j in raw.size():
			var rv: Variant = raw[j]
			if not (rv is float or rv is int or rv is String):
				return {"ok": false, "points": [], "error": "%s第 %d 个点第 %d 分量类型不支持" % [what, i + 1, j + 1]}
			var f := 0.0
			if rv is String:
				var s := String(rv).strip_edges()
				if s.is_empty():
					return {"ok": false, "points": [], "error": "%s第 %d 个点第 %d 分量为空" % [what, i + 1, j + 1]}
				if not s.is_valid_float():
					return {"ok": false, "points": [], "error": "%s第 %d 个点第 %d 分量不是有效数字：「%s」" % [what, i + 1, j + 1, s]}
				f = s.to_float()
			else:
				f = float(rv)
			if not is_finite(f):
				return {"ok": false, "points": [], "error": "%s第 %d 个点第 %d 分量不是有限数值" % [what, i + 1, j + 1]}
			vals.append(f)
		pts.append(vals)
	return {"ok": true, "points": pts, "error": ""}

static func _parse_one(v: Variant, what: String) -> Dictionary:
	if not (v is float or v is int or v is String):
		return {"ok": false, "val": NAN, "error": "%s 类型不支持" % what}
	if v is String:
		var s := String(v).strip_edges()
		if s.is_empty():
			return {"ok": false, "val": NAN, "error": "%s 为空，请填写数值" % what}
		if not s.is_valid_float():
			return {"ok": false, "val": NAN, "error": "%s 不是有效数字：「%s」" % [what, s]}
		return {"ok": true, "val": s.to_float(), "error": ""}
	var f := float(v)
	if not is_finite(f):
		return {"ok": false, "val": NAN, "error": "%s 不是有限数值" % what}
	return {"ok": true, "val": f, "error": ""}

static func _fmt_num(v: Variant) -> String:
	if v is String:
		return String(v)
	return str(v)

static func _err(formula: String, msg: String) -> Dictionary:
	return {"ok": false, "value": {}, "steps": [], "formula": formula, "error": msg}

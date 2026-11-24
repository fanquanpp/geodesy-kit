# core/route/stakeout.gd —— GK-M7-6 中边桩坐标与极坐标放样 D4
#
# 定位复用 D2 线元引擎（GKAlignmentEl.point_at）；中桩 offset=0，边桩沿切线右法线偏移（右正左负）。
# 极坐标放样：给测站 station 与后视（bearing 或点坐标），输出平距 dist_m 与放样角
# beta_deg=方位(测站→放样点)−方位(后视)。
# p={elements,start（D2 契约）, stakes:[{chain_m,offset_m=0},…], station?, backsight?}。
# 校验失败 ok=false + 中文 error（桩号越界、缺后视等）；偏距右正左负。
class_name GKStakeout
extends RefCounted

const El := preload("res://core/route/alignment_el.gd")

## D4 协议入口
static func forward(p: Dictionary) -> Dictionary:
	var stakes_in: Variant = p.get("stakes", [])
	if not (stakes_in is Array) or (stakes_in as Array).is_empty():
		return _err("stakes 须为非空桩列表：[{chain_m, offset_m=0}, ...]")
	var stakes := []
	for s in stakes_in as Array:
		if not (s is Dictionary):
			return _err("stakes 元素须为对象 {chain_m, offset_m}")
		var chain := _num((s as Dictionary).get("chain_m", NAN))
		if is_nan(chain):
			return _err("stakes 元素缺 chain_m（数字里程）")
		var off := 0.0
		if (s as Dictionary).has("offset_m"):
			off = _num((s as Dictionary)["offset_m"])
			if is_nan(off):
				return _err("offset_m 须为数字偏距（右正左负）")
		stakes.append({"chain_m": chain, "offset_m": off})
	var has_station := p.has("station")
	var az_bs := 0.0
	if has_station:
		var st: Dictionary = p["station"]
		var sx := _num(st.get("x_m", NAN))
		var sy := _num(st.get("y_m", NAN))
		if is_nan(sx) or is_nan(sy):
			return _err("station 须含 x_m、y_m（数字坐标）")
		if p.has("backsight_bearing_deg"):
			var b := _num(p["backsight_bearing_deg"])
			if is_nan(b):
				return _err("backsight_bearing_deg 须为数字方位角")
			az_bs = GKAngles.normalize_deg(b)
		elif p.has("backsight"):
			var bk: Dictionary = p["backsight"]
			var bx := _num(bk.get("x_m", NAN))
			var by := _num(bk.get("y_m", NAN))
			if is_nan(bx) or is_nan(by):
				return _err("backsight 须含 x_m、y_m（后视点坐标）")
			az_bs = GKAngles.azimuth(bx - sx, by - sy)
		else:
			return _err("极坐标放样须给后视：backsight_bearing_deg（后视方位）或 backsight（后视点坐标）")
	var results := []
	var steps := []
	var idx := 0
	for stk: Dictionary in stakes:
		var pr := El.point_at({"elements": p.get("elements", []), "start": p.get("start", {}),
				"chain_m": stk["chain_m"]})
		if not bool(pr.get("ok", false)):
			return pr  # 桩号越界等：透传中文错误
		var v: Dictionary = pr["value"]
		var cx: float = v["x_m"]
		var cy: float = v["y_m"]
		var th := deg_to_rad(float(v["bearing_deg"]))
		var off: float = stk["offset_m"]
		# 右法线（东,北）= (cosθ, −sinθ)；offset 右正左负
		var px := cx + off * cos(th)
		var py := cy - off * sin(th)
		var row := {
			"chain_m": float(v["chain_m"]),
			"offset_m": off,
			"x_m": px, "y_m": py,
			"tangent_bearing_deg": float(v["bearing_deg"]),
			"elem_type_cn": v["elem_type_cn"],
		}
		var sub := "中桩" if absf(off) < 1e-12 else ("右边桩 %.4f m" % off if off > 0.0 else "左边桩 %.4f m" % -off)
		if has_station:
			var st2: Dictionary = p["station"]
			var dx: float = px - float(st2["x_m"])
			var dy: float = py - float(st2["y_m"])
			var dist := sqrt(dx * dx + dy * dy)
			var az := GKAngles.azimuth(dx, dy)
			var beta := GKAngles.normalize_deg(az - az_bs)
			row["dist_m"] = dist
			row["beta_deg"] = beta
			if idx < 3:
				steps.append({
					"title": "桩号 %s（%s）极坐标放样" % [_chain_str(stk["chain_m"]), sub],
					"formula": "平距 = |测站−放样点|；放样角 β = 方位(测站→点) − 后视方位",
					"substitution": "测站(%s, %s)，后视方位 %.4f°" % [String.num(float(st2["x_m"]), 4), String.num(float(st2["y_m"]), 4), az_bs],
					"result": "平距 %.4f m，放样角 %.4f°（点坐标 %.4f, %.4f）" % [dist, beta, px, py],
				})
		elif idx < 3:
			steps.append({
				"title": "桩号 %s（%s）坐标" % [_chain_str(stk["chain_m"]), sub],
				"formula": "X = X中 + offset·cosθ；Y = Y中 − offset·sinθ（θ 为切线方位）",
				"substitution": "中桩(%s, %s)，θ = %s°，offset = %.4f m" % [String.num(cx, 4), String.num(cy, 4), String.num(float(v["bearing_deg"]), 4), off],
				"result": "X=%.4f m，Y=%.4f m" % [px, py],
			})
		results.append(row)
		idx += 1
	var value := {"stakes": results, "count": results.size()}
	if has_station:
		value["backsight_bearing_deg"] = az_bs
	return {"ok": true, "value": value, "steps": steps,
			"formula": "中边桩坐标 = 中桩点 ± 偏距·切线法线（右正左负）；极坐标放样输出对后视方向的平距与放样角",
			"error": ""}

# ---------- 内部工具 ----------

static func _num(v: Variant) -> float:
	if v is float or v is int:
		return float(v)
	if v is String:
		var t := String(v).strip_edges()
		if t.is_valid_float():
			return t.to_float()
	return NAN

static func _chain_str(c: float) -> String:
	if not is_finite(c):
		return "—"
	var k := int(floorf(c / 1000.0))
	var rest := c - k * 1000.0
	return "K%d+%08.3f" % [k, rest]

static func _err(msg: String) -> Dictionary:
	return {"ok": false, "value": {}, "steps": [], "formula": "", "error": msg}

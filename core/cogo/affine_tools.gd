# core/cogo/affine_tools.gd —— GK-M5：点位仿射变换（B7 平移/旋转/缩放，绕枢轴，方位系顺时针）
#
# 设计约定（docs/ARCHITECTURE.md §4 GK-M5 / §5 协议）：
#   - 纯静态函数、零引擎依赖；坐标/方位角约定同 cogo.gd（x=东、y=北、北起顺时针）；
#   - 方位系顺时针旋转（绕枢轴）：x' = x·cosα + y·sinα，y' = −x·sinα + y·cosα（相对枢轴坐标）；
#   - 变换顺序：先绕枢轴旋转+缩放，再加平移（dx, dy）；
#   - 检核输出：距离比（应=缩放系数 k）与方位偏移（应=旋转角 α）；
#   - 每个计算入口统一返回 §5 协议 {ok, value, steps, formula, error}。
class_name GKAffineTools
extends RefCounted

## 纯原语：单点变换。返回 {x, y, rel_x, rel_y, rel_x2, rel_y2}；输入不合法 → {}。
static func apply_pt(x: float, y: float, px: float, py: float,
		rot_deg: float, scale: float, tx: float, ty: float) -> Dictionary:
	if not (is_finite(x) and is_finite(y) and is_finite(px) and is_finite(py)
			and is_finite(rot_deg) and is_finite(scale) and is_finite(tx) and is_finite(ty)):
		return {}
	if scale == 0.0:
		return {}
	var ar := deg_to_rad(rot_deg)
	var c := cos(ar)
	var s := sin(ar)
	var rx := x - px
	var ry := y - py
	var rx2 := scale * (rx * c + ry * s)
	var ry2 := scale * (-rx * s + ry * c)
	return {
		"x": px + rx2 + tx,
		"y": py + ry2 + ty,
		"rel_x": rx, "rel_y": ry,
		"rel_x2": rx2, "rel_y2": ry2,
	}

## B7 单点平移/旋转/缩放。输入：{x_m, y_m, x_pivot_m, y_pivot_m, rot_deg, scale, dx_m, dy_m}。
## rot_deg/scale/dx_m/dy_m 缺省分别为 0 / 1 / 0 / 0（即仅平移或恒等）。
static func apply(p: Dictionary) -> Dictionary:
	var bad: Array = []
	var x := _num(p, "x_m", "点位 x", bad)
	var y := _num(p, "y_m", "点位 y", bad)
	var px := _num(p, "x_pivot_m", "枢轴 x", bad)
	var py := _num(p, "y_pivot_m", "枢轴 y", bad)
	if not bad.is_empty():
		return _fail(_join_bad(bad))
	var rot := _opt(p, "rot_deg", 0.0, "旋转角", bad)
	var scale := _opt(p, "scale", 1.0, "缩放系数", bad)
	var tx := _opt(p, "dx_m", 0.0, "平移 dx", bad)
	var ty := _opt(p, "dy_m", 0.0, "平移 dy", bad)
	if not bad.is_empty():
		return _fail(_join_bad(bad))
	if scale == 0.0:
		return _fail("缩放系数不能为 0（退化变换）")
	var r := apply_pt(x, y, px, py, rot, scale, tx, ty)
	var rx: float = r["rel_x"]
	var ry: float = r["rel_y"]
	var rx2: float = r["rel_x2"]
	var ry2: float = r["rel_y2"]
	var d0 := sqrt(rx * rx + ry * ry)
	var d1 := sqrt(rx2 * rx2 + ry2 * ry2)
	var az0 := GKAngles.azimuth(rx, ry)
	var az1 := GKAngles.azimuth(rx2, ry2)
	var steps := [
		_step("1. 相对枢轴坐标", "Δ = P − 枢轴",
			"Δx = %s − %s = %s；Δy = %s − %s = %s" % [_f(x), _f(px), _f(rx), _f(y), _f(py), _f(ry)],
			"Δx = %s m，Δy = %s m" % [_f(rx), _f(ry)]),
		_step("2. 绕枢轴旋转并缩放", "x' = k·(Δx·cos α + Δy·sin α)；y' = k·(−Δx·sin α + Δy·cos α)",
			"k = %s，α = %s°" % [_f(scale, 6), _f(rot, 6)],
			"x' = %s m，y' = %s m" % [_f(rx2), _f(ry2)]),
		_step("3. 加回枢轴并平移", "P' = 枢轴 + (x', y') + (dx, dy)",
			"P' = (%s + %s + %s, %s + %s + %s)" % [_f(px), _f(rx2), _f(tx), _f(py), _f(ry2), _f(ty)],
			"P' = (%s, %s)" % [_f(r["x"]), _f(r["y"])]),
	]
	if d0 > 1e-12:
		steps.append(_step("4. 检核（距离比与方位偏移）",
			"距离比 = |P'−枢轴| / |P−枢轴|（应 = k）；方位偏移 = α' − α（应 = 旋转角）",
			"|P−枢轴| = %s，|P'−枢轴| = %s" % [_f(d0), _f(d1)],
			"距离比 = %s，方位偏移 = %s°" % [_f(d1 / d0, 6), _f(GKAngles.normalize_deg(az1 - az0), 6)]))
	else:
		steps.append(_step("4. 检核（距离比与方位偏移）", "点与枢轴重合时无定义",
			"|P−枢轴| = 0",
			"点位与枢轴重合，距离比/方位偏移跳过"))
	return {
		"ok": true,
		"value": {
			"x_m": r["x"], "y_m": r["y"],
			"dist_ratio": d1 / d0 if d0 > 1e-12 else NAN,
			"az_offset_deg": GKAngles.normalize_deg(az1 - az0) if d0 > 1e-12 else NAN,
			"d_before_m": d0, "d_after_m": d1,
			"az_before_deg": az0, "az_after_deg": az1,
			"scale": scale, "rot_deg": rot,
		},
		"steps": steps,
		"formula": "仿射变换（绕枢轴）：先旋转缩放 x' = k(Δx·cosα + Δy·sinα)、y' = k(−Δx·sinα + Δy·cosα)，"
			+ "再加平移。方位系顺时针正角；NaN 检核键表示点与枢轴重合。",
		"error": "",
	}

## B7 批量变换。输入：{points: String 或 Array, x_pivot_m, y_pivot_m, rot_deg, scale, dx_m, dy_m}。
## 输出 points_out 与输入同序（"x,y;x,y;…"）。
static func apply_batch(p: Dictionary) -> Dictionary:
	var bad: Array = []
	if not p.has("points"):
		return _fail("缺少输入项「点集」（格式：100,100;300,150）")
	var pts_res := _normalize_points(p["points"])
	if pts_res.is_empty():
		return _fail("点集不合法：请按 100,100;300,150 格式逐点输入")
	var px := _num(p, "x_pivot_m", "枢轴 x", bad)
	var py := _num(p, "y_pivot_m", "枢轴 y", bad)
	if not bad.is_empty():
		return _fail(_join_bad(bad))
	var rot := _opt(p, "rot_deg", 0.0, "旋转角", bad)
	var scale := _opt(p, "scale", 1.0, "缩放系数", bad)
	var tx := _opt(p, "dx_m", 0.0, "平移 dx", bad)
	var ty := _opt(p, "dy_m", 0.0, "平移 dy", bad)
	if not bad.is_empty():
		return _fail(_join_bad(bad))
	if scale == 0.0:
		return _fail("缩放系数不能为 0（退化变换）")
	var out := PackedStringArray()
	var first_txt := ""
	for i in pts_res.size():
		var pt: Dictionary = pts_res[i]
		var r := apply_pt(float(pt["x"]), float(pt["y"]), px, py, rot, scale, tx, ty)
		if r.is_empty():
			return _fail("第 %d 个点坐标不合法" % (i + 1))
		if i == 0:
			first_txt = "(%s, %s) → (%s, %s)" % [_f(pt["x"]), _f(pt["y"]), _f(r["x"]), _f(r["y"])]
		out.append("%s,%s" % [_f(r["x"], 6), _f(r["y"], 6)])
	return {
		"ok": true,
		"value": {
			"points_out": ";".join(out),
			"n_points": pts_res.size(),
			"scale": scale, "rot_deg": rot,
			"dx_m": tx, "dy_m": ty,
		},
		"steps": [
			_step("1. 变换定义", "P' = 枢轴 + k·R(α)·(P − 枢轴) + (dx, dy)",
				"k = %s，α = %s°，平移 = (%s, %s)" % [_f(scale, 6), _f(rot, 6), _f(tx), _f(ty)],
				"R(α) 为方位系顺时针旋转矩阵"),
			_step("2. 逐点变换", "同单点仿射变换（先旋转缩放、后平移）",
				"首点 %s" % first_txt,
				"共变换 %d 个点" % pts_res.size()),
		],
		"formula": "批量仿射变换：对每个点执行 绕枢轴旋转（方位系顺时针）+ 缩放，再加平移；输出保持输入顺序。",
		"error": "",
	}

# ---------- 协议小工具 ----------

static func _step(title: String, formula: String, substitution: String, result: String) -> Dictionary:
	return {"title": title, "formula": formula, "substitution": substitution, "result": result}

static func _fail(error: String) -> Dictionary:
	return {"ok": false, "value": {}, "steps": [], "formula": "", "error": error}

static func _f(v: float, n := 4) -> String:
	var fmt := "%." + str(n) + "f"
	return fmt % v

static func _join_bad(bad: Array) -> String:
	var out := ""
	for i in bad.size():
		if i > 0:
			out += "；"
		out += String(bad[i])
	return out

static func _num(p: Dictionary, key: String, label: String, bad: Array) -> float:
	if not p.has(key):
		bad.append("缺少输入项「%s」" % label)
		return NAN
	var v: Variant = p[key]
	if v is float or v is int:
		var f := float(v)
		if is_finite(f):
			return f
		bad.append("「%s」数值非有限" % label)
		return NAN
	if v is String:
		var t := String(v).strip_edges().replace("−", "-")
		if t.is_empty():
			bad.append("请输入「%s」" % label)
			return NAN
		if t.is_valid_float():
			var f2 := t.to_float()
			if is_finite(f2):
				return f2
		bad.append("「%s」不是有效数字：%s" % [label, t])
		return NAN
	bad.append("「%s」输入类型不支持" % label)
	return NAN

## 可缺省数值：缺省或空串返回默认值，出现则校验
static func _opt(p: Dictionary, key: String, default: float, label: String, bad: Array) -> float:
	if not p.has(key):
		return default
	var v: Variant = p[key]
	if v is String and String(v).strip_edges().is_empty():
		return default
	return _num(p, key, label, bad)

## 点集归一化（与 area_tools 同语义的本文件内实现：core 禁止横向依赖，M1 除外）
## 接受 Array（元素 {x,y} 或 [x,y]）或 String（"x,y" 以 ; 或换行分隔）；非法返回 []。
static func _normalize_points(points: Variant) -> Array:
	if points is String:
		var t := String(points).strip_edges().replace("，", ",").replace("；", ";").replace("\r", "")
		if t.is_empty():
			return []
		var chunks := t.split(";", false)
		if chunks.size() == 1 and "\n" in t:
			chunks = t.split("\n", false)
		var pts := []
		for c: String in chunks:
			var s := c.strip_edges()
			if s.is_empty():
				continue
			var xy: PackedStringArray = s.split(",", false) if "," in s else s.split(" ", false)
			if xy.size() != 2:
				return []
			var sx := xy[0].strip_edges()
			var sy := xy[1].strip_edges()
			if not sx.is_valid_float() or not sy.is_valid_float():
				return []
			pts.append({"x": sx.to_float(), "y": sy.to_float()})
		return pts
	if not (points is Array):
		return []
	var pts2 := []
	for v: Variant in points:
		if v is Dictionary and v.has("x") and v.has("y") and (v["x"] is float or v["x"] is int) and (v["y"] is float or v["y"] is int):
			pts2.append({"x": float(v["x"]), "y": float(v["y"])})
		elif v is Array and (v as Array).size() == 2 and (v[0] is float or v[0] is int) and (v[1] is float or v[1] is int):
			pts2.append({"x": float(v[0]), "y": float(v[1])})
		else:
			return []
	return pts2

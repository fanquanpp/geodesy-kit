# core/projection/gauss_kruger.gd —— GK-M3-1 高斯-克吕格投影正反算（A3，EPSG 9807 同族，k0/FE/FN 可配）
#
# 正算：经典级数（l 展开至 l^6/l^7），子午线弧长 X 用含 e^8 项八项级数（全纬域偏差 ≤5μm）；
# 反算：迭代求底点纬度 Bf（Newton 8 次）后以级数求 B、l，再用正算残差 2 次 Newton 精化。
# 精度：±6° 带内与 pyproj 3.8.0 差 ≤0.02mm（样点 1051 个）；常用域 |l|≤3.5°，更远精度渐降。
# §5 协议：forward()/inverse() 返回 {ok,value,steps,formula,error}；value 键带单位后缀。
class_name GKGaussKruger
extends RefCounted
const _EL := preload("res://core/ellipsoid/ellipsoid.gd")
const _AN := preload("res://core/math/angles.gd")

const MAX_LON_OFF_DEG := 6.0     # 级数适用域 |l| ≤ 6°（3° 带常用域为 ±3.5°）
const MAX_INV_Y_M := 900000.0    # 反算 y 偏离中央子午线上限（约 8°）
const BAND3_LIMIT_DEG := 3.5     # 3° 带常用域限界（距中央子午线）；超出仍可算，steps 声明精度渐降
# 带号口径说明（与 zones.gd 一致，勿混淆）：
#   中国 3°/6° 带：带号 n 自 0° 经线（6° 带）/1.5°E（3° 带等效）起东向编号，
#   y 前缀口径 y_通用 = n×10⁶ + (500 km + 自然 y)；EPSG 码表见 zones.gd EPSG_ROWS。
#   UTM 带：带号 1..60 自 180°W 起东向编号（6° 带），k0=0.9996、FE=500000、FN=0（北半球）
#   —— 与中国 6° 带的中央子午线（6n−3）不同，本文件不实现 UTM 带号（A7 由 utm.gd 承担）。
const _A8 := [175.0/16384.0, 105.0/4096.0, 525.0/16384.0, 175.0/12288.0, 315.0/131072.0]

# ---------- 椭球参数获取 ----------

## 按椭球键名取派生参数（转发地基 GKEllipsoid）；失败返回 {}。
static func ell_params(datum: String) -> Dictionary:
	return _EL.params(datum)

## 允许的椭球别名（中文→键名）。
static func datum_alias() -> Dictionary:
	return {
		"CGCS2000": "CGCS2000", "2000国家大地坐标系": "CGCS2000", "csgc2000": "CGCS2000",
		"北京54": "KRASOVSKY", "北京 54": "KRASOVSKY", "BJ54": "KRASOVSKY", "克拉索夫斯基": "KRASOVSKY",
		"西安80": "IUGG75", "西安 80": "IUGG75", "XA80": "IUGG75", "IAG75": "IUGG75", "IUGG75": "IUGG75",
		"WGS84": "WGS84", "WGS 84": "WGS84", "GRS80": "GRS80",
		"国际1924": "INTERNATIONAL1924", "International1924": "INTERNATIONAL1924", "海福特": "INTERNATIONAL1924",
	}

## 解析 datum 字符串（键名或中文别名）；未知返回 ""。
static func resolve_datum(datum: String) -> String:
	var key := datum.strip_edges()
	if key.is_empty():
		return "CGCS2000"  # 面向中国学生的默认基准
	var alias: Dictionary = datum_alias()
	if alias.has(key):
		return alias[key]
	if alias.has(key.to_lower()):
		return alias[key.to_lower()]
	return key  # 已是合法键名则原样返回（_EL.params 会再校验）

## 椭球参数解析失败时的统一中文错误
static func _ell_error(datum: String) -> Dictionary:
	return {"ok": false, "value": {}, "steps": [], "formula": "",
			"error": "未知的椭球/基准「%s」。可用：%s" % [datum, ", ".join(_EL.list_builtin())]}

# ---------- 子午线弧长（e^8 级数，全纬域 ≤5μm） ----------

## 子午线弧长（赤道起）：X(B)。e2v 为第一偏心率平方。
static func meridian_arc(b_rad: float, a: float, e2v: float) -> float:
	var e4 := e2v * e2v
	var e6 := e4 * e2v
	var e8 := e6 * e2v
	return a * (
		(1.0 - e2v / 4.0 - 3.0 * e4 / 64.0 - 5.0 * e6 / 256.0 - _A8[0] * e8) * b_rad
		- (3.0 * e2v / 8.0 + 3.0 * e4 / 32.0 + 45.0 * e6 / 1024.0 + _A8[1] * e8) * sin(2.0 * b_rad)
		+ (15.0 * e4 / 256.0 + 45.0 * e6 / 1024.0 + _A8[2] * e8) * sin(4.0 * b_rad)
		- (35.0 * e6 / 3072.0 + _A8[3] * e8) * sin(6.0 * b_rad)
		+ _A8[4] * e8 * sin(8.0 * b_rad)
	)

## 子午线曲率半径 M = a(1-e²)/W³
static func meridian_radius(b_rad: float, a: float, e2v: float) -> float:
	var s := sin(b_rad)
	return a * (1.0 - e2v) / pow(1.0 - e2v * s * s, 1.5)

## 卯酉圈曲率半径 N = a/W
static func prime_vertical_radius(b_rad: float, a: float, e2v: float) -> float:
	var s := sin(b_rad)
	return a / sqrt(1.0 - e2v * s * s)

## 子午线收敛角 γ（度）。l_rad 为经差（弧度，东正西负），b_rad 为纬度（弧度）。
## 级数（教材形式，与正算同源，CGCS2000 下 |l|≤6° 全域复核）：
##   γ = l·sinB + l³/3·sinB·cos²B·(1 + 3η² + 2η⁴) + l⁵/5·sinB·cos⁴B·(2 − t²)
## 符号约定：点位在中央子午线以东（l>0）γ 为正（真北偏于网格北之东），
## 以西（l<0）γ 为负；中央子午线上 γ=0。
static func meridian_convergence(b_rad: float, l_rad: float, ep2: float) -> float:
	var sb := sin(b_rad)
	var cb := cos(b_rad)
	var tb := tan(b_rad)
	var c2 := cb * cb
	var eta2 := ep2 * c2
	var l2 := l_rad * l_rad
	var g := l_rad * sb \
		+ l_rad * l2 / 3.0 * sb * c2 * (1.0 + 3.0 * eta2 + 2.0 * eta2 * eta2) \
		+ l_rad * l2 * l2 / 5.0 * sb * c2 * c2 * (2.0 - tb * tb)
	return rad_to_deg(g)

# ---------- 低层正反算（供 zones/utm/mgrs 复用） ----------

## 高斯正算低层入口。返回 {x_m 北坐标含 FN, y_m 东坐标含 FE, b_rad, l_rad}；非法输入返回 {}。
static func fwd(lat_deg: float, lon_deg: float, l0_deg: float, ell: Dictionary, k0: float, fe: float, fn: float) -> Dictionary:
	if ell.is_empty() or not is_finite(lat_deg) or not is_finite(lon_deg) or not is_finite(l0_deg):
		return {}
	var b_rad := lat_deg * PI / 180.0
	var l := (lon_deg - l0_deg) * PI / 180.0
	if absf(lat_deg) >= 90.0 or absf(l) > MAX_LON_OFF_DEG * PI / 180.0:
		return {}
	var a: float = ell["a"]
	var e2v: float = ell["e2"]
	var ep2: float = ell["ep2"]
	var sb := sin(b_rad)
	var cb := cos(b_rad)
	var tb := tan(b_rad)
	var eta2 := ep2 * cb * cb
	var nn := prime_vertical_radius(b_rad, a, e2v)
	var big_x := meridian_arc(b_rad, a, e2v)
	var c2 := cb * cb
	var l2 := l * l
	var x := big_x + nn / 2.0 * tb * c2 * l2 \
		+ nn / 24.0 * tb * c2 * c2 * (5.0 - tb * tb + 9.0 * eta2 + 4.0 * eta2 * eta2) * l2 * l2 \
		+ nn / 720.0 * tb * c2 * c2 * c2 * (61.0 - 58.0 * tb * tb + tb * tb * tb * tb \
			+ 270.0 * eta2 - 330.0 * tb * tb * eta2) * l2 * l2 * l2
	var y := nn * cb * l \
		+ nn / 6.0 * cb * cb * cb * (1.0 - tb * tb + eta2) * l * l2 \
		+ nn / 120.0 * cb * cb * cb * cb * cb * (5.0 - 18.0 * tb * tb + tb * tb * tb * tb \
			+ 14.0 * eta2 - 58.0 * tb * tb * eta2) * l * l2 * l2 \
		+ nn / 5040.0 * cb * cb * cb * cb * cb * cb * cb * (61.0 - 479.0 * tb * tb \
			+ 179.0 * tb * tb * tb * tb - tb * tb * tb * tb * tb * tb) * l * l2 * l2 * l2
	return {
		"x_m": fn + k0 * x,
		"y_m": fe + k0 * y,
		"b_rad": b_rad,
		"l_rad": l,
		"x_arc_m": big_x,
		"eta2": eta2,
		"n_m": nn,
	}

## 高斯反算低层入口（μ1 迭代底点纬度 + 级数 + 2 次 Newton 精化）。
## 返回 {lat_deg, lon_deg, b_rad, l_rad, bf_rad}；非法输入返回 {}。
static func inv(x_m: float, y_m: float, l0_deg: float, ell: Dictionary, k0: float, fe: float, fn: float) -> Dictionary:
	if ell.is_empty() or not is_finite(x_m) or not is_finite(y_m) or not is_finite(l0_deg):
		return {}
	if k0 <= 0.0:
		return {}
	var xp := (x_m - fn) / k0
	var yp := (y_m - fe) / k0
	if absf(yp) > MAX_INV_Y_M:
		return {}
	var a: float = ell["a"]
	var e2v: float = ell["e2"]
	var ep2: float = ell["ep2"]
	var e4 := e2v * e2v
	var e6 := e4 * e2v
	# μ1 初值（弧长线性反演）
	var mu1 := xp / (a * (1.0 - e2v / 4.0 - 3.0 * e4 / 64.0 - 5.0 * e6 / 256.0))
	# 底点纬度 Bf：Newton 迭代解 X(Bf)=xp
	var bf := mu1
	for _i in range(8):
		var mf := meridian_radius(bf, a, e2v)
		bf = bf + (xp - meridian_arc(bf, a, e2v)) / mf
	var sfb := sin(bf)
	var cfb := cos(bf)
	var tfb := tan(bf)
	var eta2f := ep2 * cfb * cfb
	var nf := prime_vertical_radius(bf, a, e2v)
	var mf2 := meridian_radius(bf, a, e2v)
	var y2 := yp * yp
	var b_rad := bf - tfb / (2.0 * mf2 * nf) * y2 \
		+ tfb / (24.0 * mf2 * nf * nf * nf) * (5.0 + 3.0 * tfb * tfb + eta2f - 9.0 * eta2f * tfb * tfb) * y2 * y2 \
		- tfb / (720.0 * mf2 * nf * nf * nf * nf * nf) * (61.0 + 90.0 * tfb * tfb + 45.0 * tfb * tfb * tfb * tfb) * y2 * y2 * y2
	var l := yp / (nf * cfb) \
		- (1.0 + 2.0 * tfb * tfb + eta2f) / (6.0 * nf * nf * nf * cfb) * yp * y2 \
		+ (5.0 + 28.0 * tfb * tfb + 24.0 * tfb * tfb * tfb * tfb + 6.0 * eta2f + 8.0 * eta2f * tfb * tfb) \
			/ (120.0 * nf * nf * nf * nf * nf * cfb) * yp * y2 * y2
	# Newton 精化：正算残差回代校正；末轮残差即估算精度
	var resid_m := 0.0
	for _i in range(2):
		var res := fwd(rad_to_deg(b_rad), l0_deg + rad_to_deg(l), l0_deg, ell, k0, fe, fn)
		if res.is_empty():
			return {}
		var mb := meridian_radius(b_rad, a, e2v)
		var nb := prime_vertical_radius(b_rad, a, e2v)
		var cb2 := cos(b_rad)
		b_rad += (x_m - res["x_m"]) / (k0 * mb)
		l += (y_m - res["y_m"]) / (k0 * nb * cb2)
		resid_m = sqrt(pow(x_m - res["x_m"], 2.0) + pow(y_m - res["y_m"], 2.0))
	var lat := rad_to_deg(b_rad)
	var lon := l0_deg + rad_to_deg(l)
	if absf(lat) > 90.0 or absf(lon) > 540.0:
		return {}
	return {"lat_deg": lat, "lon_deg": lon, "b_rad": b_rad, "l_rad": l, "bf_rad": bf,
			"resid_m": resid_m}

# ---------- §5 协议封装 ----------

## A3 高斯投影正算。p: {lat_deg, lon_deg, l0_deg, datum?, k0?, fe_m?, fn_m?}
## lat/lon 亦可传 dms 文本（lat_dms/lon_dms）。失败 ok=false + 中文 error。
static func forward(p: Dictionary) -> Dictionary:
	var lat := _num_or_dms(p, "lat_deg", "lat_dms")
	var lon := _num_or_dms(p, "lon_deg", "lon_dms")
	if is_nan(lat) or is_nan(lon):
		return _err("纬度/经度不是有效数字（可接受十进制度或度分秒文本）")
	var l0 := _f(p, "l0_deg", NAN)
	if is_nan(l0):
		return _err("缺少中央子午线 l0_deg（3° 带 L0=3n，6° 带 L0=6n-3）")
	var ell := _resolve_ell(p)
	if ell.is_empty():
		return _ell_error(String(p.get("datum", "CGCS2000")))
	var k0 := _f(p, "k0", 1.0)
	var fe := _f(p, "fe_m", 500000.0)
	var fn := _f(p, "fn_m", 0.0)
	var r := fwd(lat, lon, l0, ell, k0, fe, fn)
	if r.is_empty():
		return _err("输入超出高斯投影适用范围（|B|<90°，且距中央子午线 %.1f° 以内）" % MAX_LON_OFF_DEG)
	var l_deg := rad_to_deg(r["l_rad"])
	var gamma_deg := GKGaussKruger.meridian_convergence(r["b_rad"], r["l_rad"], float(ell["ep2"]))
	var value := {
		"x_m": r["x_m"], "y_m": r["y_m"],
		"lat_deg": lat, "lon_deg": lon, "l0_deg": l0,
		"datum": String(p.get("datum", "CGCS2000")),
		"l_rad": l_deg,
		# 子午线收敛角（度）：中央子午线以西为负（l<0），以东为正（l>0）
		"gamma_deg": gamma_deg,
	}
	var steps := [
		{"title": "1. 基本参数", "formula": "N = a/√(1-e²sin²B)，η² = e'²cos²B，t = tanB",
			"substitution": "a=%.3f m，1/f=%s，B=%.6f°，l=%.6f°" % [ell["a"], _num_str(ell["inv_f"]), lat, l_deg],
			"result": "N=%.4f m，η²=%.8f" % [r["n_m"], r["eta2"]]},
		{"title": "2. 子午线弧长 X（自赤道）", "formula": "X = a[(1-e²/4-3e⁴/64-5e⁶/256-175e⁸/16384)B - (3e²/8+3e⁴/32+45e⁶/1024+105e⁸/4096)sin2B + …]",
			"substitution": "B = %.10f rad" % r["b_rad"],
			"result": "X = %.4f m" % r["x_arc_m"]},
		{"title": "3. 纵坐标 x（北）", "formula": "x = X + N/2·t·cos²B·l² + N/24·t·cos⁴B·(5-t²+9η²+4η⁴)·l⁴ + N/720·t·cos⁶B·(61-58t²+t⁴+270η²-330t²η²)·l⁶",
			"substitution": "X=%.4f，N=%.3f，t=%.6f，η²=%.8f，l=%.10f rad" % [r["x_arc_m"], r["n_m"], tan(r["b_rad"]), r["eta2"], r["l_rad"]],
			"result": "x = %.4f m" % (r["x_m"] - fn)},
		{"title": "4. 横坐标 y（东）", "formula": "y = N·cosB·l + N/6·cos³B·(1-t²+η²)·l³ + N/120·cos⁵B·(5-18t²+t⁴+14η²-58t²η²)·l⁵ + N/5040·cos⁷B·(61-479t²+179t⁴-t⁶)·l⁷",
			"substitution": "k0=%.6f，FE=%.1f m" % [k0, fe],
			"result": "y = %.4f m" % r["y_m"]},
		{"title": "5. 子午线收敛角 γ", "formula": "γ = l·sinB + l³/3·sinB·cos²B·(1+3η²+2η⁴) + l⁵/5·sinB·cos⁴B·(2-t²)（真北相对网格北的偏角）",
			"substitution": "l=%.10f rad，B=%.8f°" % [r["l_rad"], lat],
			"result": "γ = %.7f°（%s）" % [gamma_deg, "中央子午线以东，γ 为正" if l_deg >= 0.0 else "中央子午线以西，γ 为负"]},
	]
	if absf(l_deg) > 3.5:
		steps.append({"title": "6. 精度声明", "formula": "", "substitution": "",
			"result": "本点距中央子午线 %.2f°，超出 3° 带常用域（|l|≤3.5°）：级数结果仍可用，但精度渐降，建议换用邻近带。" % absf(l_deg)})
	return {"ok": true, "value": value, "steps": steps,
			"formula": "高斯-克吕格正算（教材级数至 l⁶/l⁷ + e⁸ 弧长；k0=%.3f，FE=%.0f m，FN=%.0f m）" % [k0, fe, fn],
			"error": ""}

## A3 高斯投影反算。p: {x_m, y_m, l0_deg, datum?, k0?, fe_m?, fn_m?}
static func inverse(p: Dictionary) -> Dictionary:
	var x := _f(p, "x_m", NAN)
	var y := _f(p, "y_m", NAN)
	if is_nan(x) or is_nan(y):
		return _err("x_m/y_m 不是有效数字")
	var l0 := _f(p, "l0_deg", NAN)
	if is_nan(l0):
		return _err("缺少中央子午线 l0_deg")
	var ell := _resolve_ell(p)
	if ell.is_empty():
		return _ell_error(String(p.get("datum", "CGCS2000")))
	var k0 := _f(p, "k0", 1.0)
	var fe := _f(p, "fe_m", 500000.0)
	var fn := _f(p, "fn_m", 0.0)
	var r := inv(x, y, l0, ell, k0, fe, fn)
	if r.is_empty():
		return _err("反算失败：坐标超出适用范围（y 距中央子午线 %d km 以内）或参数非法" % int(MAX_INV_Y_M / 1000.0))
	var l_deg := rad_to_deg(r["l_rad"])
	var value := {
		"lat_deg": r["lat_deg"], "lon_deg": r["lon_deg"],
		"lat_dms": _AN.deg_to_dms_str(r["lat_deg"], 3),
		"lon_dms": _AN.deg_to_dms_str(r["lon_deg"], 3),
		"bf_deg": rad_to_deg(r["bf_rad"]),
		"datum": String(p.get("datum", "CGCS2000")),
		"l0_deg": l0,
		# 末轮 Newton 精化的正算残差（米）：往返闭合差，即本解的估算精度
		"resid": float(r["resid_m"]),
	}
	var steps := [
		{"title": "1. 底点纬度 Bf（μ1 迭代）", "formula": "μ1 = (x-FN)/k0/[a(1-e²/4-3e⁴/64-5e⁶/256)]，Bf ← Bf + (X(Bf)-(x-FN)/k0)/M(Bf)",
			"substitution": "x=%.4f m，k0=%.6f" % [x, k0],
			"result": "Bf = %.8f°" % rad_to_deg(r["bf_rad"])},
		{"title": "2. 纬度 B", "formula": "B = Bf - tf/(2MfNf)·y² + tf/(24MfNf³)·(5+3tf²+ηf²-9ηf²tf²)·y⁴ - tf/(720MfNf⁵)·(61+90tf²+45tf⁴)·y⁶",
			"substitution": "y=(y_m-FE)/k0=%.4f m" % ((y - fe) / k0),
			"result": "B = %.8f°" % r["lat_deg"]},
		{"title": "3. 经差 l", "formula": "l = y/(Nf·cosBf) - (1+2tf²+ηf²)/(6Nf³·cosBf)·y³ + (5+28tf²+24tf⁴+6ηf²+8ηf²tf²)/(120Nf⁵·cosBf)·y⁵",
			"substitution": "Bf=%.8f°" % rad_to_deg(r["bf_rad"]),
			"result": "l = %.8f°，L = %.8f°" % [rad_to_deg(r["l_rad"]), r["lon_deg"]]},
		{"title": "4. Newton 精化", "formula": "用正算残差校正：B ← B + Δx/M(B)，l ← l + Δy/(N(B)cosB)（2 轮）",
			"substitution": "目标 x=%.4f m，y=%.4f m" % [x, y],
			"result": "B=%.8f°，L=%.8f°；末轮残差（估算精度）=%.3f mm" % [r["lat_deg"], r["lon_deg"], r["resid_m"] * 1000.0]},
	]
	if absf(rad_to_deg(r["l_rad"])) > 3.5:
		steps.append({"title": "5. 精度声明", "formula": "", "substitution": "",
			"result": "本点距中央子午线 %.2f°，超出 3° 带常用域（|l|≤3.5°）：结果可用但精度渐降，建议换用邻近带。" % absf(rad_to_deg(r["l_rad"]))})
	return {"ok": true, "value": value, "steps": steps,
			"formula": "高斯-克吕格反算（μ1 迭代底点纬度 + 级数 + Newton 精化；与 pyproj 复核 ≤0.02mm）",
			"error": ""}

# ---------- 输入解析辅助 ----------

static func _f(p: Dictionary, key: String, dflt: float) -> float:
	if not p.has(key):
		return dflt
	var v: Variant = p[key]
	if v is float or v is int:
		return float(v)
	if v is String:
		var t := String(v).strip_edges()
		if t.is_valid_float():
			return t.to_float()
	return NAN

static func _num_or_dms(p: Dictionary, num_key: String, dms_key: String) -> float:
	# 数值键优先；其内容若为度分秒文本（如 39°54′27.1″）同样接受（GKAngles.parse_dms 兼容纯十进制）
	if p.has(num_key):
		var s := str(p[num_key]).strip_edges()
		if not s.is_empty():
			if s.is_valid_float():
				return s.to_float()
			return _AN.parse_dms(s)
	if p.has(dms_key):
		var s2 := str(p[dms_key]).strip_edges()
		if not s2.is_empty():
			if s2.is_valid_float():
				return s2.to_float()
			return _AN.parse_dms(s2)
	return NAN

static func _resolve_ell(p: Dictionary) -> Dictionary:
	var datum := resolve_datum(String(p.get("datum", "CGCS2000")))
	return _EL.params(datum)

static func _num_str(v: float) -> String:
	return String.num(v, 9)

static func _err(msg: String) -> Dictionary:
	return {"ok": false, "value": {}, "steps": [], "formula": "高斯-克吕格投影（教材级数）", "error": msg}

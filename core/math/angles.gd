# core/math/angles.gd —— GK-M1 叶子库：角度工具（度分秒↔十进制度↔gon、规范化、象限角、方位角推算）
#
# 设计约定（docs/ARCHITECTURE.md §4 GK-M1）：
#   - 纯静态函数、零引擎依赖（extends RefCounted）；
#   - 度↔弧度直接用引擎内置 deg_to_rad()/rad_to_deg()，不重复造轮子；
#   - 度分秒解析（parse_dms）只接受显式分隔符（°′″、空格、-、:）；
#     测量手簿的 dd.mmss 紧凑式（30.3030=30°30′30″）另走 compact_dms_to_deg，
#     二者不混用——"30.5" 一律按十进制度处理，避免 dd.mmss 的缺位歧义；
#   - 方位角约定：坐标东为 x、北为 y，方位角从北起顺时针 [0°, 360°)。
class_name GKAngles
extends RefCounted

const DEG_PER_GON := 0.9  # 1 gon（百分度）= 0.9°；一周 = 400 gon
const QUADRANT_NAMES := ["北东", "南东", "南西", "北西"]

## 度分秒 → 十进制度。符号只由 d 决定，m/s 按绝对值参与（30°-30′ 不作混用语义）。
static func dms_to_deg(d: float, m: float, s: float) -> float:
	var sign := 1.0 if d >= 0.0 else -1.0
	return sign * (absf(d) + absf(m) / 60.0 + absf(s) / 3600.0)

## 十进制度 → 度分秒字典 {sign: +1/-1, d, m, s, total_seconds}
## s 按 sec_decimals 位小数四舍五入并向 m/d 进位，保证 0<=s<60、0<=m<60。
static func deg_to_dms(deg: float, sec_decimals := 1) -> Dictionary:
	var sign := 1 if deg >= 0.0 else -1
	var ad := absf(deg)
	var sec_total := roundf(ad * 3600.0 * pow(10.0, sec_decimals))  # 以 10^-sec_decimals 秒为单位
	var unit := pow(10.0, sec_decimals)
	var s := fmod(sec_total / unit, 60.0)
	var m_total := floorf(sec_total / (60.0 * unit))
	var m := fmod(m_total, 60.0)
	var d := floorf(m_total / 60.0)
	# 浮点残余：s=60 的边界已被 roundf+floorf 组合消除，但 m/d 可能出现 -0.0
	if absf(s - 60.0) < 1e-9:
		s = 0.0
		m += 1.0
	if m >= 60.0:
		m = 0.0
		d += 1.0
	return {"sign": sign, "d": d, "m": m, "s": s, "total_seconds": sec_total / unit}

## 十进制度 → 度分秒文本，如 30°30′00.0″；负角带负号置于最前（度不补零）。
static func deg_to_dms_str(deg: float, sec_decimals := 1) -> String:
	var d := deg_to_dms(deg, sec_decimals)
	var prefix := "" if int(d.sign) >= 0 else "-"
	var fmt := "%d°%02d′%0" + str(3 + sec_decimals) + "." + str(sec_decimals) + "f″"
	return prefix + (fmt % [int(d.d), int(d.m), d.s])

## 解析度分秒文本 → 十进制度。接受 "30°30′00″"、"30 30 00"、"30-30-30"、"30:30:00"
## 与纯十进制 "30.5"。解析失败返回 NAN。
static func parse_dms(text: String) -> float:
	var t := text.strip_edges().replace("−", "-")
	if t.is_empty():
		return NAN
	# 分隔符归一为空格：°′″ 单引号 双引号 冒号 连字符 制表符
	var cleaned := t.replace("°", " ").replace("′", " ").replace("″", " ")
	cleaned = cleaned.replace("'", " ").replace("\"", " ").replace(":", " ").replace("-", " ")
	cleaned = cleaned.replace("\t", " ")
	while "  " in cleaned:
		cleaned = cleaned.replace("  ", " ")
	var parts := cleaned.strip_edges().split(" ", false)
	if parts.is_empty() or parts.size() > 3:
		return NAN
	var vals := PackedFloat64Array()
	for p in parts:
		if not p.is_valid_float():
			return NAN  # "abc"/"1.2.3" 等：to_float() 只会静默回 0，须显式校验
		var f := p.to_float()
		vals.append(f)
	var sign := 1.0 if vals[0] >= 0.0 else -1.0
	var d := absf(vals[0])
	var m := absf(vals[1]) if vals.size() > 1 else 0.0
	var s := absf(vals[2]) if vals.size() > 2 else 0.0
	if m >= 60.0 or s >= 60.0:
		return NAN
	return sign * (d + m / 60.0 + s / 3600.0)

## 测量手簿紧凑式 dd.mmss → 十进制度（30.3030 → 30°30′30″；30.5 → 30°50′00″）。
## 仅当调用方明确知道数值是 dd.mmss 约定时使用。sec 超过 2 位按秒处理。
static func compact_dms_to_deg(ddmmss: float) -> float:
	var sign := 1.0 if ddmmss >= 0.0 else -1.0
	var x := absf(ddmmss)
	var d := floorf(x)
	var mmss := roundf((x - d) * 10000.0)  # mmss 四位
	var m := floorf(mmss / 100.0)
	var s := fmod(mmss, 100.0)
	if m >= 60.0 or s >= 60.0:
		return NAN
	return sign * (d + m / 60.0 + s / 3600.0)

## 十进制度 → gon（百分度）：×10/9
static func deg_to_gon(deg: float) -> float:
	return deg * 10.0 / 9.0

## gon → 十进制度：×9/10
static func gon_to_deg(gon: float) -> float:
	return gon * 9.0 / 10.0

## 角度规范化到 [0°, 360°)
static func normalize_deg(deg: float) -> float:
	var r := fmod(deg, 360.0)
	if r < 0.0:
		r += 360.0
	return r

## 坐标方位角：由坐标增量 (dx=东, dy=北) 求从北起顺时针方位角 [0°, 360°)
static func azimuth(dx: float, dy: float) -> float:
	return normalize_deg(rad_to_deg(atan2(dx, dy)))

## 方位角 → 象限角：{quadrant: "北东", angle_deg: 45.0, text: "北东45°00′00.0″"}
## 分区：[0,90]北东、(90,180]南东、(180,270]南西、(270,360)北西。
static func quadrant_from_azimuth(az_deg: float) -> Dictionary:
	var az := normalize_deg(az_deg)
	var idx := 0
	var angle := az
	if az <= 90.0:
		idx = 0
		angle = az
	elif az <= 180.0:
		idx = 1
		angle = 180.0 - az
	elif az <= 270.0:
		idx = 2
		angle = az - 180.0
	else:
		idx = 3
		angle = 360.0 - az
	return {"quadrant": QUADRANT_NAMES[idx], "angle_deg": angle, "text": "%s%s" % [QUADRANT_NAMES[idx], deg_to_dms_str(angle)]}

## 象限角 → 方位角。q 接受 "北东/NE/南东/SE/南西/SW/北西/NW"（大小写不敏感）。
## 无法识别返回 NAN。
static func azimuth_from_quadrant(q: String, angle_deg: float) -> float:
	var t := q.strip_edges().to_lower()
	var base := NAN
	match t:
		"北东", "ne", "北偏东":
			base = angle_deg
		"南东", "se", "南偏东":
			base = 180.0 - angle_deg
		"南西", "sw", "南偏西":
			base = 180.0 + angle_deg
		"北西", "nw", "北偏西":
			base = 360.0 - angle_deg
	if is_nan(base):
		return NAN
	return normalize_deg(base)

## 方位角推算：α_后 = α_前 + β − 180°（β 为左角）或 α_前 − β + 180°（β 为右角）。
## 结果规范化到 [0°, 360°)。
static func propagate_azimuth(az_prev_deg: float, angle_deg: float, angle_is_left: bool) -> float:
	if angle_is_left:
		return normalize_deg(az_prev_deg + angle_deg - 180.0)
	return normalize_deg(az_prev_deg - angle_deg + 180.0)

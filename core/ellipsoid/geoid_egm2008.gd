# core/ellipsoid/geoid_egm2008.gd —— F2 高程异常查询：EGM2008 5′ PGM
#
# 移植底本：GeographicLib Geoid.cpp/hpp（Charles Karney，MIT/X11）：PGM(P5) 16-bit 大端，
# z=Offset+Scale×pixel（−108.0/0.003）；双线性或三次拟合插值（12 点 stencil）；
# 极点邻域用 c3n/c3s 矩阵；越界按经度回绕、纬度极点镜像（GeographicLib 2.5 原样移植）。
# 分工：PGM 读盘放 app/data_service.gd，core 只解析传入的 PackedByteArray。
# 双格网互检：北京/上海/北海三次插值 −9.1030/+11.8126/+42.6472 m，与独立 2.5′ GeoTIFF 互差 ≤1.5 mm
# （早期分配的「−9.082/+11.835/+42.680」无法按 5′ 格网复现，ARCHITECTURE.md 向量表已更正为实测值）。
class_name GKGeoidEGM2008
extends RefCounted

const PIXEL_MAX := 65535  # 本类仅支持 16-bit .pgm（GeographicLib pixel_size_=2）
# 解析器防御上限：真实 EGM2008 格网为 4320×2161（2.5′ 为 8640×4321），该上限有 10 倍裕量。
# 若不设限，恶意头部可用"宽偶高奇"组合使 width*height*2 溢出 64 位有符号整型变负，
# 绕过下方 n<need 长度检查，让 rawval 按越界偏移索引字节（独立复核 2026-11-20 发现）。
const MAX_DIM := 100000

# 三次拟合系数（Geoid.cpp c3_，12 点 × 10 项，行 = stencil 点 j，列 = 多项式项 i）
const C3 := [
	9, -18, -88, 0, 96, 90, 0, 0, -60, -20,
	-9, 18, 8, 0, -96, 30, 0, 0, 60, -20,
	9, -88, -18, 90, 96, 0, -20, -60, 0, 0,
	186, -42, -42, -150, -96, -150, 60, 60, 60, 60,
	54, 162, -78, 30, -24, -90, -60, 60, -60, 60,
	-9, -32, 18, 30, 24, 0, 20, -60, 0, 0,
	-9, 8, 18, 30, -96, 0, -20, 60, 0, 0,
	54, -78, 162, -90, -24, 30, 60, -60, 60, -60,
	-54, 78, 78, 90, 144, 90, -60, -60, -60, -60,
	9, -8, -18, -30, -24, 0, 20, 60, 0, 0,
	-9, 18, -32, 0, 24, 30, 0, 0, -60, 20,
	9, -18, -8, 0, -24, -30, 0, 0, 60, 20,
]
const C0 := 240.0
# 北极邻域系数（c3n_，分母 c0n=372）
const C3N := [
	0, 0, -131, 0, 138, 144, 0, 0, -102, -31,
	0, 0, 7, 0, -138, 42, 0, 0, 102, -31,
	62, 0, -31, 0, 0, -62, 0, 0, 0, 31,
	124, 0, -62, 0, 0, -124, 0, 0, 0, 62,
	124, 0, -62, 0, 0, -124, 0, 0, 0, 62,
	62, 0, -31, 0, 0, -62, 0, 0, 0, 31,
	0, 0, 45, 0, -183, -9, 0, 93, 18, 0,
	0, 0, 216, 0, 33, 87, 0, -93, 12, -93,
	0, 0, 156, 0, 153, 99, 0, -93, -12, -93,
	0, 0, -45, 0, -3, 9, 0, 93, -18, 0,
	0, 0, -55, 0, 48, 42, 0, 0, -84, 31,
	0, 0, -7, 0, -48, -42, 0, 0, 84, 31,
]
const C0N := 372.0
# 南极邻域系数（c3s_，y→1−y 变换，分母 c0s=372）
const C3S := [
	18, -36, -122, 0, 120, 135, 0, 0, -84, -31,
	-18, 36, -2, 0, -120, 51, 0, 0, 84, -31,
	36, -165, -27, 93, 147, -9, 0, -93, 18, 0,
	210, 45, -111, -93, -57, -192, 0, 93, 12, 93,
	162, 141, -75, -93, -129, -180, 0, 93, -12, 93,
	-36, -21, 27, 93, 39, 9, 0, -93, -18, 0,
	0, 0, 62, 0, 0, 31, 0, 0, 0, -31,
	0, 0, 124, 0, 0, 62, 0, 0, 0, -62,
	0, 0, 124, 0, 0, 62, 0, 0, 0, -62,
	0, 0, 62, 0, 0, 31, 0, 0, 0, -31,
	-18, 36, -64, 0, 66, 51, 0, 0, -102, 31,
	18, -36, 2, 0, -66, -51, 0, 0, 102, 31,
]
const C0S := 372.0

## 解析 PGM 头（P5）→ {ok, width, height, offset, scale, description, data_start, error}。
## 只吃字节，不碰文件系统。
static func parse_header(bytes: PackedByteArray) -> Dictionary:
	var out := {"ok": false, "width": 0, "height": 0, "offset": NAN, "scale": NAN,
				"description": "", "data_start": -1, "error": ""}
	var n := bytes.size()
	if n < 3:
		out["error"] = "PGM 数据过短，不是有效格网文件"
		return out
	# P5 魔数
	if bytes[0] != 80 or bytes[1] != 53:  # "P5"
		out["error"] = "PGM 魔数不是 P5，不是本类支持的二进制灰度格网"
		return out
	var pos := 2
	var width := -1
	var height := -1
	var offset := NAN
	var scale := NAN
	var desc := ""
	# 逐 token 扫描：'#' 注释行解析 Offset/Scale/Description；首个数字行 = width height
	while pos < n and (width < 0 or height < 0):
		var ch := bytes[pos]
		if ch == 35:  # '#' 注释：读到行尾
			var line := ""
			pos += 1
			while pos < n and bytes[pos] != 10:
				line += String.chr(bytes[pos])
				pos += 1
			var parts := line.strip_edges().split(" ", false)
			if parts.size() >= 2:
				if parts[0] == "Offset":
					offset = parts[1].to_float() if parts[1].is_valid_float() else NAN
				elif parts[0] == "Scale":
					scale = parts[1].to_float() if parts[1].is_valid_float() else NAN
				elif parts[0] == "Description":
					desc = " ".join(parts.slice(1))
			continue
		if ch == 10 or ch == 13 or ch == 32 or ch == 9:
			pos += 1
			continue
		# 数字 token：width height（同一行两个整数）
		var toks := PackedStringArray()
		while pos < n and toks.size() < 2:
			var t := ""
			while pos < n and bytes[pos] != 10 and bytes[pos] != 13 and bytes[pos] != 32 and bytes[pos] != 9:
				t += String.chr(bytes[pos])
				pos += 1
			if t != "":
				toks.append(t)
			if pos < n and bytes[pos] == 10:
				break
			while pos < n and (bytes[pos] == 32 or bytes[pos] == 9 or bytes[pos] == 13):
				pos += 1
		var ok_parse := true
		var nums := PackedInt64Array()
		for t2 in toks:
			if not t2.is_valid_int():
				ok_parse = false
				break
			nums.append(t2.to_int())
		if not ok_parse or nums.size() < 2:
			out["error"] = "PGM 头部的栅格尺寸行无法解析"
			return out
		width = nums[0]
		height = nums[1]
		break
	if width < 2 or height < 2:
		out["error"] = "PGM 栅格尺寸过小（width/height < 2）"
		return out
	if width > MAX_DIM or height > MAX_DIM:
		out["error"] = "PGM 栅格尺寸超过解析器上限 %d×%d（疑似非法头部）" % [MAX_DIM, MAX_DIM]
		return out
	if width % 2 != 0:
		out["error"] = "PGM 宽度为奇数（GeographicLib 要求经度方向可跨极点延展）"
		return out
	if height % 2 == 0:
		out["error"] = "PGM 高度为偶数（GeographicLib 要求纬度格网含赤道行）"
		return out
	# maxval：跳过空白，读数字 token；数据在 maxval 后恰好 1 个空白字节开始
	while pos < n and (bytes[pos] == 10 or bytes[pos] == 13 or bytes[pos] == 32 or bytes[pos] == 9):
		pos += 1
	var maxval_s := ""
	while pos < n and bytes[pos] >= 48 and bytes[pos] <= 57:
		maxval_s += String.chr(bytes[pos])
		pos += 1
	if maxval_s.is_empty() or not maxval_s.is_valid_int():
		out["error"] = "PGM 头部缺少 maxval"
		return out
	var maxval := maxval_s.to_int()
	if maxval != PIXEL_MAX:
		out["error"] = "PGM maxval=%d，本类仅支持 16-bit（maxval=%d）格网" % [maxval, PIXEL_MAX]
		return out
	pos += 1  # maxval 后的单一空白字节
	var data_start := pos
	if is_nan(offset) or is_nan(scale):
		out["error"] = "PGM 注释头缺少 Offset/Scale 声明"
		return out
	if scale <= 0.0:
		out["error"] = "PGM Scale 声明必须为正数"
		return out
	var need := data_start + width * height * 2
	if need < 0:
		# 兜底：尺寸上限已挡住正常路径，仍防 64 位整型溢出使 need 变负、绕过长度检查
		out["error"] = "PGM 栅格尺寸过大，数据长度计算溢出（疑似非法头部）"
		return out
	if n < need:
		out["error"] = "PGM 数据长度不足：应有 %d 字节，实际 %d" % [need, n]
		return out
	out["ok"] = true
	out["width"] = width
	out["height"] = height
	out["offset"] = offset
	out["scale"] = scale
	out["description"] = desc
	out["data_start"] = data_start
	return out

## 格网对象：持字节与头参数，提供 height(lat, lon, cubic)。create 失败返回 null。
## 注意：行数成员叫 rows（height 名留给插值方法，与 GeographicLib Geoid::height 对齐）。
class Grid extends RefCounted:
	var width := 0
	var rows := 0
	var offset := 0.0
	var scale := 0.0
	var description := ""
	var rlonres := 0.0
	var rlatres := 0.0
	var _bytes: PackedByteArray
	var _data_start := 0

	static func create(bytes: PackedByteArray) -> Grid:
		var h := GKGeoidEGM2008.parse_header(bytes)
		if not bool(h["ok"]):
			return null
		var g := Grid.new()
		g.width = int(h["width"])
		g.rows = int(h["height"])
		g.offset = float(h["offset"])
		g.scale = float(h["scale"])
		g.description = String(h["description"])
		g._bytes = bytes
		g._data_start = int(h["data_start"])
		g.rlonres = float(g.width) / 360.0
		g.rlatres = float(g.rows - 1) / 180.0
		return g

	## 原始像素（大端 16-bit），经度回绕、纬度极点镜像（Geoid.hpp rawval 原样移植）。
	func rawval(ix: int, iy: int) -> int:
		if ix < 0:
			ix += width
		elif ix >= width:
			ix -= width
		if iy < 0 or iy >= rows:
			iy = -iy if iy < 0 else 2 * (rows - 1) - iy
			ix += (1 if ix < width / 2 else -1) * (width / 2)
		var o := _data_start + 2 * (iy * width + ix)
		return (_bytes[o] << 8) | _bytes[o + 1]

	## 高程异常（米）。lat/lon 无效返回 NAN；cubic=false 为双线性插值。
	func height(lat: float, lon: float, cubic := true) -> float:
		if not (is_finite(lat) and is_finite(lon)):
			return NAN
		if absf(lat) > 90.0:
			return NAN
		var lon_n := fmod(lon + 180.0, 360.0)
		if lon_n < 0.0:
			lon_n += 360.0
		lon_n -= 180.0
		var fx := lon_n * rlonres
		var fy := -lat * rlatres
		var ix := int(floor(fx))
		var iy := mini(int((rows - 1) / 2) - 1, int(floor(fy)))
		fx -= float(ix)
		fy -= float(iy)
		iy += int((rows - 1) / 2)
		if not cubic:
			var v00 := float(rawval(ix, iy))
			var v01 := float(rawval(ix + 1, iy))
			var v10 := float(rawval(ix, iy + 1))
			var v11 := float(rawval(ix + 1, iy + 1))
			var aa := (1.0 - fx) * v00 + fx * v01
			var bb := (1.0 - fx) * v10 + fx * v11
			var c := (1.0 - fy) * aa + fy * bb
			return offset + scale * c
		var v := [
			float(rawval(ix, iy - 1)), float(rawval(ix + 1, iy - 1)),
			float(rawval(ix - 1, iy)), float(rawval(ix, iy)),
			float(rawval(ix + 1, iy)), float(rawval(ix + 2, iy)),
			float(rawval(ix - 1, iy + 1)), float(rawval(ix, iy + 1)),
			float(rawval(ix + 1, iy + 1)), float(rawval(ix + 2, iy + 1)),
			float(rawval(ix, iy + 2)), float(rawval(ix + 1, iy + 2)),
		]
		var c3x: Array = C3
		var c0x := C0
		if iy == 0:
			c3x = C3N
			c0x = C0N
		elif iy == rows - 2:
			c3x = C3S
			c0x = C0S
		var t := PackedFloat64Array()
		t.resize(10)
		for i in range(10):
			var s := 0.0
			for j in range(12):
				s += v[j] * float(c3x[10 * j + i])
			t[i] = s / c0x
		var h := t[0] + fx * (t[1] + fx * (t[3] + fx * t[6])) \
			+ fy * (t[2] + fx * (t[4] + fx * t[7]) + fy * (t[5] + fx * t[8] + fy * t[9]))
		return offset + scale * h

## 由字节构建格网（app 层读盘后传入；失败返回 null）。
static func make_grid(bytes: PackedByteArray) -> Grid:
	return Grid.create(bytes)

## §5 协议查询入口。p = {bytes: PackedByteArray, lat_deg, lon_deg, cubic(bool,默认 true)}
## 另可传 grid: Grid（跳过重复解析）。
static func query(p: Dictionary) -> Dictionary:
	var lat := float(p.get("lat_deg", NAN))
	var lon := float(p.get("lon_deg", NAN))
	var cubic := bool(p.get("cubic", true))
	if not (is_finite(lat) and is_finite(lon)):
		return {"ok": false, "value": {}, "steps": [], "formula": "", "error": "输入不是有效数值（纬度/经度需为数字）"}
	if absf(lat) > 90.0:
		return {"ok": false, "value": {}, "steps": [], "formula": "", "error": "纬度超出范围：|B| ≤ 90°"}
	var grid: Grid = p.get("grid", null)
	if grid == null:
		var bytes: PackedByteArray = p.get("bytes", PackedByteArray())
		grid = make_grid(bytes)
	if grid == null:
		return {"ok": false, "value": {}, "steps": [], "formula": "", "error": "EGM2008 格网数据缺失或无法解析（app/data_service.gd 读盘后传入）"}
	var h := grid.height(lat, lon, cubic)
	if is_nan(h):
		return {"ok": false, "value": {}, "steps": [], "formula": "", "error": "插值失败（坐标非法）"}
	var interp_name := "三次拟合（GeographicLib 12 点 stencil）" if cubic else "双线性"
	var steps := [
		{"title": "1. 定位格网单元",
			"formula": "格网 5′×5′；ix = floor(L·12)，iy 由 B 反算（Origin 90N 0E，上北下南）",
			"substitution": "B = %s°，L = %s°" % [String.num(lat, 6), String.num(lon, 6)],
			"result": "%d×%d 像素格网，%s 插值" % [grid.width, grid.rows, interp_name]},
		{"title": "2. 像素值化算高程异常",
			"formula": "ζ = Offset + Scale × v（本格网 Offset=-108.0，Scale=0.003）",
			"substitution": "16-bit 大端像素按插值权重合成 v",
			"result": "ζ = %s m" % String.num(h, 4)},
		{"title": "3. 精度说明",
			"formula": "EGM2008 5′ 格网内插精度约 ±0.1~0.3 m（山区更差），格网头 MaxCubicError=0.294 m",
			"substitution": "插值误差量级为厘米~分米级，教学演示口径",
			"result": "ζ = %s m" % String.num(h, 4)},
	]
	return {
		"ok": true,
		"value": {"undulation_m": h, "cubic": 1.0 if cubic else 0.0, "grid": str(grid.width) + "x" + str(grid.rows)},
		"steps": steps,
		"formula": "EGM2008 高程异常查询（PGM 5′，Offset=-108.0/Scale=0.003，%s）" % interp_name,
		"error": "",
	}

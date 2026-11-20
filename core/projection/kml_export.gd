# core/projection/kml_export.gd —— GK-M3-7 KML 生成（A15，纯字符串 XML；KMZ 打包由 platform 层 ZIPPacker 完成）
#
# 职责：把点/线/面写成 OGC KML 2.2 文本。坐标顺序为 KML 规定的 lon,lat[,alt]（注意与测量 B/L 相反），
# 输出统一 WGS84 经纬度；XML 文本属性做转义（& < > " '）。
# 本模块不做任何 I/O——返回字符串，调用方（UI/platform）负责保存或打包 KMZ。
class_name GKKmlExport
extends RefCounted

const KML_HEADER := "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" \
	+ "<kml xmlns=\"http://www.opengis.net/kml/2.2\">"

## 文本 XML 转义
static func escape_xml(text: String) -> String:
	return text \
		.replace("&", "&amp;") \
		.replace("<", "&lt;") \
		.replace(">", "&gt;") \
		.replace("\"", "&quot;") \
		.replace("'", "&apos;")

## 经纬度 → "lon,lat,alt" 坐标串（KML 顺序：经度在前；海拔缺省 0）
static func coord_text(lon_deg: float, lat_deg: float, alt_m: float = 0.0, decimals: int = 8) -> String:
	if not is_finite(lon_deg) or not is_finite(lat_deg) or absf(lat_deg) > 90.0 or absf(lon_deg) > 180.0:
		return ""
	return "%.8f,%.8f,%.3f" % [lon_deg, lat_deg, alt_m]

## 单点 Placemark。p: {name?, description?, lat_deg, lon_deg, alt_m?}
## 返回 §5 协议，value.kml = KML 文本。
static func placemark(p: Dictionary) -> Dictionary:
	var lat := _f(p, "lat_deg", NAN)
	var lon := _f(p, "lon_deg", NAN)
	var alt := _f(p, "alt_m", 0.0)
	if is_nan(lat) or is_nan(lon):
		return _err("纬度/经度不是有效数字")
	var coord := coord_text(lon, lat, alt)
	if coord.is_empty():
		return _err("坐标超出范围（|B|≤90°，|L|≤180°）")
	var name := String(p.get("name", "点位"))
	var desc := String(p.get("description", ""))
	var kml := KML_HEADER
	kml += "\n  <Placemark>\n"
	kml += "    <name>%s</name>\n" % escape_xml(name)
	if desc != "":
		kml += "    <description>%s</description>\n" % escape_xml(desc)
	kml += "    <Point><coordinates>%s</coordinates></Point>\n" % coord
	kml += "  </Placemark>\n</kml>"
	var value := {
		"kml": kml, "coord": coord,
		"lat_deg": lat, "lon_deg": lon, "alt_m": alt,
		"name": name,
	}
	var steps := [
		{"title": "1. 坐标串", "formula": "KML 坐标顺序为 lon,lat,alt（经度在前，与测量 B/L 相反）",
			"substitution": "B=%.8f°，L=%.8f°，h=%.1f m" % [lat, lon, alt],
			"result": coord},
		{"title": "2. 生成 Placemark", "formula": "Point + coordinates；名称/描述做 XML 转义",
			"substitution": "name=%s" % name,
			"result": "已生成 %d 字符 KML 文本" % kml.length()},
	]
	return {"ok": true, "value": value, "steps": steps,
			"formula": "KML 2.2 Placemark（OGC 标准；KMZ=该文本经 platform ZIPPacker 压缩为 doc.kml）",
			"error": ""}

## 多点 LineString（线路/边界）。p: {name?, description?, points: [{lat_deg, lon_deg, alt_m?}, ...], closed?}
static func line_string(p: Dictionary) -> Dictionary:
	var pts: Variant = p.get("points", [])
	if not (pts is Array) or (pts as Array).is_empty():
		return _err("缺少 points 点列（至少 2 点）")
	var arr: Array = pts
	if arr.size() < 2:
		return _err("LineString 至少需要 2 个点")
	var coords := PackedStringArray()
	for pt: Dictionary in arr:
		var lat := _f(pt, "lat_deg", NAN)
		var lon := _f(pt, "lon_deg", NAN)
		var alt := _f(pt, "alt_m", 0.0)
		var c := coord_text(lon, lat, alt)
		if c.is_empty():
			return _err("点列中存在非法坐标（|B|≤90°，|L|≤180°）")
		coords.append(c)
	var closed := bool(p.get("closed", false))
	if closed:
		coords.append(coords[0])  # 环面：首尾闭合
	var name := String(p.get("name", "线路"))
	var desc := String(p.get("description", ""))
	var kml := KML_HEADER
	kml += "\n  <Placemark>\n"
	kml += "    <name>%s</name>\n" % escape_xml(name)
	if desc != "":
		kml += "    <description>%s</description>\n" % escape_xml(desc)
	kml += "    <LineString><tessellate>1</tessellate>\n"
	if closed:
		kml += "      <Polygon><outerBoundaryIs><LinearRing><coordinates>\n"
		kml += "        " + " ".join(coords) + "\n"
		kml += "      </coordinates></LinearRing></outerBoundaryIs></Polygon>\n"
	else:
		kml += "      <coordinates>\n        " + " ".join(coords) + "\n      </coordinates>\n"
	kml += "    </LineString>\n  </Placemark>\n</kml>" if not closed else "  </Placemark>\n</kml>"
	var value := {
		"kml": kml,
		"coord_block": " ".join(coords),
		"n_points": arr.size() + (1 if closed else 0),
		"closed": closed,
		"name": name,
	}
	var steps := [
		{"title": "1. 逐点坐标串", "formula": "lon,lat,alt 空格分隔",
			"substitution": "%d 个输入点%s" % [arr.size(), "，闭合环面自动补首点" if closed else ""],
			"result": "有效坐标 %d 段" % coords.size()},
		{"title": "2. 生成 LineString/环面", "formula": "LineString+tessellate（闭合时改用 Polygon/LinearRing）",
			"substitution": "name=%s" % name,
			"result": "已生成 %d 字符 KML 文本" % kml.length()},
	]
	return {"ok": true, "value": value, "steps": steps,
			"formula": "KML 2.2 LineString/Polygon（OGC 标准）",
			"error": ""}

## Document 包装（多 Placemark 组织 + 文档名）。p: {name?, description?, placemarks: [kml 片段...]}
static func document(p: Dictionary) -> Dictionary:
	var name := String(p.get("name", "GeodesyKit 导出"))
	var desc := String(p.get("description", ""))
	var items: Variant = p.get("placemarks", [])
	if not (items is Array):
		return _err("placemarks 应为数组（每项为 Placemark 片段或点字典）")
	var arr: Array = items
	if arr.is_empty():
		return _err("placemarks 为空")
	var inner := PackedStringArray()
	for it: Dictionary in arr:
		if it.has("kml"):
			inner.append(String(it["kml"]))
			continue
		var nested: Dictionary = it.get("value", {}) if it is Dictionary else {}
		if nested.has("kml"):
			inner.append(String(nested["kml"]))
			continue
		var r := placemark(it)
		if not bool(r.get("ok", false)):
			return r
		inner.append(String(r["value"]["kml"]))
	var body := ""
	for frag in inner:
		body += frag.replace(KML_HEADER, "").replace("</kml>", "").strip_edges() + "\n"
	var kml := KML_HEADER
	kml += "\n  <Document>\n    <name>%s</name>\n" % escape_xml(name)
	if desc != "":
		kml += "    <description>%s</description>\n" % escape_xml(desc)
	kml += body
	kml += "  </Document>\n</kml>"
	var value := {
		"kml": kml, "n_placemarks": inner.size(), "name": name,
	}
	return {"ok": true, "value": value, "steps": [],
			"formula": "KML 2.2 Document（多 Placemark 组织）", "error": ""}

# ---------- 内部 ----------

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

static func _err(msg: String) -> Dictionary:
	return {"ok": false, "value": {}, "steps": [], "formula": "KML 导出（OGC KML 2.2）", "error": msg}

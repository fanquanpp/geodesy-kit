# tests/projection/test_kml.gd —— M3-7 KML 生成（A15）结构构造测试
#
# 向量来源【构造·OGC KML 2.2 结构规则】：Placemark/坐标串 "lon,lat,alt" 顺序（经度在前）、
# XML 文本转义、LineString/Polygon 结构、Document 组织。
extends "res://tests/test_case_base.gd"

const KM := preload("res://core/projection/kml_export.gd")

func _v(res: Dictionary) -> Dictionary:
	return res.get("value", {}) if res.get("ok", false) else {}

func test_placemark_structure() -> void:
	var r := KM.placemark({"name": "天安门", "description": "测试点", "lat_deg": 39.9075, "lon_deg": 116.3913})
	assert_true(bool(r.get("ok", false)), "Placemark 生成：" + String(r.get("error", "")))
	var kml := String(_v(r)["kml"])
	assert_true(kml.begins_with("<?xml version=\"1.0\" encoding=\"UTF-8\"?>"), "XML 声明")
	assert_true(kml.contains("xmlns=\"http://www.opengis.net/kml/2.2\""), "KML 2.2 命名空间")
	assert_true(kml.contains("<Placemark>"), "Placemark 元素")
	assert_true(kml.contains("<name>天安门</name>"), "名称")
	assert_true(kml.contains("<description>测试点</description>"), "描述")
	assert_true(kml.contains("<Point><coordinates>"), "Point 元素")
	# 坐标顺序：经度在前，"lon,lat,alt"
	assert_true(kml.contains("<Point><coordinates>116.39130000,39.90750000,0.000</coordinates></Point>"),
			"坐标串 lon,lat,0 顺序：" + kml)
	assert_true(kml.ends_with("</kml>"), "闭合 kml 标签")

func test_xml_escaping() -> void:
	var r := KM.placemark({"name": "A&B <C> \"D\" 'E'", "lat_deg": 0.0, "lon_deg": 0.0})
	assert_true(bool(r.get("ok", false)), "含特殊字符生成")
	var kml := String(_v(r)["kml"])
	assert_true(kml.contains("A&amp;B &lt;C&gt; &quot;D&quot; &apos;E&apos;"), "XML 五字符转义")
	assert_false(kml.contains("A&B"), "原文 & 不应出现")

func test_coordinate_text() -> void:
	assert_eq(KM.coord_text(116.3913, 39.9075), "116.39130000,39.90750000,0.000", "缺省海拔 0")
	assert_eq(KM.coord_text(-70.252228, 43.642556, 43.5), "-70.25222800,43.64255600,43.500", "负经度与海拔")
	assert_true(KM.coord_text(200.0, 0.0).is_empty(), "经度越界返回空串")
	assert_true(KM.coord_text(0.0, 95.0).is_empty(), "纬度越界返回空串")

func test_line_string() -> void:
	var pts := [
		{"lat_deg": 39.9, "lon_deg": 116.3},
		{"lat_deg": 39.8, "lon_deg": 116.4},
		{"lat_deg": 39.7, "lon_deg": 116.5},
	]
	var r := KM.line_string({"name": "线路", "points": pts})
	assert_true(bool(r.get("ok", false)), "LineString 生成：" + String(r.get("error", "")))
	var v: Dictionary = _v(r)
	var kml := String(v["kml"])
	assert_true(kml.contains("<LineString>"), "LineString 元素")
	assert_true(kml.contains(String(v["coord_block"])),
			"空格分隔坐标串（coord_block）")
	assert_true(kml.contains("<tessellate>1</tessellate>"), "tessellate 元素")
	assert_int_eq(int(v["n_points"]), 3, "3 个点")
	# 闭合环面：Polygon + 首尾点相同
	var rc := KM.line_string({"name": "环面", "points": pts, "closed": true})
	var vc: Dictionary = _v(rc)
	assert_true(bool(rc.get("ok", false)), "环面生成：" + String(rc.get("error", "")))
	var kc := String(vc["kml"])
	assert_true(kc.contains("<Polygon><outerBoundaryIs><LinearRing><coordinates>"), "闭合用 Polygon/LinearRing")
	assert_int_eq(int(vc["n_points"]), 4, "闭合补首点")
	var block := String(vc["coord_block"])
	var segs := block.split(" ")
	assert_true(segs.size() == 4 and segs[0] == segs[3], "首尾坐标一致")

func test_document() -> void:
	var p1 := KM.placemark({"name": "点1", "lat_deg": 39.9, "lon_deg": 116.3})
	var p2 := KM.placemark({"name": "点2", "lat_deg": 39.8, "lon_deg": 116.4})
	var r := KM.document({"name": "导出文档", "placemarks": [p1, p2]})
	assert_true(bool(r.get("ok", false)), "Document 生成：" + String(r.get("error", "")))
	var kml := String(_v(r)["kml"])
	assert_true(kml.contains("<Document>"), "Document 元素")
	assert_true(kml.contains("<name>导出文档</name>"), "文档名")
	assert_true(kml.contains("点1") and kml.contains("点2"), "两个 Placemark 均在")
	assert_int_eq(int(_v(r)["n_placemarks"]), 2, "计数")
	# 非法子项应传播错误
	var bad := KM.document({"placemarks": [{"lat_deg": 200.0, "lon_deg": 0.0}]})
	assert_false(bool(bad.get("ok", true)), "非法子点传播失败")

func test_errors() -> void:
	assert_false(bool(KM.placemark({"lat_deg": "abc", "lon_deg": 0.0}).get("ok", true)), "非法纬度")
	assert_false(bool(KM.line_string({"points": []}).get("ok", true)), "空点列")
	assert_false(bool(KM.line_string({"points": [{"lat_deg": 1.0, "lon_deg": 1.0}]}).get("ok", true)), "单点 LineString")
	assert_false(bool(KM.document({"placemarks": []}).get("ok", true)), "空 Document")

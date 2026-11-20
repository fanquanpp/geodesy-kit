# tests/mathk/test_angles.gd —— GK-M1 角度工具（向量来源：ARCHITECTURE.md §4 GK-M1【构造】）
# 注：架构向量表"30.5°=33.913345 gon"与换算定义矛盾（30.5×10/9=33.888889），
# 本测试按定义式 1 gon=0.9° 断言，该出入已在交付说明中报告。
extends "res://tests/test_case_base.gd"

const A := preload("res://core/math/angles.gd")

func test_dms_roundtrip() -> void:
	assert_almost_eq(A.dms_to_deg(30, 30, 0), 30.5, 1e-12, "30°30′00″")
	assert_almost_eq(A.dms_to_deg(-118, 15, 36), -118.26, 1e-12, "负角符号由度携带")
	var d: Dictionary = A.deg_to_dms(30.5)
	assert_int_eq(int(d.sign), 1, "符号")
	assert_int_eq(int(d.d), 30, "度")
	assert_int_eq(int(d.m), 30, "分")
	assert_almost_eq(d.s, 0.0, 1e-9, "秒")
	var dn: Dictionary = A.deg_to_dms(-0.5)
	assert_int_eq(int(dn.sign), -1, "负号")
	assert_int_eq(int(dn.d), 0, "度 0")
	assert_int_eq(int(dn.m), 30, "分 30")
	# 进位检查：30.5166667° → 30°31′00″（秒取整后向分进位）
	var dc: Dictionary = A.deg_to_dms(30.5166666666666667, 0)
	assert_int_eq(int(dc.d), 30, "进位-度")
	assert_int_eq(int(dc.m), 31, "进位-分")
	assert_almost_eq(dc.s, 0.0, 1e-9, "进位-秒")
	assert_eq(A.deg_to_dms_str(30.5), "30°30′00.0″", "文本格式")
	assert_eq(A.deg_to_dms_str(-0.5), "-0°30′00.0″", "负角文本")

func test_parse_dms() -> void:
	assert_almost_eq(A.parse_dms("30°30′00″"), 30.5, 1e-12, "全角分隔")
	assert_almost_eq(A.parse_dms("30-30-30"), 30.508333333333333, 1e-9, "连字符分隔")
	assert_almost_eq(A.parse_dms("30 15 36"), 30.26, 1e-12, "空格分隔")
	assert_almost_eq(A.parse_dms("30.5"), 30.5, 1e-12, "纯十进制")
	assert_true(is_nan(A.parse_dms("30 60 00")), "分≥60 应拒绝")
	assert_true(is_nan(A.parse_dms("abc")), "非数字应拒绝")
	assert_true(is_nan(A.parse_dms("")), "空串应拒绝")

func test_compact_dms() -> void:
	assert_almost_eq(A.compact_dms_to_deg(30.3030), 30.508333333333333, 1e-9, "30.3030=30°30′30″")
	assert_almost_eq(A.compact_dms_to_deg(30.5), 30.833333333333333, 1e-9, "30.5=30°50′（紧凑式约定）")
	assert_almost_eq(A.compact_dms_to_deg(-118.2615), -118.4375, 1e-9, "负角紧凑式")
	assert_true(is_nan(A.compact_dms_to_deg(30.6030)), "分≥60 应拒绝")

func test_gon_and_normalize() -> void:
	assert_almost_eq(A.deg_to_gon(30.5), 33.888888888888886, 1e-12, "度→gon（30.5×10/9）")
	assert_almost_eq(A.gon_to_deg(400.0), 360.0, 1e-12, "一周 400 gon")
	assert_almost_eq(A.gon_to_deg(A.deg_to_gon(123.456)), 123.456, 1e-9, "往返一致")
	# 弧度关系（30.5° = 30.5×π/180 = 0.532325421858...）
	assert_almost_eq(A.deg_to_gon(30.5) * 0.9, 30.5, 1e-12, "gon 定义自洽")
	assert_almost_eq(30.5 * PI / 180.0, 0.53232542185827, 1e-12, "十进制度→弧度")
	assert_almost_eq(A.normalize_deg(-90), 270.0, 1e-12, "负角规范化")
	assert_almost_eq(A.normalize_deg(450), 90.0, 1e-12, "超周规范化")
	assert_almost_eq(A.normalize_deg(0), 0.0, 1e-12, "零角")

func test_azimuth_and_quadrant() -> void:
	assert_almost_eq(A.azimuth(3, 4), 36.869897645844021, 1e-9, "dx=3,dy=4")
	assert_almost_eq(A.azimuth(0, -1), 180.0, 1e-12, "正南")
	assert_almost_eq(A.azimuth(-1, 0), 270.0, 1e-12, "正西")
	var q: Dictionary = A.quadrant_from_azimuth(315.0)
	assert_eq(q["quadrant"], "北西", "315°象限")
	assert_almost_eq(q["angle_deg"], 45.0, 1e-12, "315°象限角值")
	assert_eq(A.quadrant_from_azimuth(135.0)["quadrant"], "南东", "135°象限")
	assert_almost_eq(A.azimuth_from_quadrant("北西", 45.0), 315.0, 1e-12, "象限角→方位")
	assert_almost_eq(A.azimuth_from_quadrant("NW", 45.0), 315.0, 1e-12, "英文象限名")
	assert_true(is_nan(A.azimuth_from_quadrant("xx", 45.0)), "未知象限名")

func test_propagate_azimuth() -> void:
	# 架构 C3 附合导线向量首步：α前=95.5°，β左=178.250556° → 93.750556°
	assert_almost_eq(A.propagate_azimuth(95.5, 178.250556, true), 93.750556, 1e-9, "左角推算")
	# 右角：α前=10°，β右=30° → 160°
	assert_almost_eq(A.propagate_azimuth(10.0, 30.0, false), 160.0, 1e-12, "右角推算")
	# 规范化到 [0,360)：α前=350°，β左=20° → 190°
	assert_almost_eq(A.propagate_azimuth(350.0, 20.0, true), 190.0, 1e-12, "越周规范化")
	# α前=350°，β左=100° → 270°；α前=350°，β左=130° → 300°
	assert_almost_eq(A.propagate_azimuth(350.0, 130.0, true), 300.0, 1e-12, "再次越周")

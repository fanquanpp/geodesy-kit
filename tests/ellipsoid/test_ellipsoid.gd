# tests/ellipsoid/test_ellipsoid.gd —— 椭球常数回归（【权威·定义精确】向量，ARCHITECTURE.md §4 GK-M1/M2）
# e²/b 的期望值取自公开文献口径：
#   WGS84 e²=0.0066943799901413165、b=6356752.3142451798（NIMA TR8350.2 派生）
#   GRS80 e'²=0.00673949677548
#   CGCS2000 e²=0.00669438002290（GB 22021-2008 派生）
#   克拉索夫斯基 e²=0.00669342162297、b=6356863.0187730473
extends "res://tests/test_case_base.gd"

const EL := preload("res://core/ellipsoid/ellipsoid.gd")

func test_builtin_exact_definitions() -> void:
	var cg: Dictionary = EL.params("CGCS2000")
	assert_almost_eq(cg["a"], 6378137.0, 1e-9, "CGCS2000 a")
	assert_almost_eq(cg["inv_f"], 298.257222101, 1e-9, "CGCS2000 1/f")
	var w: Dictionary = EL.params("WGS84")
	assert_almost_eq(w["a"], 6378137.0, 1e-9, "WGS84 a")
	assert_almost_eq(w["inv_f"], 298.257223563, 1e-9, "WGS84 1/f")
	var k: Dictionary = EL.params("KRASOVSKY")
	assert_almost_eq(k["a"], 6378245.0, 1e-9, "克拉索夫斯基 a")
	assert_almost_eq(k["inv_f"], 298.3, 1e-9, "克拉索夫斯基 1/f")
	var i75: Dictionary = EL.params("IUGG75")
	assert_almost_eq(i75["a"], 6378140.0, 1e-9, "IUGG75 a")
	assert_almost_eq(i75["inv_f"], 298.257, 1e-9, "IUGG75 1/f")
	var i24: Dictionary = EL.params("INTERNATIONAL1924")
	assert_almost_eq(i24["a"], 6378388.0, 1e-9, "Int1924 a")
	assert_almost_eq(i24["inv_f"], 297.0, 1e-9, "Int1924 1/f")
	var g80: Dictionary = EL.params("GRS80")
	assert_almost_eq(g80["a"], 6378137.0, 1e-9, "GRS80 a")
	assert_almost_eq(g80["inv_f"], 298.257222101, 1e-9, "GRS80 1/f")

func test_derived_quantities_vs_literature() -> void:
	var w: Dictionary = EL.params("WGS84")
	assert_almost_eq(w["e2"], 0.0066943799901413165, 1e-12, "WGS84 e²")
	assert_almost_eq(w["b"], 6356752.3142451798, 1e-6, "WGS84 b")
	assert_almost_eq(w["ep2"], 0.00673949674228, 1e-12, "WGS84 e'²")
	var cg: Dictionary = EL.params("CGCS2000")
	assert_almost_eq(cg["e2"], 0.00669438002290, 1e-12, "CGCS2000 e²")
	var g80: Dictionary = EL.params("GRS80")
	assert_almost_eq(g80["ep2"], 0.00673949677548, 1e-12, "GRS80 e'²")
	var k: Dictionary = EL.params("KRASOVSKY")
	assert_almost_eq(k["e2"], 0.00669342162297, 1e-12, "克拉索夫斯基 e²")
	assert_almost_eq(k["b"], 6356863.0187730473, 1e-6, "克拉索夫斯基 b")
	var i24: Dictionary = EL.params("INTERNATIONAL1924")
	assert_almost_eq(i24["e2"], 0.00672267002223, 1e-12, "Int1924 e²")

func test_derived_formula_identities() -> void:
	var d: Dictionary = EL.derived(6378137.0, 298.257223563)
	var f := 1.0 / 298.257223563
	assert_almost_eq(d["f"], f, 1e-18, "f=1/inv_f")
	assert_almost_eq(d["b"], 6378137.0 * (1.0 - f), 1e-9, "b=a(1-f)")
	assert_almost_eq(d["e2"], 2.0 * f - f * f, 1e-15, "e²=2f-f²")
	assert_almost_eq(d["ep2"], (2.0 * f - f * f) / (1.0 - (2.0 * f - f * f)), 1e-15, "e'²=e²/(1-e²)")

func test_rejections_and_lists() -> void:
	assert_true(EL.params("不存在").is_empty(), "未知椭球名返回空")
	assert_true(EL.derived(0.0, 298.3).is_empty(), "a<=0 返回空")
	assert_true(EL.derived(6378137.0, 0.0).is_empty(), "inv_f<=0 返回空")
	assert_true(EL.derived(6378137.0, NAN).is_empty(), "非有限输入返回空")
	var names: Array = EL.list_builtin()
	assert_true(names.has("CGCS2000"), "内置列表含 CGCS2000")
	assert_true(names.has("WGS84"), "内置列表含 WGS84")
	assert_true(names.has("KRASOVSKY"), "内置列表含克拉索夫斯基")

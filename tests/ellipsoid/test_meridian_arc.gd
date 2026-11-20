# tests/ellipsoid/test_meridian_arc.gd —— M2-1 椭球派生量：子午线弧长/平行圈弧长/曲率半径
#
# 向量来源【权威·pyproj 复核，本会话生成】：
#   X(B)（赤道起子午线弧长，WGS84）取 pyproj.Geod 沿子午线大地线长度：
#     X(13°)=1437710.806494、X(30°)=3320113.397940、X(45°)=4984944.377978、X(60°)=6654072.819491
#   （X(30°) 与 GK-M3 高斯正算向量 x(30°,117°)=3320113.3978 互相印证）
#   平行圈弧长 1° 经差 @40°N = 85393.409130（pyproj.Geod）
#   N(45°)=6388838.290121、M(45°)=6367381.815620（定义式直算复核）
#   R1=(2a+b)/3=6371008.7714（GeographicLib 约定，恒向线向量口径）
#   R2（等面积半径）=6371007.18091847（c2=(a²+b²·atanh(e)/e)/2 开方）
extends "res://tests/test_case_base.gd"

const EL := preload("res://core/ellipsoid/ellipsoid.gd")

const A := 6378137.0
const E2 := 0.0066943799901413165  # WGS84

func test_meridian_arc_vs_pyproj() -> void:
	assert_almost_eq(EL.meridian_arc(A, E2, 13.0), 1437710.806494, 1e-4, "X(13°)")
	assert_almost_eq(EL.meridian_arc(A, E2, 30.0), 3320113.397940, 1e-4, "X(30°)")
	assert_almost_eq(EL.meridian_arc(A, E2, 45.0), 4984944.377978, 1e-4, "X(45°)")
	assert_almost_eq(EL.meridian_arc(A, E2, 60.0), 6654072.819491, 1e-4, "X(60°)")
	assert_almost_eq(EL.meridian_arc(A, E2, 0.0), 0.0, 1e-9, "X(0°)=0")
	assert_almost_eq(EL.meridian_arc(A, E2, -30.0), -3320113.397940, 1e-4, "X(−30°) 反号")

func test_meridian_arc_inverse_roundtrip() -> void:
	for b in [13.0, 30.0, 45.0, 60.0]:
		var x := EL.meridian_arc(A, E2, b)
		var b2 := EL.meridian_arc_inverse(A, E2, x)
		assert_almost_eq(b2, b, 1e-9, "弧长反解恢复 B=%.0f°" % b)

func test_radii_vs_definition() -> void:
	assert_almost_eq(EL.radius_prime_vertical(A, E2, 45.0), 6388838.290121, 1e-4, "N(45°)")
	assert_almost_eq(EL.radius_meridian(A, E2, 45.0), 6367381.815620, 1e-4, "M(45°)")
	# M(B) = N(B)·(1−e²)/(1−e²·sin²B) 恒等式
	var b := 23.5
	var n := EL.radius_prime_vertical(A, E2, b)
	var m := EL.radius_meridian(A, E2, b)
	var sb := sin(deg_to_rad(b))
	assert_almost_eq(m, n * (1.0 - E2) / (1.0 - E2 * sb * sb), 1e-6, "M/N 恒等式")

func test_parallel_arc_vs_definition() -> void:
	# 平行圈弧长定义式 L = N(B)·cosB·ΔL(rad)，本会话 python 定义式独立复核：
	# 1° 经差 @40°N = N(40°)·cos40°·π/180 = 85393.856959（pyproj.Geod.inv 给出的
	# 85393.409130 是两点间大地线长，大地线偏向极侧比平行圈短约 0.45 m，口径不同）
	assert_almost_eq(EL.parallel_arc(A, E2, 40.0, 1.0), 85393.856959, 1e-4, "平行圈 1° 经差 @40°N（定义式）")
	assert_almost_eq(EL.parallel_arc(A, E2, 0.0, 1.0), A * PI / 180.0, 1e-4, "赤道平行圈=大圆")
	assert_almost_eq(EL.parallel_arc(A, E2, 90.0, 1.0), 0.0, 1e-9, "极点平行圈半径为 0")

func test_mean_and_authalic_radius() -> void:
	assert_almost_eq(EL.mean_radius(6378137.0, 6356752.3142451793), 6371008.7714, 1e-4, "R1=(2a+b)/3")
	assert_almost_eq(EL.authalic_radius(A, E2), 6371007.18091847, 1e-4, "R2 等面积半径")
	assert_almost_eq(EL.authalic_radius(1.0, 0.0), 1.0, 1e-12, "球退化 R2=a")

func test_invalid_inputs_return_nan() -> void:
	assert_true(is_nan(EL.meridian_arc(A, E2, 91.0)), "|B|>90 返回 NAN")
	assert_true(is_nan(EL.meridian_arc(0.0, E2, 30.0)), "a<=0 返回 NAN")
	assert_true(is_nan(EL.meridian_arc(A, 1.0, 30.0)), "e2>=1 返回 NAN")
	assert_true(is_nan(EL.meridian_arc(A, NAN, 30.0)), "e2 为 NAN 返回 NAN")
	assert_true(is_nan(EL.meridian_arc_inverse(A, E2, NAN)), "弧长 NaN 返回 NAN")
	assert_true(is_nan(EL.radius_meridian(A, E2, 91.0)), "M 越界返回 NAN")
	assert_true(is_nan(EL.parallel_arc(A, E2, 91.0, 1.0)), "平行圈越界返回 NAN")
	assert_true(is_nan(EL.mean_radius(6378137.0, 0.0)), "b<=0 返回 NAN")
	assert_true(is_nan(EL.authalic_radius(A, 1.0)), "e2>=1 返回 NAN")

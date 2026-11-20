# tests/projection/test_mgrs.gd —— M3-6 MGRS 回归
#
# 向量来源【权威·mgrs 1.7.0（本会话以该库逐条复核）】：
#   - 天安门 (39°54′27.1″N,116°23′28.6″E)→"50SMK4796917671"；
#   - 北海 GN7-2 点 (53°48′33.820″N,2°07′46.380″E)→"31UDV4268262666"；
#   - "18SUJ2285070542"→(39.4662462°,-77.0592989°)；
#   - 挪威/斯瓦尔巴例外：toMGRS(60,5)="32VKM7697958157"、toMGRS(78,15)="33XWG0000058369"；
#   - UPS：toMGRS(85,30)="ZCC7772818959"、toMGRS(-85,30)="BCS7772881040"。
extends "res://tests/test_case_base.gd"

const MG := preload("res://core/projection/mgrs.gd")

func _v(res: Dictionary) -> Dictionary:
	return res.get("value", {}) if res.get("ok", false) else {}

func test_forward_tiananmen_vector() -> void:
	var lat := 39.0 + 54.0 / 60.0 + 27.1 / 3600.0
	var lon := 116.0 + 23.0 / 60.0 + 28.6 / 3600.0
	var r := MG.forward({"lat_deg": lat, "lon_deg": lon, "precision": 5})
	assert_true(bool(r.get("ok", false)), "天安门 MGRS 正算：" + String(r.get("error", "")))
	var v: Dictionary = _v(r)
	assert_eq(String(v["mgrs"]), "50SMK4796917671", "天安门 MGRS")
	assert_int_eq(int(v["zone"]), 50, "带号 50")
	assert_eq(String(v["band"]), "S", "纬度带 S（32-40°N）")

func test_forward_north_sea_vector() -> void:
	# 舍入临界说明（本会话 pip 安装 mgrs 1.7.0 实测）：该权威向量落在 1mm 方格的
	# 舍入临界上，对输入浮点第 16 位敏感——纬度按 DMS 组装
	# 53+48/60+33.82/3600 = 53.80939444444…，toMGRS 得 …2666（与断言一致）；
	# 若改用预先截断的十进制字面量 53.8093888888889，末位翻为 …2665（<1mm 差异）。
	# 因此向量有效口径 = 输入经 DMS 组装（如下），勿改用十进制截断字面量。
	var lat := 53.0 + 48.0 / 60.0 + 33.82 / 3600.0
	var lon := 2.0 + 7.0 / 60.0 + 46.38 / 3600.0
	var r := MG.forward({"lat_deg": lat, "lon_deg": lon, "precision": 5})
	assert_true(bool(r.get("ok", false)), "北海点 MGRS 正算：" + String(r.get("error", "")))
	assert_eq(String(_v(r)["mgrs"]), "31UDV4268262666", "北海点 MGRS")

func test_inverse_vector() -> void:
	var r := MG.inverse({"mgrs": "18SUJ2285070542"})
	assert_true(bool(r.get("ok", false)), "MGRS 反算：" + String(r.get("error", "")))
	var v: Dictionary = _v(r)
	assert_almost_eq(float(v["lat_deg"]), 39.4662462, 2e-6, "18SUJ 反算 B")
	assert_almost_eq(float(v["lon_deg"]), -77.0592989, 2e-6, "18SUJ 反算 L")
	# 天安门串反算（mgrs 库复核 (39.9075313,116.3912783)，与方格 1m 精度一致）
	r = MG.inverse({"mgrs": "50SMK4796917671"})
	v = _v(r)
	assert_true(bool(r.get("ok", false)), "50SMK 反算：" + String(r.get("error", "")))
	assert_almost_eq(float(v["lat_deg"]), 39.9075312805, 2e-6, "50SMK 反算 B")
	assert_almost_eq(float(v["lon_deg"]), 116.3912782605, 2e-6, "50SMK 反算 L")

func test_zone_exceptions() -> void:
	assert_eq(MG.to_mgrs(60.0, 5.0, 5), "32VKM7697958157", "挪威例外 (60,5)→32 带")
	assert_eq(MG.to_mgrs(78.0, 15.0, 5), "33XWG0000058369", "斯瓦尔巴例外 (78,15)→33 带")
	assert_eq(MG.to_mgrs(56.0, 3.0, 5).substr(0, 4), "32VJ", "挪威边界 (56,3)→32V")
	assert_eq(MG.to_mgrs(72.0, 21.0, 5).substr(0, 4), "35XK", "斯瓦尔巴 (72,21)→35X")

func test_ups_mgrs() -> void:
	assert_eq(MG.to_mgrs(85.0, 30.0, 5), "ZCC7772818959", "UPS 北 (85,30)→ZCC…")
	assert_eq(MG.to_mgrs(-85.0, 30.0, 5), "BCS7772881040", "UPS 南 (-85,30)→BCS…")
	# UPS 反算
	var r := MG.inverse({"mgrs": "ZCC7772818959"})
	assert_true(bool(r.get("ok", false)), "UPS MGRS 反算：" + String(r.get("error", "")))
	var v: Dictionary = _v(r)
	assert_almost_eq(float(v["lat_deg"]), 85.0, 1e-5, "UPS 反算 B（1m 方格角点量化）")
	assert_almost_eq(float(v["lon_deg"]), 30.0, 5e-4, "UPS 反算 L（1m 方格角点量化）")
	# λ=0 边界：东半 Z、西半 Y
	assert_eq(String(MG.to_mgrs(85.0, 0.0, 5)[0]), "Z", "λ=0 归东半 Z")
	assert_eq(String(MG.to_mgrs(85.0, -0.0001, 5)[0]), "Y", "λ<0 归西半 Y")

func test_roundtrip_and_precision() -> void:
	# 正反往返（5 位=1m）
	var pts := [[39.9075, 116.3913], [53.8094, 2.1296], [0.0, 117.0], [-33.8678, 151.2073], [78.0, 15.0]]
	for pt: Array in pts:
		var lat := float(pt[0])
		var lon := float(pt[1])
		var s := MG.to_mgrs(lat, lon, 5)
		assert_true(not s.is_empty(), "编码成功 %s" % str(pt))
		var back := MG.from_mgrs(s)
		assert_true(not back.is_empty(), "解码成功 %s" % str(pt))
		if back.is_empty():
			continue
		# 1m 方格：往返差 ≤ 2m（角点口径）
		var dlat := absf(float(back["lat_deg"]) - lat) * 111320.0
		var dlon := absf(float(back["lon_deg"]) - lon) * 111320.0 * cos(lat * PI / 180.0)
		assert_true(dlat <= 2.0 and dlon <= 2.0, "往返 ≤2m %s（d=%.4f, %.4f m）" % [str(pt), dlat, dlon])
	# 精度位数（mgrs 1.7.0 复核）：2 位=1km、4 位=10m
	assert_eq(MG.to_mgrs(39.907527778, 116.391277778, 4), "50SMK47961767", "4 位精度（10m）")
	assert_eq(MG.to_mgrs(39.907527778, 116.391277778, 3), "50SMK479176", "3 位精度（100m）")
	assert_eq(MG.to_mgrs(39.907527778, 116.391277778, 2), "50SMK4717", "2 位精度（1km）")
	assert_eq(MG.to_mgrs(39.907527778, 116.391277778, 1), "50SMK41", "1 位精度（10km）")

func test_invalid_inputs() -> void:
	assert_true(MG.to_mgrs(95.0, 30.0, 5).is_empty(), "B>90 越界")
	assert_false(bool(MG.forward({"lat_deg": "abc", "lon_deg": 100.0}).get("ok", true)), "非法输入失败")
	assert_false(bool(MG.forward({"lat_deg": 39.0, "lon_deg": 116.0, "precision": 8}).get("ok", true)), "精度位数越界失败")
	assert_false(bool(MG.inverse({"mgrs": ""}).get("ok", true)), "空串失败")
	assert_false(bool(MG.inverse({"mgrs": "50SIJ4796917671"}).get("ok", true)), "含 I 的非法方格")
	assert_false(bool(MG.inverse({"mgrs": "50SMK479691767"}).get("ok", true)), "奇数位数字失败")
	assert_false(bool(MG.inverse({"mgrs": "ABC12345"}).get("ok", true)), "无法解析的串失败")

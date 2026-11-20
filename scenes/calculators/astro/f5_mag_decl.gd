# scenes/calculators/astro/f5_mag_decl.gd —— F5 磁偏角（WMM 球谐模型）
#
# 系数 data/wmm.json（WMM2025，NGA 官方发布，公共领域）经 app 装载后传入 core——
# 场景层属 UI/UI 编排，读 data JSON 属 app/data_service 装载职责（core 不读盘纪律不破）。
extends "res://scenes/calculators/astro/astro_calc_base.gd"

const CORE := preload("res://core/astro/magdecl.gd")

func _init() -> void:
	_entry_id = "f5_mag_decl"
	_example_inputs = {
		"year": "2025", "month": "7", "day": "2",
		"lat_deg": "39.9", "lon_deg": "116.4", "alt_km": "0",
	}

func get_title() -> String:
	return "磁偏角（WMM）（F5）"

func get_description() -> String:
	return "世界地磁模型 WMM 球谐合成：输入经纬度/椭球高/日期，输出磁偏角 D（正=东偏）、磁倾角 I、水平强度 H 与总强度 F。真北方位 = 磁北方位 + D。模型有效期随 NGA 发布（WMM2025：2025-2030），超期给中文警告。系数来自 NGA 官方发布（美国政府作品，公共领域）。"

func _build_rows() -> void:
	add_input_row("年", "year", "2025")
	add_input_row("月（1-12）", "month", "7")
	add_input_row("日（1-31）", "day", "2")
	add_input_row("纬度（°，北正）", "lat_deg", "39.9")
	add_input_row("经度（°，东正）", "lon_deg", "116.4")
	add_input_row("椭球高（km）", "alt_km", "0")

func run() -> Dictionary:
	var bad := []
	var year := int(num_field(_fields["year"], "年", bad))
	var month := int(num_field(_fields["month"], "月", bad))
	var day := int(num_field(_fields["day"], "日", bad))
	var lat := num_field(_fields["lat_deg"], "纬度", bad)
	var lon := num_field(_fields["lon_deg"], "经度", bad)
	var alt := num_field(_fields["alt_km"], "椭球高", bad)
	if not bad.is_empty():
		return fail_input(bad)
	var coeffs := GKDataService.load_json("res://data/wmm.json")
	if coeffs.is_empty() or coeffs.has("error"):
		return {"ok": false, "value": {}, "steps": [], "formula": "",
				"error": "WMM 系数数据未就位（data/wmm.json 缺失或损坏）"}
	return CORE.declination({
		"coeffs": coeffs, "year": year, "month": month, "day": day,
		"lat_deg": lat, "lon_deg": lon, "alt_km": alt,
	})

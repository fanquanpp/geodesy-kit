# app/points.gd —— 点库（控制点/碎部点；表 "points"）
# 行结构：{rid, name, code, x_m, y_m, h_m, note, ts}
# 校验口径（ARCHITECTURE.md §1.2）：名称必填，坐标必须为有限数值，失败返回 -1/false。
class_name GKPoints
extends RefCounted

const TABLE := "points"

var _store: GKDataStore

func _init(store: GKDataStore) -> void:
	_store = store

## 新增点，返回 rid（校验失败 -1）。p 支持 {name, code, x_m, y_m, h_m, note}
func add_point(p: Dictionary) -> int:
	var name := String(p.get("name", "")).strip_edges()
	if name.is_empty():
		return -1
	if not _is_num(p.get("x_m")) or not _is_num(p.get("y_m")):
		return -1
	var row := {
		"name": name,
		"code": String(p.get("code", "")),
		"x_m": float(p["x_m"]),
		"y_m": float(p["y_m"]),
		"h_m": float(p["h_m"]) if _is_num(p.get("h_m")) else NAN,
		"note": String(p.get("note", "")),
		"ts": Time.get_unix_time_from_system(),
	}
	# h_m 存 JSON：NAN 非法序列化，转空串表示"未测"
	if is_nan(row["h_m"]):
		row["h_m"] = ""
	return _store.append_row(TABLE, row)

func _is_num(v: Variant) -> bool:
	return (v is float or v is int) and is_finite(float(v))

## 全部点（按添加顺序）
func list_points() -> Array:
	var out := []
	for row: Dictionary in _store.load_table(TABLE):
		var hv: Variant = row.get("h_m", NAN)
		if not (hv is float or hv is int):
			row["h_m"] = NAN  # 空串（未测）或损坏数据统一转 NAN
		out.append(row)
	return out

## 按名称精确/包含查找
func find_by_name(name_part: String, exact := false) -> Array:
	var out := []
	var q := name_part.strip_edges()
	if q.is_empty():
		return out
	for row: Dictionary in list_points():
		var n := String(row.get("name", ""))
		if (exact and n == q) or (not exact and n.contains(q)):
			out.append(row)
	return out

func update_point(rid: int, patch: Dictionary) -> bool:
	var rows := _store.load_table(TABLE)
	for row: Dictionary in rows:
		if int(row.get("rid", 0)) == rid:
			var merged := row.duplicate(true)
			for k: String in ["name", "code", "note", "x_m", "y_m", "h_m"]:
				if patch.has(k) and patch[k] != null:
					merged[k] = patch[k]
			if String(merged.get("name", "")).strip_edges().is_empty():
				return false
			if (not _is_num(merged.get("x_m"))) or (not _is_num(merged.get("y_m"))):
				return false
			return _store.update_row(TABLE, rid, merged)
	return false

func remove_point(rid: int) -> bool:
	return _store.delete_row(TABLE, rid)

# app/favorites.gd —— 计算器收藏（按 manifest 的 entry id 关联；表 "favorites"）
# 行结构：{rid, entry_id, ts}
class_name GKFavorites
extends RefCounted

const TABLE := "favorites"

var _store: GKDataStore

func _init(store: GKDataStore) -> void:
	_store = store

## 切换收藏状态，返回切换后的状态（true=已收藏）
func toggle(entry_id: String) -> bool:
	if is_favorite(entry_id):
		return not _remove_entry(entry_id)
	return _store.append_row(TABLE, {"entry_id": entry_id, "ts": Time.get_unix_time_from_system()}) > 0

func is_favorite(entry_id: String) -> bool:
	for row: Dictionary in _store.load_table(TABLE):
		if String(row.get("entry_id", "")) == entry_id:
			return true
	return false

## 收藏的 entry_id 列表（按收藏时间正序）
func list() -> Array:
	var out := []
	for row: Dictionary in _store.load_table(TABLE):
		var id := String(row.get("entry_id", ""))
		if not id.is_empty() and not out.has(id):
			out.append(id)
	return out

func _remove_entry(entry_id: String) -> bool:
	var rows := _store.load_table(TABLE)
	var kept := []
	var hit := false
	for row: Dictionary in rows:
		if String(row.get("entry_id", "")) == entry_id:
			hit = true
		else:
			kept.append(row)
	if not hit:
		return false
	return _store.save_table(TABLE, kept)

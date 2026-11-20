# app/storage/json_store.gd —— DataStore 的 JSON 后端（降级路径，架构 §6 决策②）
# user://store/<table>.json；写入走 .tmp + 原子改名，损坏时返回空表不抛异常。
class_name GKJsonStore
extends GKDataStore

const STORE_DIR := "user://store"

func backend_name() -> String:
	return "json"

func _table_path(table: String) -> String:
	return "%s/%s.json" % [STORE_DIR, table]

func load_table(table: String) -> Array:
	var path := _table_path(table)
	if not FileAccess.file_exists(path):
		return []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return []
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Array):
		return []
	var out := []
	for row: Variant in parsed:
		if row is Dictionary:
			out.append(row)
	return out

func save_table(table: String, rows: Array) -> bool:
	DirAccess.make_dir_recursive_absolute(STORE_DIR)
	var tmp := _table_path(table) + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(rows, "  "))
	f.close()
	var final := _table_path(table)
	# 覆盖式改名（Windows 上 rename 到已存在路径先删旧文件）
	if FileAccess.file_exists(final):
		DirAccess.remove_absolute(final)
	return DirAccess.rename_absolute(tmp, final) == OK

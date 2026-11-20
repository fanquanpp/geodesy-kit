# app/storage/data_store.gd —— 双后端持久化统一接口（ARCHITECTURE.md §6）
#
# 接口约定：load_table / save_table / query / close + 行级 CRUD
#   - 表语义：一张"表"= Array[Dictionary]（一行一字典），小规模学生数据（≤千行量级）；
#   - 行标识：每行可带整型 "rid" 键，由存储层分配/回填（业务层不自行编造）；
#   - 后端选择 create()：SQLite GDExtension 可用（ClassDB 有 "SQLite"）→ SQLite；
#     否则自动降级 JSON（user://store/*.json），业务代码零改动（架构 §6 决策）；
#   - SQL 安全（Mimosa 硬约束）：所有含外部输入的 SQL 一律参数绑定，见 sqlite_store.gd；
#   - 行级 CRUD 在本基类提供"读-改-写"默认实现（两后端语义一致），
#     SQLite 后端覆写为增量 SQL 版本。
class_name GKDataStore
extends RefCounted

const SQLITE_CLASS := "SQLite"

## 工厂：优先 SQLite，失败/不可用降级 JSON
static func create() -> GKDataStore:
	if ClassDB.class_exists(SQLITE_CLASS):
		var s := GKSQLiteStore.new()
		if s.open_ok():
			return s
	return GKJsonStore.new()

## 后端名（"sqlite"/"json"）
func backend_name() -> String:
	return "none"

## 读整表 → Array[Dictionary]；表不存在返回 []
func load_table(table: String) -> Array:
	return []

## 整表覆写。成功 true
func save_table(table: String, rows: Array) -> bool:
	return false

## 仅 SQLite 后端支持的原生查询（返回 Array[Dictionary]）；JSON 后端返回 []。
## 调用方必须参数绑定，禁止拼接 SQL。
func query(sql: String, params: Array = []) -> Array:
	return []

## 追加一行并返回分配的 rid（失败返回 -1）
func append_row(table: String, row: Dictionary) -> int:
	var rows := load_table(table)
	var rid := 1
	for r: Dictionary in rows:
		rid = maxi(rid, int(r.get("rid", 0)) + 1)
	var copy := row.duplicate(true)
	copy["rid"] = rid
	rows.append(copy)
	if save_table(table, rows):
		return rid
	return -1

## 按 rid 删除（rid<=0 返回 false）
func delete_row(table: String, rid: int) -> bool:
	if rid <= 0:
		return false
	var rows := load_table(table)
	var kept := []
	var hit := false
	for r: Dictionary in rows:
		if int(r.get("rid", 0)) == rid:
			hit = true
		else:
			kept.append(r)
	if not hit:
		return false
	return save_table(table, kept)

## 按 rid 整行替换（保留原 rid；不存在返回 false）
func update_row(table: String, rid: int, row: Dictionary) -> bool:
	if rid <= 0:
		return false
	var rows := load_table(table)
	var out := []
	var hit := false
	for r: Dictionary in rows:
		if int(r.get("rid", 0)) == rid:
			var copy := row.duplicate(true)
			copy["rid"] = rid
			out.append(copy)
			hit = true
		else:
			out.append(r)
	if not hit:
		return false
	return save_table(table, out)

## 关闭后端
func close() -> void:
	pass

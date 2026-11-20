# app/history.gd —— 计算历史（可回看、改参数重算；表 "history"）
# 条目结构：{rid, ts, ts_text, entry_id, title, inputs, result}
# inputs/result 为 §5 协议快照（JSON 可序列化）；上限默认 500 条，先进先出裁剪。
class_name GKHistory
extends RefCounted

const TABLE := "history"
const DEFAULT_MAX := 500

var _store: GKDataStore
var _max: int

func _init(store: GKDataStore, max_items := DEFAULT_MAX) -> void:
	_store = store
	_max = maxi(10, max_items)

## 追加一条历史，返回 rid（失败 -1）
func add(entry_id: String, title: String, inputs: Dictionary, result: Dictionary) -> int:
	var unix := Time.get_unix_time_from_system()
	var datetime := Time.get_datetime_dict_from_unix_time(int(unix))
	var rid: int = _store.append_row(TABLE, {
		"ts": unix,
		"ts_text": "%04d-%02d-%02d %02d:%02d:%02d" % [
			datetime.year, datetime.month, datetime.day,
			datetime.hour, datetime.minute, datetime.second,
		],
		"entry_id": entry_id,
		"title": title,
		"inputs": inputs,
		"result": result,
	})
	_trim()
	return rid

## 最新在前，limit<=0 表示全部
func list(limit := 50) -> Array:
	var rows := _store.load_table(TABLE)
	rows.reverse()
	if limit > 0 and rows.size() > limit:
		rows = rows.slice(0, limit)
	return rows

## 按 entry_id 过滤
func list_by_entry(entry_id: String, limit := 50) -> Array:
	var out := []
	for row: Dictionary in list(0):
		if String(row.get("entry_id", "")) == entry_id:
			out.append(row)
			if limit > 0 and out.size() >= limit:
				break
	return out

func remove(rid: int) -> bool:
	return _store.delete_row(TABLE, rid)

func clear() -> bool:
	return _store.save_table(TABLE, [])

## 超上限先进先出裁剪
func _trim() -> void:
	var rows := _store.load_table(TABLE)
	if rows.size() <= _max:
		return
	rows = rows.slice(rows.size() - _max)
	_store.save_table(TABLE, rows)

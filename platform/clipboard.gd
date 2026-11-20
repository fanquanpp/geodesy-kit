# platform/clipboard.gd —— 剪贴板封装（引擎 I/O 统一收口，ARCHITECTURE.md §1.1）
class_name GKClipboard
extends RefCounted

## 复制文本；headless/无剪贴板环境安全降级返回 false
static func copy_text(text: String) -> bool:
	var ds := DisplayServer.get_name()
	if ds == "headless":
		return false
	DisplayServer.clipboard_set(text)
	return DisplayServer.clipboard_get() == text

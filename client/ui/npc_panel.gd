class_name NpcPanel
extends PanelContainer
## 마을 NPC 대화창: 초상, 대사, 그 NPC 의 퀘스트(수락·완료 보상)와 인연 단계.

signal quest_action(quest_id: String, action: String)
signal closed()

var _v: VBoxContainer
var _title: Label
var _lines: Label
var _quests: VBoxContainer
var _portrait: TextureRect


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(PRESET_CENTER)
	custom_minimum_size = Vector2(520, 0)
	_v = UIKit.vbox(8)
	add_child(_v)
	var h := UIKit.hbox(10)
	_portrait = TextureRect.new()
	_portrait.custom_minimum_size = Vector2(96, 96)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_SCALE
	h.add_child(_portrait)
	var tv := UIKit.vbox(4)
	_title = UIKit.label("", 18, Color(0.98, 0.85, 0.45))
	_lines = UIKit.label("", 14)
	_lines.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lines.custom_minimum_size = Vector2(380, 0)
	tv.add_child(_title)
	tv.add_child(_lines)
	h.add_child(tv)
	_v.add_child(h)
	_quests = UIKit.vbox(4)
	_v.add_child(_quests)
	_v.add_child(UIKit.button("닫기 (Esc)", func() -> void: hide_panel()))


func show_dialog(p: Dictionary) -> void:
	var npc: Dictionary = p.get("npc", {})
	_title.text = "%s — %s · 인연 %d단계" % [npc.get("name_ko", ""), npc.get("role_ko", ""), int(p.get("bond_level", 0))]
	_lines.text = "\n".join(PackedStringArray(p.get("lines", [])))
	_portrait.texture = AssetRegistry.get_texture(String(npc.get("assets", {}).get("portrait", "portrait.guardian")))
	for c: Node in _quests.get_children():
		c.queue_free()
	for q: Dictionary in p.get("quests", []):
		var row := UIKit.hbox(6)
		var kind_ko: String = {"main": "메인", "optional": "선택", "unlock": "해금"}.get(String(q.get("kind", "")), "")
		var st := String(q.get("state", ""))
		var st_ko: String = {"available": "수락 가능", "active": "진행 %d/%d" % [int(q.get("progress", 0)), int(q.get("count", 1))], "complete": "완료 — 보상 수령", "done": "끝"}.get(st, st)
		var lbl := UIKit.label("[%s] %s — %s\n%s" % [kind_ko, q.get("name_ko", ""), st_ko, q.get("desc_ko", "")], 12)
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.custom_minimum_size = Vector2(360, 0)
		row.add_child(lbl)
		var qid := String(q.get("id", ""))
		if st == "available":
			row.add_child(UIKit.button("수락", func() -> void: quest_action.emit(qid, "accept")))
		elif st == "complete":
			var rw: Dictionary = q.get("reward", {})
			row.add_child(UIKit.button("보상 받기 (조각 %d)" % int(rw.get("memory_shards", 0)), func() -> void: quest_action.emit(qid, "claim")))
		_quests.add_child(row)
	visible = true


func hide_panel() -> void:
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		hide_panel()
		get_viewport().set_input_as_handled()

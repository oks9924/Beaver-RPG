class_name HubScreen
extends Control
## 공용 마을 UI: 마을 정보, 접속자, 원정 모집판, 파티 준비 패널, 채팅.

signal create_requested()
signal join_requested(expedition_id: String)
signal leave_requested()
signal ready_toggled(ready: bool)
signal start_requested()
signal logout_requested()
signal chat_sent(text: String)

var info_label: Label
var roster_label: Label
var board_list: VBoxContainer
var party_box: VBoxContainer
var party_members: VBoxContainer
var ready_btn: Button
var start_btn: Button
var chat_log: RichTextLabel
var chat_edit: LineEdit
var _my_ready: bool = false
var _board: Array = []


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	# 좌측: 마을 정보 + 접속자
	var left := UIKit.panel(Vector2(300, 0))
	left.set_anchors_and_offsets_preset(PRESET_TOP_LEFT)
	left.position = Vector2(12, 12)
	var lv := UIKit.vbox(6)
	left.add_child(lv)
	lv.add_child(UIKit.label("버들둑 마을", 20, Color(0.98, 0.85, 0.45)))
	info_label = UIKit.label("", 13)
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_label.custom_minimum_size = Vector2(270, 0)
	lv.add_child(info_label)
	lv.add_child(UIKit.label("접속자", 15, Color(0.8, 0.9, 0.8)))
	roster_label = UIKit.label("", 13)
	lv.add_child(roster_label)
	lv.add_child(UIKit.button("로그아웃", func() -> void: logout_requested.emit()))
	add_child(left)
	# 우측: 원정 모집판 + 파티
	var right := UIKit.panel(Vector2(360, 0))
	right.set_anchors_and_offsets_preset(PRESET_TOP_RIGHT)
	right.position = Vector2(-372, 12)
	var rv := UIKit.vbox(6)
	right.add_child(rv)
	rv.add_child(UIKit.label("원정 모집판", 20, Color(0.98, 0.85, 0.45)))
	rv.add_child(UIKit.label("혼자도 출정 가능 · 파티 최대 4명 · 초대 불필요", 12, Color(0.7, 0.7, 0.65)))
	board_list = UIKit.vbox(4)
	rv.add_child(board_list)
	rv.add_child(UIKit.button("새 원정 만들기 (공개)", func() -> void: create_requested.emit()))
	party_box = UIKit.vbox(6)
	party_box.visible = false
	party_box.add_child(UIKit.label("내 파티", 17, Color(0.8, 0.9, 1.0)))
	party_members = UIKit.vbox(2)
	party_box.add_child(party_members)
	var ph := UIKit.hbox()
	ready_btn = UIKit.button("준비 완료", func() -> void: ready_toggled.emit(not _my_ready))
	start_btn = UIKit.button("출정!", func() -> void: start_requested.emit())
	ph.add_child(ready_btn)
	ph.add_child(start_btn)
	ph.add_child(UIKit.button("파티 나가기", func() -> void: leave_requested.emit()))
	party_box.add_child(ph)
	party_box.add_child(UIKit.label("직업: 수호목수 (단계 1 에서는 1개 직업만 선택 가능)", 12, Color(0.7, 0.7, 0.65)))
	rv.add_child(party_box)
	add_child(right)
	# 하단: 채팅
	var bottom := UIKit.panel(Vector2(420, 150))
	bottom.set_anchors_and_offsets_preset(PRESET_BOTTOM_LEFT)
	bottom.position = Vector2(12, -162)
	var bv := UIKit.vbox(4)
	bottom.add_child(bv)
	chat_log = RichTextLabel.new()
	chat_log.custom_minimum_size = Vector2(390, 90)
	chat_log.scroll_following = true
	bv.add_child(chat_log)
	chat_edit = UIKit.line_edit("마을 채팅 (Enter)")
	chat_edit.text_submitted.connect(func(t: String) -> void:
		if t.strip_edges() != "":
			chat_sent.emit(t)
		chat_edit.text = ""
		chat_edit.release_focus())
	bv.add_child(chat_edit)
	add_child(bottom)
	add_child(UIKit.label("WASD 이동 · 마을은 서버가 저장하며 접속자가 0명이어도 유지됩니다", 12, Color(0.75, 0.75, 0.7)))
	get_child(get_child_count() - 1).set_anchors_and_offsets_preset(PRESET_CENTER_BOTTOM)
	get_child(get_child_count() - 1).position = Vector2(-220, -30)


func show_hub(info: Dictionary, roster: Array, online: int, max_online: int) -> void:
	var st: Dictionary = info.get("structures", {})
	info_label.text = "월드 ID: %s\n서버 가동 횟수: %s · 누적 방문 %s\n누적 원정 %s · 클리어 방 %s · 전멸 %s\n기억나무 %s단계 · 작업실 %s단계" % [
		info.get("world_id", "?"), info.get("boot_count", "?"), info.get("total_visits", "?"), info.get("total_expeditions", "?"),
		info.get("total_rooms_cleared", "?"), info.get("total_wipes", "?"), st.get("memory_tree", {}).get("level", 0), st.get("workshop", {}).get("level", 0)]
	show_roster(roster, online, max_online)


func show_roster(roster: Array, online: int, max_online: int) -> void:
	var names: PackedStringArray = []
	for r: Dictionary in roster:
		names.append(String(r.get("nick", "?")))
	roster_label.text = "마을 %d명 · 서버 접속 %d/%d\n%s" % [roster.size(), online, max_online, ", ".join(names)]


func show_board(list: Array, my_expedition: String) -> void:
	_board = list
	for c: Node in board_list.get_children():
		c.queue_free()
	if list.is_empty():
		board_list.add_child(UIKit.label("모집 중인 원정이 없습니다.", 13, Color(0.7, 0.7, 0.65)))
	for e: Dictionary in list:
		var h := UIKit.hbox()
		var state_txt: String = {Protocol.ExpState.PREPARING: "준비 중", Protocol.ExpState.IN_ROOM: "전투 중", Protocol.ExpState.RESULT: "안전 지점"}.get(int(e.get("state", 0)), "?")
		h.add_child(UIKit.label("%s  %d/%d  %s  방 %d" % [String(e["id"]).left(14), int(e["members"]), int(e["max"]), state_txt, int(e.get("room_index", 0))], 13))
		var b := UIKit.button("참가", func() -> void: join_requested.emit(String(e["id"])))
		b.disabled = not bool(e.get("joinable", false)) or my_expedition != ""
		h.add_child(b)
		board_list.add_child(h)


func show_party(party: Dictionary, my_id: String) -> void:
	party_box.visible = not party.is_empty()
	for c: Node in party_members.get_children():
		c.queue_free()
	if party.is_empty():
		return
	var all_ready := true
	for m: Dictionary in party.get("members", []):
		var ready := bool(m.get("ready", false))
		if m.get("id", "") == my_id:
			_my_ready = ready
		if bool(m.get("connected", true)) and not ready:
			all_ready = false
		party_members.add_child(UIKit.label("%s %s  [%s]  %s" % ["▶" if m.get("id", "") == my_id else "  ", m.get("nick", "?"), ContentDB.get_class_def(String(m.get("class_id", ""))).get("name_ko", "?"), "준비 완료" if ready else ("연결 끊김" if not bool(m.get("connected", true)) else "대기")], 13))
	ready_btn.text = "준비 취소" if _my_ready else "준비 완료"
	start_btn.disabled = not all_ready


func add_chat(from: String, text: String, scope: String) -> void:
	chat_log.append_text("[color=#c9a26b][%s][/color] [b]%s[/b]: %s\n" % ["파티" if scope == "party" else "마을", from, text.xml_escape()])

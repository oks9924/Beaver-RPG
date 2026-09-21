class_name HubScreen
extends Control
## 공용 마을 UI: 마을 정보, 접속자, 원정 모집판, 파티 준비 패널, 채팅.

signal create_requested()
signal tutorial_requested()
signal difficulty_changed(difficulty: String)
signal pacts_changed(pacts: Dictionary)
signal settings_requested()
var difficulty_pick: OptionButton
var _pact_ranks: Dictionary = {}
var _pact_buttons: Dictionary = {}
var heat_label: Label
var _difficulty_ids: Array = []
signal join_requested(expedition_id: String)
signal leave_requested()
signal ready_toggled(ready: bool)
signal start_requested()
signal logout_requested()
signal chat_sent(text: String)
signal upgrade_requested(structure: String)
signal class_changed(class_id: String)
signal trait_requested(class_id: String, trait_id: String)
var class_pick: OptionButton
var _class_ids: Array = []

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
var village_box: VBoxContainer
var mastery_box: VBoxContainer
var codex_label: Label
var records_label: Label
var quest_label: Label
var summary_label: Label
var menu_panel: PanelContainer
var _menu_scroll: ScrollContainer
var _menu_tabs: Dictionary = {}
var _menu_tab_buttons: Dictionary = {}
var _menu_current: String = ""
var _quest_summary: Dictionary = {}
var _bond_text: String = "인연: 아직 없음"
const MENU_TABS := [["village", "내실 · 마을 복구"], ["gear", "장비"], ["mastery", "숙련 · 특성"], ["codex", "도감 · 기록"], ["quest", "퀘스트 · 인연"]]
signal equip_requested(slot: String, uid: String)
signal gear_action(action: String, uid: String, index: int)
var gear_box: VBoxContainer
var _gear_account: Dictionary = {}
var _gear_class: String = "guardian"
var _gear_selected: String = ""


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
	summary_label = UIKit.label("", 12, Color(0.8, 0.78, 0.7))
	summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary_label.custom_minimum_size = Vector2(270, 0)
	lv.add_child(summary_label)
	# 메뉴: 내실·도감·퀘스트 같은 긴 내용은 항상 보이는 패널이 아니라 메뉴 창(Tab)에서 연다.
	lv.add_child(UIKit.label("메뉴 (Tab)", 15, Color(0.8, 0.9, 0.8)))
	var mg := GridContainer.new()
	mg.columns = 2
	mg.add_theme_constant_override("h_separation", 4)
	mg.add_theme_constant_override("v_separation", 4)
	for t: Array in MENU_TABS:
		var tid := String(t[0])
		mg.add_child(UIKit.button(String(t[1]), func() -> void: open_menu(tid)))
	mg.add_child(UIKit.button("설정 (Esc)", func() -> void: settings_requested.emit()))
	mg.add_child(UIKit.button("로그아웃", func() -> void: logout_requested.emit()))
	lv.add_child(mg)
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
	var dh := UIKit.hbox(6)
	dh.add_child(UIKit.label("난이도", 13))
	difficulty_pick = OptionButton.new()
	for did: String in ContentDB.rules.get("difficulties", {}).keys():
		var dd: Dictionary = ContentDB.rules["difficulties"][did]
		_difficulty_ids.append(did)
		difficulty_pick.add_item("%s — %s" % [dd.get("name_ko", did), dd.get("desc_ko", "")])
	difficulty_pick.item_selected.connect(func(i: int) -> void: difficulty_changed.emit(String(_difficulty_ids[i])))
	dh.add_child(difficulty_pick)
	rv.add_child(dh)
	# 서약(열기): Hades 형벌의 서약처럼 모듈을 쌓아 난이도와 보상을 함께 올린다. 단추를 누를 때마다 단계가 오르고, 최대에서 다시 0.
	heat_label = UIKit.label("서약 열기 0 — 기억 조각 보상 +0%", 12, Color(1.0, 0.8, 0.5))
	rv.add_child(heat_label)
	var pact_grid := GridContainer.new()
	pact_grid.columns = 2
	pact_grid.add_theme_constant_override("h_separation", 4)
	pact_grid.add_theme_constant_override("v_separation", 2)
	for pid: String in ContentDB.pact_ids():
		var pdef: Dictionary = ContentDB.pacts[pid]
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 14)
		b.tooltip_text = String(pdef.get("desc_ko", ""))
		b.pressed.connect(func() -> void: _cycle_pact(pid))
		_pact_buttons[pid] = b
		pact_grid.add_child(b)
	rv.add_child(pact_grid)
	_refresh_pacts()
	rv.add_child(UIKit.button("새 원정 만들기 (공개)", func() -> void: create_requested.emit()))
	rv.add_child(UIKit.button("튜토리얼 (혼자 · 5분)", func() -> void: tutorial_requested.emit()))
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
	rv.add_child(party_box)
	var ch := UIKit.hbox()
	ch.add_child(UIKit.label("직업", 13))
	class_pick = OptionButton.new()
	for cid: String in ContentDB.classes.keys():
		if ContentDB.is_class_playable(cid):
			_class_ids.append(cid)
			var cdef: Dictionary = ContentDB.get_class_def(cid)
			class_pick.add_item("%s — %s" % [cdef.get("name_ko", cid), cdef.get("role_ko", "")])
	class_pick.item_selected.connect(func(i: int) -> void: class_changed.emit(String(_class_ids[i])))
	ch.add_child(class_pick)
	rv.add_child(ch)
	rv.add_child(UIKit.label("같은 직업 중복 선택 가능 · 출정 전에 바꿀 수 있습니다", 11, Color(0.7, 0.7, 0.65)))
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
	_build_menu()


## 메뉴 창: 탭(내실 / 숙련 / 도감 / 퀘스트) + 하단 설정·로그아웃·닫기. 가운데 고정 크기, 내용은 스크롤.
func _build_menu() -> void:
	menu_panel = UIKit.panel(Vector2(760, 440))
	menu_panel.visible = false
	menu_panel.set_anchors_and_offsets_preset(PRESET_CENTER)
	menu_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	menu_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	menu_panel.position = Vector2(-380, -230)
	var mv := UIKit.vbox(6)
	menu_panel.add_child(mv)
	var head := UIKit.hbox(6)
	head.add_child(UIKit.label("마을 메뉴", 20, Color(0.98, 0.85, 0.45)))
	for t: Array in MENU_TABS:
		var tid := String(t[0])
		var b := UIKit.button(String(t[1]), func() -> void: _select_tab(tid))
		_menu_tab_buttons[tid] = b
		head.add_child(b)
	mv.add_child(head)
	var body := ScrollContainer.new()
	_menu_scroll = body
	body.custom_minimum_size = Vector2(740, 340)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	mv.add_child(body)
	var pages := VBoxContainer.new()
	pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(pages)
	# 내실 · 마을 복구
	village_box = UIKit.vbox(4)
	var intro_1 := UIKit.label("기억 조각으로 마을 시설을 복구하면 모든 원정에 영구 보너스가 붙습니다.", 12, Color(0.7, 0.7, 0.65))
	intro_1.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro_1.custom_minimum_size = Vector2(700, 0)
	village_box.add_child(intro_1)
	_menu_tabs["village"] = village_box
	pages.add_child(village_box)
	# 장비 (영구): 장착 슬롯 + 창고
	gear_box = UIKit.vbox(4)
	var intro_2 := UIKit.label("장비는 원정에서 드랍되어 마을 창고에 남습니다. 무기는 직업마다 따로 장착하고, 갑옷 1개·장신구 2개는 공용입니다. 등급이 오를수록 부가 속성이 한 줄씩 늘고 전설은 고유 특성을 갖습니다.", 12, Color(0.7, 0.7, 0.65))
	intro_2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro_2.custom_minimum_size = Vector2(700, 0)
	gear_box.add_child(intro_2)
	_menu_tabs["gear"] = gear_box
	pages.add_child(gear_box)
	# 숙련 · 특성
	mastery_box = UIKit.vbox(4)
	var intro_3 := UIKit.label("직업별 숙련 경험치는 원정 완료 시 쌓이며, 특성은 직업마다 하나만 켤 수 있습니다.", 12, Color(0.7, 0.7, 0.65))
	intro_3.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro_3.custom_minimum_size = Vector2(700, 0)
	mastery_box.add_child(intro_3)
	_menu_tabs["mastery"] = mastery_box
	pages.add_child(mastery_box)
	# 도감 · 기록
	var cbox := UIKit.vbox(4)
	codex_label = UIKit.label("", 13, Color(0.9, 0.88, 0.8))
	codex_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	codex_label.custom_minimum_size = Vector2(700, 0)
	cbox.add_child(codex_label)
	records_label = UIKit.label("", 13, Color(0.8, 0.78, 0.7))
	records_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	records_label.custom_minimum_size = Vector2(700, 0)
	cbox.add_child(records_label)
	_menu_tabs["codex"] = cbox
	pages.add_child(cbox)
	# 퀘스트 · 인연
	var qbox := UIKit.vbox(4)
	quest_label = UIKit.label("", 13, Color(0.85, 0.95, 0.8))
	quest_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	quest_label.custom_minimum_size = Vector2(700, 0)
	qbox.add_child(quest_label)
	var intro_4 := UIKit.label("퀘스트 수락·완료는 마을 NPC 에게 다가가 F 키로 대화하세요. 대화할 때마다 목록이 갱신됩니다.", 12, Color(0.7, 0.7, 0.65))
	intro_4.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro_4.custom_minimum_size = Vector2(700, 0)
	qbox.add_child(intro_4)
	_menu_tabs["quest"] = qbox
	pages.add_child(qbox)
	var foot := UIKit.hbox(6)
	foot.add_child(UIKit.button("설정 · 접근성", func() -> void: close_menu(); settings_requested.emit()))
	foot.add_child(UIKit.button("로그아웃", func() -> void: close_menu(); logout_requested.emit()))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(sp)
	foot.add_child(UIKit.button("닫기 (Esc / Tab)", func() -> void: close_menu()))
	mv.add_child(foot)
	add_child(menu_panel)
	_select_tab("village")


func _select_tab(tid: String) -> void:
	_menu_current = tid
	for k: String in _menu_tabs.keys():
		(_menu_tabs[k] as Control).visible = k == tid
		(_menu_tab_buttons[k] as Button).modulate = Color(1.0, 0.9, 0.6) if k == tid else Color(0.8, 0.8, 0.8)


func open_menu(tid: String = "") -> void:
	if tid != "" and _menu_tabs.has(tid):
		_select_tab(tid)
	menu_panel.visible = true
	menu_panel.move_to_front()


func close_menu() -> void:
	menu_panel.visible = false


func menu_open() -> bool:
	return menu_panel != null and menu_panel.visible


func toggle_menu() -> void:
	if menu_open():
		close_menu()
	else:
		open_menu()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey) or not event.pressed or event.is_echo():
		return
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return
	var key := (event as InputEventKey).keycode
	if key == KEY_TAB:
		toggle_menu()
		get_viewport().set_input_as_handled()
	elif key == KEY_ESCAPE and menu_open():
		close_menu()
		get_viewport().set_input_as_handled()


func show_hub(info: Dictionary, roster: Array, online: int, max_online: int) -> void:
	var st: Dictionary = info.get("structures", {})
	info_label.text = "월드 ID: %s\n서버 가동 횟수: %d · 누적 방문 %d\n누적 원정 %d · 클리어 방 %d · 전멸 %d\n기억나무 %d단계 · 작업실 %d단계" % [
		info.get("world_id", "?"), int(info.get("boot_count", 0)), int(info.get("total_visits", 0)), int(info.get("total_expeditions", 0)),
		int(info.get("total_rooms_cleared", 0)), int(info.get("total_wipes", 0)), int(st.get("memory_tree", {}).get("level", 0)), int(st.get("workshop", {}).get("level", 0))]
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
		var state_txt: String = {Protocol.ExpState.PREPARING: "준비 중", Protocol.ExpState.IN_ROOM: "전투 중", Protocol.ExpState.RESULT: "안전 지점"}.get(int(e.get("state", 0)), "안전 지점")
		if bool(e.get("paused", false)):
			state_txt = "중단됨 (이어하기)"
		var dname: String = String(ContentDB.rules.get("difficulties", {}).get(String(e.get("difficulty", "normal")), {}).get("name_ko", e.get("difficulty", "")))
		var heat_txt := ("  열기 %d" % int(e.get("heat", 0))) if int(e.get("heat", 0)) > 0 else ""
		h.add_child(UIKit.label("%s  %d/%d  %s  방 %d  %s%s%s" % [String(e["id"]).left(14), int(e["members"]), int(e["max"]), state_txt, int(e.get("room_index", 0)), dname, heat_txt, ("  " + String(e.get("region", ""))) if String(e.get("region", "")) != "" else ""], 13))
		var b := UIKit.button("이어하기" if bool(e.get("resume", false)) else "참가", func() -> void: join_requested.emit(String(e["id"])))
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


## 마을 시설 단계·복구 버튼, 개인 내실(기억 조각·숙련·도감). 메뉴 창의 각 탭을 채우고, 좌측 패널에는 한 줄 요약만 남긴다.
func show_progression(info: Dictionary, account: Dictionary) -> void:
	_gear_account = account
	_refresh_gear()
	for box: VBoxContainer in [village_box, mastery_box]:
		for i: int in range(box.get_child_count() - 1, 0, -1):
			box.get_child(i).queue_free()
	var prog: Dictionary = account.get("progression", {})
	var shards := int(prog.get("memory_shards", 0))
	var structures: Dictionary = info.get("structures", {})
	var defs: Dictionary = info.get("village", {})
	var bonus: Dictionary = info.get("bonus", {})
	summary_label.text = "기억 조각 %d · 최고 완주 열기 %d\n영구 보너스: 체력 +%d, 회복 +%d, 목재 +%d" % [shards, int(prog.get("best_heat", 0)), int(bonus.get("max_hp_add", 0)), int(bonus.get("heal_uses_add", 0)), int(bonus.get("team_wood_add", 0))]
	village_box.add_child(UIKit.label("기억 조각 %d · 영구 보너스: 최대 체력 +%d, 회복 도구 +%d, 팀 목재 +%d (상한 적용) · 최고 완주 열기 %d" % [shards, int(bonus.get("max_hp_add", 0)), int(bonus.get("heal_uses_add", 0)), int(bonus.get("team_wood_add", 0)), int(prog.get("best_heat", 0))], 13, Color(1.0, 0.9, 0.7)))
	for sid: String in defs.keys():
		var sdef: Dictionary = defs[sid]
		var level := int(structures.get(sid, {}).get("level", 0))
		var next := level + 1
		var ldef: Dictionary = sdef.get("levels", {}).get(str(next), {})
		var h := UIKit.hbox(6)
		var nl := UIKit.label("%s %d/%d단계" % [sdef.get("name_ko", sid), level, int(sdef.get("max_level", 1))], 13)
		nl.custom_minimum_size = Vector2(150, 0)
		h.add_child(nl)
		if ldef.is_empty():
			h.add_child(UIKit.label("완료", 12, Color(0.6, 1.0, 0.6)))
		else:
			var b := UIKit.button("복구 (%d조각): %s" % [int(ldef.get("cost_shards", 0)), ldef.get("desc_ko", "")], func() -> void: upgrade_requested.emit(sid))
			b.disabled = shards < int(ldef.get("cost_shards", 0))
			h.add_child(b)
		village_box.add_child(h)
	var mastery: Dictionary = prog.get("class_mastery", {})
	var chosen: Dictionary = prog.get("mastery_traits", {})
	var parts: PackedStringArray = []
	var table: Array = ContentDB.mastery.get("level_xp", [0])
	if mastery.is_empty():
		mastery_box.add_child(UIKit.label("아직 숙련이 없습니다. 원정을 완주하면 직업 숙련 경험치가 쌓입니다.", 13))
	for cid: String in mastery.keys():
		var xp := int(mastery[cid].get("xp", 0))
		var lv := ContentDB.mastery_level(xp)
		var next_xp: String = str(int(table[lv])) if lv < table.size() else "최대"
		parts.append("%s %d" % [ContentDB.get_class_def(cid).get("name_ko", cid), lv])
		mastery_box.add_child(UIKit.label("%s 숙련 %d/10 (경험치 %d / 다음 %s)" % [ContentDB.get_class_def(cid).get("name_ko", cid), lv, xp, next_xp], 13, Color(1.0, 0.9, 0.7)))
		var th := UIKit.hbox(4)
		th.add_child(UIKit.label("특성:", 12))
		for t: Dictionary in ContentDB.mastery.get("traits", {}).get(cid, []):
			var tid := String(t.get("id", ""))
			var unlocked := lv >= int(t.get("unlock_level", 1))
			var b := UIKit.button(("● " if String(chosen.get(cid, "")) == tid else "○ ") + String(t.get("name_ko", tid)) + ("" if unlocked else " (숙련 %d)" % int(t.get("unlock_level", 1))), func() -> void: trait_requested.emit(cid, "" if String(chosen.get(cid, "")) == tid else tid))
			b.disabled = not unlocked
			b.tooltip_text = String(t.get("desc_ko", ""))
			th.add_child(b)
		mastery_box.add_child(th)
	var codex: Dictionary = prog.get("codex", {})
	var enemies: Dictionary = codex.get("enemies", {})
	var ename: PackedStringArray = []
	for eid: String in enemies.keys():
		ename.append("%s %d" % [ContentDB.get_enemy_def(eid).get("name_ko", eid), int(enemies[eid])])
	var rname: PackedStringArray = []
	for rid: String in codex.get("relics", []):
		rname.append(String(ContentDB.relics.get(rid, {}).get("name_ko", rid)))
	var bname: PackedStringArray = []
	for bid: String in codex.get("bosses", []):
		bname.append(String(ContentDB.bosses.get(bid, {}).get("name_ko", bid)))
	var bonds: Dictionary = prog.get("npc_bonds", {})
	var bond_parts: PackedStringArray = []
	for nid: String in bonds.keys():
		bond_parts.append("%s %d" % [ContentDB.npcs.get(nid, {}).get("name_ko", nid), int(bonds[nid])])
	var recs: Array = prog.get("build_records", [])
	var rec_lines: PackedStringArray = []
	for r0: Dictionary in recs.slice(0, 5):
		rec_lines.append("· %s · 유물 %d · 강화 %d · %s" % [ContentDB.get_class_def(String(r0.get("class_id", ""))).get("name_ko", ""), (r0.get("relics", []) as Array).size(), (r0.get("upgrades", []) as Array).size(), "완주" if int(r0.get("outcome", 0)) == Protocol.Outcome.VICTORY else "미완"])
	var stats: Dictionary = account.get("stats", {})
	codex_label.text = "적 도감 %d종: %s\n유물 %d/%d: %s\n보스 %d: %s" % [
		enemies.size(), ", ".join(ename) if not ename.is_empty() else "없음", rname.size(), ContentDB.relics.size(), ", ".join(rname) if not rname.is_empty() else "없음", bname.size(), ", ".join(bname) if not bname.is_empty() else "없음"]
	records_label.text = "기록: 원정 %d회, 완주 %d, 클리어 방 %d, 전멸 %d · 숙련: %s\n비밀 %d/9 · 결말: %s\n최근 빌드:\n%s" % [
		int(stats.get("expeditions_started", 0)), int(stats.get("runs_completed", 0)), int(stats.get("rooms_cleared", 0)), int(stats.get("wipes", 0)), ", ".join(parts) if not parts.is_empty() else "없음",
		(prog.get("secrets_found", []) as Array).size(), ", ".join(PackedStringArray(prog.get("endings_seen", []))) if not (prog.get("endings_seen", []) as Array).is_empty() else "없음", "\n".join(rec_lines) if not rec_lines.is_empty() else "없음"]
	_bond_text = ("인연: " + ", ".join(bond_parts)) if not bond_parts.is_empty() else "인연: 아직 없음"
	if _quest_summary.is_empty():
		_quest_summary = _local_quest_summary(prog)
	_refresh_quest_tab()


## 서버 QuestEngine.summary 와 같은 모양을 계정 progression 에서 만든다 (NPC 대화 전에도 탭을 채우기 위해).
static func _local_quest_summary(prog: Dictionary) -> Dictionary:
	var active: Array = []
	var complete: Array = []
	var states: Dictionary = prog.get("quests", {})
	for q: Dictionary in ContentDB.quests.get("quests", []):
		var st: Dictionary = states.get(String(q.get("id", "")), {})
		var obj: Dictionary = q.get("objective", {})
		match String(st.get("state", "")):
			"active":
				active.append({"id": q.get("id", ""), "name_ko": q.get("name_ko", ""), "progress": int(st.get("run_progress", 0)) if bool(obj.get("per_run", false)) else int(st.get("progress", 0)), "count": int(obj.get("count", 1)), "giver": q.get("giver", "")})
			"complete":
				complete.append({"id": q.get("id", ""), "name_ko": q.get("name_ko", ""), "giver": q.get("giver", "")})
	return {"active": active, "complete": complete}


func _refresh_quest_tab() -> void:
	var lines: PackedStringArray = [_bond_text, ""]
	var active: Array = _quest_summary.get("active", [])
	var complete: Array = _quest_summary.get("complete", [])
	if active.is_empty() and complete.is_empty():
		lines.append("진행 중인 퀘스트 없음")
	for q: Dictionary in complete:
		lines.append("✔ %s — 보상 수령 가능 (%s에게 F)" % [q.get("name_ko", ""), ContentDB.npcs.get(String(q.get("giver", "")), {}).get("name_ko", "NPC")])
	for q: Dictionary in active:
		lines.append("▷ %s %d/%d" % [q.get("name_ko", ""), int(q.get("progress", 0)), int(q.get("count", 1))])
	quest_label.text = "\n".join(lines)


func set_selected_class(cid: String) -> void:
	var i := _class_ids.find(cid)
	if i >= 0 and class_pick != null:
		class_pick.select(i)
	if cid != _gear_class:
		_gear_class = cid
		_refresh_gear()


## 장비 탭: 현재 직업의 무기 슬롯 + 갑옷 + 장신구 2, 창고(등급 내림차순), 고른 장비의 상세(장착·강화·재감정·분해).
func _refresh_gear() -> void:
	if gear_box == null:
		return
	for i: int in range(gear_box.get_child_count() - 1, 0, -1):
		gear_box.get_child(i).queue_free()
	var prog: Dictionary = _gear_account.get("progression", {})
	var inv: Array = prog.get("inventory", [])
	var eqp: Dictionary = prog.get("equipped", {})
	var wslot: Dictionary = eqp.get("weapon", {}) if eqp.get("weapon", {}) is Dictionary else {}
	var cname := String(ContentDB.get_class_def(_gear_class).get("name_ko", _gear_class))
	gear_box.add_child(UIKit.label("장착 중 (%s 무기 · 갑옷 · 장신구 2) — 창고 %d/%d · 수액 결정 %d" % [cname, inv.size(), int(ContentDB.equipment.get("drop", {}).get("inventory_cap", 60)), Equipment.material_count(prog)], 14, Color(1.0, 0.9, 0.7)))
	var slots := [["weapon:" + _gear_class, "무기", String(wslot.get(_gear_class, ""))], ["armor", "갑옷", String(eqp.get("armor", ""))], ["trinket1", "장신구 1", String(eqp.get("trinket1", ""))], ["trinket2", "장신구 2", String(eqp.get("trinket2", ""))]]
	var equipped_uids: Array = []
	var top := UIKit.hbox(12)
	var slot_col := UIKit.vbox(3)
	for sl: Array in slots:
		var h := UIKit.hbox(6)
		var sname := UIKit.label(String(sl[1]), 13)
		sname.custom_minimum_size = Vector2(60, 0)
		h.add_child(sname)
		var uid := String(sl[2])
		var it := Equipment.find_item(prog, uid)
		if it.is_empty():
			var dw := ""
			if String(sl[0]).begins_with("weapon:"):
				dw = String(ContentDB.equipment.get("weapons", {}).get(Equipment.default_weapon(_gear_class), {}).get("name_ko", "기본"))
			h.add_child(UIKit.label("(비어 있음%s)" % ((" · 기본 " + dw) if dw != "" else ""), 12, Color(0.6, 0.6, 0.55)))
		else:
			equipped_uids.append(uid)
			var b := _item_button(it, true)
			b.pressed.connect(func() -> void: _select_gear(uid))
			h.add_child(b)
		slot_col.add_child(h)
	top.add_child(slot_col)
	top.add_child(_gear_detail(prog, equipped_uids))
	gear_box.add_child(top)
	gear_box.add_child(UIKit.label("창고 (누르면 상세 · 무기는 해당 직업 슬롯에 장착)", 14, Color(1.0, 0.9, 0.7)))
	var sorted := inv.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ra := Equipment.rarity_index(String(a.get("rarity", "")))
		var rb := Equipment.rarity_index(String(b.get("rarity", "")))
		if ra != rb:
			return ra > rb
		return String(a.get("slot", "")) < String(b.get("slot", "")))
	if sorted.is_empty():
		gear_box.add_child(UIKit.label("아직 장비가 없습니다. 방을 클리어하면 25% 확률로, 정예·보스에서는 확정으로 떨어집니다.", 13))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 4)
	for it: Dictionary in sorted:
		var uid := String(it.get("uid", ""))
		var b := _item_button(it, equipped_uids.has(uid))
		if uid == _gear_selected:
			b.modulate = Color(1.15, 1.15, 1.0)
		b.pressed.connect(func() -> void: _select_gear(uid))
		grid.add_child(b)
	gear_box.add_child(grid)
	# 제작 도안: 처음부터 열린 고급 3종 + 보스 처치로 해금되는 희귀·영웅
	gear_box.add_child(UIKit.label("제작 (송진 대장장이의 작업대) — 수액 결정 + 기억 조각 %d" % int(prog.get("memory_shards", 0)), 14, Color(1.0, 0.9, 0.7)))
	var cgrid := GridContainer.new()
	cgrid.columns = 2
	cgrid.add_theme_constant_override("h_separation", 6)
	cgrid.add_theme_constant_override("v_separation", 4)
	var mats := Equipment.material_count(prog)
	for r: Dictionary in Equipment.recipes():
		var rid := String(r.get("id", ""))
		var cost: Dictionary = r.get("cost", {})
		var unlocked := Equipment.recipe_unlocked(prog, r)
		var cb := Button.new()
		cb.text = "%s  (결정 %d · 조각 %d)" % [r.get("name_ko", rid), int(cost.get("sap_crystal", 0)), int(cost.get("memory_shards", 0))]
		cb.alignment = HORIZONTAL_ALIGNMENT_LEFT
		cb.add_theme_font_size_override("font_size", 14)
		cb.add_theme_color_override("font_color", Equipment.rarity_color(String(r.get("rarity", "uncommon"))))
		cb.tooltip_text = String(r.get("desc_ko", "")) + ("" if unlocked else "\n잠김: %s 처치 시 해금" % ContentDB.bosses.get(String(r.get("unlock", {}).get("boss", "")), {}).get("name_ko", "지역 보스"))
		cb.custom_minimum_size = Vector2(340, 0)
		cb.clip_text = true
		cb.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		cb.disabled = not unlocked or mats < int(cost.get("sap_crystal", 0)) or int(prog.get("memory_shards", 0)) < int(cost.get("memory_shards", 0))
		if not unlocked:
			cb.text = "🔒 " + cb.text
		cb.pressed.connect(func() -> void: gear_action.emit("craft", rid, 0))
		cgrid.add_child(cb)
	gear_box.add_child(cgrid)


func _select_gear(uid: String) -> void:
	_gear_selected = "" if _gear_selected == uid else uid
	_refresh_gear()


## 고른 장비 상세: 설명 줄 + 장착/해제 · 강화(비용) · 재감정(줄마다 비용) · 분해(획득량)
func _gear_detail(prog: Dictionary, equipped_uids: Array) -> Control:
	var box := UIKit.vbox(4)
	box.custom_minimum_size = Vector2(360, 0)
	var it := Equipment.find_item(prog, _gear_selected)
	if it.is_empty():
		box.add_child(UIKit.label("장비를 누르면 여기에 상세와 강화·재감정·분해가 나옵니다.\n수액 결정은 장비 분해(등급별 1/2/5/12/30)와 정예(+1)·보스(+3) 처치로 얻습니다.", 12, Color(0.7, 0.7, 0.65)))
		return box
	var uid := String(it.get("uid", ""))
	var rarity := String(it.get("rarity", "common"))
	var title := UIKit.label("[%s] %s" % [Equipment.rarity_name(rarity), it.get("name_ko", Equipment.display_name(it))], 14, Equipment.rarity_color(rarity))
	box.add_child(title)
	var lines := Equipment.describe(it)
	var affix_start := 1 + (1 if not Equipment.base_def(it).get("basic_attack", {}).is_empty() else 0)
	var mats := Equipment.material_count(prog)
	var rcost := Equipment.reforge_cost(it)
	for i in lines.size():
		var h := UIKit.hbox(6)
		var l := UIKit.label(String(lines[i]), 12)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(250, 0)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
		var ai := i - affix_start
		if ai >= 0 and ai < (it.get("affixes", []) as Array).size() and rcost > 0:
			var rb := UIKit.button("재감정 (%d)" % rcost, func() -> void: gear_action.emit("reforge", uid, ai))
			rb.add_theme_font_size_override("font_size", 14)
			rb.disabled = mats < rcost
			rb.tooltip_text = "이 줄을 같은 등급 계층 안에서 다시 굴립니다 (수액 결정 %d)" % rcost
			h.add_child(rb)
		box.add_child(h)
	var actions := UIKit.hbox(6)
	var is_eq := equipped_uids.has(uid)
	var slot := String(it.get("slot", ""))
	if slot == "weapon" and String(it.get("class", "")) != _gear_class:
		actions.add_child(UIKit.label("%s 전용 (직업을 바꾸면 장착)" % ContentDB.get_class_def(String(it.get("class", ""))).get("name_ko", ""), 12, Color(0.7, 0.7, 0.65)))
	elif is_eq:
		var eqp: Dictionary = prog.get("equipped", {})
		actions.add_child(UIKit.button("해제", func() -> void: equip_requested.emit(_slot_of_equipped(eqp, uid), "")))
	else:
		var eqp: Dictionary = prog.get("equipped", {})
		var target := slot
		if slot == "trinket":
			target = "trinket1" if String(eqp.get("trinket1", "")) == "" else "trinket2"
		actions.add_child(UIKit.button("장착", func() -> void: equip_requested.emit(target, uid)))
	var ecost := Equipment.enhance_cost(it)
	var succ := int(round(Equipment.enhance_success_chance(it) * 100.0))
	var destroy := int(round(Equipment.enhance_destroy_chance() * 100.0))
	var eb := UIKit.button("강화 +%d (%d) 성공 %d%% · 파괴 %d%%" % [int(it.get("enhance", 0)) + 1, ecost, succ, destroy] if ecost >= 0 else "강화 최대 (+%d)" % int(ContentDB.equipment.get("enhance", {}).get("max", 5)), func() -> void: gear_action.emit("enhance", uid, 0))
	eb.disabled = ecost < 0 or mats < ecost
	eb.tooltip_text = "기본 속성 ×(1 + 0.1 × 단계). 수액 결정 %d\n성공 %d%% / 실패 %d%% (재료만 소모, 단계 유지) / 파괴 %d%% (장비 소멸)" % [maxi(ecost, 0), succ, maxi(100 - succ - destroy, 0), destroy]
	actions.add_child(eb)
	var sb := UIKit.button("분해 (+%d 결정)" % Equipment.salvage_value(it), func() -> void: gear_action.emit("salvage", uid, 0))
	sb.disabled = is_eq
	sb.tooltip_text = "장비를 없애고 수액 결정을 얻습니다" + (" — 장착 중이라 불가" if is_eq else "")
	actions.add_child(sb)
	box.add_child(actions)
	return box


## 데모/검증용: 창고의 첫 장착 가능 항목을 고른 뒤 장착한다 (EQUIP 왕복 확인)
func demo_equip_first() -> bool:
	var prog: Dictionary = _gear_account.get("progression", {})
	for it: Dictionary in prog.get("inventory", []):
		var slot := String(it.get("slot", ""))
		if slot == "weapon" and String(it.get("class", "")) != _gear_class:
			continue
		if Equipment.is_equipped(prog, String(it.get("uid", ""))):
			continue
		_gear_selected = String(it.get("uid", ""))
		_refresh_gear()
		var target := slot if slot != "trinket" else "trinket1"
		equip_requested.emit(target, _gear_selected)
		return true
	return false


## 데모/검증용: 메뉴 내용을 맨 아래로 스크롤 (제작 섹션 촬영)
func demo_scroll_bottom() -> void:
	if _menu_scroll != null:
		_menu_scroll.scroll_vertical = 100000


## 데모/검증용: 고른 장비를 강화한다
func demo_enhance_selected() -> void:
	if _gear_selected != "":
		gear_action.emit("enhance", _gear_selected, 0)


func _slot_of_equipped(eqp: Dictionary, uid: String) -> String:
	for sk: String in ["armor", "trinket1", "trinket2"]:
		if String(eqp.get(sk, "")) == uid:
			return sk
	var wslot: Dictionary = eqp.get("weapon", {}) if eqp.get("weapon", {}) is Dictionary else {}
	for cid: String in wslot.keys():
		if String(wslot[cid]) == uid:
			return "weapon:" + cid
	return ""


func _item_button(it: Dictionary, equipped: bool) -> Button:
	var rarity := String(it.get("rarity", "common"))
	var slot_ko: String = {"weapon": "무기", "armor": "갑옷", "trinket": "장신구"}.get(String(it.get("slot", "")), "")
	var b := Button.new()
	b.text = "%s[%s] %s  (%s · 지역 %d)" % ["● " if equipped else "", Equipment.rarity_name(rarity), it.get("name_ko", Equipment.display_name(it)), slot_ko, int(it.get("level", 1))]
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 14)
	b.add_theme_color_override("font_color", Equipment.rarity_color(rarity))
	b.tooltip_text = "\n".join(Equipment.describe(it))
	b.custom_minimum_size = Vector2(340, 0)
	b.clip_text = true
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	# 아이콘(icon.gear.<base>)은 v5 팩이 들어오면 자동으로 붙는다 (docs/asset_request_v5.md)
	var icon_id := "icon.gear." + String(it.get("base", ""))
	if AssetRegistry.has(icon_id) and AssetRegistry.status(icon_id) == "final":
		b.icon = AssetRegistry.get_texture(icon_id)
		b.add_theme_constant_override("icon_max_width", 20)
	return b


func show_quests(summary: Dictionary) -> void:
	_quest_summary = summary
	_refresh_quest_tab()
	var parts: PackedStringArray = []
	for q: Dictionary in summary.get("active", []):
		parts.append("%s %d/%d" % [q.get("name_ko", ""), int(q.get("progress", 0)), int(q.get("count", 1))])
	for q: Dictionary in summary.get("complete", []):
		parts.append("%s (보상 수령 가능)" % q.get("name_ko", ""))
	add_chat("퀘스트", ("진행: " + ", ".join(parts)) if not parts.is_empty() else "진행 중인 퀘스트 없음 (NPC 에게 F)", "hub")


func set_selected_difficulty(did: String) -> void:
	var i := _difficulty_ids.find(did)
	if i >= 0 and difficulty_pick != null:
		difficulty_pick.select(i)


func _cycle_pact(pid: String) -> void:
	var maxr := int(ContentDB.pacts.get(pid, {}).get("max_rank", 1))
	_pact_ranks[pid] = (int(_pact_ranks.get(pid, 0)) + 1) % (maxr + 1)
	_refresh_pacts()
	pacts_changed.emit(selected_pacts())


func selected_pacts() -> Dictionary:
	var out := {}
	for pid: String in _pact_ranks.keys():
		if int(_pact_ranks[pid]) > 0:
			out[pid] = int(_pact_ranks[pid])
	return out


func _refresh_pacts() -> void:
	var n := ContentDB.normalize_pacts(selected_pacts())
	var heat := int(n["heat"])
	var pr: Dictionary = ContentDB.pacts.get("_rewards", {})
	heat_label.text = "서약 열기 %d — 기억 조각 보상 +%d%%, 도토리 +%d%%" % [heat, int(heat * float(pr.get("shards_mult_per_heat", 0.15)) * 100), int(heat * float(pr.get("acorn_mult_per_heat", 0.1)) * 100)]
	for pid: String in _pact_buttons.keys():
		var pdef: Dictionary = ContentDB.pacts[pid]
		var rank := int(_pact_ranks.get(pid, 0))
		var maxr := int(pdef.get("max_rank", 1))
		var mark := "●".repeat(rank) + "○".repeat(maxr - rank)
		(_pact_buttons[pid] as Button).text = "%s %s (열기 %d)" % [mark, pdef.get("name_ko", pid), int(pdef.get("heat_per_rank", 1))]
		(_pact_buttons[pid] as Button).modulate = Color(1.0, 0.85, 0.6) if rank > 0 else Color(0.8, 0.8, 0.8)

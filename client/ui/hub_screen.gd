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
var codex_label: Label
var quest_label: Label


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
	lv.add_child(UIKit.label("내실 · 마을 복구", 15, Color(0.8, 0.9, 0.8)))
	village_box = UIKit.vbox(3)
	lv.add_child(village_box)
	codex_label = UIKit.label("", 12, Color(0.8, 0.78, 0.7))
	quest_label = UIKit.label("", 12, Color(0.85, 0.95, 0.8))
	quest_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	codex_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	codex_label.custom_minimum_size = Vector2(270, 0)
	lv.add_child(codex_label)
	lv.add_child(quest_label)
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
		b.add_theme_font_size_override("font_size", 11)
		b.tooltip_text = String(pdef.get("desc_ko", ""))
		b.pressed.connect(func() -> void: _cycle_pact(pid))
		_pact_buttons[pid] = b
		pact_grid.add_child(b)
	rv.add_child(pact_grid)
	_refresh_pacts()
	rv.add_child(UIKit.button("새 원정 만들기 (공개)", func() -> void: create_requested.emit()))
	var th := UIKit.hbox(6)
	th.add_child(UIKit.button("튜토리얼 (혼자 · 5분)", func() -> void: tutorial_requested.emit()))
	th.add_child(UIKit.button("설정 (Esc)", func() -> void: settings_requested.emit()))
	rv.add_child(th)
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


## 마을 시설 단계·복구 버튼, 개인 내실(기억 조각·숙련·도감). 런 보너스와 영구 보너스를 구분해 표시한다.
func show_progression(info: Dictionary, account: Dictionary) -> void:
	for c: Node in village_box.get_children():
		c.queue_free()
	var prog: Dictionary = account.get("progression", {})
	var shards := int(prog.get("memory_shards", 0))
	var structures: Dictionary = info.get("structures", {})
	var defs: Dictionary = info.get("village", {})
	var bonus: Dictionary = info.get("bonus", {})
	village_box.add_child(UIKit.label("기억 조각 %d · 영구 보너스: 최대 체력 +%d, 회복 도구 +%d, 팀 목재 +%d (상한 적용) · 최고 완주 열기 %d" % [shards, int(bonus.get("max_hp_add", 0)), int(bonus.get("heal_uses_add", 0)), int(bonus.get("team_wood_add", 0)), int(prog.get("best_heat", 0))], 12))
	for sid: String in defs.keys():
		var sdef: Dictionary = defs[sid]
		var level := int(structures.get(sid, {}).get("level", 0))
		var next := level + 1
		var ldef: Dictionary = sdef.get("levels", {}).get(str(next), {})
		var h := UIKit.hbox(6)
		h.add_child(UIKit.label("%s %d/%d단계" % [sdef.get("name_ko", sid), level, int(sdef.get("max_level", 1))], 13))
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
	for cid: String in mastery.keys():
		var xp := int(mastery[cid].get("xp", 0))
		var lv := ContentDB.mastery_level(xp)
		var next_xp: String = str(table[lv]) if lv < table.size() else "최대"
		parts.append("%s 숙련 %d/10 (경험치 %d / 다음 %s)" % [ContentDB.get_class_def(cid).get("name_ko", cid), lv, xp, next_xp])
		var th := UIKit.hbox(4)
		th.add_child(UIKit.label("%s 특성:" % ContentDB.get_class_def(cid).get("name_ko", cid), 12))
		for t: Dictionary in ContentDB.mastery.get("traits", {}).get(cid, []):
			var tid := String(t.get("id", ""))
			var unlocked := lv >= int(t.get("unlock_level", 1))
			var b := UIKit.button(("● " if String(chosen.get(cid, "")) == tid else "○ ") + String(t.get("name_ko", tid)) + ("" if unlocked else " (숙련 %d)" % int(t.get("unlock_level", 1))), func() -> void: trait_requested.emit(cid, "" if String(chosen.get(cid, "")) == tid else tid))
			b.disabled = not unlocked
			b.tooltip_text = String(t.get("desc_ko", ""))
			th.add_child(b)
		village_box.add_child(th)
	var codex: Dictionary = prog.get("codex", {})
	var enemies: Dictionary = codex.get("enemies", {})
	var ename: PackedStringArray = []
	for eid: String in enemies.keys():
		ename.append("%s %d" % [ContentDB.get_enemy_def(eid).get("name_ko", eid), int(enemies[eid])])
	var bonds: Dictionary = prog.get("npc_bonds", {})
	var bond_parts: PackedStringArray = []
	for nid: String in bonds.keys():
		bond_parts.append("%s %d" % [ContentDB.npcs.get(nid, {}).get("name_ko", nid), int(bonds[nid])])
	var recs: Array = prog.get("build_records", [])
	var rec_txt := ""
	if not recs.is_empty():
		var r0: Dictionary = recs[0]
		rec_txt = "최근 빌드: %s · 유물 %d · 강화 %d · %s" % [ContentDB.get_class_def(String(r0.get("class_id", ""))).get("name_ko", ""), (r0.get("relics", []) as Array).size(), (r0.get("upgrades", []) as Array).size(), "완주" if int(r0.get("outcome", 0)) == Protocol.Outcome.VICTORY else "미완"]
	quest_label.text = "비밀 %d/9 · 결말 %s · 인연: %s
%s" % [(prog.get("secrets_found", []) as Array).size(), ", ".join(PackedStringArray(prog.get("endings_seen", []))) if not (prog.get("endings_seen", []) as Array).is_empty() else "없음", ", ".join(bond_parts) if not bond_parts.is_empty() else "없음", rec_txt]
	var stats: Dictionary = account.get("stats", {})
	codex_label.text = "%s\n도감: 적 %d종 (%s) · 유물 %d/%d · 보스 %d\n기록: 원정 %d회, 완주 %d, 클리어 방 %d, 전멸 %d" % [
		", ".join(parts) if not parts.is_empty() else "직업 숙련 없음", enemies.size(), ", ".join(ename), (codex.get("relics", []) as Array).size(), ContentDB.relics.size(), (codex.get("bosses", []) as Array).size(),
		int(stats.get("expeditions_started", 0)), int(stats.get("runs_completed", 0)), int(stats.get("rooms_cleared", 0)), int(stats.get("wipes", 0))]


func set_selected_class(cid: String) -> void:
	var i := _class_ids.find(cid)
	if i >= 0 and class_pick != null:
		class_pick.select(i)


func show_quests(summary: Dictionary) -> void:
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

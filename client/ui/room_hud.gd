class_name RoomHud
extends Control
## 전투 HUD: 체력·보호막, 회피 충전, 스킬 쿨다운, 회복 도구, 파티 상태, 웨이브, 다운·구조 안내, 연결 상태.

var hp_bar: ProgressBar
var hp_label: Label
var shield_label: Label
var dodge_label: Label
var resource_label: Label
var build_label: Label
var _icon_class: String = ""
var skill_boxes: Dictionary = {}
var heal_label: Label
var party_label: Label
var wave_label: Label
var hint_label: Label
var conn_label: Label
var room_label: Label
var toast_label: Label
var _toast_t: float = 0.0
var chat_log: RichTextLabel
var chat_edit: LineEdit
var run_label: Label
var objective_label: Label
var relic_label: Label
var boss_bar: ProgressBar
var boss_label: Label
var boss_box: VBoxContainer
var minimap: Minimap
var tutorial_label: Label
var skip_btn: Button
signal chat_sent(text: String)
signal skip_tutorial()


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	var bl := UIKit.panel(Vector2(340, 0))
	bl.set_anchors_and_offsets_preset(PRESET_BOTTOM_LEFT)
	bl.position = Vector2(12, -132)
	var v := UIKit.vbox(4)
	bl.add_child(v)
	var hh := UIKit.hbox()
	hp_bar = ProgressBar.new()
	hp_bar.custom_minimum_size = Vector2(200, 18)
	hp_bar.show_percentage = false
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.08, 0.06)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.3, 0.85, 0.35)
	hp_bar.add_theme_stylebox_override("background", bg)
	hp_bar.add_theme_stylebox_override("fill", fill)
	hp_label = UIKit.label("", 13)
	shield_label = UIKit.label("", 12, Color(0.6, 0.85, 1.0))
	hh.add_child(hp_bar)
	hh.add_child(hp_label)
	hh.add_child(shield_label)
	v.add_child(hh)
	var sh := UIKit.hbox(6)
	for k in ["q", "e", "r"]:
		var box := UIKit.vbox(0)
		var icon := TextureRect.new()
		icon.texture = AssetRegistry.get_texture("icon.skill.guardian." + k)
		icon.custom_minimum_size = Vector2(40, 40)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_SCALE
		var lbl := UIKit.label(k.to_upper(), 12)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(icon)
		box.add_child(lbl)
		sh.add_child(box)
		skill_boxes[k] = {"icon": icon, "label": lbl}
	resource_label = UIKit.label("", 13, Color(1.0, 0.85, 0.5))
	sh.add_child(resource_label)
	build_label = UIKit.label("B 통나무 엄폐 · G 바꾸기", 11, Color(0.75, 0.7, 0.6))
	sh.add_child(build_label)
	dodge_label = UIKit.label("회피 ◆◆", 13, Color(0.6, 0.85, 1.0))
	heal_label = UIKit.label("회복(1) x2", 13, Color(0.6, 1.0, 0.6))
	sh.add_child(dodge_label)
	sh.add_child(heal_label)
	v.add_child(sh)
	add_child(bl)
	var tr := UIKit.panel(Vector2(270, 0))
	tr.set_anchors_and_offsets_preset(PRESET_TOP_RIGHT)
	tr.position = Vector2(-282, 12)
	var pv := UIKit.vbox(4)
	tr.add_child(pv)
	wave_label = UIKit.label("", 15, Color(0.98, 0.85, 0.45))
	pv.add_child(wave_label)
	party_label = UIKit.label("", 13)
	pv.add_child(party_label)
	room_label = UIKit.label("", 11, Color(0.7, 0.7, 0.65))
	room_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	room_label.custom_minimum_size = Vector2(230, 0)
	pv.add_child(room_label)
	objective_label = UIKit.label("", 13, Color(0.6, 1.0, 0.6))
	objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	objective_label.custom_minimum_size = Vector2(230, 0)
	pv.add_child(objective_label)
	run_label = UIKit.label("", 12, Color(0.9, 0.85, 0.7))
	run_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	run_label.custom_minimum_size = Vector2(230, 0)
	pv.add_child(run_label)
	relic_label = UIKit.label("", 11, Color(0.8, 0.75, 0.6))
	relic_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	relic_label.custom_minimum_size = Vector2(230, 0)
	pv.add_child(relic_label)
	add_child(tr)
	conn_label = UIKit.label("", 12, Color(0.9, 0.9, 0.8))
	conn_label.set_anchors_and_offsets_preset(PRESET_TOP_LEFT)
	conn_label.position = Vector2(12, 12)
	add_child(conn_label)
	minimap = Minimap.new()
	minimap.set_anchors_and_offsets_preset(PRESET_TOP_RIGHT)
	minimap.position = Vector2(-500, 12)
	add_child(minimap)
	tutorial_label = UIKit.label("", 16, Color(0.7, 1.0, 0.8))
	tutorial_label.set_anchors_and_offsets_preset(PRESET_CENTER_TOP)
	tutorial_label.position = Vector2(-300, 150)
	tutorial_label.custom_minimum_size = Vector2(600, 0)
	tutorial_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tutorial_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(tutorial_label)
	skip_btn = UIKit.button("튜토리얼 건너뛰기", func() -> void: skip_tutorial.emit())
	skip_btn.set_anchors_and_offsets_preset(PRESET_CENTER_TOP)
	skip_btn.position = Vector2(-80, 200)
	skip_btn.visible = false
	add_child(skip_btn)
	hint_label = UIKit.label("", 16, Color(1.0, 0.8, 0.5))
	hint_label.set_anchors_and_offsets_preset(PRESET_CENTER)
	hint_label.position = Vector2(-200, 120)
	hint_label.custom_minimum_size = Vector2(400, 0)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(hint_label)
	boss_box = UIKit.vbox(2)
	boss_box.set_anchors_and_offsets_preset(PRESET_CENTER_TOP)
	boss_box.position = Vector2(-260, 100)
	boss_box.custom_minimum_size = Vector2(520, 0)
	boss_label = UIKit.label("", 15, Color(1.0, 0.8, 0.6))
	boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_bar = ProgressBar.new()
	boss_bar.custom_minimum_size = Vector2(520, 16)
	boss_bar.show_percentage = false
	var bbg := StyleBoxFlat.new()
	bbg.bg_color = Color(0.1, 0.05, 0.05)
	var bfill := StyleBoxFlat.new()
	bfill.bg_color = Color(0.85, 0.25, 0.2)
	boss_bar.add_theme_stylebox_override("background", bbg)
	boss_bar.add_theme_stylebox_override("fill", bfill)
	boss_box.add_child(boss_label)
	boss_box.add_child(boss_bar)
	boss_box.visible = false
	add_child(boss_box)
	toast_label = UIKit.label("", 26, Color(1.0, 0.95, 0.7))
	toast_label.set_anchors_and_offsets_preset(PRESET_CENTER_TOP)
	toast_label.position = Vector2(-250, 60)
	toast_label.custom_minimum_size = Vector2(500, 0)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(toast_label)
	var cb := UIKit.panel(Vector2(320, 110))
	cb.set_anchors_and_offsets_preset(PRESET_BOTTOM_RIGHT)
	cb.position = Vector2(-332, -122)
	var cv := UIKit.vbox(2)
	cb.add_child(cv)
	chat_log = RichTextLabel.new()
	chat_log.custom_minimum_size = Vector2(290, 60)
	chat_log.scroll_following = true
	cv.add_child(chat_log)
	chat_edit = UIKit.line_edit("파티 채팅 (Enter)")
	chat_edit.text_submitted.connect(func(t: String) -> void:
		if t.strip_edges() != "":
			chat_sent.emit(t)
		chat_edit.text = ""
		chat_edit.release_focus())
	cv.add_child(chat_edit)
	add_child(cb)


func toast(text: String, sec: float = 2.5) -> void:
	toast_label.text = text
	_toast_t = sec


func _process(dt: float) -> void:
	if _toast_t > 0.0:
		_toast_t -= dt
		if _toast_t <= 0.0:
			toast_label.text = ""


func update_me(me: PackedFloat32Array, cdef: Dictionary) -> void:
	var max_hp := float(cdef.get("base_hp", 100))
	hp_bar.max_value = max_hp
	hp_bar.value = me[Protocol.SNAP_P.HP]
	hp_label.text = "%d / %d" % [int(me[Protocol.SNAP_P.HP]), int(max_hp)]
	shield_label.text = ("보호막 %d" % int(me[Protocol.SNAP_P.SHIELD])) if me[Protocol.SNAP_P.SHIELD] > 0.0 else ""
	var charges := int(me[Protocol.SNAP_P.DODGE])
	dodge_label.text = "회피 " + "◆".repeat(charges) + "◇".repeat(maxi(int(ContentDB.rule("dodge_charges", 2)) - charges, 0))
	heal_label.text = "회복(1) x%d" % int(me[Protocol.SNAP_P.HEAL])
	if _icon_class != String(cdef.get("id", "")):
		_icon_class = String(cdef.get("id", ""))
		for k in ["q", "e", "r"]:
			(skill_boxes[k]["icon"] as TextureRect).texture = AssetRegistry.get_texture(String(cdef.get("skills", {}).get(k, {}).get("assets", {}).get("icon", "icon.skill.guardian." + k)))
	var res := float(me[Protocol.SNAP_P.RESOURCE]) if me.size() > Protocol.SNAP_P.RESOURCE else 0.0
	match String(cdef.get("id", "")):
		"sawtooth": resource_label.text = "열의 " + "▮".repeat(int(res)) + "▯".repeat(maxi(5 - int(res), 0))
		"sapshaman": resource_label.text = "씨앗 " + "●".repeat(int(res)) + "○".repeat(maxi(5 - int(res), 0))
		"hydro": resource_label.text = "수압 %d" % int(res)
		_: resource_label.text = ""
	for k in ["q", "e", "r"]:
		var cd := float(me[{"q": Protocol.SNAP_P.CD_Q, "e": Protocol.SNAP_P.CD_E, "r": Protocol.SNAP_P.CD_R}[k]])
		var box: Dictionary = skill_boxes[k]
		(box["icon"] as TextureRect).modulate = Color(0.4, 0.4, 0.4) if cd > 0.0 else Color.WHITE
		(box["label"] as Label).text = ("%.1f" % cd) if cd > 0.0 else "%s (%s)" % [k.to_upper(), cdef.get("skills", {}).get(k, {}).get("name_ko", "")]
	match int(me[Protocol.SNAP_P.STATE]):
		Protocol.EntState.DOWNED:
			hint_label.text = "다운! 아군이 %d초 안에 F 키로 구조해야 합니다" % int(me[Protocol.SNAP_P.DOWN_T])
		Protocol.EntState.DEAD:
			hint_label.text = "사망 — 관전 중. 생존자가 방을 클리어하면 다음 방에서 복귀합니다"
		_:
			if me[Protocol.SNAP_P.RESCUE_T] > 0.0:
				hint_label.text = "구조 중... %.1f / %.1f초" % [me[Protocol.SNAP_P.RESCUE_T], float(ContentDB.rule("rescue_hold_sec", 3.0))]
			else:
				hint_label.text = ""


func update_party(snapshot_players: Array, party: Array, my_id: String) -> void:
	var lines: PackedStringArray = []
	for m: Dictionary in party:
		var st := "?"
		var hp := 0
		for entry: Array in snapshot_players:
			if entry[0] == m.get("id", ""):
				var p: PackedFloat32Array = entry[1]
				hp = int(p[Protocol.SNAP_P.HP])
				st = {Protocol.EntState.ALIVE: "생존", Protocol.EntState.DOWNED: "다운 %ds" % int(p[Protocol.SNAP_P.DOWN_T]), Protocol.EntState.DEAD: "사망"}.get(int(p[Protocol.SNAP_P.STATE]), "?")
				if p[Protocol.SNAP_P.CONNECTED] < 0.5:
					st = "연결 끊김"
		lines.append("%s %s  HP %d  %s" % ["▶" if m.get("id", "") == my_id else "  ", m.get("nick", "?"), hp, st])
	party_label.text = "\n".join(lines)


func update_wave(wave: Array, enemies_alive: int) -> void:
	wave_label.text = "웨이브 %d / %d   적 %d" % [int(wave[0]), int(wave[1]), enemies_alive]


func update_room(room: Dictionary) -> void:
	room_label.text = "%s · 방 %d · 기준 인원 %d · 시드 %d" % [room.get("room_def", {}).get("name_ko", room.get("room_id", "?")), int(room.get("room_index", 0)), int(room.get("n", 0)), int(room.get("seed", 0))]


func update_run(run: Dictionary, my_id: String) -> void:
	if run.is_empty():
		run_label.text = ""
		relic_label.text = ""
		return
	var mine: Dictionary = run.get("players", {}).get(my_id, {})
	var table: Array = run.get("xp_table", [])
	var lvl := int(run.get("level", 1))
	var next_xp: String = str(table[lvl]) if lvl < table.size() else "최대"
	run_label.text = "런 레벨 %d (경험치 %d/%s) · 팀 목재 %d · 도토리 %d · 노드 %d/%d" % [lvl, int(run.get("xp", 0)), next_xp, int(run.get("team_wood", 0)), int(mine.get("acorns", 0)), (run.get("path", []) as Array).size(), (run.get("layers", []) as Array).size()]
	var names: PackedStringArray = []
	for rid: String in mine.get("relics", []):
		names.append(String(ContentDB.relics.get(rid, {}).get("name_ko", rid)))
	for uid: String in mine.get("upgrades", []):
		for cls: String in ContentDB.upgrades.keys():
			if ContentDB.upgrades[cls].has(uid):
				names.append("★" + String(ContentDB.upgrades[cls][uid].get("name_ko", uid)))
	relic_label.text = ("유물·강화: " + ", ".join(names)) if not names.is_empty() else ""


func update_objective(obj: Array, wood: int, boss_state: Dictionary) -> void:
	if obj.size() < 3:
		objective_label.text = ""
		return
	var kind := String(obj[0])
	var prog := float(obj[1])
	var done := int(obj[2]) == 1
	match kind:
		"hold_point": objective_label.text = "목표: 거점 유지 %d%%%s" % [int(prog * 100), " · 완료" if done else ""]
		"device": objective_label.text = "목표: 장치 가동 %d%%%s" % [int(prog * 100), " · 완료" if done else ""]
		"escort": objective_label.text = "목표: 뗏목 호위 %d%%%s" % [int(prog * 100), " · 완료" if done else ""]
		"boss": objective_label.text = "보스 체력 %d%%" % int(prog * 100)
		_: objective_label.text = "목표: 섬멸 (처치 %d%%)" % int(prog * 100)
	objective_label.text += "   팀 목재 %d (B: 엄폐 %d)" % [wood, int(ContentDB.rule("build_cost_wood", 3))]
	boss_box.visible = not boss_state.is_empty()
	if not boss_state.is_empty():
		boss_bar.max_value = float(boss_state.get("max_hp", 1))
		boss_bar.value = float(boss_state.get("hp", 0))
		var tags: PackedStringArray = []
		tags.append("갑각 %d/%d 파괴" % [int(boss_state.get("shell_broken", 0)), int(boss_state.get("shell_total", 3))])
		if bool(boss_state.get("claw_weak", false)): tags.append("집게 약화")
		if bool(boss_state.get("joint_weak", false)): tags.append("관절 약화")
		if bool(boss_state.get("exposed", false)): tags.append("노출")
		if bool(boss_state.get("molting", false)): tags.append("탈피 중")
		boss_label.text = "%s  %d / %d  ·  단계 %d  ·  %s" % [boss_state.get("name", ""), int(boss_state.get("hp", 0)), int(boss_state.get("max_hp", 0)), int(boss_state.get("phase", 0)) + 1, " · ".join(tags)]
		var hint := String(boss_state.get("hint_ko", ""))
		if hint != "":
			objective_label.text += "\n" + hint


func update_conn(state: int, ping: int) -> void:
	var names := ["연결 끊김", "연결 중", "인증 중", "동기화 중", "온라인"]
	conn_label.text = "%s · %dms" % [names[clampi(state, 0, 4)], ping]


func add_chat(from: String, text: String) -> void:
	chat_log.append_text("[b]%s[/b]: %s\n" % [from, text.xml_escape()])


func set_build_hint(kind: String) -> void:
	var bk: Dictionary = ContentDB.rules.get("build_kinds", {}).get(kind, {})
	build_label.text = "B %s(%d) · G 바꾸기" % [bk.get("name_ko", kind), int(bk.get("cost_wood", 3))]


func set_tutorial(text: String, index: int, total: int) -> void:
	tutorial_label.text = ("튜토리얼 %d/%d — %s" % [index + 1, total, text]) if text != "" else ""
	skip_btn.visible = text != ""

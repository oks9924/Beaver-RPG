class_name RoomHud
extends Control
## 전투 HUD: 체력·보호막, 회피 충전, 스킬 쿨다운, 회복 도구, 파티 상태, 웨이브, 다운·구조 안내, 연결 상태.

var hp_bar: TextureBar
var status_box: HBoxContainer
var _status_icons: Dictionary = {}
var hp_label: Label
var shield_label: Label
var dodge_label: Label
var resource_label: Label
var build_label: Label
var _icon_class: String = ""
var skill_boxes: Dictionary = {}
var heal_label: Label
var party_label: Label
var party_portraits: PartyPortraits
var party_max_hp: Dictionary = {}   # account_id -> 최대 체력 (초상 체력 바용)
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
var boss_bar: TextureBar
var boss_label: Label
var boss_box: VBoxContainer
var minimap: Minimap
var dungeon_map: DungeonMap
var tutorial_label: Label
var skip_btn: Button
var detail_panel: PanelContainer
var extra_label: Label
var boss_hint: Label
var bag_label: Label
var _chat_panel: PanelContainer
const CHAT_H_SMALL := 44
const CHAT_H_BIG := 130
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
	hp_bar = TextureBar.new()
	hp_bar.setup("ui.bar.hp", Color(0.3, 0.85, 0.35), 220.0)
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
	build_label = UIKit.label("B 엄폐(3) · G", 11, Color(0.75, 0.7, 0.6))
	sh.add_child(build_label)
	dodge_label = UIKit.label("회피 ◆◆", 13, Color(0.6, 0.85, 1.0))
	heal_label = UIKit.label("회복(1) x2", 13, Color(0.6, 1.0, 0.6))
	sh.add_child(_small_icon("icon.dodge"))
	sh.add_child(dodge_label)
	sh.add_child(_small_icon("icon.heal"))
	sh.add_child(heal_label)
	bag_label = UIKit.label("가방 0/60 (I)", 12, Color(0.85, 0.8, 0.7))
	sh.add_child(bag_label)
	status_box = UIKit.hbox(4)
	for sid in ["slow", "bleed", "shield"]:
		var ic := _small_icon("icon.status." + sid)
		ic.visible = false
		_status_icons[sid] = ic
		status_box.add_child(ic)
	sh.add_child(status_box)
	v.add_child(sh)
	add_child(bl)
	# 우측 끝: 파티 초상 세로 카드 (체력 바 위, 초상, 이름)
	party_portraits = PartyPortraits.new()
	party_portraits.set_anchors_and_offsets_preset(PRESET_TOP_RIGHT)
	party_portraits.position = Vector2(-100, 12)
	add_child(party_portraits)
	# 상단 중앙 한 줄: 웨이브·적 수·목표, 둘째 줄에 런 정보. 자세한 내용(방 이름·시드·유물)은 Tab 상세 패널로
	var top := UIKit.panel(Vector2(560, 0))
	top.set_anchors_and_offsets_preset(PRESET_CENTER_TOP)
	top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	top.position = Vector2(-280, 8)
	var pv := UIKit.vbox(0)
	top.add_child(pv)
	var l1 := UIKit.hbox(12)
	l1.alignment = BoxContainer.ALIGNMENT_CENTER
	wave_label = UIKit.label("", 15, Color(0.98, 0.85, 0.45))
	l1.add_child(wave_label)
	objective_label = UIKit.label("", 14, Color(0.6, 1.0, 0.6))
	l1.add_child(objective_label)
	pv.add_child(l1)
	run_label = UIKit.label("", 12, Color(0.85, 0.82, 0.72))
	run_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pv.add_child(run_label)
	add_child(top)
	party_label = UIKit.label("", 13)
	party_label.visible = false
	# Tab 상세 패널 (큰 지도와 함께 열림): 방 이름·시드·유물·서약 등
	detail_panel = UIKit.panel(Vector2(300, 0))
	detail_panel.set_anchors_and_offsets_preset(PRESET_TOP_RIGHT)
	detail_panel.position = Vector2(-416, 12)
	detail_panel.visible = false
	var dv := UIKit.vbox(4)
	detail_panel.add_child(dv)
	room_label = UIKit.label("", 12, Color(0.8, 0.8, 0.75))
	room_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	room_label.custom_minimum_size = Vector2(270, 0)
	dv.add_child(room_label)
	extra_label = UIKit.label("", 12, Color(0.9, 0.85, 0.7))
	extra_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	extra_label.custom_minimum_size = Vector2(270, 0)
	dv.add_child(extra_label)
	relic_label = UIKit.label("", 12, Color(0.8, 0.75, 0.6))
	relic_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	relic_label.custom_minimum_size = Vector2(270, 0)
	dv.add_child(relic_label)
	add_child(detail_panel)
	conn_label = UIKit.label("", 12, Color(0.9, 0.9, 0.8))
	conn_label.set_anchors_and_offsets_preset(PRESET_TOP_LEFT)
	conn_label.position = Vector2(12, 12)
	add_child(conn_label)
	# 던전 격자 지도: 화면 좌측 상단 구석 (접속 상태 줄 아래). 팀원 지도(미니맵)는 같은 폭으로 그 아래에 붙는다 (_process 가 위치 갱신)
	dungeon_map = DungeonMap.new()
	dungeon_map.set_anchors_and_offsets_preset(PRESET_TOP_LEFT)
	dungeon_map.position = Vector2(16, 40)
	add_child(dungeon_map)
	minimap = Minimap.new()
	minimap.set_anchors_and_offsets_preset(PRESET_TOP_LEFT)
	minimap.position = Vector2(16, 160)
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
	boss_bar = TextureBar.new()
	boss_bar.setup("ui.bar.boss", Color(0.85, 0.25, 0.2), 520.0)
	boss_box.add_child(boss_label)
	boss_box.add_child(boss_bar)
	boss_hint = UIKit.label("", 14, Color(1.0, 0.9, 0.6))
	boss_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_box.add_child(boss_hint)
	boss_box.visible = false
	add_child(boss_box)
	toast_label = UIKit.label("", 26, Color(1.0, 0.95, 0.7))
	toast_label.set_anchors_and_offsets_preset(PRESET_CENTER_TOP)
	toast_label.position = Vector2(-250, 60)
	toast_label.custom_minimum_size = Vector2(500, 0)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(toast_label)
	# 하단 우측 채팅: 평소 2줄 반투명, Enter 로 입력창을 잡으면 커진다
	_chat_panel = UIKit.panel(Vector2(320, 0))
	_chat_panel.set_anchors_and_offsets_preset(PRESET_BOTTOM_RIGHT)
	_chat_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_chat_panel.position = Vector2(-332, -12)
	var cv := UIKit.vbox(2)
	_chat_panel.add_child(cv)
	chat_log = RichTextLabel.new()
	chat_log.custom_minimum_size = Vector2(290, CHAT_H_SMALL)
	chat_log.scroll_following = true
	cv.add_child(chat_log)
	chat_edit = UIKit.line_edit("파티 채팅 (Enter)")
	chat_edit.text_submitted.connect(func(t: String) -> void:
		if t.strip_edges() != "":
			chat_sent.emit(t)
		chat_edit.text = ""
		chat_edit.release_focus())
	chat_edit.focus_entered.connect(func() -> void: _set_chat_expanded(true))
	chat_edit.focus_exited.connect(func() -> void: _set_chat_expanded(false))
	cv.add_child(chat_edit)
	add_child(_chat_panel)
	_set_chat_expanded(false)


func _set_chat_expanded(on: bool) -> void:
	chat_log.custom_minimum_size = Vector2(290, CHAT_H_BIG if on else CHAT_H_SMALL)
	_chat_panel.modulate = Color(1, 1, 1, 1.0 if on else 0.8)
	_chat_panel.reset_size()


## Tab(큰 지도)과 함께 상세 패널(방 이름·시드·유물)을 보인다
func set_details(on: bool) -> void:
	detail_panel.visible = on


func set_bag(count: int, cap: int) -> void:
	bag_label.text = "가방 %d/%d (I)" % [count, cap]
	bag_label.modulate = Color(1.0, 0.6, 0.5) if count >= cap else Color.WHITE


func toast(text: String, sec: float = 2.5) -> void:
	toast_label.text = text
	_toast_t = sec


func _process(dt: float) -> void:
	if dungeon_map != null and minimap != null:
		var sz := dungeon_map.size_px()
		minimap.map_width = maxf(sz.x, 120.0) if not dungeon_map.dungeon.is_empty() else (200.0 if minimap.big else 148.0)
		minimap.position = dungeon_map.position + Vector2(0, (sz.y if not dungeon_map.dungeon.is_empty() else 0.0) + 10.0)
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
	var bits := int(me[Protocol.SNAP_P.STATUS]) if me.size() > Protocol.SNAP_P.STATUS else 0
	(_status_icons["slow"] as Control).visible = (bits & Protocol.ST_SLOW) != 0 or (bits & Protocol.ST_ROOT) != 0
	(_status_icons["bleed"] as Control).visible = (bits & Protocol.ST_BLEED) != 0
	(_status_icons["shield"] as Control).visible = me[Protocol.SNAP_P.SHIELD] > 0.0
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
	if party_portraits != null:
		party_portraits.update(snapshot_players, party, my_id, party_max_hp)
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
	wave_label.text = "웨이브 %d/%d · 적 %d" % [int(wave[0]), int(wave[1]), enemies_alive]


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
	var g: Dictionary = run.get("dungeon", {})
	run_label.text = "Lv %d · 목재 %d · 도토리 %d · 지역 %d/%d 방 %d/%d · 위험 ×%.2f" % [lvl, int(run.get("team_wood", 0)), int(mine.get("acorns", 0)), int(run.get("region_index", 0)) + 1, int(run.get("regions_total", 1)), int(g.get("rooms_cleared", 0)), int(g.get("rooms_total", 0)), float(run.get("danger", 1.0))]
	if int(run.get("heat", 0)) > 0:
		run_label.text += " · 열기 %d" % int(run.get("heat", 0))
	if int(run.get("curse_rooms", 0)) > 0:
		run_label.text += " · 저주 %d방" % int(run.get("curse_rooms", 0))
	var extra: PackedStringArray = ["경험치 %d/%s" % [int(run.get("xp", 0)), next_xp]]
	if int(run.get("bonus_shards", 0)) > 0:
		extra.append("약속된 기억 조각 +%d" % int(run.get("bonus_shards", 0)))
	if int(run.get("curse_rooms", 0)) > 0:
		extra.append("저주: 받는 피해 증가 (%d방 남음)" % int(run.get("curse_rooms", 0)))
	extra_label.text = " · ".join(extra)
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
		"hold_point": objective_label.text = "거점 유지 %d%%%s" % [int(prog * 100), " ✓" if done else ""]
		"device": objective_label.text = "장치 가동 %d%%%s" % [int(prog * 100), " ✓" if done else ""]
		"escort": objective_label.text = "뗏목 호위 %d%%%s" % [int(prog * 100), " ✓" if done else ""]
		"boss": objective_label.text = "보스 %d%%" % int(prog * 100)
		"explore": objective_label.text = "탐색 · 문 앞에 모이면 이동"
		_: objective_label.text = "섬멸 %d%%" % int(prog * 100)
	build_label.text = build_label.text.get_slice(" · 목재", 0) + " · 목재 %d" % wood
	boss_box.visible = not boss_state.is_empty()
	if not boss_state.is_empty():
		boss_bar.max_value = float(boss_state.get("max_hp", 1))
		boss_bar.value = float(boss_state.get("hp", 0))
		var tags: PackedStringArray = []
		var bdef: Dictionary = ContentDB.bosses.get(String(boss_state.get("id", "")), {})
		var bf := int(boss_state.get("f", 0))
		if int(boss_state.get("shell_total", 0)) > 0:
			tags.append("갑각 %d/%d 파괴" % [int(boss_state.get("shell_broken", 0)), int(boss_state.get("shell_total", 3))])
		if bf & 1: tags.append("집게 약화")
		if bf & 2: tags.append("관절 약화")
		if bf & 4: tags.append("노출")
		if bf & 16: tags.append("격노")
		if bf & 32: tags.append("취약")
		var mid := String(boss_state.get("m", ""))
		var hint_built := ""
		if mid != "":
			var md: Dictionary = bdef.get("mechanics", {}).get(mid, {})
			hint_built = "%s (%s) — %s · 남은 %ds" % [md.get("name_ko", mid), mid, md.get("telegraph_ko", ""), int(float(boss_state.get("mt", 0.0)))]
		elif int(boss_state.get("state", 0)) == BossIronclaw.BS.STAGGER:
			hint_built = "경직! 집중 공격"
		if int(boss_state.get("f", 0)) & 8: tags.append("탈피 중")
		boss_label.text = "%s  %d / %d  ·  단계 %d  ·  %s" % [bdef.get("name_ko", ""), int(boss_state.get("hp", 0)), int(boss_state.get("max_hp", 0)), int(boss_state.get("phase", 0)) + 1, " · ".join(tags)]
		boss_hint.text = hint_built


func update_conn(state: int, ping: int) -> void:
	var names := ["연결 끊김", "연결 중", "인증 중", "동기화 중", "온라인"]
	conn_label.text = "%s · %dms" % [names[clampi(state, 0, 4)], ping]


func add_chat(from: String, text: String) -> void:
	chat_log.append_text("[b]%s[/b]: %s\n" % [from, text.xml_escape()])


func set_build_hint(kind: String) -> void:
	var bk: Dictionary = ContentDB.rules.get("build_kinds", {}).get(kind, {})
	build_label.text = "B %s(%d) · G" % [bk.get("name_ko", kind), int(bk.get("cost_wood", 3))]


func set_tutorial(text: String, index: int, total: int) -> void:
	tutorial_label.text = ("튜토리얼 %d/%d — %s" % [index + 1, total, text]) if text != "" else ""
	skip_btn.visible = text != ""


func _small_icon(id: String) -> TextureRect:
	var t := TextureRect.new()
	t.texture = AssetRegistry.get_texture(id)
	t.custom_minimum_size = Vector2(20, 20)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	return t

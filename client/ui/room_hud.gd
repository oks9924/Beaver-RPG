class_name RoomHud
extends Control
## 전투 HUD: 체력·보호막, 회피 충전, 스킬 쿨다운, 회복 도구, 파티 상태, 웨이브, 다운·구조 안내, 연결 상태.

var hp_bar: ProgressBar
var hp_label: Label
var shield_label: Label
var dodge_label: Label
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
signal chat_sent(text: String)


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
	dodge_label = UIKit.label("회피 ◆◆", 13, Color(0.6, 0.85, 1.0))
	heal_label = UIKit.label("회복(1) x2", 13, Color(0.6, 1.0, 0.6))
	sh.add_child(dodge_label)
	sh.add_child(heal_label)
	v.add_child(sh)
	add_child(bl)
	var tr := UIKit.panel(Vector2(260, 0))
	tr.set_anchors_and_offsets_preset(PRESET_TOP_RIGHT)
	tr.position = Vector2(-272, 12)
	var pv := UIKit.vbox(4)
	tr.add_child(pv)
	wave_label = UIKit.label("", 15, Color(0.98, 0.85, 0.45))
	pv.add_child(wave_label)
	party_label = UIKit.label("", 13)
	pv.add_child(party_label)
	room_label = UIKit.label("", 11, Color(0.7, 0.7, 0.65))
	pv.add_child(room_label)
	add_child(tr)
	conn_label = UIKit.label("", 12, Color(0.9, 0.9, 0.8))
	conn_label.set_anchors_and_offsets_preset(PRESET_TOP_LEFT)
	conn_label.position = Vector2(12, 12)
	add_child(conn_label)
	hint_label = UIKit.label("", 16, Color(1.0, 0.8, 0.5))
	hint_label.set_anchors_and_offsets_preset(PRESET_CENTER)
	hint_label.position = Vector2(-200, 120)
	hint_label.custom_minimum_size = Vector2(400, 0)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(hint_label)
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


func update_conn(state: int, ping: int) -> void:
	var names := ["연결 끊김", "연결 중", "인증 중", "동기화 중", "온라인"]
	conn_label.text = "%s · %dms" % [names[clampi(state, 0, 4)], ping]


func add_chat(from: String, text: String) -> void:
	chat_log.append_text("[b]%s[/b]: %s\n" % [from, text.xml_escape()])

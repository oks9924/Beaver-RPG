class_name ResultPanel
extends Control
## 방 결과: 승리/전멸 구분, 피해량뿐 아니라 구조·피해 방지·다운을 함께 표시하고 서열화하지 않는다.

signal choice_made(choice: String)

var title: Label
var body: Label
var choice_label: Label
var restart_btn: Button
var hub_btn: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	var panel := UIKit.panel(Vector2(560, 0))
	var v := UIKit.vbox(8)
	panel.add_child(v)
	title = UIKit.label("", 26, Color(0.98, 0.85, 0.45))
	v.add_child(title)
	body = UIKit.label("", 14)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(520, 0)
	v.add_child(body)
	choice_label = UIKit.label("", 13, Color(0.8, 0.9, 1.0))
	v.add_child(choice_label)
	var h := UIKit.hbox()
	restart_btn = UIKit.button("새 원정 (새 시드)", func() -> void: choice_made.emit("restart"))
	hub_btn = UIKit.button("마을로 돌아가기", func() -> void: choice_made.emit("hub"))
	h.add_child(restart_btn)
	h.add_child(hub_btn)
	v.add_child(h)
	v.add_child(UIKit.label("연결된 파티원 전원이 같은 선택을 하면 진행됩니다. 원정 밖 기록(기억 조각·숙련)은 결과와 함께 저장되었습니다.", 12, Color(0.7, 0.7, 0.65)))
	add_child(UIKit.center(panel))


func show_result(r: Dictionary, party: Array, my_id: String) -> void:
	var outcome := int(r.get("run_outcome", r.get("outcome", 0)))
	title.text = {Protocol.Outcome.VICTORY: "원정 완주!", Protocol.Outcome.WIPE: "전멸... 기억나무가 원정대를 마을로 되돌립니다", Protocol.Outcome.ABORTED: "중단", Protocol.Outcome.SERVER_ERROR: "서버 오류로 복구된 원정"}.get(outcome, "결과")
	var rs: Dictionary = r.get("run_stats", {})
	if not rs.is_empty():
		title.text += "  (클리어 방 %d · 처치 %d · 전투 %s)" % [int(rs.get("rooms_cleared", 0)), int(rs.get("enemies_killed", 0)), UIKit.fmt_time(float(rs.get("combat_sec", 0)))]
	var lines: PackedStringArray = []
	lines.append("소요 %s · 기준 인원 %d · 시드 %d · 처치 %d · 다운 %d · 구조 %d" % [UIKit.fmt_time(float(r.get("elapsed", 0))), int(r.get("n", 0)), int(r.get("seed", 0)), int(r.get("stats", {}).get("enemies_killed", 0)), int(r.get("stats", {}).get("downs", 0)), int(r.get("stats", {}).get("rescues", 0))])
	var players: Dictionary = r.get("players", {})
	var rewards: Dictionary = r.get("rewards", {})
	for m: Dictionary in party:
		var id := String(m.get("id", ""))
		var ps: Dictionary = players.get(id, {})
		var rw: Dictionary = rewards.get(id, {})
		lines.append("%s%s: 피해 %d · 처치 %d · 받은 피해 %d · 다운 %d · 구조 %d   → 기억 조각 +%d, 숙련 +%d" % ["▶" if id == my_id else "  ", m.get("nick", "?"), int(ps.get("damage_dealt", 0)), int(ps.get("kills", 0)), int(ps.get("damage_taken", 0)), int(ps.get("downs", 0)), int(ps.get("rescues", 0)), int(rw.get("memory_shards", 0)), int(rw.get("mastery_xp", 0))])
	body.text = "\n".join(lines)


func show_choices(party: Array) -> void:
	var parts: PackedStringArray = []
	for m: Dictionary in party:
		var c := String(m.get("choice", ""))
		parts.append("%s: %s" % [m.get("nick", "?"), {"restart": "다시 도전", "hub": "마을로", "": "선택 중"}.get(c, c)])
	choice_label.text = " · ".join(parts)

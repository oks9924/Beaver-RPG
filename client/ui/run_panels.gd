class_name RunPanels
extends Control
## 원정 진행 패널: 보상 3지선다, 경로 투표, 사건/상점/휴식 노드. 제한시간과 기본 규칙을 표시한다 (4절·14절).

signal reward_picked(index: int)
signal route_voted(node_id: String)
signal node_action(payload: Dictionary)

var panel: PanelContainer
var vbox: VBoxContainer
var title: Label
var body: Label
var timer_label: Label
var buttons_box: VBoxContainer
var footer: Label
var _deadline: float = 0.0
var _mode: String = ""
var _my_id: String = ""


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	panel = UIKit.panel(Vector2(640, 0))
	vbox = UIKit.vbox(8)
	panel.add_child(vbox)
	title = UIKit.label("", 24, Color(0.98, 0.85, 0.45))
	body = UIKit.label("", 14)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(600, 0)
	timer_label = UIKit.label("", 13, Color(0.8, 0.9, 1.0))
	buttons_box = UIKit.vbox(6)
	footer = UIKit.label("", 12, Color(0.7, 0.7, 0.65))
	footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer.custom_minimum_size = Vector2(600, 0)
	for c in [title, body, timer_label, buttons_box, footer]:
		vbox.add_child(c)
	add_child(UIKit.center(panel))


func _clear_buttons() -> void:
	for c: Node in buttons_box.get_children():
		c.queue_free()


func _process(_dt: float) -> void:
	if _deadline > 0.0:
		var left := maxf(_deadline - Time.get_unix_time_from_system(), 0.0)
		timer_label.text = "남은 시간 %d초 · 시간이 끝나면 기본 규칙이 적용됩니다" % int(ceil(left))


func show_reward(p: Dictionary, my_id: String) -> void:
	_mode = "reward"
	_my_id = my_id
	visible = true
	_deadline = Time.get_unix_time_from_system() + float(p.get("deadline_in", 0))
	var res: Dictionary = p.get("result", {})
	title.text = "방 클리어 — 보상 선택"
	var ps: Dictionary = res.get("players", {}).get(my_id, {})
	body.text = "소요 %s · 처치 %d · 내 피해 %d · 받은 피해 %d · 도토리 +%d · 경험치 +%d (런 레벨 %d)" % [UIKit.fmt_time(float(res.get("elapsed", 0))), int(res.get("stats", {}).get("enemies_killed", 0)), int(ps.get("damage_dealt", 0)), int(ps.get("damage_taken", 0)), int(ps.get("acorns_gained", 0)), int(res.get("xp_gained", 0)), int(res.get("level", 1))]
	_clear_buttons()
	var options: Array = p.get("options", [])
	if options.is_empty() or bool(p.get("picked", false)):
		buttons_box.add_child(UIKit.label("선택 완료. 다른 파티원을 기다리는 중...", 14))
	for i in options.size():
		var o: Dictionary = options[i]
		var kind_ko: String = {"relic": "유물", "upgrade": "스킬 강화", "acorns": "도토리"}.get(String(o.get("kind", "")), "")
		var b := UIKit.button("[%s] %s — %s" % [kind_ko, o.get("name_ko", ""), o.get("desc_ko", "")], func() -> void: reward_picked.emit(i))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		buttons_box.add_child(b)
	footer.text = "개인 선택입니다. 시간이 끝나면 첫 번째 항목이 자동 선택됩니다. 유물·강화는 이번 원정에만 적용됩니다."


func show_route(p: Dictionary, my_id: String, party: Array) -> void:
	_mode = "route"
	_my_id = my_id
	visible = true
	_deadline = Time.get_unix_time_from_system() + float(p.get("deadline_in", 0))
	title.text = "경로 선택 (지역 %d층)" % (int(p.get("layer", 0)) + 1)
	body.text = "다음 목적지를 투표합니다. 목적지 유형과 알려진 위험을 보고 고르세요."
	_clear_buttons()
	var votes: Dictionary = p.get("votes", {})
	for n: Dictionary in p.get("nodes", []):
		var voters: PackedStringArray = []
		for aid: String in votes.keys():
			if votes[aid] == n["id"]:
				voters.append(_nick(aid, party))
		var label := "%s — %s%s" % [_node_type_ko(String(n.get("type", ""))), _node_name(n), ("   [투표: %s]" % ", ".join(voters)) if not voters.is_empty() else ""]
		var b := UIKit.button(label, func() -> void: route_voted.emit(String(n["id"])))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		buttons_box.add_child(b)
	footer.text = String(p.get("rule", ""))


func show_menu(p: Dictionary, my_id: String, party: Array) -> void:
	_mode = "menu"
	_my_id = my_id
	visible = true
	_deadline = Time.get_unix_time_from_system() + float(p.get("deadline_in", 0))
	var kind := String(p.get("kind", ""))
	var data: Dictionary = p.get("data", {})
	var run: Dictionary = p.get("run", {})
	var mine: Dictionary = run.get("players", {}).get(my_id, {})
	_clear_buttons()
	match kind:
		"event":
			title.text = "사건: %s" % data.get("name_ko", "")
			body.text = String(data.get("text_ko", ""))
			var votes: Dictionary = p.get("votes", {})
			for ch: Dictionary in data.get("choices", []):
				var voters: PackedStringArray = []
				for aid: String in votes.keys():
					if votes[aid] == ch["id"]:
						voters.append(_nick(aid, party))
				var b := UIKit.button("%s%s" % [ch.get("text_ko", ""), ("   [%s]" % ", ".join(voters)) if not voters.is_empty() else ""], func() -> void: node_action.emit({"action": "vote", "choice": String(ch["id"])}))
				b.alignment = HORIZONTAL_ALIGNMENT_LEFT
				buttons_box.add_child(b)
			footer.text = "파티 투표로 결정합니다. 동률이면 시드 추첨. 효과는 이번 원정에만 적용됩니다."
		"shop":
			title.text = "상점: %s" % data.get("name_ko", "")
			body.text = "내 도토리: %d · 팀 목재: %d" % [int(mine.get("acorns", 0)), int(run.get("team_wood", 0))]
			for it: Dictionary in data.get("items", []):
				var b := UIKit.button("%s — %d 도토리" % [it.get("name_ko", ""), int(it.get("cost", 0))], func() -> void: node_action.emit({"action": "buy", "item": String(it["id"])}))
				b.alignment = HORIZONTAL_ALIGNMENT_LEFT
				b.disabled = int(mine.get("acorns", 0)) < int(it.get("cost", 0))
				buttons_box.add_child(b)
			var done: Array = p.get("done", [])
			var cont := UIKit.button("계속 (%d/%d 준비)" % [done.size(), party.size()], func() -> void: node_action.emit({"action": "continue"}))
			buttons_box.add_child(cont)
			footer.text = "구매는 서버가 한 번만 처리합니다. 전원이 계속을 누르거나 시간이 끝나면 다음으로 이동합니다."
		"rest":
			title.text = String(data.get("name_ko", "휴식"))
			body.text = String(data.get("text_ko", ""))
			var done: Array = p.get("done", [])
			buttons_box.add_child(UIKit.button("계속 (%d/%d 준비)" % [done.size(), party.size()], func() -> void: node_action.emit({"action": "continue"})))
			footer.text = ""
	if _mode == "menu" and (p.get("done", []) as Array).has(my_id):
		buttons_box.add_child(UIKit.label("다른 파티원을 기다리는 중...", 13))


func hide_panel() -> void:
	visible = false
	_deadline = 0.0
	_mode = ""


func _nick(aid: String, party: Array) -> String:
	for m: Dictionary in party:
		if m.get("id", "") == aid:
			return String(m.get("nick", aid))
	return aid.left(6)


static func _node_type_ko(t: String) -> String:
	return {"combat": "전투", "event": "탐험·사건", "shop": "상점", "rest": "휴식", "boss": "지역 보스", "elite": "정예"}.get(t, t)


static func _node_name(n: Dictionary) -> String:
	var v := String(n.get("variant", ""))
	match String(n.get("type", "")):
		"combat": return String(ContentDB.get_room_def(v).get("name_ko", v))
		"event": return String(ContentDB.events.get(v, {}).get("name_ko", v))
		"shop": return String(ContentDB.shop.get(v, {}).get("name_ko", v))
		"boss": return String(ContentDB.bosses.get(v, {}).get("name_ko", "철턱 가재"))
		"rest": return "모닥불"
	return v

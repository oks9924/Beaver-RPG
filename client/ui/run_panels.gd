class_name RunPanels
extends Control
## 원정 진행 패널: 보상 3지선다(보물 방 포함), 사건/상점/휴식 노드. 제한시간과 기본 규칙을 표시한다 (4절·14절). 경로는 던전 격자의 문으로 걸어서 고른다.

signal reward_picked(index: int)
signal reward_reroll()
signal node_action(payload: Dictionary)
signal pause_requested()
var pause_btn: Button

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
	pause_btn = UIKit.button("원정 중단 (안전 지점 저장 · 모집판에서 이어하기)", func() -> void: pause_requested.emit())
	vbox.add_child(pause_btn)
	add_child(UIKit.center(panel))


func _clear_buttons() -> void:
	for c: Node in buttons_box.get_children():
		c.queue_free()


func _process(_dt: float) -> void:
	if _deadline > 0.0:
		var left := maxf(_deadline - Time.get_unix_time_from_system(), 0.0)
		timer_label.text = "남은 시간 %d초 · 시간이 끝나면 기본 규칙이 적용됩니다" % int(ceil(left))


const RARITY_KO := {"common": "일반", "rare": "희귀", "legendary": "전설"}
const RARITY_COLOR := {"common": Color(1, 1, 1), "rare": Color(0.6, 0.85, 1.0), "legendary": Color(1.0, 0.8, 0.4)}


var run_class: String = "guardian"


func show_reward(p: Dictionary, my_id: String, rerolls: int = 0) -> void:
	_mode = "reward"
	_my_id = my_id
	visible = true
	_deadline = Time.get_unix_time_from_system() + float(p.get("deadline_in", 0))
	var res: Dictionary = p.get("result", {})
	var treasure := bool(p.get("treasure", false))
	title.text = "보물 방 — 상자를 연다" if treasure else "방 클리어 — 보상 선택"
	var ps: Dictionary = res.get("players", {}).get(my_id, {})
	if treasure:
		body.text = "옆길 보물 방: 희귀 이상 유물이 후보에 섞여 나옵니다. 각자 하나를 고르고 나면 문이 열립니다."
	else:
		body.text = "소요 %s · 처치 %d · 내 피해 %d · 받은 피해 %d · 도토리 +%d · 경험치 +%d (런 레벨 %d)" % [UIKit.fmt_time(float(res.get("elapsed", 0))), int(res.get("stats", {}).get("enemies_killed", 0)), int(ps.get("damage_dealt", 0)), int(ps.get("damage_taken", 0)), int(ps.get("acorns_gained", 0)), int(res.get("xp_gained", 0)), int(res.get("level", 1))]
	if bool(res.get("par_bonus", false)):
		body.text += "\n기록 보너스! 기준 %d초 안에 클리어 — 도토리·경험치 추가" % int(res.get("par_sec", 0))
	var rw: Dictionary = res.get("rewards", {}).get(my_id, {})
	var gear: Dictionary = rw.get("gear", {})
	if not gear.is_empty():
		var gtxt := "장비 획득: [%s] %s — %s" % [Equipment.rarity_name(String(gear.get("rarity", ""))), gear.get("name_ko", ""), " / ".join(Equipment.describe(gear))]
		if bool(rw.get("gear_lost", false)):
			gtxt = "창고가 가득 차 장비를 버렸습니다: " + String(gear.get("name_ko", ""))
		body.text += "\n" + gtxt
	if int(rw.get("crystals", 0)) > 0:
		body.text += "\n수액 결정 +%d (강화·재감정 재료)" % int(rw.get("crystals", 0))
	_clear_buttons()
	var options: Array = p.get("options", [])
	if options.is_empty() or bool(p.get("picked", false)):
		buttons_box.add_child(UIKit.label("선택 완료. 다른 파티원을 기다리는 중...", 14))
	var cards := UIKit.hbox(10)
	for i in options.size():
		var o: Dictionary = options[i]
		var kind: String = String(o.get("kind", ""))
		var rarity: String = String(o.get("rarity", "common"))
		var kind_ko: String = {"relic": "유물", "upgrade": "스킬 강화", "acorns": "도토리"}.get(kind, "")
		var b := UIKit.card_button("[%s · %s]\n%s\n\n%s" % [kind_ko, RARITY_KO.get(rarity, rarity), o.get("name_ko", ""), o.get("desc_ko", "")], "ui.card.reward", 0 if kind == "relic" else 1, Vector2(196, 270), func() -> void: reward_picked.emit(i))
		b.add_theme_color_override("font_color", RARITY_COLOR.get(rarity, Color.WHITE))
		var icon_id := ""
		if kind == "relic":
			icon_id = String(ContentDB.relics.get(String(o.get("id", "")), {}).get("assets", {}).get("icon", ""))
		elif kind == "upgrade":
			icon_id = String(ContentDB.get_class_def(String(run_class)).get("skills", {}).get(String(o.get("skill", "")), {}).get("assets", {}).get("icon", ""))
		if icon_id != "" and AssetRegistry.status(icon_id) == "final":
			b.icon = AssetRegistry.get_texture(icon_id)
			b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
			b.expand_icon = true
			b.add_theme_constant_override("icon_max_width", 48)
		if rarity != "common":
			b.modulate = Color(1.05, 1.05, 1.0) if rarity == "rare" else Color(1.1, 1.05, 0.9)
		cards.add_child(b)
	buttons_box.add_child(cards)
	if not options.is_empty() and not bool(p.get("picked", false)):
		var rb := UIKit.button("다시 뽑기 (남은 %d회)" % rerolls, func() -> void: reward_reroll.emit())
		rb.disabled = rerolls <= 0
		buttons_box.add_child(rb)
	footer.text = "개인 선택입니다. 시간이 끝나면 첫 번째 항목이 자동 선택됩니다. 유물·강화는 이번 원정에만 적용됩니다. 깊이 들어갈수록 희귀·전설이 자주 나옵니다. 선택이 끝나면 같은 방에서 문으로 이동합니다."


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
			buttons_box.add_child(UIKit.frame_icon("prop.stall", 0, 96))
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
			buttons_box.add_child(UIKit.frame_icon("prop.campfire", int(Time.get_ticks_msec() / 400) % 2, 96))
			var rc: Dictionary = data.get("rest_choice", {})
			var mine_choice := String(rc.get(my_id, ""))
			if mine_choice == "":
				var ch := UIKit.hbox(8)
				ch.add_child(UIKit.button("휴식 — 체력 회복 + 회복 도구 보충", func() -> void: node_action.emit({"action": "rest_choice", "choice": "heal"})))
				ch.add_child(UIKit.button("숫돌 — 무작위 스킬 강화 1개 (회복 없음)", func() -> void: node_action.emit({"action": "rest_choice", "choice": "smith"})))
				buttons_box.add_child(ch)
			else:
				buttons_box.add_child(UIKit.label("내 선택: %s" % ("휴식" if mine_choice == "heal" else "숫돌"), 13, Color(0.7, 1.0, 0.7)))
			var picks: PackedStringArray = []
			for aid: String in rc.keys():
				picks.append("%s: %s" % [_nick(aid, party), "휴식" if String(rc[aid]) == "heal" else "숫돌"])
			if not picks.is_empty():
				buttons_box.add_child(UIKit.label(" · ".join(picks), 12))
			var done: Array = p.get("done", [])
			buttons_box.add_child(UIKit.button("계속 (%d/%d 준비)" % [done.size(), party.size()], func() -> void: node_action.emit({"action": "continue"})))
			footer.text = "고르지 않고 계속하면 휴식으로 처리됩니다."
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
	return {"combat": "전투", "event": "탐험·사건", "shop": "상점", "rest": "휴식", "boss": "지역 보스", "elite": "정예", "treasure": "보물"}.get(t, t)


static func _node_name(n: Dictionary) -> String:
	var v := String(n.get("variant", ""))
	match String(n.get("type", "")):
		"combat": return String(ContentDB.get_room_def(v).get("name_ko", v))
		"event": return String(ContentDB.events.get(v, {}).get("name_ko", v))
		"shop": return String(ContentDB.shop.get(v, {}).get("name_ko", v))
		"boss": return String(ContentDB.bosses.get(v, {}).get("name_ko", "철턱 가재"))
		"rest": return "모닥불"
	return v

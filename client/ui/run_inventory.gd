class_name RunInventory
extends PanelContainer
## 원정 중 가방 (I 키): 창고 목록을 보고 바닥에 버리거나 파티원에게 건넨다. 장착 변경은 마을에서만.

signal drop_requested(uid: String)
signal give_requested(uid: String, to: String)
var _title: Label
var _list: VBoxContainer
var _target: OptionButton
var _targets: Array = []   # [{id, nick}]
var _account: Dictionary = {}
var _party: Array = []
var _my_id: String = ""


func _ready() -> void:
	visible = false
	custom_minimum_size = Vector2(460, 0)
	top_level = true   # 부모 레이아웃과 무관하게 화면 가운데에 둔다 (_process 가 매 프레임 맞춘다)
	var v := UIKit.vbox(6)
	add_child(v)
	var head := UIKit.hbox(6)
	_title = UIKit.label("가방", 17, Color(0.98, 0.85, 0.45))
	head.add_child(_title)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	head.add_child(UIKit.button("닫기 (I)", func() -> void: visible = false))
	v.add_child(head)
	var th := UIKit.hbox(6)
	th.add_child(UIKit.label("건넬 대상", 13))
	_target = OptionButton.new()
	th.add_child(_target)
	v.add_child(th)
	v.add_child(UIKit.label("장착 변경은 마을 메뉴에서. 드랍은 개인별(내 것만 보임)이고, 버린 장비는 공용이라 파티원이 주울 수 있으며 방을 떠나면 사라집니다.", 12, Color(0.75, 0.75, 0.7)))
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(440, 320)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	_list = UIKit.vbox(3)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_list)


func _process(_dt: float) -> void:
	if visible:
		position = ((get_viewport_rect().size - size) * 0.5).floor()


func toggle(account: Dictionary, party: Array, my_id: String) -> void:
	if visible:
		visible = false
		return
	refresh(account, party, my_id)
	visible = true
	move_to_front()


func refresh(account: Dictionary, party: Array, my_id: String) -> void:
	_account = account
	_party = party
	_my_id = my_id
	var prog: Dictionary = account.get("progression", {})
	var inv: Array = prog.get("inventory", [])
	var cap := int(ContentDB.equipment.get("drop", {}).get("inventory_cap", 60))
	_title.text = "가방 %d / %d · 수액 결정 %d" % [inv.size(), cap, Equipment.material_count(prog)]
	var prev := _target.selected
	_target.clear()
	_targets.clear()
	for m: Dictionary in party:
		if String(m.get("id", "")) == my_id or not bool(m.get("connected", true)):
			continue
		_targets.append({"id": String(m.get("id", "")), "nick": String(m.get("nick", "?"))})
		_target.add_item(String(m.get("nick", "?")))
	if _targets.is_empty():
		_target.add_item("(파티원 없음)")
		_target.disabled = true
	else:
		_target.disabled = false
		_target.selected = clampi(prev, 0, _targets.size() - 1)
	for c: Node in _list.get_children():
		c.queue_free()
	if inv.is_empty():
		_list.add_child(UIKit.label("가방이 비어 있습니다. 적을 처치하면 장비가 바닥에 떨어집니다.", 13, Color(0.75, 0.75, 0.7)))
		return
	var sorted := inv.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ra := Equipment.rarity_index(String(a.get("rarity", "common")))
		var rb := Equipment.rarity_index(String(b.get("rarity", "common")))
		return ra > rb if ra != rb else String(a.get("name_ko", "")) < String(b.get("name_ko", "")))
	for it: Dictionary in sorted:
		var uid := String(it.get("uid", ""))
		var equipped := Equipment.is_equipped(prog, uid)
		var row := UIKit.hbox(6)
		var icon := HubScreen.GearIcon.new()
		icon.item = it
		icon.px = 32.0
		row.add_child(icon)
		var col := Equipment.rarity_color(String(it.get("rarity", "common")))
		var name := UIKit.label(Equipment.display_name(it) + ("  (장착 중)" if equipped else ""), 13, col.lightened(0.2))
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name.clip_text = true
		name.tooltip_text = "\n".join(Equipment.describe(it))
		row.add_child(name)
		var give := UIKit.button("건네기", func() -> void:
			if not _targets.is_empty():
				give_requested.emit(uid, String(_targets[clampi(_target.selected, 0, _targets.size() - 1)]["id"])))
		give.disabled = equipped or _targets.is_empty()
		row.add_child(give)
		var drop := UIKit.button("버리기", func() -> void: drop_requested.emit(uid))
		drop.disabled = equipped
		row.add_child(drop)
		_list.add_child(row)

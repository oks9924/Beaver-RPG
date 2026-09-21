class_name PartyPortraits
extends VBoxContainer
## 우측 세로 파티 카드: 체력 바(위) + 직업 초상(가운데) + 이름·상태(아래). 내 캐릭터는 금색 테두리, 다운·사망·연결 끊김은 초상을 어둡게 하고 글자로 표시.

const CARD_W := 84.0
const PORTRAIT_PX := 68.0
var _cards: Dictionary = {}   # account_id -> {root, bar, portrait, frame, name, status}


## 초상 위 체력 띠: 작아도 읽히게 단색으로 그린다 (텍스처 바는 이 폭에서 8px 로 얇아진다)
class HpStrip extends Control:
	var max_value: float = 100.0
	var value: float = 100.0
	var fill_color: Color = Color(0.3, 0.85, 0.35)

	func _ready() -> void:
		custom_minimum_size = Vector2(CARD_W, 14)
		mouse_filter = MOUSE_FILTER_IGNORE

	func _process(_dt: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var frac := clampf(value / maxf(max_value, 1.0), 0.0, 1.0)
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.06, 0.04, 0.95))
		draw_rect(Rect2(Vector2(2, 2), Vector2((size.x - 4.0) * frac, size.y - 4.0)), fill_color)
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.85, 0.75, 0.5, 0.9), false, 1.5)
		var font := AssetRegistry.get_font("font.ui.main")
		var txt := str(int(round(value)))
		draw_string_outline(font, Vector2(0, size.y - 3), txt, HORIZONTAL_ALIGNMENT_CENTER, size.x, 11, 3, Color(0.05, 0.03, 0.01, 0.9))
		draw_string(font, Vector2(0, size.y - 3), txt, HORIZONTAL_ALIGNMENT_CENTER, size.x, 11, Color(1, 1, 0.95))


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	mouse_filter = MOUSE_FILTER_IGNORE


func _ensure_card(aid: String, class_id: String) -> Dictionary:
	var c: Dictionary = _cards.get(aid, {})
	if not c.is_empty():
		if String(c.get("class_id", "")) != class_id:
			_set_portrait(c, class_id)
		return c
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 2)
	root.custom_minimum_size = Vector2(CARD_W, 0)
	var bar := HpStrip.new()
	root.add_child(bar)
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(CARD_W, PORTRAIT_PX + 8)
	var portrait := TextureRect.new()
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_SCALE
	portrait.position = Vector2((CARD_W - PORTRAIT_PX) * 0.5, 4)
	portrait.size = Vector2(PORTRAIT_PX, PORTRAIT_PX)
	holder.add_child(portrait)
	var frame := TextureRect.new()
	frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame.stretch_mode = TextureRect.STRETCH_SCALE
	frame.position = Vector2((CARD_W - PORTRAIT_PX) * 0.5 - 6, -2)
	frame.size = Vector2(PORTRAIT_PX + 12, PORTRAIT_PX + 12)
	frame.mouse_filter = MOUSE_FILTER_IGNORE
	if AssetRegistry.status("ui.frame.portrait") == "final":
		frame.texture = AssetRegistry.get_texture("ui.frame.portrait")
	holder.add_child(frame)
	var status := UIKit.label("", 14, Color(1.0, 0.5, 0.4))
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.position = Vector2(0, PORTRAIT_PX * 0.5 - 8)
	status.size = Vector2(CARD_W, 20)
	holder.add_child(status)
	root.add_child(holder)
	var name := UIKit.label("", 14)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.custom_minimum_size = Vector2(CARD_W, 0)
	name.clip_text = true
	name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	root.add_child(name)
	add_child(root)
	c = {"root": root, "bar": bar, "portrait": portrait, "frame": frame, "name": name, "status": status, "class_id": ""}
	_set_portrait(c, class_id)
	_cards[aid] = c
	return c


func _set_portrait(c: Dictionary, class_id: String) -> void:
	c["class_id"] = class_id
	var pid := "portrait." + class_id
	var tr: TextureRect = c["portrait"]
	if AssetRegistry.has(pid) and AssetRegistry.status(pid) == "final":
		tr.texture = AssetRegistry.get_texture(pid)
	else:
		tr.texture = AssetRegistry.get_texture("icon.class." + class_id) if AssetRegistry.has("icon.class." + class_id) else null


## party: [{id, nick, class_id, connected}], snapshot_players: [[id, PackedFloat32Array]], max_hps: {id: max_hp}
func update(snapshot_players: Array, party: Array, my_id: String, max_hps: Dictionary) -> void:
	var seen: Dictionary = {}
	for m: Dictionary in party:
		var aid := String(m.get("id", ""))
		seen[aid] = true
		var c := _ensure_card(aid, String(m.get("class_id", "guardian")))
		var bar: HpStrip = c["bar"]
		var hp := 0.0
		var state := Protocol.EntState.ALIVE
		var connected := bool(m.get("connected", true))
		var down_t := 0.0
		var found := false
		for entry: Array in snapshot_players:
			if entry[0] == aid:
				var p: PackedFloat32Array = entry[1]
				hp = float(p[Protocol.SNAP_P.HP])
				state = int(p[Protocol.SNAP_P.STATE])
				connected = p[Protocol.SNAP_P.CONNECTED] >= 0.5
				down_t = float(p[Protocol.SNAP_P.DOWN_T])
				found = true
		bar.max_value = maxf(float(max_hps.get(aid, ContentDB.get_class_def(String(m.get("class_id", "guardian"))).get("base_hp", 100))), 1.0)
		bar.value = hp if found else 0.0
		var frac := bar.value / bar.max_value
		bar.fill_color = Color(0.3, 0.85, 0.35) if frac > 0.5 else (Color(0.95, 0.75, 0.25) if frac > 0.25 else Color(0.9, 0.3, 0.25))
		var status: Label = c["status"]
		var portrait: TextureRect = c["portrait"]
		if not connected:
			status.text = "끊김"
			portrait.modulate = Color(0.45, 0.45, 0.5)
		elif state == Protocol.EntState.DOWNED:
			status.text = "다운 %ds" % int(ceil(down_t))
			portrait.modulate = Color(0.7, 0.35, 0.35)
		elif state == Protocol.EntState.DEAD:
			status.text = "사망"
			portrait.modulate = Color(0.35, 0.35, 0.35)
		else:
			status.text = ""
			portrait.modulate = Color.WHITE
		var frame: TextureRect = c["frame"]
		frame.modulate = Color(1.0, 0.85, 0.4) if aid == my_id else Color.WHITE
		var name: Label = c["name"]
		name.text = ("▶" if aid == my_id else "") + String(m.get("nick", "?"))
		name.add_theme_color_override("font_color", Color(1.0, 0.95, 0.6) if aid == my_id else Color(0.95, 0.92, 0.85))
	for aid: String in _cards.keys().duplicate():
		if not seen.has(aid):
			(_cards[aid]["root"] as Node).queue_free()
			_cards.erase(aid)

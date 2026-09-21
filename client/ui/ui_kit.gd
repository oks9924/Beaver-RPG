class_name UIKit
extends RefCounted
## 코드로 UI 를 만들 때 쓰는 공통 헬퍼. 폰트·패널은 에셋 ID 로 가져온다.

static var _theme: Theme = null
static var click_sound: Callable = Callable()

static func error_text(code: String, payload: Dictionary = {}) -> String:
	match code:
		Protocol.ERR_VERSION_MISMATCH:
			var req: Dictionary = payload.get("required", {})
			return "버전이 맞지 않습니다. 서버 요구: 프로토콜 %s / 콘텐츠 %s (내 버전: 프로토콜 %d / 콘텐츠 %s). 업데이트: %s" % [req.get("protocol", "?"), req.get("content", "?"), Protocol.PROTOCOL_VERSION, Protocol.CONTENT_VERSION, payload.get("update_url", "")]
		Protocol.ERR_SERVER_FULL: return "서버가 가득 찼습니다 (%s/%s). 잠시 후 다시 시도하거나 다른 서버를 선택하세요." % [payload.get("online", "?"), payload.get("max_online", "?")]
		Protocol.ERR_ALREADY_ONLINE: return "이 계정은 이미 접속 중입니다. 다른 클라이언트를 종료한 뒤 다시 시도하세요."
		Protocol.ERR_BAD_CREDENTIALS: return "닉네임 또는 비밀번호가 올바르지 않습니다."
		Protocol.ERR_NICK_TAKEN: return "이미 사용 중인 닉네임입니다."
		"NOT_ENOUGH_MATERIALS": return "수액 결정이 부족합니다 (장비를 분해하거나 정예·보스를 잡으세요)."
		"MAX_ENHANCE": return "최대 강화 단계입니다."
		"ITEM_EQUIPPED": return "장착 중인 장비는 분해할 수 없습니다. 먼저 해제하세요."
		"NO_ITEM": return "창고에 없는 장비입니다."
		"NO_CANDIDATE": return "바꿀 수 있는 특성이 없습니다."
		"RECIPE_LOCKED": return "아직 해금되지 않은 도안입니다 (지역 보스를 잡으면 해금)."
		"NOT_ENOUGH_SHARDS": return "기억 조각이 부족합니다."
		"INVENTORY_FULL": return "창고가 가득 찼습니다. 분해로 자리를 만드세요."
		"NO_RECIPE": return "없는 도안입니다."
		Protocol.ERR_INVALID_NICK: return "닉네임은 2~16자의 글자·숫자·밑줄만 가능합니다."
		Protocol.ERR_INVALID_PASSWORD: return "비밀번호는 6자 이상이어야 합니다."
		Protocol.ERR_REGISTRATION_DISABLED: return "이 서버는 신규 계정 생성을 허용하지 않습니다."
		Protocol.ERR_RATE_LIMITED: return "요청이 너무 잦습니다. 잠시 후 다시 시도하세요."
		Protocol.ERR_PARTY_FULL: return "이 원정은 이미 4명이 가득 찼습니다."
		Protocol.ERR_EXPEDITION_LIMIT: return "서버의 동시 원정 수가 상한(%s)에 도달했습니다. 진행 중인 원정이 끝나면 다시 시도하세요." % payload.get("max", "?")
		Protocol.ERR_NO_EXPEDITION: return "원정을 찾을 수 없습니다."
		Protocol.ERR_ALREADY_IN_EXPEDITION: return "이미 원정에 참가 중입니다."
		Protocol.ERR_NOT_READY: return "모든 파티원이 준비 완료여야 출정할 수 있습니다."
		Protocol.ERR_TOKEN_EXPIRED: return "저장된 접속 정보가 만료되었습니다. 다시 로그인하세요."
		Protocol.ERR_SAVE_FAILED: return "서버 저장에 실패했습니다. 운영자에게 알려주세요."
		"CONNECT_FAILED": return "서버에 연결할 수 없습니다. 주소·포트와 서버 실행 여부를 확인하세요."
		"CONNECT_TIMEOUT": return "서버 응답이 없습니다. 서버가 꺼져 있거나 방화벽(UDP)에 막혔을 수 있습니다."
		"SERVER_CLOSED": return "서버와의 연결이 끊어졌습니다."
		"MAINTENANCE": return "서버가 점검 중입니다."
		"LOGOUT": return "로그아웃했습니다."
		Protocol.ERR_HELLO_TIMEOUT: return "서버 인사 단계에서 시간이 초과되었습니다."
		_: return "오류: %s %s" % [code, payload.get("message", "")]


static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	var font := AssetRegistry.get_font("font.ui.main")
	t.default_font = font
	t.default_font_size = 16
	# 가독성: 모든 글자에 어두운 외곽선을 준다 (나무결 패널·전장 위에서도 읽힌다)
	var outline := Color(0.08, 0.05, 0.02, 0.92)
	for cls: String in ["Label", "Button", "RichTextLabel", "LineEdit", "OptionButton", "CheckBox", "PopupMenu"]:
		t.set_color("font_outline_color", cls, outline)
		t.set_constant("outline_size", cls, OUTLINE_PX)
	t.set_color("default_color", "RichTextLabel", Color(0.97, 0.95, 0.9))
	t.set_color("font_color", "Button", Color(0.98, 0.96, 0.9))
	t.set_color("font_hover_color", "Button", Color(1.0, 0.98, 0.85))
	t.set_color("font_disabled_color", "Button", Color(0.75, 0.72, 0.65))
	t.set_color("font_color", "Label", Color(0.97, 0.95, 0.9))
	var panel_tex := AssetRegistry.get_texture("ui.panel.default")
	var sb := StyleBoxTexture.new()
	sb.texture = panel_tex
	var m: int = int(AssetRegistry.entry("ui.panel.default").get("nine_slice_margin", 12))
	sb.texture_margin_left = m
	sb.texture_margin_right = m
	sb.texture_margin_top = m
	sb.texture_margin_bottom = m
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	sb.modulate_color = Color(0.86, 0.84, 0.8)   # 패널을 살짝 어둡게 해 밝은 글자와 대비를 키운다
	t.set_stylebox("panel", "PanelContainer", sb)
	var btn := StyleBoxTexture.new()
	btn.texture = AssetRegistry.get_texture("ui.button.default")
	for side in ["left", "right", "top", "bottom"]:
		btn.set("texture_margin_" + side, m)
	btn.content_margin_left = 12
	btn.content_margin_right = 12
	btn.content_margin_top = 6
	btn.content_margin_bottom = 6
	t.set_stylebox("normal", "Button", btn)
	var btn_h: StyleBoxTexture = btn.duplicate()
	if AssetRegistry.status("ui.button.hover") == "final":
		btn_h.texture = AssetRegistry.get_texture("ui.button.hover")
	else:
		btn_h.modulate_color = Color(1.15, 1.15, 1.0)
	t.set_stylebox("hover", "Button", btn_h)
	var btn_p: StyleBoxTexture = btn.duplicate()
	if AssetRegistry.status("ui.button.pressed") == "final":
		btn_p.texture = AssetRegistry.get_texture("ui.button.pressed")
	else:
		btn_p.modulate_color = Color(0.8, 0.8, 0.7)
	t.set_stylebox("pressed", "Button", btn_p)
	var btn_d := btn.duplicate()
	btn_d.modulate_color = Color(0.5, 0.5, 0.5)
	t.set_stylebox("disabled", "Button", btn_d)
	_theme = t
	return t


## 가독성 규칙: 글자 크기 하한(FONT_MIN)과 흐린 색 보정(너무 어두운 회색은 밝게). 외곽선은 테마가 준다.
const FONT_MIN := 14
const OUTLINE_PX := 3


static func readable_color(c: Color) -> Color:
	# 명도가 낮은(회색) 안내 글자는 밝게 끌어올린다. 색상 계열은 유지.
	if c.v < 0.82:
		return c.lerp(Color(1.0, 0.98, 0.92), 0.35)
	return c


static func label(text: String, size: int = 16, color: Color = Color(0.95, 0.92, 0.85)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", maxi(size, FONT_MIN))
	l.add_theme_color_override("font_color", readable_color(color))
	return l


static func button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	b.pressed.connect(_click)
	return b


static func _click() -> void:
	if click_sound.is_valid():
		click_sound.call()


static func line_edit(placeholder: String, secret: bool = false) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.secret = secret
	e.custom_minimum_size = Vector2(240, 0)
	return e


static func panel(min_size: Vector2 = Vector2.ZERO) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = min_size
	return p


static func vbox(sep: int = 8) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep: int = 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func center(child: Control) -> CenterContainer:
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.add_child(child)
	return c


static func fmt_time(sec: float) -> String:
	var s := int(sec)
	return "%d:%02d" % [s / 60, s % 60]


## 시트의 한 프레임을 배경으로 쓰는 카드 버튼 (보상·경로 카드). 시트가 없으면 일반 버튼.
static func card_button(text: String, sheet_id: String, frame: int, size: Vector2, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	var sheet := AssetRegistry.get_sheet(sheet_id)
	if bool(sheet["is_fallback"]) or AssetRegistry.status(sheet_id) != "final":
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		return b
	var sb := StyleBoxTexture.new()
	sb.texture = AssetRegistry.get_frame_texture(sheet_id, frame)
	for side in ["left", "right", "top", "bottom"]:
		sb.set("texture_margin_" + side, 28)
	# 팩의 content_rect(투명 안쪽 영역)를 카드 크기에 비례해 여백으로 적용한다 (docs/ui_layout.json)
	var fs: Vector2 = sheet["frame_size"]
	var cr: Array = AssetRegistry.entry(sheet_id).get("content_rect", [])
	var sx := size.x / maxf(fs.x, 1.0)
	var sy := size.y / maxf(fs.y, 1.0)
	if cr.size() == 4:
		sb.content_margin_left = float(cr[0]) * sx
		sb.content_margin_top = float(cr[1]) * sy
		sb.content_margin_right = (fs.x - float(cr[0]) - float(cr[2])) * sx
		sb.content_margin_bottom = (fs.y - float(cr[1]) - float(cr[3])) * sy
	else:
		sb.content_margin_left = 22
		sb.content_margin_right = 22
		sb.content_margin_top = 26
		sb.content_margin_bottom = 20
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sbx: StyleBoxTexture = sb.duplicate()
		if st == "hover":
			sbx.modulate_color = Color(1.12, 1.12, 1.05)
		elif st == "pressed":
			sbx.modulate_color = Color(0.85, 0.85, 0.8)
		elif st == "disabled":
			sbx.modulate_color = Color(0.55, 0.55, 0.55)
		b.add_theme_stylebox_override(st, sbx)
	b.custom_minimum_size = size
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_theme_font_size_override("font_size", 13)
	b.pressed.connect(_click)
	return b


static func frame_icon(sheet_id: String, frame: int, px: int) -> TextureRect:
	var t := TextureRect.new()
	t.texture = AssetRegistry.get_frame_texture(sheet_id, frame)
	t.custom_minimum_size = Vector2(px, px)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return t

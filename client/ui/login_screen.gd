class_name LoginScreen
extends Control
## 서버 내부 계정 생성·로그인. 별도 웹 가입이나 초대가 필요 없다.

signal login_requested(nick: String, password: String)
signal register_requested(nick: String, password: String)
signal back_requested()

var nick_edit: LineEdit
var pw_edit: LineEdit
var status_label: Label
var info_label: Label
var login_btn: Button
var register_btn: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var panel := UIKit.panel(Vector2(460, 0))
	var v := UIKit.vbox(10)
	panel.add_child(v)
	if AssetRegistry.status("ui.title.logo") == "final":
		var logo := TextureRect.new()
		logo.texture = AssetRegistry.get_texture("ui.title.logo")
		logo.custom_minimum_size = Vector2(420, 150)
		logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		v.add_child(logo)
		var tl := UIKit.label("꼬리원정대", 30, Color(0.98, 0.9, 0.6))
		tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(tl)
	v.add_child(UIKit.label("계정 로그인 / 생성", 24, Color(0.98, 0.85, 0.45)))
	info_label = UIKit.label("", 13, Color(0.7, 0.75, 0.7))
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(info_label)
	nick_edit = UIKit.line_edit("닉네임 (2~16자)")
	pw_edit = UIKit.line_edit("비밀번호 (6자 이상)", true)
	v.add_child(nick_edit)
	v.add_child(pw_edit)
	var h := UIKit.hbox()
	login_btn = UIKit.button("로그인", func() -> void: login_requested.emit(nick_edit.text.strip_edges(), pw_edit.text))
	register_btn = UIKit.button("새 계정 만들기", func() -> void: register_requested.emit(nick_edit.text.strip_edges(), pw_edit.text))
	h.add_child(login_btn)
	h.add_child(register_btn)
	h.add_child(UIKit.button("뒤로", func() -> void: back_requested.emit()))
	v.add_child(h)
	status_label = UIKit.label("", 14, Color(0.95, 0.7, 0.6))
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size = Vector2(420, 40)
	v.add_child(status_label)
	add_child(UIKit.center(panel))
	pw_edit.text_submitted.connect(func(_t: String) -> void: login_requested.emit(nick_edit.text.strip_edges(), pw_edit.text))


func show_server(info: Dictionary) -> void:
	info_label.text = "서버 '%s' (월드 %s)  접속 %s/%s  원정 %s/%s  신규 가입 %s" % [info.get("name", "?"), info.get("world_id", "?"), info.get("online", "?"), info.get("max_online", "?"), info.get("active_expeditions", "?"), info.get("max_expeditions", "?"), "허용" if info.get("allow_registration", true) else "불가"]
	register_btn.disabled = not bool(info.get("allow_registration", true))


func set_status(text: String, busy: bool = false) -> void:
	status_label.text = text
	login_btn.disabled = busy
	register_btn.disabled = busy

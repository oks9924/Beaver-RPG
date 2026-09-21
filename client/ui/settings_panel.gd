class_name SettingsPanel
extends PanelContainer
## 설정·접근성 (18절): 텍스트 크기, 아군 VFX 투명도, 화면 흔들림·섬광 감소, 음량 3채널, 전체 화면, 키 재설정.

signal changed()
signal closed()

var settings: ClientSettings
var _v: VBoxContainer
var _rebind_action: String = ""
var _rebind_btn: Button
var _key_buttons: Dictionary = {}

const REBINDABLE := {"move_up": "위로 이동", "move_down": "아래로 이동", "move_left": "왼쪽 이동", "move_right": "오른쪽 이동", "dodge": "회피", "skill_q": "스킬 Q", "skill_e": "스킬 E", "skill_r": "스킬 R", "interact": "상호작용", "heal": "회복 도구", "build_place": "건설", "build_cycle": "건설 종류", "map": "지도", "dev_overlay": "개발 정보"}


func setup(s: ClientSettings) -> void:
	settings = s
	visible = false
	set_anchors_and_offsets_preset(PRESET_CENTER)
	custom_minimum_size = Vector2(560, 0)
	_v = UIKit.vbox(6)
	add_child(_v)
	_v.add_child(UIKit.label("설정 · 접근성", 20, Color(0.98, 0.85, 0.45)))
	_slider("텍스트·UI 크기", "ui_scale", 0.8, 1.6, 0.1)
	_slider("아군 이펙트 투명도", "ally_vfx_alpha", 0.0, 1.0, 0.1)
	_slider("화면 흔들림", "screen_shake", 0.0, 1.0, 0.1)
	_toggle("섬광·번쩍임 감소", "flash_reduce")
	_toggle("자동 공격 (서 있을 때 마우스 방향으로 계속 공격)", "auto_attack")
	_slider("배경 음악", "volume_bgm", 0.0, 1.0, 0.05)
	_slider("효과음", "volume_sfx", 0.0, 1.0, 0.05)
	_slider("환경음", "volume_ambient", 0.0, 1.0, 0.05)
	_toggle("전체 화면 (F11)", "fullscreen")
	_v.add_child(UIKit.label("키 재설정 — 버튼을 누른 뒤 새 키를 누르세요 (Esc 취소)", 13, Color(0.8, 0.9, 1.0)))
	var grid := GridContainer.new()
	grid.columns = 4
	for action: String in REBINDABLE.keys():
		grid.add_child(UIKit.label(String(REBINDABLE[action]), 12))
		var b := UIKit.button(_key_name(action), func() -> void: _begin_rebind(action))
		_key_buttons[action] = b
		grid.add_child(b)
	_v.add_child(grid)
	var h := UIKit.hbox()
	h.add_child(UIKit.button("기본 키로", func() -> void:
		settings.data["keybinds"] = {}
		settings.save()
		changed.emit()
		_refresh_keys()))
	h.add_child(UIKit.button("닫기 (Esc)", func() -> void: hide_panel()))
	_v.add_child(h)


func _slider(label: String, key: String, lo: float, hi: float, step: float) -> void:
	var h := UIKit.hbox(8)
	var lbl := UIKit.label(label, 13)
	lbl.custom_minimum_size = Vector2(160, 0)
	h.add_child(lbl)
	var sl := HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = step
	sl.value = float(settings.data.get(key, hi))
	sl.custom_minimum_size = Vector2(260, 0)
	var val := UIKit.label("%.2f" % sl.value, 12)
	sl.value_changed.connect(func(v: float) -> void:
		settings.data[key] = v
		val.text = "%.2f" % v
		settings.save()
		changed.emit())
	h.add_child(sl)
	h.add_child(val)
	_v.add_child(h)


func _toggle(label: String, key: String) -> void:
	var cb := CheckBox.new()
	cb.text = label
	cb.button_pressed = bool(settings.data.get(key, false))
	cb.toggled.connect(func(on: bool) -> void:
		settings.data[key] = on
		settings.save()
		changed.emit())
	_v.add_child(cb)


func _key_name(action: String) -> String:
	var binds: Dictionary = settings.data.get("keybinds", {})
	if binds.has(action):
		return OS.get_keycode_string(int(binds[action]))
	for ev: InputEvent in InputMap.action_get_events(action):
		if ev is InputEventKey:
			return OS.get_keycode_string((ev as InputEventKey).physical_keycode)
	return "?"


func _refresh_keys() -> void:
	for action: String in _key_buttons.keys():
		(_key_buttons[action] as Button).text = _key_name(action)


func _begin_rebind(action: String) -> void:
	_rebind_action = action
	(_key_buttons[action] as Button).text = "키 입력..."


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed:
		var k := event as InputEventKey
		if _rebind_action != "":
			if k.keycode != KEY_ESCAPE:
				var binds: Dictionary = settings.data.get("keybinds", {})
				binds[_rebind_action] = int(k.physical_keycode)
				settings.data["keybinds"] = binds
				settings.save()
				changed.emit()
			_rebind_action = ""
			_refresh_keys()
			get_viewport().set_input_as_handled()
		elif k.keycode == KEY_ESCAPE:
			hide_panel()
			get_viewport().set_input_as_handled()


func show_panel() -> void:
	_refresh_keys()
	visible = true


func hide_panel() -> void:
	visible = false
	closed.emit()

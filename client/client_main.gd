extends Node
## 설치형 클라이언트 진입점. 화면 흐름: 서버 선택 → 로그인 → 공용 마을 → 원정 준비 → 전투방 → 결과 → 마을.
## 입력 의도만 서버로 보내고, 로컬 이동은 예측 후 서버 보정(ack seq 이후 입력 재적용)한다.

var launch_args: Dictionary = {}
var settings := ClientSettings.new()
var net: NetClient
var world: WorldView
var ui := CanvasLayer.new()
var connect_screen: ConnectScreen
var login_screen: LoginScreen
var hub_screen: HubScreen
var hud: RoomHud
var result_panel: ResultPanel
var overlay: DevOverlay
var bot: BotRunner = null
var mode: String = "connect"
var my_id: String = ""
var hub_info: Dictionary = {}
var roster: Array = []
var party: Dictionary = {}
var room: Dictionary = {}
var last_result: Dictionary = {}
var _seq: int = 0
var _pending: Array = []            # [{seq, mv, dt}]
var _pred_pos: Vector2 = Vector2.ZERO
var _me_snapshot: PackedFloat32Array = PackedFloat32Array()
var _room_players: Array = []
var _enemies_alive: int = 0
var _hub_positions: Dictionary = {}
var _auto_login_tried: bool = false
var _pending_addr: String = ""
var _pending_port: int = 0
var _chat_focus: bool = false
# 데모/스크린샷 모드 (--demo=<nick> --shots=<dir>): 자동으로 가입·출정하고 화면을 저장한다. 시각 검증용.
var demo: bool = false
var _demo_t: float = 0.0
var _demo_step: int = 0
var _shots_dir: String = ""


func _ready() -> void:
	settings.load()
	_setup_input_map()
	net = NetClient.new()
	net.name = "NetClient"
	add_child(net)
	world = WorldView.new()
	world.name = "World"
	world.ally_vfx_alpha = float(settings.data.get("ally_vfx_alpha", 0.7))
	add_child(world)
	add_child(ui)
	if launch_args.has("bot"):
		bot = BotRunner.new()
		bot.name = "Bot"
		add_child(bot)
		bot.start(net, launch_args)
		return
	ui.layer = 10
	var theme := UIKit.theme()
	var root := Control.new()
	root.name = "UIRoot"
	root.theme = theme
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root)
	connect_screen = ConnectScreen.new()
	login_screen = LoginScreen.new()
	hub_screen = HubScreen.new()
	hud = RoomHud.new()
	result_panel = ResultPanel.new()
	overlay = DevOverlay.new()
	for s: Control in [connect_screen, login_screen, hub_screen, hud, result_panel]:
		root.add_child(s)
		s.visible = false
	root.add_child(overlay)
	overlay.visible = bool(settings.data.get("show_dev_overlay", false))
	connect_screen.refresh(settings)
	connect_screen.connect_requested.connect(_on_connect_requested)
	login_screen.login_requested.connect(func(n: String, p: String) -> void: _auth(Protocol.C.LOGIN, {"nick": n, "password": p}))
	login_screen.register_requested.connect(func(n: String, p: String) -> void: _auth(Protocol.C.REGISTER, {"nick": n, "password": p}))
	login_screen.back_requested.connect(func() -> void: net.disconnect_from_server(""); _set_mode("connect"))
	hub_screen.create_requested.connect(func() -> void: net.send(Protocol.C.BOARD_CREATE, {"public": true, "difficulty": "normal", "class_id": "guardian"}))
	hub_screen.join_requested.connect(func(id: String) -> void: net.send(Protocol.C.BOARD_JOIN, {"expedition_id": id, "class_id": "guardian"}))
	hub_screen.leave_requested.connect(func() -> void: net.send(Protocol.C.BOARD_LEAVE))
	hub_screen.ready_toggled.connect(func(r: bool) -> void: net.send(Protocol.C.READY, {"ready": r, "class_id": "guardian"}))
	hub_screen.start_requested.connect(func() -> void: net.send(Protocol.C.BOARD_START))
	hub_screen.logout_requested.connect(func() -> void: settings.clear_token(net.host, net.port); net.send(Protocol.C.LOGOUT))
	hub_screen.chat_sent.connect(func(t: String) -> void: net.send(Protocol.C.CHAT, {"text": t}))
	hud.chat_sent.connect(func(t: String) -> void: net.send(Protocol.C.CHAT, {"text": t}))
	result_panel.choice_made.connect(func(c: String) -> void: net.send(Protocol.C.ROOM_CHOICE, {"choice": c}))
	net.state_changed.connect(_on_net_state)
	net.hello_result.connect(_on_hello)
	net.auth_result.connect(_on_auth)
	net.message.connect(_on_message)
	net.snapshot.connect(_on_snapshot)
	net.disconnected.connect(_on_disconnected)
	_set_mode("connect")
	if bool(settings.data.get("fullscreen", false)):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	if launch_args.has("demo"):
		demo = true
		_shots_dir = String(launch_args.get("shots", "user://shots"))
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_shots_dir) if _shots_dir.begins_with("user://") else _shots_dir)
		overlay.visible = true
	if launch_args.has("connect"):
		var parts: PackedStringArray = String(launch_args["connect"]).split(":")
		_on_connect_requested(parts[0], int(parts[1]) if parts.size() > 1 else Protocol.DEFAULT_PORT)


func _setup_input_map() -> void:
	var binds := {
		"move_up": [KEY_W, KEY_UP], "move_down": [KEY_S, KEY_DOWN], "move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"dodge": [KEY_SPACE], "skill_q": [KEY_Q], "skill_e": [KEY_E], "skill_r": [KEY_R], "interact": [KEY_F], "heal": [KEY_1],
		"build": [KEY_B], "map": [KEY_TAB], "dev_overlay": [KEY_F3], "chat": [KEY_ENTER], "fullscreen": [KEY_F11],
	}
	for action: String in binds.keys():
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			for key: Key in binds[action]:
				var ev := InputEventKey.new()
				ev.physical_keycode = key
				InputMap.action_add_event(action, ev)
	if not InputMap.has_action("attack"):
		InputMap.add_action("attack")
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("attack", mb)


func _set_mode(m: String) -> void:
	mode = m
	if bot != null:
		return
	connect_screen.visible = m == "connect"
	login_screen.visible = m == "login"
	hub_screen.visible = m == "hub"
	hud.visible = m in ["room", "result"]
	result_panel.visible = m == "result"
	world.visible = m in ["hub", "room", "result"]


# ------------------------------------------------------------------ 접속·인증

func _on_connect_requested(addr: String, port: int) -> void:
	_pending_addr = addr
	_pending_port = port
	_auto_login_tried = false
	connect_screen.set_status("연결 중... %s:%d" % [addr, port], true)
	net.connect_to(addr, port)


func _on_net_state(state: int) -> void:
	if hud != null:
		hud.update_conn(state, net.ping_ms)


func _on_hello(p: Dictionary) -> void:
	if not bool(p.get("ok", false)):
		connect_screen.set_status(UIKit.error_text(String(p.get("error", "")), p))
		return
	settings.add_recent(_pending_addr, _pending_port)
	connect_screen.refresh(settings)
	login_screen.show_server(p.get("server", {}))
	login_screen.set_status("")
	login_screen.nick_edit.text = String(settings.data.get("last_nick", ""))
	_set_mode("login")
	if demo:
		_auto_login_tried = true
		await get_tree().create_timer(0.8).timeout
		_screenshot("01_login.png")
		net.send(Protocol.C.REGISTER, {"nick": String(launch_args["demo"]), "password": "demopass1"})
		return
	var saved := settings.token_for(_pending_addr, _pending_port)
	if not saved.is_empty() and not _auto_login_tried:
		_auto_login_tried = true
		login_screen.set_status("저장된 접속 정보로 로그인 중... (%s)" % saved.get("nick", ""), true)
		net.send(Protocol.C.LOGIN_TOKEN, {"account_id": saved["account_id"], "token": saved["token"]})


func _auth(type: int, payload: Dictionary) -> void:
	if payload["nick"] == "" or payload["password"] == "":
		login_screen.set_status("닉네임과 비밀번호를 입력하세요.")
		return
	settings.data["last_nick"] = payload["nick"]
	settings.save()
	login_screen.set_status("확인 중...", true)
	net.send(type, payload)


func _on_auth(p: Dictionary) -> void:
	if not bool(p.get("ok", false)):
		var code := String(p.get("error", ""))
		if code == Protocol.ERR_TOKEN_EXPIRED:
			settings.clear_token(net.host, net.port)
		login_screen.set_status(UIKit.error_text(code, p))
		if demo and code == Protocol.ERR_NICK_TAKEN:
			net.send(Protocol.C.LOGIN, {"nick": String(launch_args["demo"]), "password": "demopass1"})
		return
	my_id = String(net.account.get("id", ""))
	settings.store_token(net.host, net.port, my_id, net.token, String(net.account.get("nickname", "")))
	login_screen.set_status("로그인 성공. 월드 동기화 중...", true)


func _on_disconnected(reason: String) -> void:
	world.clear_entities()
	party = {}
	room = {}
	_set_mode("connect")
	connect_screen.set_status(UIKit.error_text(reason, net.last_error_payload))
	net.last_error_payload = {}


# ------------------------------------------------------------------ 서버 메시지

func _on_message(type: int, p: Dictionary) -> void:
	match type:
		Protocol.S.ENTER_HUB:
			hub_info = p.get("hub", {})
			roster = p.get("roster", [])
			party = {}
			room = {}
			var b: Array = hub_info.get("bounds", [0, 0, 1600, 1000])
			world.clear_entities()
			world.setup(Rect2(b[0], b[1], b[2], b[3]), "tile.willow.ground", hub_info.get("obstacles", []), [])
			var you: Dictionary = p.get("you", {})
			_pred_pos = Vector2(float(you.get("x", 800)), float(you.get("y", 600)))
			_pending.clear()
			world.camera.position = _pred_pos
			world.camera.reset_smoothing()
			hub_screen.show_hub(hub_info, roster, int(net.server_info.get("online", 0)), int(net.server_info.get("max_online", 0)))
			hub_screen.show_board(p.get("board", []), "")
			hub_screen.show_party({}, my_id)
			_set_mode("hub")
		Protocol.S.HUB_ROSTER:
			roster = p.get("roster", [])
			hub_screen.show_roster(roster, int(p.get("online", 0)), int(p.get("max_online", 0)))
		Protocol.S.BOARD_STATE:
			hub_screen.show_board(p.get("list", []), String(party.get("expedition_id", "")))
		Protocol.S.PARTY_STATE:
			party = p
			hub_screen.show_party(party, my_id)
			hub_screen.show_board(hub_screen._board, String(party.get("expedition_id", "")))
			if mode == "result":
				result_panel.show_choices(party.get("members", []))
		Protocol.S.ENTER_EXPEDITION:
			room = p
			var def: Dictionary = p.get("room_def", {})
			var b: Dictionary = def.get("bounds", {"x": 0, "y": 0, "w": 1200, "h": 800})
			world.clear_entities()
			world.setup(Rect2(b["x"], b["y"], b["w"], b["h"]), String(def.get("assets", {}).get("ground", "tile.willow.ground")), def.get("obstacles", []), def.get("water", []))
			_pending.clear()
			_me_snapshot = PackedFloat32Array()
			var spawns: Array = def.get("player_spawns", [[100, 100]])
			_pred_pos = Vector2(float(spawns[0][0]), float(spawns[0][1]))
			world.camera.position = _pred_pos
			world.camera.reset_smoothing()
			hud.update_room(room)
			hud.toast("%s — 기준 인원 %d" % [def.get("name_ko", "전투방"), int(p.get("n", 1))], 3.0)
			_set_mode("room")
		Protocol.S.ROOM_EVENTS:
			for ev: Dictionary in p.get("events", []):
				_on_room_event(ev)
		Protocol.S.ROOM_RESULT:
			last_result = p
			result_panel.show_result(p, room.get("party", []), my_id)
			result_panel.show_choices(party.get("members", []))
			_set_mode("result")
		Protocol.S.LEAVE_EXPEDITION:
			party = {}
			room = {}
		Protocol.S.ERROR:
			var code := String(p.get("error", ""))
			var text := UIKit.error_text(code, p)
			if mode == "hub":
				hub_screen.add_chat("서버", text, "hub")
			elif hud.visible:
				hud.toast(text, 3.0)
		Protocol.S.KICKED:
			pass
		Protocol.S.CHAT:
			if mode == "hub":
				hub_screen.add_chat(String(p.get("from", "?")), String(p.get("text", "")), String(p.get("scope", "hub")))
			else:
				hud.add_chat(String(p.get("from", "?")), String(p.get("text", "")))
		Protocol.S.PONG:
			hud.update_conn(net.state, net.ping_ms)


func _on_room_event(ev: Dictionary) -> void:
	var k := String(ev.get("k", ""))
	match k:
		"swing":
			var pos := Vector2(float(ev.get("x", 0)), float(ev.get("y", 0)))
			var f := Vector2(float(ev.get("fx", 1)), float(ev.get("fy", 0)))
			world.spawn_effect("vfx.hammer_swing", pos + f * 40.0 + Vector2(0, -24), f.angle())
			world.play_sound("sfx.hammer_hit" if int(ev.get("hits", 0)) > 0 else "sfx.dodge")
		"enemy_hit":
			var key := "e:%d" % int(ev.get("eid", 0))
			if world.entities.has(key):
				world.entities[key].flash()
			world.spawn_effect("vfx.hit_spark", Vector2(float(ev.get("x", 0)), float(ev.get("y", 0))) + Vector2(0, -30))
			world.play_sound("sfx.snail_hit")
		"enemy_died":
			world.play_sound("sfx.snail_death")
		"hit":
			var key := "p:" + String(ev.get("id", ""))
			if world.entities.has(key):
				world.entities[key].flash()
			if ev.get("id", "") == my_id:
				world.play_sound("sfx.player_hit")
				world.camera.offset = Vector2(randf_range(-4, 4), randf_range(-4, 4)) * float(settings.data.get("screen_shake", 1.0))
		"circle_hit":
			var key := "p:" + String(ev.get("id", ""))
			if world.entities.has(key):
				world.spawn_effect("vfx.tail_shockwave", world.entities[key].position + Vector2(0, -20))
			world.play_sound("sfx.tail_slam")
		"skill":
			var slot := String(ev.get("slot", ""))
			var pos := Vector2(float(ev.get("x", 0)), float(ev.get("y", 0)))
			if slot == "r":
				world.spawn_effect("vfx.great_tree", pos + Vector2(0, -20))
				world.play_sound("sfx.great_tree")
			elif slot == "q":
				world.play_sound("sfx.wood_block")
		"dodge":
			if ev.get("id", "") == my_id:
				world.play_sound("sfx.dodge")
		"player_downed":
			world.play_sound("sfx.down")
			hud.toast("%s 다운! F 키로 구조" % _nick_of(String(ev.get("id", ""))), 2.5)
		"rescued":
			var key := "p:" + String(ev.get("id", ""))
			if world.entities.has(key):
				world.spawn_effect("vfx.rescue_ring", world.entities[key].position, 0.0, 0.6)
			world.play_sound("sfx.rescue")
			hud.toast("%s 구조 완료" % _nick_of(String(ev.get("id", ""))), 2.0)
		"player_died":
			hud.toast("%s 사망" % _nick_of(String(ev.get("id", ""))), 2.0)
		"wave":
			hud.toast("웨이브 %d / %d" % [int(ev.get("index", 1)), int(ev.get("count", 1))], 2.0)
		"room_clear":
			hud.toast("방 클리어!", 3.0)
		"wipe":
			hud.toast("전멸... 기억나무가 원정대를 마을로 되돌립니다", 4.0)
		"heal":
			world.play_sound("sfx.rescue")


func _nick_of(id: String) -> String:
	for m: Dictionary in room.get("party", []):
		if m.get("id", "") == id:
			return String(m.get("nick", id))
	return id


# ------------------------------------------------------------------ 스냅샷

func _on_snapshot(p: Dictionary) -> void:
	if p.has("hub"):
		_apply_hub_snapshot(p)
	else:
		_apply_room_snapshot(p)


func _apply_hub_snapshot(p: Dictionary) -> void:
	if mode != "hub":
		return
	var keys: Array = []
	var idx := 0
	for e: Array in p.get("p", []):
		var id := String(e[0])
		var key := "p:" + id
		keys.append(key)
		var pos := Vector2(float(e[1]), float(e[2]))
		var ev := world.get_or_create(key, true, "char." + String(e[5]), pos)
		ev.entity_id = id
		ev.is_local = id == my_id
		ev.display_name = _roster_nick(id)
		ev.facing = Vector2(float(e[3]), float(e[4]))
		ev.hp = 1.0
		ev.max_hp = 1.0
		ev.party_color = world.party_color(idx)
		if ev.is_local:
			if _pred_pos.distance_to(pos) > 48.0:
				_pred_pos = pos
			ev.position = _pred_pos
		else:
			ev.target_pos = pos
		idx += 1
	world.remove_missing(keys, "p:")


func _roster_nick(id: String) -> String:
	for r: Dictionary in roster:
		if r.get("id", "") == id:
			return String(r.get("nick", ""))
	return ""


func _apply_room_snapshot(p: Dictionary) -> void:
	if mode not in ["room", "result"]:
		return
	var keys: Array = []
	_room_players = p.get("p", [])
	var party_list: Array = room.get("party", [])
	for entry: Array in _room_players:
		var id := String(entry[0])
		var e: PackedFloat32Array = entry[1]
		var key := "p:" + id
		keys.append(key)
		var pos := Vector2(e[Protocol.SNAP_P.X], e[Protocol.SNAP_P.Y])
		var class_id := "guardian"
		var pidx := 0
		for i in party_list.size():
			if party_list[i].get("id", "") == id:
				class_id = String(party_list[i].get("class_id", "guardian"))
				pidx = i
		var ev := world.get_or_create(key, true, "char." + class_id, pos)
		ev.entity_id = id
		ev.is_local = id == my_id
		ev.display_name = _nick_of(id)
		ev.facing = Vector2(e[Protocol.SNAP_P.FX], e[Protocol.SNAP_P.FY])
		ev.hp = e[Protocol.SNAP_P.HP]
		ev.max_hp = float(ContentDB.get_class_def(class_id).get("base_hp", 100))
		ev.state = int(e[Protocol.SNAP_P.STATE])
		ev.action = int(e[Protocol.SNAP_P.ACTION])
		ev.shield = e[Protocol.SNAP_P.SHIELD]
		ev.down_t = e[Protocol.SNAP_P.DOWN_T]
		ev.invuln = e[Protocol.SNAP_P.INVULN] > 0.5
		ev.rescue_t = e[Protocol.SNAP_P.RESCUE_T]
		ev.connected = e[Protocol.SNAP_P.CONNECTED] > 0.5
		ev.front_guard = e[Protocol.SNAP_P.FRONT_GUARD] > 0.5
		ev.party_color = world.party_color(pidx)
		if ev.is_local:
			_me_snapshot = e
			_reconcile(pos, int(p.get("ack", 0)), e)
			ev.position = _pred_pos
		else:
			ev.target_pos = pos
	world.remove_missing(keys, "p:")
	var ekeys: Array = []
	_enemies_alive = 0
	for entry: Array in p.get("e", []):
		var e: PackedFloat32Array = entry[2]
		var key := "e:%d" % int(entry[0])
		ekeys.append(key)
		var pos := Vector2(e[Protocol.SNAP_E.X], e[Protocol.SNAP_E.Y])
		var ev := world.get_or_create(key, false, "enemy." + String(entry[1]), pos)
		ev.entity_id = int(entry[0])
		ev.facing = Vector2(e[Protocol.SNAP_E.FX], e[Protocol.SNAP_E.FY])
		ev.hp = e[Protocol.SNAP_E.HP]
		ev.max_hp = e[Protocol.SNAP_E.MAX_HP]
		ev.ai_state = int(e[Protocol.SNAP_E.AI])
		ev.target_pos = pos
		if ev.ai_state != Protocol.EnemyAI.DEAD:
			_enemies_alive += 1
	world.remove_missing(ekeys, "e:")
	world.telegraphs = p.get("tg", [])
	if hud != null:
		hud.update_wave(p.get("wave", [0, 0]), _enemies_alive)
		hud.update_party(_room_players, party_list, my_id)
		if not _me_snapshot.is_empty():
			hud.update_me(_me_snapshot, ContentDB.get_class_def(_my_class()))


func _my_class() -> String:
	for m: Dictionary in room.get("party", []):
		if m.get("id", "") == my_id:
			return String(m.get("class_id", "guardian"))
	return "guardian"


func _reconcile(server_pos: Vector2, ack: int, me: PackedFloat32Array) -> void:
	# 서버 위치를 기준으로 삼고, 아직 확인되지 않은 입력을 다시 적용한다.
	while not _pending.is_empty() and int(_pending[0]["seq"]) <= ack:
		_pending.pop_front()
	var pos := server_pos
	var movable := int(me[Protocol.SNAP_P.STATE]) == Protocol.EntState.ALIVE and int(me[Protocol.SNAP_P.ACTION]) in [Protocol.Action.IDLE, Protocol.Action.RECOVERY]
	if movable:
		var speed := float(ContentDB.get_class_def(_my_class()).get("move_speed", 180))
		for inp: Dictionary in _pending:
			pos = SimRules.move(pos, inp["mv"], speed, float(inp["dt"]), world.bounds, 18.0, room.get("room_def", {}).get("obstacles", []))
	if _pred_pos.distance_to(pos) > 2.0:
		_pred_pos = _pred_pos.lerp(pos, 0.5) if _pred_pos.distance_to(pos) < 60.0 else pos


# ------------------------------------------------------------------ 입력

func _unhandled_input(event: InputEvent) -> void:
	if bot != null:
		return
	if event.is_action_pressed("dev_overlay"):
		overlay.visible = not overlay.visible
		settings.data["show_dev_overlay"] = overlay.visible
		settings.save()
	if event.is_action_pressed("fullscreen"):
		var fs := DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fs else DisplayServer.WINDOW_MODE_WINDOWED)
		settings.data["fullscreen"] = fs
		settings.save()
	if event.is_action_pressed("chat"):
		if mode == "hub":
			hub_screen.chat_edit.grab_focus()
		elif mode in ["room", "result"]:
			hud.chat_edit.grab_focus()


func _text_focused() -> bool:
	var f := get_viewport().gui_get_focus_owner()
	return f != null and (f is LineEdit)


func _physics_process(dt: float) -> void:
	if bot != null or not net.is_online():
		return
	if mode not in ["hub", "room"]:
		return
	var mv := Vector2.ZERO
	var btn := 0
	var demo_in := {}
	if demo:
		demo_in = _demo_input()
		mv = demo_in["mv"]
		btn = demo_in["btn"]
	elif not _text_focused():
		mv = Input.get_vector("move_left", "move_right", "move_up", "move_down")
		if Input.is_action_pressed("attack"): btn |= Protocol.BTN_ATTACK
		if Input.is_action_just_pressed("dodge") or Input.is_action_pressed("dodge"): btn |= Protocol.BTN_DODGE
		if Input.is_action_pressed("skill_q"): btn |= Protocol.BTN_Q
		if Input.is_action_pressed("skill_e"): btn |= Protocol.BTN_E
		if Input.is_action_pressed("skill_r"): btn |= Protocol.BTN_R
		if Input.is_action_pressed("interact"): btn |= Protocol.BTN_INTERACT
		if Input.is_action_pressed("heal"): btn |= Protocol.BTN_HEAL
	var aim: Vector2 = demo_in["aim"] if demo else (world.get_global_mouse_position() - _pred_pos + Vector2(0, 24))
	_seq += 1
	net.send_input(_seq, mv, aim, btn)
	var speed := 200.0
	var obstacles: Array = hub_info.get("obstacles", []) if mode == "hub" else room.get("room_def", {}).get("obstacles", [])
	var movable := true
	if mode == "room":
		speed = float(ContentDB.get_class_def(_my_class()).get("move_speed", 180))
		if not _me_snapshot.is_empty():
			movable = int(_me_snapshot[Protocol.SNAP_P.STATE]) == Protocol.EntState.ALIVE and int(_me_snapshot[Protocol.SNAP_P.ACTION]) in [Protocol.Action.IDLE, Protocol.Action.RECOVERY]
		_pending.append({"seq": _seq, "mv": mv, "dt": dt})
		if _pending.size() > 60:
			_pending.pop_front()
	if movable and mv.length_squared() > 0.0:
		_pred_pos = SimRules.move(_pred_pos, mv, speed, dt, world.bounds, 18.0, obstacles)
	var mine: EntityView = world.entities.get("p:" + my_id, null)
	if mine != null:
		mine.position = _pred_pos
		if aim.length_squared() > 1.0 and mv.length_squared() < 0.01:
			mine.facing = aim.normalized()
		elif mv.length_squared() > 0.01:
			mine.facing = mv.normalized()


func _screenshot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img != null:
		var path := _shots_dir.path_join(name)
		img.save_png(path)
		print("[demo] screenshot " + path)


func _demo_tick(dt: float) -> void:
	_demo_t += dt
	match mode:
		"hub":
			if _demo_step == 0 and _demo_t > 1.0:
				_demo_step = 1
				_screenshot("02_hub.png")
			elif _demo_step == 1 and _demo_t > 1.6 and party.is_empty():
				_demo_step = 2
				net.send(Protocol.C.BOARD_CREATE, {"public": true, "difficulty": "normal", "class_id": "guardian"})
			elif _demo_step == 2 and not party.is_empty() and _demo_t > 2.2:
				_demo_step = 3
				net.send(Protocol.C.READY, {"ready": true, "class_id": "guardian"})
			elif _demo_step == 3 and _demo_t > 2.8:
				_demo_step = 4
				_screenshot("03_party.png")
				net.send(Protocol.C.BOARD_START)
		"room":
			if _demo_step == 4:
				_demo_step = 5
				_demo_t = 0.0
			elif _demo_step == 5 and _demo_t > 2.0:
				_demo_step = 6
				_screenshot("04_room.png")
			elif _demo_step == 6 and _demo_t > 6.0:
				_demo_step = 7
				_screenshot("05_room_combat.png")
			elif _demo_step == 7 and _demo_t > 12.0:
				_demo_step = 8
				_screenshot("06_room_late.png")
		"result":
			if _demo_step < 9:
				_demo_step = 9
				_demo_t = 0.0
			elif _demo_step == 9 and _demo_t > 0.8:
				_demo_step = 10
				_screenshot("07_result.png")
				await get_tree().create_timer(0.5).timeout
				get_tree().quit()
	if _demo_t > 60.0:
		get_tree().quit(1)


## 데모 모드의 자동 입력: 가장 가까운 적에게 접근해 공격하고, 예고 범위에서는 회피한다.
func _demo_input() -> Dictionary:
	var mv := Vector2.ZERO
	var btn := 0
	var aim := Vector2.RIGHT * 10
	if mode != "room" or _me_snapshot.is_empty():
		return {"mv": mv, "btn": btn, "aim": aim}
	var best := 1e9
	var target := Vector2.ZERO
	for k: String in world.entities.keys():
		if k.begins_with("e:"):
			var ev: EntityView = world.entities[k]
			if ev.ai_state == Protocol.EnemyAI.DEAD:
				continue
			var d := ev.position.distance_to(_pred_pos)
			if d < best:
				best = d
				target = ev.position
	if best < 1e8:
		aim = target - _pred_pos
		var danger := false
		for tg: PackedFloat32Array in world.telegraphs:
			if Vector2(tg[0], tg[1]).distance_to(_pred_pos) < tg[2] + 20 and tg[3] < 0.35:
				danger = true
		if danger and int(_me_snapshot[Protocol.SNAP_P.DODGE]) > 0:
			mv = -aim.normalized()
			btn |= Protocol.BTN_DODGE
		elif best > 60.0:
			mv = aim.normalized()
		else:
			btn |= Protocol.BTN_ATTACK
			if _me_snapshot[Protocol.SNAP_P.CD_E] <= 0.0:
				btn |= Protocol.BTN_E
	return {"mv": mv, "btn": btn, "aim": aim}


func _process(dt: float) -> void:
	if bot != null:
		return
	if demo:
		_demo_tick(dt)
	world.camera.position = _pred_pos
	world.camera.offset = world.camera.offset.lerp(Vector2.ZERO, 0.2)
	if overlay.visible:
		overlay.update_info(net, world, room, _seq, _pending.size())

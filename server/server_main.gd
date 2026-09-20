extends Node
## 전용 서버 진입점. ENet 으로 접속을 받고, 세션·인증·공용 마을·원정 인스턴스를 서버 시간으로 구동한다.
## 클라이언트는 입력 의도만 보내며 피해·재화·위치를 확정하지 못한다 (15절).

var launch_args: Dictionary = {}
var config := ServerConfig.new()
var store: StoreBase
var auth: AuthService
var hub: HubWorld
var expeditions: ExpeditionManager
var sessions: Dictionary = {}          # peer_id -> Session
var world: Dictionary = {}
var peer: ENetMultiplayerPeer
var log_level: int = 1                 # 0=debug 1=info 2=warn 3=error
var started_at: float
var _hub_snap_accum: int = 0
var _metrics_accum: float = 0.0
var _flush_accum: float = 0.0
var _tick_ms_accum: float = 0.0
var _tick_count: int = 0
var _tick_ms_max: float = 0.0
var _snap_max_bytes: int = 0
var metrics := {"connections": 0, "logins": 0, "rejected_full": 0, "rejected_version": 0, "save_failures": 0, "expeditions_started": 0, "rooms_cleared": 0, "wipes": 0}
var shutting_down: bool = false
var status_file: String = ""
var stop_file: String = ""
var _log_file: FileAccess = null
var _stop_check_accum: float = 0.0


func _ready() -> void:
	started_at = Time.get_unix_time_from_system()
	var cfg_path: String = String(launch_args.get("config", ServerConfig.default_config_path()))
	config.load(cfg_path, launch_args)
	log_level = {"debug": 0, "info": 1, "warn": 2, "error": 3}.get(String(config.get_value("log_level")), 1)
	_open_log_file(String(config.get_value("data_dir")))
	_log(1, "server build %s protocol %d content %s" % [Protocol.BUILD_VERSION, Protocol.PROTOCOL_VERSION, Protocol.CONTENT_VERSION])
	_log(1, "config %s (from_file=%s)" % [cfg_path, config.loaded_from_file])
	if not ContentDB.load_errors.is_empty():
		_log(3, "content data errors: %s" % ", ".join(ContentDB.load_errors))
	# 저장소와 월드
	store = JsonFileStore.new(String(config.get_value("data_dir")))
	var err := store.open()
	if err != OK:
		_log(3, "store open failed: %s" % error_string(err))
		get_tree().quit(2)
		return
	_log(1, "store %s accounts=%d" % [store.describe(), store.account_count()])
	world = store.load_world()
	if world.is_empty():
		var wid: String = String(config.get_value("world_id"))
		if wid == "":
			wid = "world_" + Crypto.new().generate_random_bytes(6).hex_encode()
		world = HubWorld.new_world(wid, String(config.get_value("world_name")))
		_log(1, "created new persistent world %s" % wid)
	else:
		_log(1, "loaded persistent world %s (created %d, boots %d)" % [world.get("world_id", "?"), int(world.get("created_at", 0)), int(world.get("boot_count", 0))])
	world["boot_count"] = int(world.get("boot_count", 0)) + 1
	if store.save_world(world) != OK:
		_log(3, "world save failed at boot")
	hub = HubWorld.new()
	hub.world = world
	auth = AuthService.new(store, int(config.get_value("password_iterations")), int(config.get_value("token_ttl_days")))
	auth.lockout_sec = float(config.get_value("login_fail_lockout_sec"))
	auth.fail_max = int(config.get_value("login_fail_max"))
	expeditions = ExpeditionManager.new(int(config.get_value("max_active_expeditions")), int(Time.get_ticks_usec()))
	ExpeditionInstance.debug_route_layers = int(config.get_value("debug_route_layers"))
	if ExpeditionInstance.debug_route_layers > 0:
		_log(2, "debug_route_layers=%d: routes are truncated (test configuration)" % ExpeditionInstance.debug_route_layers)
	ExpeditionInstance.debug_boss = String(config.get_value("debug_boss"))
	if ExpeditionInstance.debug_boss != "":
		_log(2, "debug_boss=%s: every expedition is a single boss room (practice/test configuration)" % ExpeditionInstance.debug_boss)
	_restore_expeditions()
	# 네트워크
	peer = ENetMultiplayerPeer.new()
	var bind: String = String(config.get_value("bind_address"))
	if bind != "*" and bind != "":
		peer.set_bind_ip(bind)
	var port := int(config.get_value("port"))
	err = peer.create_server(port, 64)
	if err != OK:
		_log(3, "cannot bind port %d: %s" % [port, error_string(err)])
		get_tree().quit(3)
		return
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	Net.client_message.connect(_on_client_message)
	Net.client_input.connect(_on_client_input)
	Engine.physics_ticks_per_second = int(ContentDB.rule("server_sim_hz", 30))
	status_file = String(config.get_value("data_dir")).path_join("server_status.json")
	stop_file = String(config.get_value("data_dir")).path_join("STOP")
	if FileAccess.file_exists(stop_file):
		DirAccess.remove_absolute(stop_file)
	_write_status()
	_log(1, "listening on %s:%d  max_online=%d max_expeditions=%d party=%d registration=%s" % [bind, port, int(config.get_value("max_online_players")), int(config.get_value("max_active_expeditions")), Protocol.MAX_PARTY_SIZE, config.get_value("allow_registration")])
	_log(1, "world persists with 0 players online; hub '%s' ready" % world.get("name", ""))


## 서버 재시작 후 안전 지점 체크포인트를 복구한다. 유예 시간이 지난 원정은 버린다.
func _restore_expeditions() -> void:
	var grace := float(ContentDB.rule("checkpoint_grace_sec", 600.0))
	var now := Time.get_unix_time_from_system()
	for cid: String in store.load_expeditions().keys():
		var cp: Dictionary = store.load_expeditions()[cid]
		if now - float(cp.get("saved_at", 0)) > grace or String(cp.get("content_version", "")) != Protocol.CONTENT_VERSION:
			store.delete_expedition(cid)
			_log(1, "discarded stale checkpoint %s" % cid)
			continue
		var inst := ExpeditionInstance.from_checkpoint(cp)
		expeditions.instances[inst.id] = inst
		_log(1, "restored expedition %s at state %d (members %d, note %s)" % [inst.id, inst.state, inst.member_count(), inst.run.get("checkpoint_note", "")])


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_CRASH or what == NOTIFICATION_EXIT_TREE:
		_shutdown()


## 정상 종료: 신규 출정을 막고, 접속자에게 알린 뒤 저장을 플러시한다. STOP 파일(scripts/stop_server.sh) 또는 창 닫기로 진입한다.
func _shutdown() -> void:
	if shutting_down:
		return
	shutting_down = true
	for s: Session in sessions.values():
		Net.send_to_peer(s.peer_id, Protocol.S.KICKED, {"error": "SERVER_SHUTDOWN", "message": "서버가 종료됩니다. 진행 기록은 저장되었습니다."})
	if store != null:
		var err := store.flush()
		_log(1, "shutdown flush: %s (online=%d, expeditions=%d)" % [error_string(err), _online_count(), expeditions.active_count() if expeditions else 0])
		store.close()
	_write_status(true)
	if _log_file != null:
		_log_file.close()
		_log_file = null


func _open_log_file(data_dir: String) -> void:
	var dir := data_dir.path_join("logs")
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join("server-%s.log" % Time.get_date_string_from_system(true))
	_log_file = FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if _log_file != null:
		_log_file.seek_end()


func request_stop(reason: String) -> void:
	_log(1, "stop requested: %s" % reason)
	_shutdown()
	if peer != null:
		peer.close()
	get_tree().quit(0)


# ------------------------------------------------------------------ 로그·상태

func _log(level: int, msg: String) -> void:
	if level < log_level:
		return
	var tag: String = ["DEBUG", "INFO", "WARN", "ERROR"][clampi(level, 0, 3)]
	var line := "[%s] [%s] %s" % [Time.get_datetime_string_from_system(true, true), tag, msg]
	print(line)
	if _log_file != null:
		_log_file.store_line(line)
		_log_file.flush()


func _online_count() -> int:
	var c := 0
	for s: Session in sessions.values():
		if s.is_authed():
			c += 1
	return c


func _write_status(stopped: bool = false) -> void:
	var f := FileAccess.open(status_file, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({
		"stopped": stopped, "world_id": world.get("world_id", ""), "port": config.get_value("port"), "online": _online_count(),
		"max_online": config.get_value("max_online_players"), "active_expeditions": expeditions.active_count() if expeditions else 0,
		"uptime_sec": Time.get_unix_time_from_system() - started_at, "metrics": metrics, "build": Protocol.BUILD_VERSION,
		"tick_ms_avg": (_tick_ms_accum / _tick_count) if _tick_count > 0 else 0.0, "tick_ms_max": _tick_ms_max,
	}, "  "))
	f.close()


# ------------------------------------------------------------------ 접속

func _on_peer_connected(id: int) -> void:
	sessions[id] = Session.new(id)
	metrics["connections"] += 1
	_log(0, "peer %d connected" % id)


func _on_peer_disconnected(id: int) -> void:
	var s: Session = sessions.get(id, null)
	if s == null:
		return
	sessions.erase(id)
	if s.is_authed():
		_log(1, "%s (%s) disconnected" % [s.nickname, s.account_id])
		if hub.has(s.account_id):
			hub.leave(s.account_id)
			_broadcast_hub_roster()
		var inst := expeditions.get_for_session(s)
		if inst != null:
			if inst.state == Protocol.ExpState.PREPARING:
				# 준비 중 이탈은 즉시 파티에서 제외한다. 전투·결과 중에는 유예 시간 동안 슬롯을 남긴다.
				expeditions.leave(s)
				if inst.state != Protocol.ExpState.CLOSED:
					_broadcast_party(inst)
			else:
				inst.mark_disconnected(s.account_id)
				_broadcast_party(inst)
				if inst.suspended:
					_log(1, "expedition %s suspended (all members offline)" % inst.id)
			_broadcast_board()
	else:
		_log(0, "peer %d disconnected before auth" % id)


func _kick(s: Session, code: String, msg: String = "") -> void:
	Net.send_to_peer(s.peer_id, Protocol.S.KICKED, {"error": code, "message": msg})
	_disconnect_later(s.peer_id)


func _disconnect_later(peer_id: int) -> void:
	await get_tree().create_timer(0.25).timeout
	if sessions.has(peer_id) and peer != null:
		peer.disconnect_peer(peer_id, false)


func _err(s: Session, code: String, extra: Dictionary = {}) -> void:
	var payload := {"error": code}
	payload.merge(extra)
	Net.send_to_peer(s.peer_id, Protocol.S.ERROR, payload)


# ------------------------------------------------------------------ 메시지

func _on_client_message(peer_id: int, type: int, payload: Dictionary) -> void:
	var s: Session = sessions.get(peer_id, null)
	if s == null:
		return
	# 요청 속도 제한: 초당 30개
	var now := Time.get_unix_time_from_system()
	if now - s.msg_window_start > 1.0:
		s.msg_window_start = now
		s.msg_count_window = 0
	s.msg_count_window += 1
	if s.msg_count_window > 30:
		if s.msg_count_window == 31:
			_err(s, Protocol.ERR_RATE_LIMITED)
		return
	if type == Protocol.C.HELLO:
		_handle_hello(s, payload)
		return
	if s.state == Session.State.CONNECTED:
		_err(s, Protocol.ERR_BAD_STATE, {"message": "hello first"})
		return
	match type:
		Protocol.C.REGISTER: _handle_register(s, payload)
		Protocol.C.LOGIN: _handle_login(s, payload)
		Protocol.C.LOGIN_TOKEN: _handle_login_token(s, payload)
		Protocol.C.PING: Net.send_to_peer(peer_id, Protocol.S.PONG, {"t": payload.get("t", 0), "tick_ms": (_tick_ms_accum / _tick_count) if _tick_count > 0 else 0.0, "online": _online_count(), "expeditions": expeditions.active_count()})
		_:
			if not s.is_authed():
				_err(s, Protocol.ERR_NOT_AUTHED)
				return
			match type:
				Protocol.C.LOGOUT: _handle_logout(s)
				Protocol.C.BOARD_LIST: Net.send_to_peer(peer_id, Protocol.S.BOARD_STATE, {"list": _board_for(s.account_id)})
				Protocol.C.BOARD_CREATE: _handle_board_create(s, payload)
				Protocol.C.BOARD_JOIN: _handle_board_join(s, payload)
				Protocol.C.BOARD_LEAVE: _handle_board_leave(s)
				Protocol.C.READY: _handle_ready(s, payload)
				Protocol.C.BOARD_START: _handle_board_start(s)
				Protocol.C.ROOM_CHOICE: _handle_room_choice(s, payload)
				Protocol.C.REWARD_PICK: _handle_reward_pick(s, payload)
				Protocol.C.ROUTE_VOTE: _handle_route_vote(s, payload)
				Protocol.C.NODE_ACTION: _handle_node_action(s, payload)
				Protocol.C.CHAT: _handle_chat(s, payload)
				Protocol.C.HUB_UPGRADE: _handle_hub_upgrade(s, payload)
				Protocol.C.MASTERY_TRAIT: _handle_mastery_trait(s, payload)
				Protocol.C.BUILD_SELECT: _handle_build_select(s, payload)
				Protocol.C.NPC_TALK: _handle_npc_talk(s, payload)
				Protocol.C.QUEST_ACTION: _handle_quest_action(s, payload)
				Protocol.C.EXPEDITION_PAUSE: _handle_expedition_pause(s)
				Protocol.C.MARK: _handle_mark(s, payload)
				_: _err(s, Protocol.ERR_BAD_STATE, {"message": "unknown message %d" % type})


func _handle_hello(s: Session, payload: Dictionary) -> void:
	var proto := int(payload.get("protocol", -1))
	var content := String(payload.get("content", ""))
	s.client_build = String(payload.get("build", ""))
	var required := Protocol.version_info()
	if proto != Protocol.PROTOCOL_VERSION or content != Protocol.CONTENT_VERSION:
		metrics["rejected_version"] += 1
		Net.send_to_peer(s.peer_id, Protocol.S.HELLO_RESULT, {"ok": false, "error": Protocol.ERR_VERSION_MISMATCH, "required": required, "got": {"protocol": proto, "content": content}, "update_url": "https://github.com/oks9924/Beaver-RPG/releases"})
		_log(1, "peer %d rejected: version mismatch (proto %d content %s build %s)" % [s.peer_id, proto, content, s.client_build])
		_disconnect_later(s.peer_id)
		return
	if bool(config.get_value("maintenance")):
		Net.send_to_peer(s.peer_id, Protocol.S.HELLO_RESULT, {"ok": false, "error": "MAINTENANCE", "required": required})
		_disconnect_later(s.peer_id)
		return
	s.state = Session.State.HELLO_OK
	Net.send_to_peer(s.peer_id, Protocol.S.HELLO_RESULT, {"ok": true, "server": _server_info()})


func _server_info() -> Dictionary:
	return {
		"name": world.get("name", ""), "world_id": world.get("world_id", ""), "online": _online_count(),
		"max_online": int(config.get_value("max_online_players")), "active_expeditions": expeditions.active_count(),
		"max_expeditions": int(config.get_value("max_active_expeditions")), "allow_registration": bool(config.get_value("allow_registration")),
		"version": Protocol.version_info(), "party_max": Protocol.MAX_PARTY_SIZE,
	}


func _handle_register(s: Session, payload: Dictionary) -> void:
	if s.is_authed():
		_err(s, Protocol.ERR_BAD_STATE)
		return
	if not bool(config.get_value("allow_registration")):
		Net.send_to_peer(s.peer_id, Protocol.S.AUTH_RESULT, {"ok": false, "error": Protocol.ERR_REGISTRATION_DISABLED})
		return
	var r := auth.register(String(payload.get("nick", "")), String(payload.get("password", "")))
	if not r["ok"]:
		Net.send_to_peer(s.peer_id, Protocol.S.AUTH_RESULT, {"ok": false, "error": r["error"]})
		return
	var account: Dictionary = r["account"]
	var token := auth.issue_token(account)
	account["stats"]["logins"] = 1
	if store.put_account(account) != OK:
		metrics["save_failures"] += 1
		Net.send_to_peer(s.peer_id, Protocol.S.AUTH_RESULT, {"ok": false, "error": Protocol.ERR_SAVE_FAILED})
		return
	_log(1, "registered account %s (%s)" % [account["nickname"], account["id"]])
	_finish_login(s, account, token, true)


func _handle_login(s: Session, payload: Dictionary) -> void:
	if s.is_authed():
		_err(s, Protocol.ERR_BAD_STATE)
		return
	s.login_attempts += 1
	if s.login_attempts > 8:
		_kick(s, Protocol.ERR_RATE_LIMITED)
		return
	var r := auth.login(String(payload.get("nick", "")), String(payload.get("password", "")))
	if not r["ok"]:
		Net.send_to_peer(s.peer_id, Protocol.S.AUTH_RESULT, {"ok": false, "error": r["error"]})
		return
	_finish_login(s, r["account"], r["token"], false)


func _handle_login_token(s: Session, payload: Dictionary) -> void:
	if s.is_authed():
		_err(s, Protocol.ERR_BAD_STATE)
		return
	s.login_attempts += 1
	var r := auth.login_with_token(String(payload.get("account_id", "")), String(payload.get("token", "")))
	if not r["ok"]:
		Net.send_to_peer(s.peer_id, Protocol.S.AUTH_RESULT, {"ok": false, "error": r["error"]})
		return
	_finish_login(s, r["account"], r["token"], false)


func _session_for_account(account_id: String) -> Session:
	for o: Session in sessions.values():
		if o.is_authed() and o.account_id == account_id:
			return o
	return null


func _finish_login(s: Session, account: Dictionary, token: String, is_new: bool) -> void:
	var aid: String = account["id"]
	if _session_for_account(aid) != null:
		Net.send_to_peer(s.peer_id, Protocol.S.AUTH_RESULT, {"ok": false, "error": Protocol.ERR_ALREADY_ONLINE})
		return
	var reserved := expeditions.find_by_member(aid)
	var max_online := int(config.get_value("max_online_players"))
	if _online_count() >= max_online and reserved == null:
		metrics["rejected_full"] += 1
		Net.send_to_peer(s.peer_id, Protocol.S.AUTH_RESULT, {"ok": false, "error": Protocol.ERR_SERVER_FULL, "online": _online_count(), "max_online": max_online})
		_log(1, "login rejected (server full) for %s" % account["nickname"])
		return
	s.state = Session.State.AUTHED
	s.account_id = aid
	s.nickname = account["nickname"]
	var unlocked: Array = account["progression"].get("unlocked_classes", ["guardian"])
	s.class_id = String(unlocked[0]) if not unlocked.is_empty() else "guardian"
	metrics["logins"] += 1
	Net.send_to_peer(s.peer_id, Protocol.S.AUTH_RESULT, {"ok": true, "account": _public_account(account), "token": token, "new_account": is_new, "server": _server_info()})
	_log(1, "%s logged in (%s) online=%d/%d" % [s.nickname, aid, _online_count(), max_online])
	if reserved != null:
		reserved.mark_reconnected(s)
		_log(1, "%s reconnected to expedition %s (state %d)" % [s.nickname, reserved.id, reserved.state])
		if reserved.state == Protocol.ExpState.PREPARING:
			_enter_hub(s)
		_flush_outbox(reserved)
		_broadcast_party(reserved)
		return
	_enter_hub(s)


func _public_account(account: Dictionary) -> Dictionary:
	return {"id": account["id"], "nickname": account["nickname"], "created_at": account["created_at"], "last_login_at": account.get("last_login_at", 0), "stats": account["stats"], "progression": account["progression"]}


func _enter_hub(s: Session) -> void:
	hub.enter(s)
	s.expedition_id = ""
	Net.send_to_peer(s.peer_id, Protocol.S.ENTER_HUB, {"hub": hub.hub_info(), "roster": hub.roster(), "board": _board_for(s.account_id), "you": {"id": s.account_id, "x": s.hub_pos.x, "y": s.hub_pos.y}})
	_broadcast_hub_roster()


func _handle_logout(s: Session) -> void:
	var inst := expeditions.get_for_session(s)
	if inst != null and inst.state != Protocol.ExpState.IN_ROOM:
		expeditions.leave(s)
		if inst.state != Protocol.ExpState.CLOSED:
			_broadcast_party(inst)
	_kick(s, "LOGOUT", "bye")


# ------------------------------------------------------------------ 원정 모집판

func _handle_board_create(s: Session, payload: Dictionary) -> void:
	if s.location != Protocol.Location.HUB:
		_err(s, Protocol.ERR_BAD_STATE)
		return
	var class_id := String(payload.get("class_id", s.class_id))
	if not ContentDB.is_class_playable(class_id):
		_err(s, Protocol.ERR_BAD_CONTENT_ID, {"message": class_id})
		return
	s.class_id = class_id
	var r := expeditions.create(s, bool(payload.get("public", true)), String(payload.get("difficulty", "normal")), _permanent_bonus(s.account_id), bool(payload.get("tutorial", false)))
	if not r["ok"]:
		_err(s, r["error"], {"active": expeditions.active_count(), "max": expeditions.max_active})
		return
	var inst: ExpeditionInstance = r["expedition"]
	inst.members[s.account_id]["trait"] = _trait_for(s.account_id, s.class_id)
	_log(1, "%s created expedition %s" % [s.nickname, inst.id])
	_broadcast_party(inst)
	_broadcast_board()


func _handle_board_join(s: Session, payload: Dictionary) -> void:
	if s.location != Protocol.Location.HUB:
		_err(s, Protocol.ERR_BAD_STATE)
		return
	var class_id := String(payload.get("class_id", s.class_id))
	if ContentDB.is_class_playable(class_id):
		s.class_id = class_id
	var r := expeditions.join(s, String(payload.get("expedition_id", "")), _permanent_bonus(s.account_id))
	if not r["ok"]:
		_err(s, r["error"], {"expedition_id": payload.get("expedition_id", "")})
		return
	var inst: ExpeditionInstance = r["expedition"]
	if bool(r.get("resumed", false)):
		_log(1, "%s resumed paused expedition %s" % [s.nickname, inst.id])
		if hub.has(s.account_id):
			hub.leave(s.account_id)
			_broadcast_hub_roster()
		_flush_outbox(inst)
		_broadcast_party(inst)
		_broadcast_board()
		return
	inst.members[s.account_id]["trait"] = _trait_for(s.account_id, s.class_id)
	_log(1, "%s joined expedition %s (%d/%d, state %d)" % [s.nickname, inst.id, inst.member_count(), Protocol.MAX_PARTY_SIZE, inst.state])
	if inst.is_safe_point():
		if hub.has(s.account_id):
			hub.leave(s.account_id)
			_broadcast_hub_roster()
		_flush_outbox(inst)
	_broadcast_party(inst)
	_broadcast_board()


func _handle_board_leave(s: Session) -> void:
	var inst := expeditions.get_for_session(s)
	if inst == null:
		_err(s, Protocol.ERR_NO_EXPEDITION)
		return
	if inst.state == Protocol.ExpState.IN_ROOM:
		_err(s, Protocol.ERR_BAD_STATE, {"message": "leave at a safe point"})
		return
	expeditions.leave(s)
	if inst.state != Protocol.ExpState.CLOSED:
		_broadcast_party(inst)
	Net.send_to_peer(s.peer_id, Protocol.S.LEAVE_EXPEDITION, {"reason": "left"})
	if not hub.has(s.account_id):
		_enter_hub(s)
	_broadcast_board()


func _handle_ready(s: Session, payload: Dictionary) -> void:
	var inst := expeditions.get_for_session(s)
	if inst == null:
		_err(s, Protocol.ERR_NO_EXPEDITION)
		return
	if inst.state != Protocol.ExpState.PREPARING:
		_err(s, Protocol.ERR_BAD_STATE)
		return
	var class_id := String(payload.get("class_id", s.class_id))
	if ContentDB.is_class_playable(class_id):
		s.class_id = class_id
	inst.set_ready(s.account_id, bool(payload.get("ready", true)), s.class_id)
	inst.members[s.account_id]["trait"] = _trait_for(s.account_id, s.class_id)
	_broadcast_party(inst)


func _handle_board_start(s: Session) -> void:
	var inst := expeditions.get_for_session(s)
	if inst == null:
		_err(s, Protocol.ERR_NO_EXPEDITION)
		return
	if inst.state != Protocol.ExpState.PREPARING:
		_err(s, Protocol.ERR_BAD_STATE)
		return
	if not inst.all_ready():
		_err(s, Protocol.ERR_NOT_READY)
		return
	_start_run(inst)


func _start_run(inst: ExpeditionInstance) -> void:
	metrics["expeditions_started"] += 1
	for aid: String in inst.members.keys():
		var acc := store.get_account(aid)
		if acc.is_empty():
			continue
		QuestEngine.on_run_start(acc["progression"])
		inst.members[aid]["secrets_found"] = (acc["progression"].get("secrets_found", []) as Array).duplicate()
		store.put_account(acc)
	world["hub"]["total_expeditions"] = int(world["hub"].get("total_expeditions", 0)) + 1
	store.save_world(world)
	for aid: String in inst.members.keys():
		if not inst.members[aid]["connected"]:
			continue
		var acc := store.get_account(aid)
		if not acc.is_empty():
			acc["stats"]["expeditions_started"] = int(acc["stats"].get("expeditions_started", 0)) + 1
			store.put_account(acc)
	inst.start_run()
	_flush_outbox(inst)
	_log(1, "expedition %s run started: seed=%d members=%d" % [inst.id, inst.seed_value, inst.member_count()])
	_broadcast_hub_roster()
	_broadcast_board()


## 인스턴스가 쌓아 둔 메시지를 보낸다. ENTER_EXPEDITION 은 세션 위치도 갱신한다.
func _flush_outbox(inst: ExpeditionInstance) -> void:
	while not inst.outbox.is_empty():
		var msg: Dictionary = inst.outbox.pop_front()
		var targets: Array = []
		if msg["to"] == "members":
			targets = inst.members.keys()
		else:
			targets = [msg["to"]]
		for aid: String in targets:
			if not inst.members.has(aid) or not inst.members[aid]["connected"]:
				continue
			var ms: Session = _session_for_account(aid)
			if ms == null:
				continue
			if int(msg["type"]) == Protocol.S.ENTER_EXPEDITION:
				ms.location = Protocol.Location.IN_ROOM
				if hub.has(aid):
					hub.leave(aid)
					_broadcast_hub_roster()
			elif int(msg["type"]) in [Protocol.S.REWARD_OFFER, Protocol.S.ROUTE_OFFER, Protocol.S.NODE_MENU]:
				ms.location = inst._location_for_state()
			Net.send_to_peer(ms.peer_id, int(msg["type"]), msg["payload"])
	if inst.run_finished_unreported:
		inst.run_finished_unreported = false
		_on_run_finished(inst)
	if inst.checkpoint_dirty:
		inst.checkpoint_dirty = false
		if inst.state == Protocol.ExpState.CLOSED:
			return
		if store.save_expedition(inst.to_checkpoint()) != OK:
			metrics["save_failures"] += 1


## 원정 종료(완주·전멸·오류 복구): 원정 단위 보상을 계정에 반영하고 결과 화면을 보낸다.
func _on_run_finished(inst: ExpeditionInstance) -> void:
	var victory: bool = inst.run_outcome == Protocol.Outcome.VICTORY
	if victory:
		world["hub"]["total_runs_completed"] = int(world["hub"].get("total_runs_completed", 0)) + 1
		store.save_world(world)
	var rewards: Dictionary = inst.last_result.get("rewards", {})
	for aid: String in inst.members.keys():
		var acc := store.get_account(aid)
		if acc.is_empty():
			continue
		var st: Dictionary = acc["stats"]
		var prog: Dictionary = acc["progression"]
		var shard := 3 if victory else 0
		QuestEngine.ensure(prog)
		var completed: Array = []
		if victory:
			st["runs_completed"] = int(st.get("runs_completed", 0)) + 1
			prog["memory_shards"] = int(prog.get("memory_shards", 0)) + shard
			completed = QuestEngine.on_event(prog, {"type": "run_complete", "count": 1})
			var ending := QuestEngine.ending_for(prog, inst.run.get("stats", {}))
			if not (prog["endings_seen"] as Array).has(String(ending.get("id", "base"))):
				prog["endings_seen"].append(String(ending.get("id", "base")))
			inst.last_result["ending"] = ending
			var codex: Dictionary = prog.get("codex", {"enemies": {}, "relics": [], "bosses": []})
			for bid: String in inst.run.get("stats", {}).get("bosses_killed", []):
				if not (codex.get("bosses", []) as Array).has(bid):
					codex["bosses"].append(bid)
			prog["codex"] = codex
		# 빌드 기록: 직업·유물·강화·결과 (최근 N개)
		var rpx: Dictionary = inst.run.get("players", {}).get(aid, {})
		var records: Array = prog.get("build_records", [])
		records.push_front({"class_id": inst.members[aid]["class_id"], "relics": rpx.get("relics", []), "upgrades": rpx.get("upgrades", []), "outcome": inst.run_outcome, "rooms": int(inst.run.get("stats", {}).get("rooms_cleared", 0)), "at": int(Time.get_unix_time_from_system())})
		while records.size() > int(ContentDB.rule("build_records_keep", 5)):
			records.pop_back()
		prog["build_records"] = records
		if store.put_account(acc) != OK:
			metrics["save_failures"] += 1
		var entry: Dictionary = rewards.get(aid, {"memory_shards": 0, "mastery_xp": 0})
		entry["memory_shards"] = int(entry.get("memory_shards", 0)) + shard
		entry["totals"] = {"memory_shards": prog.get("memory_shards", 0), "mastery": prog.get("class_mastery", {}).get(String(inst.members[aid]["class_id"]), {})}
		var qc: Array = entry.get("quests_completed", [])
		qc.append_array(completed)
		entry["quests_completed"] = qc
		rewards[aid] = entry
		var ms := _session_for_account(aid)
		if ms != null:
			ms.location = Protocol.Location.RESULT
			Net.send_to_peer(ms.peer_id, Protocol.S.ACCOUNT_UPDATE, {"account": _public_account(acc)})
	inst.last_result["rewards"] = rewards
	_log(1, "expedition %s run finished: %s (rooms %d, combat %.0fs)" % [inst.id, "VICTORY" if victory else ("WIPE" if inst.run_outcome == Protocol.Outcome.WIPE else "OTHER"), int(inst.run.get("stats", {}).get("rooms_cleared", 0)), float(inst.run.get("stats", {}).get("combat_sec", 0))])
	_send_to_members(inst, Protocol.S.ROOM_RESULT, inst.result_payload())
	_broadcast_party(inst)
	_broadcast_board()


## 계정이 그 직업에 고른 숙련 특성 (해금 단계 검증 포함)
func _trait_for(account_id: String, class_id: String) -> String:
	var acc := store.get_account(account_id)
	var prog: Dictionary = acc.get("progression", {})
	var tid := String(prog.get("mastery_traits", {}).get(class_id, ""))
	if tid == "":
		return ""
	var tdef := ContentDB.mastery_trait(class_id, tid)
	var lv := ContentDB.mastery_level(int(prog.get("class_mastery", {}).get(class_id, {}).get("xp", 0)))
	return tid if not tdef.is_empty() and lv >= int(tdef.get("unlock_level", 1)) else ""


func _handle_mastery_trait(s: Session, payload: Dictionary) -> void:
	if s.location != Protocol.Location.HUB:
		_err(s, Protocol.ERR_BAD_STATE)
		return
	var class_id := String(payload.get("class_id", ""))
	var tid := String(payload.get("trait_id", ""))
	var acc := store.get_account(s.account_id)
	var prog: Dictionary = acc["progression"]
	if tid != "":
		var tdef := ContentDB.mastery_trait(class_id, tid)
		if tdef.is_empty():
			_err(s, Protocol.ERR_BAD_CONTENT_ID, {"message": tid})
			return
		var lv := ContentDB.mastery_level(int(prog.get("class_mastery", {}).get(class_id, {}).get("xp", 0)))
		if lv < int(tdef.get("unlock_level", 1)):
			_err(s, "TRAIT_LOCKED", {"need_level": tdef.get("unlock_level", 1), "level": lv})
			return
	var traits: Dictionary = prog.get("mastery_traits", {})
	if tid == "":
		traits.erase(class_id)
	else:
		traits[class_id] = tid
	prog["mastery_traits"] = traits
	if store.put_account(acc) != OK:
		metrics["save_failures"] += 1
		_err(s, Protocol.ERR_SAVE_FAILED)
		return
	Net.send_to_peer(s.peer_id, Protocol.S.ACCOUNT_UPDATE, {"account": _public_account(acc)})


func _npc_dialog(s: Session, npc_id: String) -> Dictionary:
	var npc: Dictionary = ContentDB.npcs.get(npc_id, {})
	var acc := store.get_account(s.account_id)
	var prog: Dictionary = acc["progression"]
	QuestEngine.ensure(prog)
	var lv := QuestEngine.bond_level(prog, npc_id)
	var lines: Array = (npc.get("lines", {}).get("greet", []) as Array).duplicate()
	if lv >= 2:
		lines.append_array(npc.get("lines", {}).get("bond2", []))
	if lv >= 3:
		lines.append_array(npc.get("lines", {}).get("bond3", []))
	return {"npc": {"id": npc_id, "name_ko": npc.get("name_ko", npc_id), "role_ko": npc.get("role_ko", ""), "assets": npc.get("assets", {})}, "lines": lines, "bond_level": lv, "bond_points": int(prog.get("npc_bonds", {}).get(npc_id, 0)), "quests": QuestEngine.npc_view(prog, npc_id), "summary": QuestEngine.summary(prog)}


func _handle_npc_talk(s: Session, payload: Dictionary) -> void:
	if s.location != Protocol.Location.HUB:
		_err(s, Protocol.ERR_BAD_STATE)
		return
	var npc_id := String(payload.get("npc", ""))
	var npc: Dictionary = ContentDB.npcs.get(npc_id, {})
	if npc.is_empty():
		_err(s, Protocol.ERR_BAD_CONTENT_ID, {"message": npc_id})
		return
	if Vector2(float(npc.get("x", 0)), float(npc.get("y", 0))).distance_to(s.hub_pos) > float(ContentDB.rule("hub_talk_range", 90.0)) + 40.0:
		_err(s, "TOO_FAR", {"npc": npc_id})
		return
	# 첫 대화는 인연 +1 (NPC 당 하루 한 번)
	var acc := store.get_account(s.account_id)
	var prog: Dictionary = acc["progression"]
	QuestEngine.ensure(prog)
	var talked: Dictionary = prog.get("npc_talked_day", {})
	var day := int(Time.get_unix_time_from_system() / 86400)
	if int(talked.get(npc_id, -1)) != day:
		talked[npc_id] = day
		prog["npc_talked_day"] = talked
		QuestEngine.add_bond(prog, npc_id, 1)
		QuestEngine.on_event(prog, {"type": "talk", "target": npc_id, "count": 1})
		store.put_account(acc)
	Net.send_to_peer(s.peer_id, Protocol.S.NPC_DIALOG, _npc_dialog(s, npc_id))


func _handle_quest_action(s: Session, payload: Dictionary) -> void:
	var qid := String(payload.get("quest", ""))
	var action := String(payload.get("action", ""))
	var acc := store.get_account(s.account_id)
	var prog: Dictionary = acc["progression"]
	QuestEngine.ensure(prog)
	var q := QuestEngine.get_def(qid)
	if q.is_empty():
		_err(s, Protocol.ERR_BAD_CONTENT_ID, {"message": qid})
		return
	var ok := false
	match action:
		"accept":
			ok = QuestEngine.accept(prog, qid)
		"claim":
			var r := QuestEngine.claim(prog, qid)
			ok = bool(r.get("ok", false))
			if ok:
				var rw: Dictionary = r.get("reward", {})
				Net.send_to_peer(s.peer_id, Protocol.S.NOTICE, {"text": "퀘스트 완료: %s — 기억 조각 +%d%s" % [q.get("name_ko", qid), int(rw.get("memory_shards", 0)), (" · 해금: " + String(rw["unlock"])) if rw.has("unlock") else ""]})
	if not ok:
		_err(s, Protocol.ERR_BAD_STATE, {"quest": qid, "action": action})
		return
	if store.put_account(acc) != OK:
		metrics["save_failures"] += 1
		_err(s, Protocol.ERR_SAVE_FAILED)
		return
	Net.send_to_peer(s.peer_id, Protocol.S.ACCOUNT_UPDATE, {"account": _public_account(acc)})
	Net.send_to_peer(s.peer_id, Protocol.S.NPC_DIALOG, _npc_dialog(s, String(q.get("giver", ""))))


## 파티 중단 (SAVE-01): 안전 지점에서만. 체크포인트 저장 후 전원 마을로. 멤버는 모집판의 '이어하기'로 복귀한다.
func _handle_expedition_pause(s: Session) -> void:
	var inst := expeditions.get_for_session(s)
	if inst == null:
		_err(s, Protocol.ERR_NO_EXPEDITION)
		return
	if not inst.pause_run():
		_err(s, Protocol.ERR_BAD_STATE, {"message": "safe_point_only"})
		return
	if store.save_expedition(inst.to_checkpoint()) != OK:
		metrics["save_failures"] += 1
	inst.checkpoint_dirty = false
	_log(1, "%s paused expedition %s at %s" % [s.nickname, inst.id, String(inst.run.get("checkpoint_note", ""))])
	for aid: String in inst.members.keys():
		var ms := _session_for_account(aid)
		if ms == null:
			continue
		inst.members[aid]["connected"] = false
		inst.members[aid]["disconnect_at"] = Time.get_unix_time_from_system()
		Net.send_to_peer(ms.peer_id, Protocol.S.NOTICE, {"text": "원정을 중단했습니다. 모집판의 '이어하기'로 같은 자리에서 계속할 수 있습니다."})
		Net.send_to_peer(ms.peer_id, Protocol.S.LEAVE_EXPEDITION, {"expedition_id": inst.id, "paused": true})
		_enter_hub(ms)
	_broadcast_board()


## 핑 (중클릭): 같은 방 멤버에게 표식 이벤트를 보낸다. 서버 판정에는 영향이 없다.
func _handle_mark(s: Session, payload: Dictionary) -> void:
	var inst := expeditions.get_for_session(s)
	if inst == null or inst.room == null:
		return
	if Time.get_unix_time_from_system() - float(s.get_meta("last_ping", 0.0)) < float(ContentDB.rule("ping_cooldown_sec", 1.0)):
		return
	s.set_meta("last_ping", Time.get_unix_time_from_system())
	inst.node_action(s.account_id, {"action": "ping", "x": payload.get("x", 0), "y": payload.get("y", 0)})


func _handle_build_select(s: Session, payload: Dictionary) -> void:
	var inst := expeditions.get_for_session(s)
	if inst == null:
		_err(s, Protocol.ERR_NO_EXPEDITION)
		return
	var kind := String(payload.get("kind", "log_cover"))
	if not (ContentDB.rules.get("build_kinds", {}) as Dictionary).has(kind):
		_err(s, Protocol.ERR_BAD_CONTENT_ID, {"message": kind})
		return
	inst.members[s.account_id]["build_kind"] = kind
	if inst.room != null:
		inst.room.set_build_kind(s.account_id, kind)


func _permanent_bonus(account_id: String) -> Dictionary:
	# 마을 시설(공용)과 개인 내실의 영구 보너스. 상한은 13-1절에 따라 ContentDB.village_bonus 가 통합 관리한다.
	var bonus := ContentDB.village_bonus(world.get("hub", {}).get("structures", {}))
	var acc := store.get_account(account_id)
	var perm: Dictionary = acc.get("progression", {}).get("permanent", {})
	for k: String in perm.keys():
		bonus[k] = float(bonus.get(k, 0.0)) + float(perm[k])
	return bonus


func _handle_reward_pick(s: Session, payload: Dictionary) -> void:
	var inst := expeditions.get_for_session(s)
	if inst == null:
		_err(s, Protocol.ERR_NO_EXPEDITION)
		return
	if not inst.pick_reward(s.account_id, int(payload.get("index", 0))):
		_err(s, Protocol.ERR_BAD_STATE)
		return
	_flush_outbox(inst)
	_broadcast_party(inst)


func _handle_route_vote(s: Session, payload: Dictionary) -> void:
	var inst := expeditions.get_for_session(s)
	if inst == null:
		_err(s, Protocol.ERR_NO_EXPEDITION)
		return
	if not inst.vote_route(s.account_id, String(payload.get("node_id", ""))):
		_err(s, Protocol.ERR_BAD_STATE)
		return
	_flush_outbox(inst)


func _handle_node_action(s: Session, payload: Dictionary) -> void:
	var inst := expeditions.get_for_session(s)
	if inst == null:
		_err(s, Protocol.ERR_NO_EXPEDITION)
		return
	var r := inst.node_action(s.account_id, payload)
	if not r["ok"]:
		_err(s, String(r["error"]))
	_flush_outbox(inst)


func _handle_room_choice(s: Session, payload: Dictionary) -> void:
	var inst := expeditions.get_for_session(s)
	if inst == null:
		_err(s, Protocol.ERR_NO_EXPEDITION)
		return
	if inst.state != Protocol.ExpState.RESULT:
		_err(s, Protocol.ERR_BAD_STATE)
		return
	inst.set_choice(s.account_id, String(payload.get("choice", "")))
	_broadcast_party(inst)
	var resolved := inst.resolved_choice()
	if resolved == "restart":
		store.delete_expedition(inst.id)
		_start_run(inst)
	elif resolved == "hub":
		_return_to_hub(inst)


func _return_to_hub(inst: ExpeditionInstance) -> void:
	var ids := inst.members.keys()
	for aid: String in ids:
		var ms: Session = _session_for_account(aid)
		inst.remove_member(aid)
		if ms != null:
			ms.expedition_id = ""
			Net.send_to_peer(ms.peer_id, Protocol.S.LEAVE_EXPEDITION, {"reason": "returned"})
			_enter_hub(ms)
	expeditions.close(inst)
	store.delete_expedition(inst.id)
	_log(1, "expedition %s closed (returned to hub)" % inst.id)
	_broadcast_board()


## 마을 시설 복구: 요청자의 기억 조각을 차감(트랜잭션)하고 공용 시설 단계를 올린다. 저장 실패 시 환불한다.
func _handle_hub_upgrade(s: Session, payload: Dictionary) -> void:
	if s.location != Protocol.Location.HUB:
		_err(s, Protocol.ERR_BAD_STATE)
		return
	var sid := String(payload.get("structure", ""))
	var sdef: Dictionary = ContentDB.village.get("structures", {}).get(sid, {})
	if sdef.is_empty():
		_err(s, Protocol.ERR_BAD_CONTENT_ID, {"message": sid})
		return
	var structures: Dictionary = world["hub"].get("structures", {})
	var level := int(structures.get(sid, {}).get("level", 0))
	var next := level + 1
	var ldef: Dictionary = sdef.get("levels", {}).get(str(next), {})
	if next > int(sdef.get("max_level", 1)) or ldef.is_empty():
		_err(s, "MAX_LEVEL", {"structure": sid})
		return
	var cost := int(ldef.get("cost_shards", 0))
	var acc := store.get_account(s.account_id)
	var shards := int(acc.get("progression", {}).get("memory_shards", 0))
	if shards < cost:
		_err(s, "NOT_ENOUGH_SHARDS", {"need": cost, "have": shards})
		return
	acc["progression"]["memory_shards"] = shards - cost
	acc["progression"]["village_repair"] = int(acc["progression"].get("village_repair", 0)) + cost
	if store.put_account(acc) != OK:
		metrics["save_failures"] += 1
		_err(s, Protocol.ERR_SAVE_FAILED)
		return
	structures[sid] = {"level": next, "repaired_by": s.nickname, "repaired_at": int(Time.get_unix_time_from_system())}
	world["hub"]["structures"] = structures
	if store.save_world(world) != OK:
		acc["progression"]["memory_shards"] = shards
		store.put_account(acc)
		metrics["save_failures"] += 1
		_err(s, Protocol.ERR_SAVE_FAILED)
		return
	_log(1, "%s repaired %s to level %d (-%d shards)" % [s.nickname, sid, next, cost])
	QuestEngine.ensure(acc["progression"])
	var qdone: Array = QuestEngine.on_event(acc["progression"], {"type": "village_level", "target": sid, "count": next, "absolute": true})
	store.put_account(acc)
	if not qdone.is_empty():
		Net.send_to_peer(s.peer_id, Protocol.S.NOTICE, {"text": "퀘스트 목표 달성: " + ", ".join(qdone.map(func(q: String) -> String: return String(QuestEngine.get_def(q).get("name_ko", q))))})
	Net.send_to_peer(s.peer_id, Protocol.S.ACCOUNT_UPDATE, {"account": _public_account(acc)})
	for hs: Session in hub.sessions.values():
		Net.send_to_peer(hs.peer_id, Protocol.S.ENTER_HUB, {"hub": hub.hub_info(), "roster": hub.roster(), "board": _board_for(hs.account_id), "you": {"id": hs.account_id, "x": hs.hub_pos.x, "y": hs.hub_pos.y}, "refresh": true})
		Net.send_to_peer(hs.peer_id, Protocol.S.NOTICE, {"text": "%s 이(가) %s 을(를) %d단계로 복구했습니다: %s" % [s.nickname, sdef.get("name_ko", sid), next, ldef.get("desc_ko", "")]})


func _handle_chat(s: Session, payload: Dictionary) -> void:
	var text := String(payload.get("text", "")).strip_edges().left(200)
	if text == "":
		return
	var inst := expeditions.get_for_session(s)
	var msg := {"from": s.nickname, "id": s.account_id, "text": text, "scope": "party" if inst != null else "hub"}
	if inst != null:
		for aid: String in inst.members.keys():
			var ms: Session = _session_for_account(aid)
			if ms != null:
				Net.send_to_peer(ms.peer_id, Protocol.S.CHAT, msg)
	else:
		for hs: Session in hub.sessions.values():
			Net.send_to_peer(hs.peer_id, Protocol.S.CHAT, msg)


# ------------------------------------------------------------------ 입력

func _on_client_input(peer_id: int, seq: int, mx: float, my: float, ax: float, ay: float, buttons: int) -> void:
	var s: Session = sessions.get(peer_id, null)
	if s == null or not s.is_authed():
		return
	if not (is_finite(mx) and is_finite(my) and is_finite(ax) and is_finite(ay)):
		return
	var mv := Vector2(mx, my).limit_length(1.0)
	var aim := Vector2(ax, ay)
	if s.location == Protocol.Location.HUB:
		hub.apply_input(s, mv, aim)
	elif s.location == Protocol.Location.IN_ROOM:
		var inst := expeditions.get_for_session(s)
		if inst != null and inst.room != null:
			inst.room.queue_input(s.account_id, seq, mv, aim, buttons)


# ------------------------------------------------------------------ 틱

func _physics_process(dt: float) -> void:
	if shutting_down:
		return
	var t0 := Time.get_ticks_usec()
	_stop_check_accum += dt
	if _stop_check_accum >= 1.0:
		_stop_check_accum = 0.0
		if FileAccess.file_exists(stop_file):
			DirAccess.remove_absolute(stop_file)
			request_stop("STOP file")
			return
	_check_hello_timeouts()
	hub.step(dt)
	_hub_snap_accum += 1
	var hub_every := maxi(int(round(float(ContentDB.rule("server_sim_hz", 30)) / float(ContentDB.rule("hub_snapshot_hz", 10)))), 1)
	if _hub_snap_accum >= hub_every and not hub.sessions.is_empty():
		_hub_snap_accum = 0
		var snap := hub.snapshot()
		for hs: Session in hub.sessions.values():
			Net.send_snapshot(hs.peer_id, snap)
	var snap_every := maxi(int(round(float(ContentDB.rule("server_sim_hz", 30)) / float(ContentDB.rule("server_snapshot_hz", 15)))), 1)
	var grace := float(ContentDB.rule("disconnect_grace_sec", 120.0))
	for inst: ExpeditionInstance in expeditions.instances.values().duplicate():
		var removed := inst.prune_disconnected(grace)
		if not removed.is_empty():
			_log(1, "expedition %s: removed %s after grace" % [inst.id, removed])
			if inst.member_count() == 0:
				expeditions.close(inst)
				store.delete_expedition(inst.id)
				_broadcast_board()
				continue
			_broadcast_party(inst)
		var r := inst.step(dt, snap_every)
		if inst.state == Protocol.ExpState.CLOSED:
			continue
		var evs: Array = r["events"]
		if not evs.is_empty():
			_send_to_members(inst, Protocol.S.ROOM_EVENTS, {"t": inst.room.tick if inst.room else 0, "events": evs})
		if r["snapshot"] != null:
			var snap: Dictionary = r["snapshot"]
			for aid: String in inst.members.keys():
				var m: Dictionary = inst.members[aid]
				if not m["connected"]:
					continue
				var ms: Session = _session_for_account(aid)
				if ms == null:
					continue
				var own := snap.duplicate()
				own["ack"] = int(inst.room.players.get(aid, {}).get("last_seq", 0))
				var nbytes := var_to_bytes(own).size()
				if nbytes > _snap_max_bytes:
					_snap_max_bytes = nbytes
					if nbytes > 1392:
						_log(2, "snapshot %d bytes exceeds ENet MTU 1392 (room %s, n=%d)" % [nbytes, inst.id, inst.members.size()])
				Net.send_snapshot(ms.peer_id, own)
		if r["finished"]:
			_on_room_finished(inst)
		if not inst.outbox.is_empty() or inst.checkpoint_dirty:
			_flush_outbox(inst)
	_flush_accum += dt
	if _flush_accum >= 5.0:
		_flush_accum = 0.0
		if hub.dirty:
			hub.dirty = false
			if store.save_world(world) != OK:
				metrics["save_failures"] += 1
		elif store.flush() != OK:
			metrics["save_failures"] += 1
	var ms_taken := (Time.get_ticks_usec() - t0) / 1000.0
	_tick_ms_accum += ms_taken
	_tick_count += 1
	_tick_ms_max = maxf(_tick_ms_max, ms_taken)
	_metrics_accum += dt
	if _metrics_accum >= float(config.get_value("metrics_interval_sec")):
		_metrics_accum = 0.0
		_log(1, "metrics online=%d/%d expeditions=%d(running %d) tick_avg=%.2fms tick_max=%.2fms snapshot_max=%dB save_failures=%d" % [_online_count(), int(config.get_value("max_online_players")), expeditions.active_count(), expeditions.running_count(), _tick_ms_accum / maxf(_tick_count, 1), _tick_ms_max, _snap_max_bytes, metrics["save_failures"]])
		metrics["snapshot_max_bytes"] = _snap_max_bytes
		_tick_ms_accum = 0.0
		_tick_count = 0
		_tick_ms_max = 0.0
		_write_status()


func _check_hello_timeouts() -> void:
	var now := Time.get_unix_time_from_system()
	var timeout := float(config.get_value("hello_timeout_sec"))
	for s: Session in sessions.values().duplicate():
		if s.state == Session.State.CONNECTED and now - s.connected_at > timeout:
			_log(0, "peer %d hello timeout" % s.peer_id)
			_kick(s, Protocol.ERR_HELLO_TIMEOUT)


func _on_room_finished(inst: ExpeditionInstance) -> void:
	var res := inst.last_result
	var victory: bool = int(res.get("outcome", 0)) == Protocol.Outcome.VICTORY
	var run_over: bool = false
	if victory:
		metrics["rooms_cleared"] += 1
		world["hub"]["total_rooms_cleared"] = int(world["hub"].get("total_rooms_cleared", 0)) + 1
	else:
		metrics["wipes"] += 1
		world["hub"]["total_wipes"] = int(world["hub"].get("total_wipes", 0)) + 1
	store.save_world(world)
	var rewards: Dictionary = {}
	for aid: String in res.get("players", {}).keys():
		if not inst.members.has(aid):
			continue
		var ps: Dictionary = res["players"][aid]
		var acc := store.get_account(aid)
		if acc.is_empty():
			continue
		var st: Dictionary = acc["stats"]
		st["kills"] = int(st.get("kills", 0)) + int(ps.get("kills", 0))
		st["downs"] = int(st.get("downs", 0)) + int(ps.get("downs", 0))
		st["deaths"] = int(st.get("deaths", 0)) + int(ps.get("deaths", 0))
		st["rescues"] = int(st.get("rescues", 0)) + int(ps.get("rescues", 0))
		st["damage_dealt"] = int(st.get("damage_dealt", 0)) + int(ps.get("damage_dealt", 0))
		if victory:
			st["rooms_cleared"] = int(st.get("rooms_cleared", 0)) + 1
		else:
			st["wipes"] = int(st.get("wipes", 0)) + 1
		var prog: Dictionary = acc["progression"]
		# 기억 조각: 방 클리어마다 1 (원정 완주 보너스는 _on_run_finished). 유물 도감·적 도감 갱신.
		var dmult := float(ContentDB.rules.get("difficulties", {}).get(inst.difficulty, {}).get("reward_mult", 1.0))
		var shard := (1 if victory else 0) if inst.difficulty == "normal" else (int(ceil(dmult)) if victory and dmult >= 1.0 else (1 if victory and randf() < dmult else 0))
		if inst.tutorial:
			shard = 0
		var rp: Dictionary = inst.run.get("players", {}).get(aid, {})
		if victory and int(inst.member_mods(aid)["mods"].get("shard_bonus", 0)) > 0 and int(rp.get("shard_bonus_used", 0)) < 3:
			shard += 1
			rp["shard_bonus_used"] = int(rp.get("shard_bonus_used", 0)) + 1
		prog["memory_shards"] = int(prog.get("memory_shards", 0)) + shard
		var cls: String = inst.members[aid]["class_id"]
		var mastery: Dictionary = prog.get("class_mastery", {})
		var entry: Dictionary = mastery.get(cls, {"xp": 0, "level": 1})
		var xpr: Dictionary = ContentDB.mastery.get("xp", {})
		var xp_gain := int(ps.get("kills", 0)) * int(xpr.get("per_kill", 5)) + (int(xpr.get("room_clear", 10)) if victory else int(xpr.get("room_wipe", 2)))
		if victory and String(res.get("objective", "")) == "boss":
			xp_gain += int(xpr.get("boss_kill", 40))
		xp_gain = int(round(xp_gain * (1.0 + float(_permanent_bonus(aid).get("mastery_xp_mult", 0.0))) * float(ContentDB.rules.get("difficulties", {}).get(inst.difficulty, {}).get("xp_mult", 1.0))))
		if inst.tutorial:
			xp_gain = 0
		entry["xp"] = int(entry.get("xp", 0)) + xp_gain
		entry["level"] = ContentDB.mastery_level(int(entry["xp"]))
		mastery[cls] = entry
		prog["class_mastery"] = mastery
		var codex: Dictionary = prog.get("codex", {"enemies": {}, "relics": [], "bosses": []})
		for type_id: String in res.get("stats", {}).get("kills_by_type", {}).keys():
			codex["enemies"][type_id] = int(codex["enemies"].get(type_id, 0)) + int(res["stats"]["kills_by_type"][type_id])
		for rid: String in inst.run.get("players", {}).get(aid, {}).get("relics", []):
			if not (codex["relics"] as Array).has(rid):
				codex["relics"].append(rid)
		prog["codex"] = codex
		# 지역 비밀·퀘스트 진행 (한 번만 반영)
		QuestEngine.ensure(prog)
		for sid: String in res.get("stats", {}).get("secrets", []):
			if not (prog["secrets_found"] as Array).has(sid):
				prog["secrets_found"].append(sid)
				prog["memory_shards"] = int(prog["memory_shards"]) + int(ContentDB.rule("secret_reward_shards", 2)) + int(_permanent_bonus(aid).get("secret_reward_add", 0))
		inst.members[aid]["secrets_found"] = (prog["secrets_found"] as Array).duplicate()
		var completed: Array = []
		completed.append_array(QuestEngine.on_event(prog, {"type": "kills", "count": int(ps.get("kills", 0))}))
		completed.append_array(QuestEngine.on_event(prog, {"type": "codex_enemies", "count": codex["enemies"].size(), "absolute": true}))
		completed.append_array(QuestEngine.on_event(prog, {"type": "secrets", "count": (prog["secrets_found"] as Array).size(), "absolute": true}))
		completed.append_array(QuestEngine.on_event(prog, {"type": "structures_built", "count": int(res.get("stats", {}).get("builds", 0))}))
		completed.append_array(QuestEngine.on_event(prog, {"type": "sluice_toggles", "count": int(res.get("stats", {}).get("sluice_toggles", 0))}))
		for mid: String in res.get("mechanics_succeeded", []):
			completed.append_array(QuestEngine.on_event(prog, {"type": "mechanic_success", "target": mid, "count": 1}))
		if victory:
			completed.append_array(QuestEngine.on_event(prog, {"type": "rooms_cleared_objective", "target": String(res.get("objective", "")), "count": 1}))
			if String(res.get("objective", "")) == "escort":
				completed.append_array(QuestEngine.on_event(prog, {"type": "escort_clear", "count": 1}))
			if String(res.get("boss_id", "")) != "":
				completed.append_array(QuestEngine.on_event(prog, {"type": "boss_kill", "target": String(res["boss_id"]), "count": 1}))
			if bool(res.get("elite", false)):
				if int(res.get("stats", {}).get("builds", 0)) == 0:
					completed.append_array(QuestEngine.on_event(prog, {"type": "elite_no_structure", "count": 1}))
				else:
					QuestEngine.fail_for_run(prog, "opt_03")
		if store.put_account(acc) != OK:
			metrics["save_failures"] += 1
		rewards[aid] = {"memory_shards": shard, "mastery_xp": xp_gain, "class_id": cls, "totals": {"memory_shards": prog["memory_shards"], "mastery": entry}, "quests_completed": completed, "secrets": res.get("stats", {}).get("secrets", [])}
		var ms := _session_for_account(aid)
		if ms != null:
			Net.send_to_peer(ms.peer_id, Protocol.S.ACCOUNT_UPDATE, {"account": _public_account(acc)})
	inst.last_result["rewards"] = rewards
	_log(1, "expedition %s room %d (%s) finished: %s in %.1fs (kills %d, downs %d)" % [inst.id, inst.room_index, inst.room_id, "VICTORY" if victory else "WIPE", float(res.get("elapsed", 0)), int(res.get("stats", {}).get("enemies_killed", 0)), int(res.get("stats", {}).get("downs", 0))])
	_broadcast_party(inst)
	_broadcast_board()


func _result_payload(inst: ExpeditionInstance) -> Dictionary:
	return inst.result_payload()


# ------------------------------------------------------------------ 브로드캐스트

func _send_to_members(inst: ExpeditionInstance, type: int, payload: Dictionary) -> void:
	for aid: String in inst.members.keys():
		if not inst.members[aid]["connected"]:
			continue
		var ms: Session = _session_for_account(aid)
		if ms != null:
			Net.send_to_peer(ms.peer_id, type, payload)


func _broadcast_party(inst: ExpeditionInstance) -> void:
	_send_to_members(inst, Protocol.S.PARTY_STATE, inst.party_payload())


func _board_for(account_id: String) -> Array:
	return expeditions.board_list(account_id)


func _broadcast_board() -> void:
	# 중단된 원정(이어하기)은 그 멤버에게만 보이므로 접속자마다 목록을 따로 만든다
	for hs: Session in hub.sessions.values():
		Net.send_to_peer(hs.peer_id, Protocol.S.BOARD_STATE, {"list": _board_for(hs.account_id)})


func _broadcast_hub_roster() -> void:
	var payload := {"roster": hub.roster(), "online": _online_count(), "max_online": int(config.get_value("max_online_players"))}
	for hs: Session in hub.sessions.values():
		Net.send_to_peer(hs.peer_id, Protocol.S.HUB_ROSTER, payload)

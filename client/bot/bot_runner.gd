class_name BotRunner
extends Node
## 통합 테스트용 자동 클라이언트. UI 없이 NetClient 를 통해 실제 서버와 같은 프로토콜로 동작한다.
## 시나리오: expedition(등록→허브→원정 생성/참가→준비→출정→전투→결과→마을), hub_only(허브 대기·참가 시도 기록), persist_check(계정 기록 확인)
## 결과는 --out=<path> JSON 으로 남긴다. 이 봇은 실제 플레이어를 대신하는 NPC 가 아니라 프로토콜 검증 도구다.

var client: NetClient
var args: Dictionary
var scenario: String = "expedition"
var nick: String = "bot"
var password: String = "botpass1"
var out_path: String = ""
var result := {"ok": false, "scenario": "", "nick": "", "errors": [], "events": {}, "log": []}
var _phase: String = "connect"
var _timer: float = 0.0
var _seq: int = 0
var _room: Dictionary = {}
var _party: Dictionary = {}
var _snapshot: Dictionary = {}
var _my_id: String = ""
var _hub_info: Dictionary = {}
var _board: Array = []
var _expedition_id: String = ""
var _finished: bool = false
var _total_timeout: float = 90.0
var _join_attempts: int = 0
var _restarts_done: int = 0
var _dropped: bool = false
var _drop_pending: bool = false
var _run: Dictionary = {}
var _bought: bool = false
var _voted_layer: int = -1


func start(net: NetClient, launch_args: Dictionary) -> void:
	client = net
	args = launch_args
	scenario = String(args.get("bot", "expedition"))
	nick = String(args.get("nick", "bot_%d" % (randi() % 10000)))
	password = String(args.get("password", "botpass1"))
	out_path = String(args.get("out", ""))
	_total_timeout = float(args.get("timeout", 90.0))
	result["scenario"] = scenario
	result["nick"] = nick
	result["asset_check"] = _asset_check()
	client.hello_result.connect(_on_hello)
	client.auth_result.connect(_on_auth)
	client.message.connect(_on_message)
	client.snapshot.connect(_on_snapshot)
	client.disconnected.connect(_on_disconnected)
	if args.has("proto"):
		client.hello_override = {"protocol": int(args["proto"])}
	var addr := String(args.get("addr", "127.0.0.1:7777")).split(":")
	_log("connecting to %s" % [addr])
	client.connect_to(addr[0], int(addr[1]) if addr.size() > 1 else Protocol.DEFAULT_PORT)


## export 된 실행 파일에서도 에셋이 ID 로 로드되는지 확인한다 (AST-01 의 export 검증 항목).
func _asset_check() -> Dictionary:
	var ids := ["char.guardian.idle", "char.guardian.walk", "char.guardian.attack", "enemy.sap_snail.walk", "tile.willow.ground", "icon.skill.guardian.q", "vfx.telegraph_circle", "ui.panel.default"]
	var ok := 0
	var bad: Array = []
	for id in ids:
		var sheet := AssetRegistry.get_sheet(id)
		if bool(sheet.get("is_fallback", false)):
			bad.append(id)
		else:
			ok += 1
	var font_ok := AssetRegistry.resolve_path("font.ui.main") != ""
	var audio_ok := AssetRegistry.get_audio("sfx.hammer_hit") != null
	return {"textures_ok": ok, "fallbacks": bad, "font_ok": font_ok, "audio_ok": audio_ok, "exported": not OS.has_feature("editor"), "override_dir": AssetRegistry.override_dir}


func _log(msg: String) -> void:
	result["log"].append("%.2f %s" % [Time.get_ticks_msec() / 1000.0, msg])
	print("[bot %s] %s" % [nick, msg])


func _count(ev: String, n: int = 1) -> void:
	result["events"][ev] = int(result["events"].get(ev, 0)) + n


func _fail(msg: String) -> void:
	result["errors"].append(msg)
	_log("ERROR " + msg)


func _finish(ok: bool) -> void:
	if _finished:
		return
	_finished = true
	result["ok"] = ok and result["errors"].is_empty()
	result["account_id"] = _my_id
	result["hub_info"] = _hub_info
	if not client.account.is_empty():
		result["account"] = client.account
	if out_path != "":
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify(result, "  "))
			f.close()
	_log("finished ok=%s" % result["ok"])
	client.disconnect_from_server("")
	await get_tree().create_timer(0.3).timeout
	get_tree().quit(0 if result["ok"] else 1)


func _on_hello(p: Dictionary) -> void:
	if not bool(p.get("ok", false)):
		result["hello"] = p
		if args.has("expect_hello_error") and String(args["expect_hello_error"]) == String(p.get("error", "")):
			_log("got expected hello error %s" % p.get("error", ""))
			_finish(true)
			return
		_fail("hello rejected: %s" % p.get("error", "?"))
		_finish(false)
		return
	result["server_info"] = p.get("server", {})
	if args.has("login_only") or _dropped:
		client.send(Protocol.C.LOGIN, {"nick": nick, "password": password})
	else:
		client.send(Protocol.C.REGISTER, {"nick": nick, "password": password})


func _on_auth(p: Dictionary) -> void:
	if bool(p.get("ok", false)):
		_my_id = String(p["account"]["id"])
		result["account"] = p["account"]
		result["auth"] = {"ok": true, "new_account": p.get("new_account", false)}
		_log("authenticated as %s" % _my_id)
		return
	var err := String(p.get("error", ""))
	if err == Protocol.ERR_NICK_TAKEN and not args.has("login_only"):
		_log("nick taken, logging in instead")
		client.send(Protocol.C.LOGIN, {"nick": nick, "password": password})
		return
	result["auth"] = {"ok": false, "error": err, "payload": p}
	if args.has("expect_auth_error") and String(args["expect_auth_error"]) == err:
		_log("got expected auth error %s" % err)
		_finish(true)
		return
	_fail("auth failed: %s" % err)
	_finish(false)


func _on_disconnected(reason: String) -> void:
	if _finished:
		return
	if reason == "LOGOUT" and _phase == "done":
		_finish(true)
		return
	if _drop_pending:
		return
	_fail("disconnected: %s" % reason)
	_finish(false)


func _on_message(type: int, p: Dictionary) -> void:
	match type:
		Protocol.S.ENTER_HUB:
			_hub_info = p.get("hub", {})
			_board = p.get("board", [])
			result["hub_roster_size"] = p.get("roster", []).size()
			_log("entered hub world=%s visits=%s" % [_hub_info.get("world_id", "?"), _hub_info.get("total_visits", "?")])
			_count("enter_hub")
			if _phase == "connect" or _phase == "returning":
				_phase = "hub"
				_timer = 0.0
				if _phase == "hub" and _room.size() > 0:
					pass
		Protocol.S.BOARD_STATE:
			_board = p.get("list", [])
		Protocol.S.PARTY_STATE:
			_party = p
			_expedition_id = String(p.get("expedition_id", ""))
			if _phase == "hub" or _phase == "joining":
				_phase = "party"
				_timer = 0.0
				_log("in party %s members=%d" % [_expedition_id, p.get("members", []).size()])
		Protocol.S.ENTER_EXPEDITION:
			_room = p
			_snapshot = {}
			_phase = "room"
			_timer = 0.0
			_count("enter_room")
			if _dropped:
				_count("reconnected_to_room")
				result["reconnect_party_size"] = p.get("party", []).size()
			result["room_n"] = p.get("n", 0)
			result["room_seed"] = p.get("seed", 0)
			_log("entered room %s N=%s seed=%s party=%d" % [p.get("room_id", "?"), p.get("n", "?"), p.get("seed", "?"), p.get("party", []).size()])
		Protocol.S.ROOM_EVENTS:
			for ev: Dictionary in p.get("events", []):
				var k := String(ev.get("k", ""))
				match k:
					"hit": if ev.get("id", "") == _my_id: _count("hits_taken")
					"enemy_hit": if ev.get("by", "") == _my_id: _count("hits_dealt")
					"enemy_died": if ev.get("by", "") == _my_id: _count("kills")
					"player_downed": if ev.get("id", "") == _my_id: _count("downed")
					"rescued": if ev.get("by", "") == _my_id: _count("rescues_done")
					"dodge": if ev.get("id", "") == _my_id: _count("dodges")
					"evaded": if ev.get("id", "") == _my_id: _count("evaded")
					"wave": _count("waves")
					"room_clear": _count("room_clear")
					"wipe": _count("wipe")
		Protocol.S.ROOM_RESULT:
			result["room_result"] = {"outcome": p.get("outcome", 0), "run_outcome": p.get("run_outcome", 0), "elapsed": p.get("elapsed", 0), "stats": p.get("stats", {}), "rewards": p.get("rewards", {}), "run_stats": p.get("run_stats", {}), "run": p.get("run", {})}
			if int(p.get("run_outcome", 0)) == Protocol.Outcome.VICTORY:
				_count("run_complete")
			_log("run result outcome=%s rooms=%s" % [p.get("run_outcome", 0), p.get("run_stats", {}).get("rooms_cleared", "?")])
			_phase = "result"
			_timer = 0.0
		Protocol.S.LEAVE_EXPEDITION:
			_log("left expedition (%s)" % p.get("reason", ""))
			_phase = "returning"
		Protocol.S.RUN_STATE:
			_run = p
		Protocol.S.REWARD_OFFER:
			_count("reward_offers")
			if not bool(p.get("picked", false)) and not (p.get("options", []) as Array).is_empty():
				_log("reward options: %s" % [p["options"].map(func(o: Dictionary) -> String: return String(o.get("id", "")))])
				client.send(Protocol.C.REWARD_PICK, {"index": 0})
				_count("reward_picks")
			_phase = "phase"
			_timer = 0.0
		Protocol.S.ROUTE_OFFER:
			var votes: Dictionary = p.get("votes", {})
			if not votes.has(_my_id) and _voted_layer != int(p.get("layer", -1)):
				_voted_layer = int(p.get("layer", -1))
				var nodes: Array = p.get("nodes", [])
				var pick: Dictionary = nodes[0]
				for n: Dictionary in nodes:
					if String(n.get("type", "")) == String(args.get("prefer", "combat")):
						pick = n
				_log("voting %s (%s)" % [pick["id"], pick["type"]])
				client.send(Protocol.C.ROUTE_VOTE, {"node_id": String(pick["id"])})
				_count("route_votes")
			_phase = "phase"
			_timer = 0.0
		Protocol.S.NODE_MENU:
			_phase = "phase"
			_timer = 0.0
			var kind := String(p.get("kind", ""))
			var done: Array = p.get("done", [])
			match kind:
				"event":
					if not (p.get("votes", {}) as Dictionary).has(_my_id):
						var choices: Array = p.get("data", {}).get("choices", [])
						client.send(Protocol.C.NODE_ACTION, {"action": "vote", "choice": String(choices[0]["id"])})
						_count("event_votes")
				"shop":
					if not done.has(_my_id):
						var mine: Dictionary = p.get("run", {}).get("players", {}).get(_my_id, {})
						if int(mine.get("acorns", 0)) >= 15 and not _bought:
							_bought = true
							client.send(Protocol.C.NODE_ACTION, {"action": "buy", "item": "heal_charge"})
							_count("shop_buys")
						else:
							client.send(Protocol.C.NODE_ACTION, {"action": "continue"})
				"rest":
					if not done.has(_my_id):
						client.send(Protocol.C.NODE_ACTION, {"action": "continue"})
						_count("rests")
		Protocol.S.ERROR:
			var code := String(p.get("error", ""))
			result["last_error"] = p
			_count("error:" + code)
			if args.has("expect_join_error") and String(args["expect_join_error"]) == code:
				_log("got expected error %s" % code)
				result["expected_error_seen"] = true
				if scenario == "hub_only":
					_phase = "done"
					client.send(Protocol.C.LOGOUT)
			elif _phase == "joining" and code in [Protocol.ERR_PARTY_FULL, Protocol.ERR_NO_EXPEDITION, Protocol.ERR_BAD_STATE]:
				_log("join failed (%s), retrying later" % code)
				_phase = "hub"
				_timer = 0.0
			else:
				_fail("server error %s %s" % [code, p])
		Protocol.S.KICKED:
			if _phase != "done":
				_fail("kicked: %s" % p.get("error", ""))
		Protocol.S.ACCOUNT_UPDATE:
			result["account"] = p.get("account", {})


func _on_snapshot(p: Dictionary) -> void:
	if p.has("hub"):
		return
	_snapshot = p


func _physics_process(dt: float) -> void:
	if _finished:
		return
	_timer += dt
	if Time.get_ticks_msec() / 1000.0 > _total_timeout:
		_fail("timeout in phase %s" % _phase)
		_finish(false)
		return
	match _phase:
		"hub": _phase_hub()
		"party": _phase_party()
		"room": _phase_room()
		"result": _phase_result()
		"phase": pass
		"returning": pass
		"done": pass


func _phase_hub() -> void:
	match scenario:
		"hub_only":
			if _timer > float(args.get("wait", 3.0)):
				if args.has("join"):
					var target := _resolve_join_target(String(args["join"]))
					if target == "":
						client.send(Protocol.C.BOARD_LIST)
						_timer = float(args.get("wait", 3.0)) - 0.5
						return
					_log("trying to join %s" % target)
					_phase = "joining"
					client.send(Protocol.C.BOARD_JOIN, {"expedition_id": target, "class_id": "guardian"})
					_timer = 0.0
				else:
					_phase = "done"
					client.send(Protocol.C.LOGOUT)
		"persist_check":
			_phase = "done"
			client.send(Protocol.C.LOGOUT)
		_:
			if _room.size() > 0:
				# 이미 원정을 마치고 돌아온 경우
				_phase = "done"
				client.send(Protocol.C.LOGOUT)
				return
			if args.has("create"):
				if _timer > 0.5:
					_log("creating expedition")
					_phase = "joining"
					client.send(Protocol.C.BOARD_CREATE, {"public": true, "difficulty": "normal", "class_id": String(args.get("class", "guardian"))})
					_timer = 0.0
			elif _timer > float(args.get("join_delay", 1.5)):
				var target := _resolve_join_target(String(args.get("join", "")))
				if target != "":
					_join_attempts += 1
					_log("joining %s (attempt %d)" % [target, _join_attempts])
					_phase = "joining"
					client.send(Protocol.C.BOARD_JOIN, {"expedition_id": target, "class_id": String(args.get("class", "guardian"))})
				else:
					client.send(Protocol.C.BOARD_LIST)
				_timer = 0.0


## "" → 참가 가능한 첫 원정, "host:<nick>" → 그 사람이 만든 원정, 그 외 → 원정 ID 그대로
func _resolve_join_target(spec: String) -> String:
	if spec.begins_with("host:"):
		var hn := spec.substr(5)
		for b: Dictionary in _board:
			if String(b.get("host_nick", "")) == hn:
				return String(b["id"])
		return ""
	if spec == "":
		for b: Dictionary in _board:
			if bool(b.get("joinable", false)):
				return String(b["id"])
		return ""
	return spec


func _phase_party() -> void:
	if _timer < 0.3:
		return
	var members: Array = _party.get("members", [])
	var me_ready := false
	for m: Dictionary in members:
		if m.get("id", "") == _my_id:
			me_ready = bool(m.get("ready", false))
	if not me_ready:
		client.send(Protocol.C.READY, {"ready": true, "class_id": String(args.get("class", "guardian"))})
		_timer = 0.0
		return
	if args.has("starter"):
		var want := int(args.get("party", 1))
		var all_ready := true
		for m: Dictionary in members:
			if not bool(m.get("ready", false)):
				all_ready = false
		if members.size() >= want and all_ready and _timer > 0.5:
			_log("starting expedition with %d members" % members.size())
			client.send(Protocol.C.BOARD_START)
			_timer = -3.0


func _phase_room() -> void:
	if args.has("drop") and not _dropped and _timer > float(args["drop"]):
		_dropped = true
		_drop_pending = true
		_log("simulating connection drop")
		client.disconnect_from_server("")
		await get_tree().create_timer(float(args.get("drop_wait", 1.5))).timeout
		_drop_pending = false
		_snapshot = {}
		var addr := String(args.get("addr", "127.0.0.1:7777")).split(":")
		_log("reconnecting")
		client.connect_to(addr[0], int(addr[1]) if addr.size() > 1 else Protocol.DEFAULT_PORT)
		return
	if _drop_pending or _snapshot.is_empty():
		return
	var me := PackedFloat32Array()
	for entry: Array in _snapshot.get("p", []):
		if entry[0] == _my_id:
			me = entry[1]
	if me.is_empty():
		return
	var my_pos := Vector2(me[Protocol.SNAP_P.X], me[Protocol.SNAP_P.Y])
	var my_state := int(me[Protocol.SNAP_P.STATE])
	var mv := Vector2.ZERO
	var aim := Vector2.ZERO
	var btn := 0
	if my_state == Protocol.EntState.ALIVE:
		var downed := PackedFloat32Array()
		for entry: Array in _snapshot.get("p", []):
			var p: PackedFloat32Array = entry[1]
			if int(p[Protocol.SNAP_P.STATE]) == Protocol.EntState.DOWNED:
				downed = p
		var nearest := PackedFloat32Array()
		var best := 1e9
		for entry: Array in _snapshot.get("e", []):
			var e: PackedFloat32Array = entry[2]
			if int(e[Protocol.SNAP_E.AI]) in [Protocol.EnemyAI.DEAD, Protocol.EnemyAI.RETREAT]:
				continue
			var ep := Vector2(e[Protocol.SNAP_E.X], e[Protocol.SNAP_E.Y])
			var d := ep.distance_to(my_pos)
			if d < best:
				best = d
				nearest = e
		var bs: Dictionary = _snapshot.get("boss", {})
		if not bs.is_empty() and int(bs.get("state", 0)) != BossIronclaw.BS.DEAD and not bool(bs.get("molting", false)):
			var bp := Vector2(float(bs["x"]), float(bs["y"]))
			var bd := bp.distance_to(my_pos) - 46.0
			if bd < best or nearest.is_empty():
				best = bd
				nearest = PackedFloat32Array([bp.x, bp.y, 0, 0, float(bs["hp"]), float(bs["max_hp"]), Protocol.EnemyAI.CHASE])
		# 보스 기믹 오브젝트: 가까운 상호작용물이 있으면 F 유지 (봇은 규칙을 모르지만 접근·조작은 한다)
		var boss_obj := PackedFloat32Array()
		if not bs.is_empty():
			for o: PackedFloat32Array in _snapshot.get("ob", []):
				if int(o[Protocol.SNAP_OB.KIND]) >= Protocol.ObKind.PILLAR and int(o[Protocol.SNAP_OB.KIND]) != Protocol.ObKind.HAZARD and int(o[Protocol.SNAP_OB.KIND]) != Protocol.ObKind.PLATFORM and int(o[Protocol.SNAP_OB.KIND]) != Protocol.ObKind.HUSK:
					var od := Vector2(o[2], o[3]).distance_to(my_pos)
					if od < 110.0 and (boss_obj.is_empty() or od < Vector2(boss_obj[2], boss_obj[3]).distance_to(my_pos)):
						boss_obj = o
		var in_danger := false
		for tg: PackedFloat32Array in _snapshot.get("tg", []):
			var tc := Vector2(tg[Protocol.SNAP_TG.X], tg[Protocol.SNAP_TG.Y])
			var rem := tg[Protocol.SNAP_TG.REMAINING]
			if int(tg[Protocol.SNAP_TG.TYPE]) == 1:
				var d := Vector2(tg[Protocol.SNAP_TG.DX], tg[Protocol.SNAP_TG.DY])
				var rel := my_pos - tc
				var along := rel.dot(d)
				var side := absf(rel.cross(d))
				if along > -20 and along < tg[Protocol.SNAP_TG.R] + 20 and side < tg[Protocol.SNAP_TG.W] * 0.5 + 24 and rem < 0.5:
					in_danger = true
					aim = Vector2(-d.y, d.x)
			elif tc.distance_to(my_pos) < tg[Protocol.SNAP_TG.R] + 20.0 and rem < 0.35:
				in_danger = true
				aim = my_pos - tc
		var obj: Array = _snapshot.get("obj", ["annihilate", 0, 0])
		var objective := String(obj[0])
		var target_obj := PackedFloat32Array()
		for o: PackedFloat32Array in _snapshot.get("ob", []):
			var kind := int(o[Protocol.SNAP_OB.KIND])
			if objective == "device" and kind == Protocol.ObKind.DEVICE and int(o[Protocol.SNAP_OB.STATE]) == 0:
				if target_obj.is_empty() or Vector2(o[2], o[3]).distance_to(my_pos) < Vector2(target_obj[2], target_obj[3]).distance_to(my_pos):
					target_obj = o
			elif objective == "hold_point" and kind == Protocol.ObKind.HOLD_ZONE:
				target_obj = o
		if not boss_obj.is_empty() and randf() < 0.7:
			var op := Vector2(boss_obj[Protocol.SNAP_OB.X], boss_obj[Protocol.SNAP_OB.Y])
			if op.distance_to(my_pos) > boss_obj[Protocol.SNAP_OB.R] + 40.0:
				mv = (op - my_pos).normalized()
			else:
				btn |= Protocol.BTN_INTERACT
			aim = op - my_pos
		elif not downed.is_empty():
			var dp := Vector2(downed[Protocol.SNAP_P.X], downed[Protocol.SNAP_P.Y])
			if dp.distance_to(my_pos) > 50.0:
				mv = (dp - my_pos).normalized()
			else:
				btn |= Protocol.BTN_INTERACT
			aim = dp - my_pos
		elif in_danger and int(me[Protocol.SNAP_P.DODGE]) > 0:
			mv = aim.normalized() if aim.length() > 0.1 else Vector2.RIGHT
			btn |= Protocol.BTN_DODGE
		elif not target_obj.is_empty() and (nearest.is_empty() or best > 90.0 or objective == "hold_point"):
			var op := Vector2(target_obj[Protocol.SNAP_OB.X], target_obj[Protocol.SNAP_OB.Y])
			var r := target_obj[Protocol.SNAP_OB.R]
			if objective == "hold_point":
				if op.distance_to(my_pos) > r * 0.5:
					mv = (op - my_pos).normalized()
				elif not nearest.is_empty() and best < 140.0:
					aim = Vector2(nearest[Protocol.SNAP_E.X], nearest[Protocol.SNAP_E.Y]) - my_pos
					btn |= Protocol.BTN_ATTACK
			else:
				if op.distance_to(my_pos) > r + 40.0:
					mv = (op - my_pos).normalized()
				else:
					btn |= Protocol.BTN_INTERACT
				aim = op - my_pos
		elif not nearest.is_empty():
			var ep := Vector2(nearest[Protocol.SNAP_E.X], nearest[Protocol.SNAP_E.Y])
			aim = ep - my_pos
			var reach := 60.0 if String(args.get("class", "guardian")) == "guardian" else 260.0
			if best > reach:
				mv = aim.normalized()
			else:
				btn |= Protocol.BTN_ATTACK
				if me[Protocol.SNAP_P.CD_E] <= 0.0 and randf() < 0.3:
					btn |= Protocol.BTN_E
				if me[Protocol.SNAP_P.CD_Q] <= 0.0 and randf() < 0.2:
					btn |= Protocol.BTN_Q
			if me[Protocol.SNAP_P.HP] < 60.0 and int(me[Protocol.SNAP_P.HEAL]) > 0 and best > 120.0:
				btn |= Protocol.BTN_HEAL
			if int(_snapshot.get("wood", 0)) >= 3 and randf() < 0.01:
				btn |= Protocol.BTN_BUILD
	_seq += 1
	client.send_input(_seq, mv, aim, btn)


func _phase_result() -> void:
	if _timer < 0.5:
		return
	var want_restarts := int(args.get("restarts", 0))
	var choice := "restart" if _restarts_done < want_restarts else "hub"
	var mine: String = ""
	for m: Dictionary in _party.get("members", []):
		if m.get("id", "") == _my_id:
			mine = String(m.get("choice", ""))
	if mine != choice:
		if choice == "restart":
			_restarts_done += 1
		_log("choosing %s" % choice)
		client.send(Protocol.C.ROOM_CHOICE, {"choice": choice})
		_timer = 0.0

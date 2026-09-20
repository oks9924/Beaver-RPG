class_name ExpeditionInstance
extends RefCounted
## 1~4인 원정 인스턴스. 다른 원정과 적·보상·상태를 공유하지 않는다.
## 파티 대표는 편의 기능만 가지며 월드·저장·전투 소유권은 서버에 있다 (14절).

var id: String
var seed_value: int
var state: int = Protocol.ExpState.PREPARING
var public: bool = true
var difficulty: String = "normal"
var created_at: float
var members: Dictionary = {}      # account_id -> {nickname, class_id, ready, connected, peer_id, disconnect_at, joined_at, heal_uses}
var room: CombatRoom = null
var room_index: int = 0
var room_id: String = "test_arena"
var choices: Dictionary = {}      # account_id -> "restart" | "hub"
var last_result: Dictionary = {}
var n_locked: int = 0
var suspended: bool = false
var suspended_at: float = 0.0
var content_version: String = Protocol.CONTENT_VERSION
var _snap_accum: int = 0
var rooms_cleared: int = 0
var host_nick: String = ""   # 편의 표시용. 대표 권한(서버 종료·데이터 삭제)은 없다.
var rng := RandomNumberGenerator.new()


func _init(expedition_id: String, seed_: int) -> void:
	id = expedition_id
	seed_value = seed_
	rng.seed = seed_
	created_at = Time.get_unix_time_from_system()


func member_count() -> int:
	return members.size()


func connected_count() -> int:
	var c := 0
	for m: Dictionary in members.values():
		if m["connected"]:
			c += 1
	return c


func is_joinable() -> bool:
	return state == Protocol.ExpState.PREPARING or state == Protocol.ExpState.RESULT


func can_join(account_id: String) -> String:
	if members.has(account_id):
		return ""
	if members.size() >= Protocol.MAX_PARTY_SIZE:
		return Protocol.ERR_PARTY_FULL
	if not is_joinable():
		return Protocol.ERR_BAD_STATE
	return ""


func add_member(s: Session) -> void:
	members[s.account_id] = {
		"nickname": s.nickname, "class_id": s.class_id, "ready": false, "connected": true, "peer_id": s.peer_id,
		"disconnect_at": 0.0, "joined_at": Time.get_unix_time_from_system(), "heal_uses": int(ContentDB.rule("heal_uses_per_expedition", 2)),
	}
	s.expedition_id = id
	s.location = Protocol.Location.PREPARING_EXPEDITION if state == Protocol.ExpState.PREPARING else Protocol.Location.RESULT
	choices.erase(s.account_id)


func remove_member(account_id: String) -> void:
	members.erase(account_id)
	choices.erase(account_id)
	if room != null:
		room.remove_player(account_id)


func set_ready(account_id: String, ready: bool, class_id: String) -> void:
	if members.has(account_id):
		members[account_id]["ready"] = ready
		if ContentDB.is_class_playable(class_id):
			members[account_id]["class_id"] = class_id


func all_ready() -> bool:
	if members.is_empty():
		return false
	for m: Dictionary in members.values():
		if m["connected"] and not m["ready"]:
			return false
	return true


func mark_disconnected(account_id: String) -> void:
	if not members.has(account_id):
		return
	members[account_id]["connected"] = false
	members[account_id]["disconnect_at"] = Time.get_unix_time_from_system()
	members[account_id]["ready"] = false
	if room != null:
		room.set_connected(account_id, false)
	if connected_count() == 0 and state == Protocol.ExpState.IN_ROOM:
		suspended = true
		suspended_at = Time.get_unix_time_from_system()


func mark_reconnected(s: Session) -> void:
	if not members.has(s.account_id):
		return
	members[s.account_id]["connected"] = true
	members[s.account_id]["peer_id"] = s.peer_id
	members[s.account_id]["disconnect_at"] = 0.0
	s.expedition_id = id
	if room != null:
		room.set_connected(s.account_id, true)
	if suspended:
		suspended = false
	match state:
		Protocol.ExpState.IN_ROOM: s.location = Protocol.Location.IN_ROOM
		Protocol.ExpState.RESULT: s.location = Protocol.Location.RESULT
		_: s.location = Protocol.Location.PREPARING_EXPEDITION


## 유예 시간이 지난 이탈자를 정리한다. 돌려주는 값은 제거된 계정 ID 목록.
func prune_disconnected(grace_sec: float) -> Array:
	var removed: Array = []
	var now := Time.get_unix_time_from_system()
	for aid: String in members.keys():
		var m: Dictionary = members[aid]
		if not m["connected"] and now - float(m["disconnect_at"]) > grace_sec:
			removed.append(aid)
	for aid: String in removed:
		remove_member(aid)
	return removed


## 방 시작: 이 시점의 연결된 멤버 수로 N 을 확정하고 프로필을 고정한다.
func start_room() -> Dictionary:
	var member_list: Array = []
	for aid: String in members.keys():
		var m: Dictionary = members[aid]
		if not m["connected"]:
			continue
		member_list.append({"account_id": aid, "nickname": m["nickname"], "class_id": m["class_id"], "connected": true, "heal_uses": m["heal_uses"]})
		m["ready"] = false
	n_locked = clampi(member_list.size(), 1, Protocol.MAX_PARTY_SIZE)
	var profile := ContentDB.get_party_profile(n_locked)
	var room_seed := int(rng.randi())
	room = CombatRoom.new(ContentDB.get_room_def(room_id), profile, ContentDB.rules, room_seed, member_list)
	room_index += 1
	state = Protocol.ExpState.IN_ROOM
	choices.clear()
	last_result = {}
	return room_enter_payload()


func room_enter_payload() -> Dictionary:
	var def := ContentDB.get_room_def(room_id)
	var party: Array = []
	for aid: String in members.keys():
		var m: Dictionary = members[aid]
		party.append({"id": aid, "nick": m["nickname"], "class_id": m["class_id"], "connected": m["connected"]})
	return {
		"expedition_id": id, "room_index": room_index, "room_id": room_id, "room_def": def, "seed": room.seed_value if room else 0,
		"n": n_locked, "profile": ContentDB.get_party_profile(n_locked), "party": party, "difficulty": difficulty,
		"rules": {"down_duration_sec": ContentDB.rule("down_duration_sec"), "rescue_hold_sec": ContentDB.rule("rescue_hold_sec"), "rescue_range": ContentDB.rule("rescue_range"), "dodge_charges": ContentDB.rule("dodge_charges")},
		"content_version": content_version,
	}


func party_payload() -> Dictionary:
	var party: Array = []
	for aid: String in members.keys():
		var m: Dictionary = members[aid]
		party.append({"id": aid, "nick": m["nickname"], "class_id": m["class_id"], "ready": m["ready"], "connected": m["connected"], "choice": choices.get(aid, "")})
	return {"expedition_id": id, "state": state, "public": public, "difficulty": difficulty, "members": party, "room_index": room_index, "rooms_cleared": rooms_cleared, "suspended": suspended, "seed": seed_value}


func board_entry() -> Dictionary:
	return {"id": id, "state": state, "public": public, "difficulty": difficulty, "members": members.size(), "max": Protocol.MAX_PARTY_SIZE, "room_index": room_index, "joinable": is_joinable() and members.size() < Protocol.MAX_PARTY_SIZE, "host_nick": host_nick}


## 서버 tick. 돌려주는 값: {"events": [...], "snapshot": {...} | null, "finished": bool}
func step(dt: float, snapshot_every: int) -> Dictionary:
	var out := {"events": [], "snapshot": null, "finished": false}
	if state != Protocol.ExpState.IN_ROOM or room == null or suspended:
		return out
	out["events"] = room.step(dt).duplicate()
	_snap_accum += 1
	if _snap_accum >= snapshot_every:
		_snap_accum = 0
		out["snapshot"] = room.snapshot()
	if room.is_finished():
		state = Protocol.ExpState.RESULT
		last_result = room.result_summary()
		if room.outcome == Protocol.Outcome.VICTORY:
			rooms_cleared += 1
		out["finished"] = true
		choices.clear()
	return out


func set_choice(account_id: String, choice: String) -> void:
	if members.has(account_id) and choice in ["restart", "hub"]:
		choices[account_id] = choice


## RESULT 상태에서 연결된 전원이 같은 선택을 했는지. "" 이면 아직 대기.
func resolved_choice() -> String:
	if state != Protocol.ExpState.RESULT:
		return ""
	var first := ""
	for aid: String in members.keys():
		if not members[aid]["connected"]:
			continue
		var c: String = choices.get(aid, "")
		if c == "":
			return ""
		if first == "":
			first = c
		elif c != first:
			return ""
	return first

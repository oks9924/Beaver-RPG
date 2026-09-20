class_name ExpeditionManager
extends RefCounted
## 원정 모집판과 활성 인스턴스 관리. 서버 정원(max_online_players)과 원정 상한(max_active_expeditions)을 구분한다.

var instances: Dictionary = {}   # id -> ExpeditionInstance
var max_active: int = 2
var _seq: int = 1
var rng := RandomNumberGenerator.new()


func _init(max_active_expeditions: int, seed_: int) -> void:
	max_active = max_active_expeditions
	rng.seed = seed_


func active_count() -> int:
	var c := 0
	for e: ExpeditionInstance in instances.values():
		if e.state != Protocol.ExpState.CLOSED:
			c += 1
	return c


func running_count() -> int:
	var c := 0
	for e: ExpeditionInstance in instances.values():
		if e.state == Protocol.ExpState.IN_ROOM:
			c += 1
	return c


func create(s: Session, public: bool, difficulty: String, permanent: Dictionary = {}, tutorial: bool = false) -> Dictionary:
	if s.expedition_id != "":
		return {"ok": false, "error": Protocol.ERR_ALREADY_IN_EXPEDITION}
	if active_count() >= max_active:
		return {"ok": false, "error": Protocol.ERR_EXPEDITION_LIMIT}
	var id := "exp_%d_%04x" % [_seq, rng.randi() & 0xFFFF]
	_seq += 1
	var inst := ExpeditionInstance.new(id, int(rng.randi()))
	inst.public = public
	inst.difficulty = difficulty if (ContentDB.rules.get("difficulties", {}) as Dictionary).has(difficulty) else "normal"
	inst.tutorial = tutorial
	if tutorial:
		inst.public = false
	inst.host_nick = s.nickname
	inst.add_member(s, permanent)
	instances[id] = inst
	return {"ok": true, "expedition": inst}


func join(s: Session, id: String, permanent: Dictionary = {}) -> Dictionary:
	if s.expedition_id != "":
		return {"ok": false, "error": Protocol.ERR_ALREADY_IN_EXPEDITION}
	var inst: ExpeditionInstance = instances.get(id, null)
	if inst == null or inst.state == Protocol.ExpState.CLOSED:
		return {"ok": false, "error": Protocol.ERR_NO_EXPEDITION}
	if inst.paused:
		if not inst.members.has(s.account_id):
			return {"ok": false, "error": Protocol.ERR_NO_EXPEDITION}
		inst.resume_member(s)
		return {"ok": true, "expedition": inst, "resumed": true}
	var err := inst.can_join(s.account_id)
	if err != "":
		return {"ok": false, "error": err}
	inst.add_member(s, permanent)
	return {"ok": true, "expedition": inst}


func get_for_session(s: Session) -> ExpeditionInstance:
	if s.expedition_id == "":
		return null
	return instances.get(s.expedition_id, null)


func find_by_member(account_id: String) -> ExpeditionInstance:
	for e: ExpeditionInstance in instances.values():
		if e.state != Protocol.ExpState.CLOSED and e.members.has(account_id):
			return e
	return null


func leave(s: Session) -> ExpeditionInstance:
	var inst := get_for_session(s)
	if inst == null:
		s.expedition_id = ""
		return null
	inst.remove_member(s.account_id)
	s.expedition_id = ""
	if inst.member_count() == 0:
		close(inst)
	return inst


func close(inst: ExpeditionInstance) -> void:
	inst.state = Protocol.ExpState.CLOSED
	instances.erase(inst.id)


## 공개 원정 + (account_id 가 주어지면) 그 계정이 멤버인 중단된 원정(이어하기)
func board_list(account_id: String = "") -> Array:
	var out: Array = []
	for e: ExpeditionInstance in instances.values():
		if e.state == Protocol.ExpState.CLOSED:
			continue
		if e.paused and account_id != "" and e.members.has(account_id):
			var entry := e.board_entry()
			entry["resume"] = true
			entry["joinable"] = true
			out.append(entry)
			continue
		if not e.public or e.paused:
			continue
		out.append(e.board_entry())
	return out

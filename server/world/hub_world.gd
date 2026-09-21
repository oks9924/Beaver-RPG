class_name HubWorld
extends RefCounted
## 서버가 소유·저장하는 공용 마을. 접속자가 0명이어도 사라지지 않는다.
## 단계 1: 자유 이동, 접속자 목록, 마을 통계·구조물 단계 저장. 전투 판정은 없다.

const HUB_W := 1600.0
const HUB_H := 1000.0
const SPAWN := Vector2(800, 620)
const SPEED := 200.0

var world: Dictionary = {}
var sessions: Dictionary = {}   # account_id -> Session
var bounds := Rect2(0, 0, HUB_W, HUB_H)
var obstacles: Array = [
	{"shape": "circle", "x": 800, "y": 380, "r": 70, "asset": "prop.hub.memory_tree"},
	{"shape": "circle", "x": 1100, "y": 700, "r": 50, "asset": "prop.willow.log"},
]
var dirty: bool = false


static func new_world(world_id: String, name: String) -> Dictionary:
	return {
		"schema_version": StoreBase.SCHEMA_VERSION,
		"world_id": world_id,
		"name": name,
		"created_at": int(Time.get_unix_time_from_system()),
		"boot_count": 0,
		"hub": {
			"structures": {"memory_tree": {"level": 1}, "workshop": {"level": 0}},
			"total_visits": 0,
			"total_expeditions": 0,
			"total_rooms_cleared": 0,
			"total_wipes": 0,
		},
		"counters": {"next_expedition_seq": 1},
	}


func enter(s: Session) -> void:
	s.location = Protocol.Location.HUB
	s.hub_pos = SPAWN + Vector2(randf_range(-60, 60), randf_range(-30, 30))
	s.hub_move = Vector2.ZERO
	sessions[s.account_id] = s
	world["hub"]["total_visits"] = int(world["hub"].get("total_visits", 0)) + 1
	dirty = true


func leave(account_id: String) -> void:
	sessions.erase(account_id)


func has(account_id: String) -> bool:
	return sessions.has(account_id)


func apply_input(s: Session, mv: Vector2, _aim: Vector2) -> void:
	s.hub_move = mv.limit_length(1.0)
	s.hub_facing = SimRules.move_facing(mv, s.hub_facing)   # 마을에서는 이동 방향만 본다


func step(dt: float) -> void:
	for s: Session in sessions.values():
		if s.hub_move.length_squared() > 0.0001:
			s.hub_pos = SimRules.move(s.hub_pos, s.hub_move, SPEED, dt, bounds, 18.0, obstacles)


func snapshot() -> Dictionary:
	var ps: Array = []
	for s: Session in sessions.values():
		ps.append([s.account_id, snappedf(s.hub_pos.x, 0.1), snappedf(s.hub_pos.y, 0.1), snappedf(s.hub_facing.x, 0.01), snappedf(s.hub_facing.y, 0.01), s.class_id, 1 if s.hub_move.length_squared() > 0.0001 else 0])
	return {"hub": 1, "p": ps}


func roster() -> Array:
	var out: Array = []
	for s: Session in sessions.values():
		out.append({"id": s.account_id, "nick": s.nickname, "class_id": s.class_id})
	return out


func hub_info() -> Dictionary:
	return {
		"world_id": world.get("world_id", ""),
		"name": world.get("name", ""),
		"created_at": world.get("created_at", 0),
		"boot_count": world.get("boot_count", 0),
		"structures": world["hub"].get("structures", {}),
		"total_visits": world["hub"].get("total_visits", 0),
		"total_expeditions": world["hub"].get("total_expeditions", 0),
		"total_rooms_cleared": world["hub"].get("total_rooms_cleared", 0),
		"total_wipes": world["hub"].get("total_wipes", 0),
		"bounds": [bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y],
		"obstacles": obstacles,
		"spawn": [SPAWN.x, SPAWN.y],
		"village": ContentDB.village.get("structures", {}),
		"npcs": _npc_list(),
		"bonus": ContentDB.village_bonus(world["hub"].get("structures", {})),
	}


func _npc_list() -> Array:
	var out: Array = []
	for nid: String in ContentDB.npcs.keys():
		if nid.begins_with("_"):
			continue
		var n: Dictionary = ContentDB.npcs[nid]
		out.append({"id": nid, "name_ko": n.get("name_ko", nid), "role_ko": n.get("role_ko", ""), "x": n.get("x", 0), "y": n.get("y", 0), "sprite": n.get("assets", {}).get("sprite", "")})
	return out

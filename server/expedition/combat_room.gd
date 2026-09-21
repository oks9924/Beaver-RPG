class_name CombatRoom
extends RefCounted
## 서버 권위 전투방 시뮬레이션. 노드·렌더링에 의존하지 않는 순수 상태 기계.
## 이동·공격·피격·회피·다운·구조·전멸·웨이브·목표·상호작용물·투사체·구조물·수문을 서버 시간(tick)으로 판정한다.
## 방 시작 시 기준 인원 N 과 PartyScalingProfile 을 고정하며, 다운·이탈로 즉시 낮추지 않는다 (8절).

var room_def: Dictionary
var profile: Dictionary
var rules: Dictionary
var seed_value: int
var n_players: int
var rng := RandomNumberGenerator.new()
var tick: int = 0
var elapsed: float = 0.0
var players: Dictionary = {}    # account_id -> state dict
var enemies: Dictionary = {}    # enemy_id -> state dict
var projectiles: Array = []
var objects: Dictionary = {}    # object_id -> {id, kind, pos, r, ...}
var next_enemy_id: int = 1
var next_object_id: int = 1
var bounds: Rect2
var obstacles: Array = []
var outcome: int = Protocol.Outcome.NONE
var objective: String = "annihilate"
var objective_progress: float = 0.0
var objective_done: bool = false
var wave_index: int = 0
var wave_count: int = 1
var wave_budget_total: float = 0.0
var _wave_gap_t: float = 0.0
var _all_spawned: bool = false
var events: Array = []
var stats := {"enemies_spawned": 0, "enemies_killed": 0, "downs": 0, "rescues": 0, "deaths": 0, "kills_by_type": {}, "wood_gained": 0, "builds": 0, "sluice_toggles": 0, "gnaws": 0, "secrets": []}
var hit_damage_mult: float = 1.0
var team_wood: int = 0
var water_zone: Dictionary = {}   # {x,y,w,h,state(0 low,1 warning,2 high), t}
var hazards: Array = []           # 지역 위험 구역 [{x,y,w,h,kind,slow,dps}] (수액 웅덩이 등)
var _members_snapshot: Array = []
var pending_events: Array = []     # 서버 틱 밖에서 들어온 이벤트(핑 등)를 다음 틱 이벤트에 싣는다
var tutorial_step: int = 0
var _tutorial_moved: float = 0.0
var _tutorial_flags: Dictionary = {}
var elite_spawned: bool = false
var _director_reserve: float = 0.0     # 웨이브 뒤 증원용 예산 (RoR2 디렉터 크레딧). 0 이 되면 증원이 끝난다
var _director_credits: float = 0.0
var _affix_elites_this_wave: int = 0
var _forced_elite_done: bool = false
var enemy_pool: Array = []
var boss: RefCounted = null        # 보스방일 때 BossController (단계 2-3)
var _retreat_t: float = -1.0
var explore: bool = false          # 던파식 탐색 모드: 클리어된 방. 적 없음, 문으로 이동
var doors: Array = []              # [{dir, target, target_type, target_cleared, pos}] (opts.doors)
var pending_travel: String = ""    # 문 이동이 결정되면 방향("n"/"e"/"s"/"w")
var entry_dir: String = ""
var entry_spawns: Dictionary = {}  # account_id -> [x, y] (문 기준 입장 위치)


func _init(def: Dictionary, party_profile: Dictionary, game_rules: Dictionary, seed_: int, members: Array, opts: Dictionary = {}) -> void:
	room_def = def
	profile = party_profile
	rules = game_rules
	seed_value = seed_
	rng.seed = seed_
	n_players = clampi(int(party_profile.get("n", members.size())), 1, Protocol.MAX_PARTY_SIZE)
	var b: Dictionary = def.get("bounds", {"x": 0, "y": 0, "w": 1200, "h": 800})
	bounds = Rect2(b["x"], b["y"], b["w"], b["h"])
	obstacles = def.get("obstacles", []).duplicate(true)
	hit_damage_mult = float(profile.get("hit_damage_mult", 1.0)) * float(profile.get("player_damage_taken_mult", 1.0))
	objective = String(def.get("objective", "annihilate"))
	enemy_pool = opts.get("enemy_pool", def.get("enemy_pool", [{"id": "sap_snail", "weight": 1.0}]))
	team_wood = int(opts.get("team_wood", 0))
	var w: Dictionary = def.get("waves", {})
	wave_count = maxi(int(w.get("wave_count", 1)), 1)
	wave_budget_total = (float(w.get("base_budget", 4.0)) + float(opts.get("budget_add", 0.0))) * float(profile.get("wave_budget_mult", 1.0))
	var dr: Dictionary = game_rules.get("director", {})
	_director_reserve = wave_budget_total * float(dr.get("reserve_frac", 0.5)) if float(w.get("base_budget", 0.0)) > 0.0 else 0.0
	explore = bool(opts.get("explore", false))
	if explore:
		objective = "explore"
	entry_dir = String(opts.get("entry_dir", ""))
	doors = (opts.get("doors", []) as Array).duplicate(true)
	# 문 기준 입장: 들어온 문 앞에 부채꼴로 선다. 보스방은 항상 정해진 입구(플레이어 스폰)를 쓴다.
	var spawns: Array = def.get("player_spawns", [[100, 100]])
	if entry_dir != "" and objective != "boss":
		spawns = entry_spawn_points(def, entry_dir, game_rules)
		if entry_dir == "e":
			# 동쪽에서 들어오면 적 스폰을 좌우 반전해 반대편에서 나오게 한다
			room_def = def.duplicate(true)
			var mirrored: Array = []
			for sp: Array in def.get("enemy_spawns", []):
				mirrored.append([bounds.position.x + bounds.size.x - float(sp[0]), float(sp[1])])
			room_def["enemy_spawns"] = mirrored
	var i := 0
	_members_snapshot = members
	for m: Dictionary in members:
		add_player(m, spawns[i % spawns.size()], members.size())
		entry_spawns[String(m.get("account_id", ""))] = spawns[i % spawns.size()]
		i += 1
	hazards = def.get("hazards", []).duplicate(true)
	_setup_objects()
	_setup_doors()
	if objective != "boss" and not explore:
		_spawn_wave()
	if objective == "tutorial":
		var steps: Array = rules.get("tutorial_steps", [])
		if not steps.is_empty():
			pending_events.append({"k": "tutorial_step", "index": 0, "total": steps.size(), "text": steps[0].get("text_ko", "")})


# ------------------------------------------------------------------ setup

func _setup_objects() -> void:
	if explore:
		_setup_secret()
		return
	for t: Array in room_def.get("gnaw_trees", []):
		var o := _add_object(Protocol.ObKind.GNAW_TREE, Vector2(t[0], t[1]), 30.0, {"hold_sec": float(rules.get("gnaw_hold_sec", 1.2))})
		obstacles.append({"shape": "circle", "x": o["pos"].x, "y": o["pos"].y, "r": 30, "object_id": o["id"]})
	for d: Dictionary in room_def.get("devices", []):
		_add_object(Protocol.ObKind.DEVICE, Vector2(float(d["x"]), float(d["y"])), 34.0, {"hold_sec": float(d.get("hold_sec", 4.0))})
	var hz: Dictionary = room_def.get("hold_zone", {})
	if not hz.is_empty():
		_add_object(Protocol.ObKind.HOLD_ZONE, Vector2(float(hz["x"]), float(hz["y"])), float(hz.get("r", 120)), {"required": float(hz.get("required_sec", 20)), "contest_radius": float(hz.get("contest_radius", 140))})
	_setup_secret()
	var esc: Dictionary = room_def.get("escort", {})
	if not esc.is_empty() and objective == "escort":
		var path: Array = esc.get("path", [[100, 100], [900, 100]])
		_add_object(Protocol.ObKind.RAFT, Vector2(path[0][0], path[0][1]), 34.0, {"path": path, "seg": 0, "speed": float(esc.get("speed", 55)), "radius": float(esc.get("radius", 140)), "contest_radius": float(esc.get("contest_radius", 170)), "hp": float(esc.get("hp", 200)), "max_hp": float(esc.get("hp", 200)), "total_len": _path_length(path), "done_len": 0.0})
	var sl: Variant = room_def.get("sluice", null)
	if sl is Dictionary:
		var lever: Array = sl["lever"]
		_add_object(Protocol.ObKind.SLUICE_LEVER, Vector2(lever[0], lever[1]), 28.0, {"hold_sec": float(sl.get("hold_sec", 1.5))})
		var z: Dictionary = sl["zone"]
		water_zone = {"x": float(z["x"]), "y": float(z["y"]), "w": float(z["w"]), "h": float(z["h"]), "state": 0, "t": 0.0}


func _setup_secret() -> void:
	var sec: Dictionary = room_def.get("secret", {})
	if not sec.is_empty() and rng.randf() < float(sec.get("chance", 0.6)):
		var found := false
		for m: Dictionary in _members_snapshot:
			if (m.get("secrets_found", []) as Array).has(String(sec.get("id", ""))):
				found = true
		if not found:
			_add_object(Protocol.ObKind.SECRET, Vector2(float(sec["x"]), float(sec["y"])), 24.0, {"hold_sec": 2.0, "interactable": true, "secret_id": String(sec.get("id", "")), "name_ko": String(sec.get("name_ko", ""))})


## 던파식 문: 격자에서 이웃 방이 있는 방향에만 놓인다. 전투 중엔 잠기고(비트 7) 클리어 뒤 열린다.
func _setup_doors() -> void:
	var dr: Dictionary = rules.get("dungeon_doors", {})
	var positions := door_positions(room_def, rules)
	for d: Dictionary in doors:
		var dir := String(d.get("dir", "e"))
		if not positions.has(dir):
			continue
		var o := _add_object(Protocol.ObKind.DOOR, positions[dir], float(dr.get("radius", 72)), {"dir": dir, "target": String(d.get("target", "")), "target_type": String(d.get("target_type", "combat")), "target_cleared": bool(d.get("target_cleared", false)), "locked": not explore, "inside": 0})
		_refresh_door_state(o)


func _refresh_door_state(o: Dictionary) -> void:
	var st := Protocol.DOOR_DIRS.find(String(o.get("dir", "e")))
	st |= maxi(Protocol.DOOR_TYPES.find(String(o.get("target_type", "combat"))), 0) << 2
	if bool(o.get("target_cleared", false)):
		st |= 1 << 6
	if bool(o.get("locked", false)):
		st |= 1 << 7
	st |= clampi(int(o.get("inside", 0)), 0, 7) << 8
	o["state"] = st


## 방 정의의 경계·물·장애물을 피해서 네 방향 문 위치를 정한다 (서버·검수 도구 공용).
static func door_positions(def: Dictionary, game_rules: Dictionary) -> Dictionary:
	var b: Dictionary = def.get("bounds", {"x": 0, "y": 0, "w": 1200, "h": 800})
	var rect := Rect2(float(b["x"]), float(b["y"]), float(b["w"]), float(b["h"]))
	var margin := float(game_rules.get("dungeon_doors", {}).get("margin", 90))
	var c := rect.get_center()
	var out := {
		"n": Vector2(c.x, rect.position.y + margin), "s": Vector2(c.x, rect.end.y - margin),
		"e": Vector2(rect.end.x - margin, c.y), "w": Vector2(rect.position.x + margin, c.y),
	}
	for dir: String in out.keys():
		var pos: Vector2 = out[dir]
		var inward: Vector2 = (c - pos).normalized()
		var guard := 0
		while guard < 40 and _door_blocked(pos, def):
			pos += inward * 20.0
			guard += 1
		out[dir] = pos
	return out


static func _door_blocked(pos: Vector2, def: Dictionary) -> bool:
	for w: Dictionary in def.get("water", []):
		var r := Rect2(float(w["x"]) - 40.0, float(w["y"]) - 40.0, float(w["w"]) + 80.0, float(w["h"]) + 80.0)
		if r.has_point(pos):
			return true
	for o: Dictionary in def.get("obstacles", []):
		if String(o.get("shape", "circle")) == "circle" and pos.distance_to(Vector2(float(o["x"]), float(o["y"]))) < float(o.get("r", 30)) + 70.0:
			return true
	return false


## 들어온 문 앞 입장 위치 4개 (문에서 안쪽으로 entry_offset, 좌우로 부채꼴)
static func entry_spawn_points(def: Dictionary, dir: String, game_rules: Dictionary) -> Array:
	var positions := door_positions(def, game_rules)
	var b: Dictionary = def.get("bounds", {"x": 0, "y": 0, "w": 1200, "h": 800})
	var c := Rect2(float(b["x"]), float(b["y"]), float(b["w"]), float(b["h"])).get_center()
	var door: Vector2 = positions.get(dir, c)
	var inward: Vector2 = (c - door).normalized()
	var side := Vector2(-inward.y, inward.x)
	var base: Vector2 = door + inward * float(game_rules.get("dungeon_doors", {}).get("entry_offset", 120))
	var rect := Rect2(float(b["x"]), float(b["y"]), float(b["w"]), float(b["h"])).grow(-40.0)
	var out: Array = []
	for k: float in [0.0, -1.0, 1.0, -2.0]:
		var p := base + side * 44.0 * k + inward * 18.0 * absf(k)
		# 장애물 안이면 장애물 중심 반대쪽으로 밀어낸다
		for guard in 3:
			for o: Dictionary in def.get("obstacles", []):
				var oc := Vector2(float(o["x"]), float(o["y"]))
				var need := float(o.get("r", 30)) + 26.0
				var dist := p.distance_to(oc)
				if dist < need:
					p = oc + ((p - oc).normalized() if dist > 0.5 else inward) * need
		p = Vector2(clampf(p.x, rect.position.x, rect.end.x), clampf(p.y, rect.position.y, rect.end.y))
		out.append([p.x, p.y])
	return out


## 클리어된 방을 탐색 모드로 바꾼다: 적·투사체·목표 오브젝트를 치우고 문을 연다. 플레이어 위치는 그대로.
func enter_explore() -> void:
	explore = true
	objective = "explore"
	objective_done = false
	outcome = Protocol.Outcome.NONE
	pending_travel = ""
	enemies.clear()
	projectiles.clear()
	boss = null
	hazards = hazards.filter(func(h: Dictionary) -> bool: return not h.has("life"))
	for oid: int in objects.keys().duplicate():
		var o: Dictionary = objects[oid]
		if int(o["kind"]) in [Protocol.ObKind.DOOR, Protocol.ObKind.SECRET, Protocol.ObKind.STRUCTURE, Protocol.ObKind.TRAP]:
			continue
		objects.erase(oid)
	for o: Dictionary in objects.values():
		if int(o["kind"]) == Protocol.ObKind.DOOR:
			o["locked"] = false
			o["progress"] = 0.0
			_refresh_door_state(o)
	for p: Dictionary in players.values():
		if p["state"] == Protocol.EntState.DOWNED:
			# 클리어 시점에 다운돼 있던 사람은 일어난다 (돌아온 체력은 원정 규칙이 정한다)
			p["state"] = Protocol.EntState.ALIVE
			p["hp"] = maxf(p["hp"], float(p["max_hp"]) * float(rules.get("return_from_death_hp_fraction", 0.5)))
			p["down_t"] = 0.0
	events.append({"k": "explore", "doors": doors.size()})


## 문 집합 판정: 살아 있는 접속 인원이 전원이면 all_sec, 과반이면 majority_sec 뒤에 이동. 아니면 진행이 줄어든다.
func _step_doors(dt: float) -> void:
	if pending_travel != "":
		return
	var dr: Dictionary = rules.get("dungeon_doors", {})
	var total := alive_connected_count()
	for o: Dictionary in objects.values():
		if int(o["kind"]) != Protocol.ObKind.DOOR or bool(o.get("locked", false)):
			continue
		var inside := 0
		for p: Dictionary in players.values():
			if p["state"] == Protocol.EntState.ALIVE and p["connected"] and (p["pos"] as Vector2).distance_to(o["pos"]) <= float(o["r"]):
				inside += 1
		o["inside"] = inside
		var prog := float(o["progress"])
		if total > 0 and inside >= total:
			prog += dt / maxf(float(dr.get("all_sec", 3.0)), 0.1)
		elif total > 0 and inside * 2 > total:
			prog += dt / maxf(float(dr.get("majority_sec", 10.0)), 0.1)
		else:
			prog = maxf(prog - dt * 0.5, 0.0)
		o["progress"] = clampf(prog, 0.0, 1.0)
		_refresh_door_state(o)
		if prog >= 1.0:
			pending_travel = String(o["dir"])
			events.append({"k": "door", "dir": pending_travel, "target": String(o.get("target", "")), "target_type": String(o.get("target_type", ""))})
			return


func _add_object(kind: int, pos: Vector2, r: float, extra: Dictionary) -> Dictionary:
	var o := {"id": next_object_id, "kind": kind, "pos": pos, "r": r, "progress": 0.0, "state": 0, "hold_sec": 1.0}
	o.merge(extra, true)
	next_object_id += 1
	objects[o["id"]] = o
	return o


func add_player(m: Dictionary, spawn: Array, members_count: int = 1) -> Dictionary:
	var cdef: Dictionary = ContentDB.get_class_def(String(m.get("class_id", "guardian")))
	var mods: Dictionary = m.get("mods", RunMods.empty())
	var max_hp := float(cdef.get("base_hp", 100)) + float(mods.get("max_hp_add", 0.0)) + float(mods.get("hp_per_ally", 0.0)) * clampf(members_count - 1, 0, 3)
	var p := {
		"id": m["account_id"], "nick": m.get("nickname", ""), "class_id": cdef.get("id", "guardian"),
		"pos": Vector2(spawn[0], spawn[1]), "facing": Vector2(1, 0), "speed": float(cdef.get("move_speed", 180)) * (1.0 + float(mods.get("speed_mult", 0.0))),
		"radius": float(cdef.get("radius", 18)), "hp": maxf(minf(float(m.get("hp", max_hp)), max_hp), 1.0) if m.has("hp") else max_hp, "max_hp": max_hp, "state": Protocol.EntState.ALIVE,
		"action": Protocol.Action.IDLE, "action_kind": "", "action_t": 0.0, "action_total": 0.0, "hit_applied": false,
		"cd": {"q": 0.0, "e": 0.0, "r": 0.0}, "dodge_max": maxi(int(rules.get("dodge_charges", 2)) + int(mods.get("dodge_charges_add", 0)) + int(profile.get("dodge_charges_add", 0)), 1), "dodge_charges": 0, "dodge_recharge_t": 0.0,
		"invuln_t": 0.0, "protect_t": 0.0, "shield": 0.0, "shield_t": 0.0, "front_guard_t": 0.0, "stagger_t": 0.0,
		"down_t": 0.0, "rescue_target": "", "rescue_t": 0.0, "rescued_count": 0, "heal_uses": int(m.get("heal_uses", rules.get("heal_uses_per_expedition", 2))),
		"connected": bool(m.get("connected", true)), "disconnect_t": 0.0, "inputs": [], "last_seq": 0, "prev_buttons": 0, "move_dir": Vector2.ZERO,
		"mods": mods, "procs": m.get("procs", []), "interact_target": 0, "grab_t": 0.0,
		"resource": 0.0, "resource_t": 0.0, "haste_t": 0.0, "haste_mult": 0.0, "whirl_t": 0.0, "whirl_tick": 0.0, "heal_log": [], "delayed": [], "guard_bonus": 0.0, "build_kind": String(m.get("build_kind", "log_cover")),
		"slow_t": 0.0, "slow_mult": 0.0, "root_t": 0.0, "bleed_t": 0.0, "bleed_dps": 0.0, "heal_cut_t": 0.0, "heal_cut_mult": 1.0,
		"stats": {"damage_dealt": 0.0, "damage_taken": 0.0, "kills": 0, "downs": 0, "rescues": 0, "deaths": 0, "objective": 0.0, "guards": 0},
	}
	p["dodge_charges"] = p["dodge_max"]
	if float(mods.get("start_shield", 0.0)) > 0.0:
		p["shield"] = minf(float(mods["start_shield"]), float(rules.get("caps", {}).get("shield_max", 60)) + float(mods.get("shield_cap_add", 0.0)))
		p["shield_t"] = 20.0
	players[p["id"]] = p
	return p


func remove_player(id: String) -> void:
	players.erase(id)


func set_connected(id: String, connected: bool) -> void:
	if players.has(id):
		players[id]["connected"] = connected
		players[id]["disconnect_t"] = 0.0
		if not connected:
			players[id]["inputs"].clear()
			players[id]["move_dir"] = Vector2.ZERO


func queue_input(id: String, seq: int, mv: Vector2, aim: Vector2, buttons: int) -> void:
	var p: Dictionary = players.get(id, {})
	if p.is_empty():
		return
	if seq <= int(p["last_seq"]) or seq <= int(p.get("last_queued_seq", 0)):
		return  # 중복·역순 입력 무시
	p["last_queued_seq"] = seq
	var q: Array = p["inputs"]
	if q.size() >= int(rules.get("input_queue_max", 8)):
		q.pop_front()
	q.append({"seq": seq, "mv": mv.limit_length(1.0), "aim": aim, "btn": buttons})


func is_finished() -> bool:
	return outcome != Protocol.Outcome.NONE


func alive_connected_count() -> int:
	var c := 0
	for p: Dictionary in players.values():
		if p["state"] == Protocol.EntState.ALIVE and p["connected"]:
			c += 1
	return c


func any_connected() -> bool:
	for p: Dictionary in players.values():
		if p["connected"]:
			return true
	return false


func all_obstacles() -> Array:
	var out := obstacles.duplicate()
	for o: Dictionary in objects.values():
		if o["kind"] in [Protocol.ObKind.STRUCTURE, Protocol.ObKind.DAM]:
			out.append({"shape": "circle", "x": o["pos"].x, "y": o["pos"].y, "r": o["r"]})
	return out


# ------------------------------------------------------------------ tick

func step(dt: float) -> Array:
	events.clear()
	if not pending_events.is_empty():
		events.append_array(pending_events)
		pending_events.clear()
	if is_finished():
		return events
	tick += 1
	elapsed += dt
	for p: Dictionary in players.values():
		_step_player(p, dt)
	for e: Dictionary in enemies.values():
		_step_enemy(e, dt)
	_separate_enemies()
	_step_projectiles(dt)
	_step_objects(dt)
	# 임시 위험 구역(젖은 정예 웅덩이 등)은 수명이 다하면 사라진다
	for i in range(hazards.size() - 1, -1, -1):
		var hz: Dictionary = hazards[i]
		if hz.has("life"):
			hz["life"] = float(hz["life"]) - dt
			if float(hz["life"]) <= 0.0:
				hazards.remove_at(i)
	_step_water(dt)
	if explore:
		_step_doors(dt)
		return events
	if boss != null:
		boss.step(dt)
	_step_waves(dt)
	_step_objective(dt)
	_check_outcome()
	return events


func _step_player(p: Dictionary, dt: float) -> void:
	for k in ["q", "e", "r"]:
		p["cd"][k] = maxf(float(p["cd"][k]) - dt, 0.0)
	if int(p["dodge_charges"]) < int(p["dodge_max"]):
		p["dodge_recharge_t"] = float(p["dodge_recharge_t"]) + dt
		if float(p["dodge_recharge_t"]) >= maxf(float(rules.get("dodge_recharge_sec", 4.0)) + float(p["mods"].get("dodge_recharge_add", 0.0)), 1.0):
			p["dodge_recharge_t"] = 0.0
			p["dodge_charges"] = int(p["dodge_charges"]) + 1
	p["invuln_t"] = maxf(float(p["invuln_t"]) - dt, 0.0)
	p["protect_t"] = maxf(float(p["protect_t"]) - dt, 0.0)
	p["front_guard_t"] = maxf(float(p["front_guard_t"]) - dt, 0.0)
	p["stagger_t"] = maxf(float(p["stagger_t"]) - dt, 0.0)
	p["haste_t"] = maxf(float(p["haste_t"]) - dt, 0.0)
	p["slow_t"] = maxf(float(p["slow_t"]) - dt, 0.0)
	p["root_t"] = maxf(float(p["root_t"]) - dt, 0.0)
	p["heal_cut_t"] = maxf(float(p.get("heal_cut_t", 0.0)) - dt, 0.0)
	if float(p["mods"].get("low_hp_regen", 0.0)) > 0.0 and p["state"] == Protocol.EntState.ALIVE and float(p["hp"]) <= float(p["max_hp"]) * 0.3:
		p["hp"] = minf(float(p["hp"]) + float(p["mods"]["low_hp_regen"]) * dt, float(p["max_hp"]))
	if float(p["bleed_t"]) > 0.0 and p["state"] == Protocol.EntState.ALIVE:
		p["bleed_t"] = float(p["bleed_t"]) - dt
		_damage_player(p, float(p["bleed_dps"]) * dt, p["pos"], "bleed")
	_step_class_passive(p, dt)
	if float(p["shield_t"]) > 0.0:
		p["shield_t"] = maxf(float(p["shield_t"]) - dt, 0.0)
		if float(p["shield_t"]) <= 0.0:
			p["shield"] = 0.0
	if not p["connected"]:
		p["disconnect_t"] = float(p["disconnect_t"]) + dt
	if p["state"] == Protocol.EntState.DOWNED:
		p["down_t"] = maxf(float(p["down_t"]) - dt, 0.0)
		if float(p["down_t"]) <= 0.0:
			p["state"] = Protocol.EntState.DEAD
			p["stats"]["deaths"] = int(p["stats"]["deaths"]) + 1
			stats["deaths"] += 1
			events.append({"k": "player_died", "id": p["id"]})
		return
	if p["state"] != Protocol.EntState.ALIVE:
		return
	if p["action"] == Protocol.Action.GRABBED:
		var held := 0
		while not p["inputs"].is_empty():
			var inp: Dictionary = p["inputs"].pop_front()
			p["last_seq"] = inp["seq"]
			held = int(inp["btn"])
		if boss != null:
			boss.on_grabbed_input(p, held, dt)
		return
	var q: Array = p["inputs"]
	var processed := 0
	var max_per_tick := int(rules.get("input_max_per_tick", 2))
	var held_buttons := 0
	while not q.is_empty() and processed < max_per_tick:
		var inp: Dictionary = q.pop_front()
		p["last_seq"] = inp["seq"]
		_apply_input(p, inp, dt if processed == 0 else 0.0)
		held_buttons = int(inp["btn"])
		processed += 1
	if processed == 0:
		_apply_input(p, {"seq": p["last_seq"], "mv": p["move_dir"], "aim": Vector2.ZERO, "btn": held_buttons if q.is_empty() else 0, "repeat": true}, dt)
	_step_action(p, dt)


func _can_act(p: Dictionary) -> bool:
	return p["action"] == Protocol.Action.IDLE and float(p["stagger_t"]) <= 0.0 and float(p["whirl_t"]) <= 0.0


func _apply_input(p: Dictionary, inp: Dictionary, dt: float) -> void:
	var mv: Vector2 = inp["mv"]
	var aim: Vector2 = inp["aim"]
	var btn := int(inp["btn"])
	var pressed := btn & ~int(p["prev_buttons"])
	if not inp.get("repeat", false):
		p["prev_buttons"] = btn
	p["move_dir"] = mv
	if not inp.get("repeat", false):
		p["aim"] = aim   # 반복 틱에서는 마지막 조준을 유지한다 (시전 완료 시 사용)
	var action: int = p["action"]
	if action == Protocol.Action.IDLE or action == Protocol.Action.RECOVERY:
		p["facing"] = SimRules.facing_from(aim, p["facing"] if mv.length_squared() < 0.01 else mv.normalized())
	if pressed & Protocol.BTN_DODGE and int(p["dodge_charges"]) > 0 and action in [Protocol.Action.IDLE, Protocol.Action.RECOVERY, Protocol.Action.INTERACTING] and float(p["stagger_t"]) <= 0.0:
		p["dodge_charges"] = int(p["dodge_charges"]) - 1
		p["action"] = Protocol.Action.DODGE
		p["action_kind"] = "dodge"
		p["action_total"] = float(rules.get("dodge_duration_sec", 0.22))
		p["action_t"] = p["action_total"]
		p["invuln_t"] = float(rules.get("dodge_invuln_sec", 0.2)) + float(p["mods"].get("dodge_invuln_add", 0.0))
		p["dodge_dir"] = mv.normalized() if mv.length_squared() > 0.01 else p["facing"]
		p["rescue_t"] = 0.0
		p["interact_target"] = 0
		events.append({"k": "dodge", "id": p["id"]})
		_tutorial_flags["dodge"] = true
		_fire_procs(p, "on_dodge", {})
		action = p["action"]
	elif _can_act(p):
		var cdef: Dictionary = ContentDB.get_class_def(p["class_id"])
		if btn & Protocol.BTN_ATTACK:
			var atk: Dictionary = cdef.get("basic_attack", {})
			_start_action(p, Protocol.Action.WINDUP, "basic", float(atk.get("windup_sec", 0.2)))
		elif pressed & Protocol.BTN_Q and float(p["cd"]["q"]) <= 0.0:
			_start_action(p, Protocol.Action.CAST, "q", float(cdef["skills"]["q"].get("cast_sec", 0.2)))
		elif pressed & Protocol.BTN_E and float(p["cd"]["e"]) <= 0.0:
			_start_action(p, Protocol.Action.CAST, "e", float(cdef["skills"]["e"].get("cast_sec", 0.2)))
		elif pressed & Protocol.BTN_R and float(p["cd"]["r"]) <= 0.0:
			_start_action(p, Protocol.Action.CAST, "r", float(cdef["skills"]["r"].get("cast_sec", 0.2)))
		elif pressed & Protocol.BTN_HEAL and int(p["heal_uses"]) > 0 and float(p["hp"]) < float(p["max_hp"]):
			_start_action(p, Protocol.Action.CAST, "heal", float(rules.get("heal_cast_sec", 0.8)))
		elif pressed & Protocol.BTN_BUILD:
			_try_build(p)
		elif btn & Protocol.BTN_INTERACT:
			var target := _find_rescue_target(p)
			if target != "":
				p["action"] = Protocol.Action.RESCUING
				p["action_kind"] = "rescue"
				p["rescue_target"] = target
			else:
				var oid := _find_interactable(p)
				if oid != 0:
					p["action"] = Protocol.Action.INTERACTING
					p["action_kind"] = "interact"
					p["interact_target"] = oid
		action = p["action"]
	if action == Protocol.Action.RESCUING:
		var t: Dictionary = players.get(p["rescue_target"], {})
		var in_range: bool = not t.is_empty() and t["state"] == Protocol.EntState.DOWNED and (t["pos"] as Vector2).distance_to(p["pos"]) <= float(rules.get("rescue_range", 70.0))
		if btn & Protocol.BTN_INTERACT and in_range:
			p["rescue_t"] = float(p["rescue_t"]) + dt
			if float(p["rescue_t"]) >= maxf(float(rules.get("rescue_hold_sec", 3.0)) + float(p["mods"].get("rescue_hold_add", 0.0)), 0.5):
				_rescue(p, t)
				p["action"] = Protocol.Action.IDLE
				p["action_kind"] = ""
				p["rescue_t"] = 0.0
		else:
			p["action"] = Protocol.Action.IDLE
			p["action_kind"] = ""
			p["rescue_t"] = 0.0
			p["rescue_target"] = ""
		return
	if action == Protocol.Action.INTERACTING:
		var o: Dictionary = objects.get(p["interact_target"], {})
		var ok := (btn & Protocol.BTN_INTERACT) != 0 and not o.is_empty() and (o["pos"] as Vector2).distance_to(p["pos"]) <= float(rules.get("interact_range", 70.0)) + float(o["r"]) and bool(o.get("interactable", int(o["state"]) == 0))
		if ok:
			o["progress"] = minf(float(o["progress"]) + dt * (1.0 + float(p["mods"].get("interact_speed", 0.0))) / maxf(float(o.get("hold_sec", 1.0)), 0.05), 1.0)
			o["last_holder"] = p["id"]
			if float(o["progress"]) >= 1.0:
				_complete_object(o, p)
				p["action"] = Protocol.Action.IDLE
				p["action_kind"] = ""
				p["interact_target"] = 0
		else:
			p["action"] = Protocol.Action.IDLE
			p["action_kind"] = ""
			p["interact_target"] = 0
			if not o.is_empty() and o["kind"] == Protocol.ObKind.SLUICE_LEVER:
				o["progress"] = 0.0
		return
	var can_move := action in [Protocol.Action.IDLE, Protocol.Action.RECOVERY] and float(p["stagger_t"]) <= 0.0 and float(p["root_t"]) <= 0.0
	var slow := 1.0
	if _in_water(p["pos"]) and water_zone.get("state", 0) == 2:
		slow = 1.0 - float(rules.get("sluice_player_slow", 0.3))
	slow *= 1.0 - _hazard_slow_at(p["pos"])
	if float(p["slow_t"]) > 0.0:
		slow *= 1.0 - minf(float(p["slow_mult"]), float(rules.get("caps", {}).get("slow_max", 0.5)))
	slow *= 1.0 - _aura_slow_at(p["pos"])
	if action == Protocol.Action.DODGE:
		p["pos"] = SimRules.move(p["pos"], p["dodge_dir"], float(p["speed"]) * float(rules.get("dodge_speed_mult", 3.0)), dt, bounds, float(p["radius"]), obstacles)
	elif can_move and mv.length_squared() > 0.0001:
		var speed := float(p["speed"]) * (0.6 if action == Protocol.Action.RECOVERY else 1.0) * slow
		if float(p["haste_t"]) > 0.0:
			speed *= 1.0 + float(p["haste_mult"])
		if float(p["whirl_t"]) > 0.0:
			speed *= float(p.get("whirl_move_mult", 0.7))
		p["pos"] = SimRules.move(p["pos"], mv, speed, dt, bounds, float(p["radius"]), obstacles)


func _start_action(p: Dictionary, action: int, kind: String, t: float) -> void:
	p["action"] = action
	p["action_kind"] = kind
	p["action_total"] = t
	p["action_t"] = t
	p["hit_applied"] = false
	events.append({"k": "action", "id": p["id"], "kind": kind})


func _step_action(p: Dictionary, dt: float) -> void:
	var action: int = p["action"]
	if action in [Protocol.Action.IDLE, Protocol.Action.RESCUING, Protocol.Action.INTERACTING, Protocol.Action.GRABBED]:
		return
	p["action_t"] = float(p["action_t"]) - dt
	if float(p["action_t"]) > 0.0:
		return
	var cdef: Dictionary = ContentDB.get_class_def(p["class_id"])
	match action:
		Protocol.Action.WINDUP:
			var atk: Dictionary = cdef.get("basic_attack", {})
			_apply_basic_attack(p, atk)
			p["action"] = Protocol.Action.ACTIVE
			p["action_total"] = float(atk.get("active_sec", 0.1))
			p["action_t"] = p["action_total"]
		Protocol.Action.ACTIVE:
			var atk: Dictionary = cdef.get("basic_attack", {})
			p["action"] = Protocol.Action.RECOVERY
			p["action_total"] = float(atk.get("recovery_sec", 0.3)) * maxf(1.0 + float(p["mods"].get("basic_recovery_mult", 0.0)), 0.3)
			p["action_t"] = p["action_total"]
		Protocol.Action.RECOVERY, Protocol.Action.DODGE:
			p["action"] = Protocol.Action.IDLE
			p["action_kind"] = ""
		Protocol.Action.CAST:
			_apply_cast(p, cdef, String(p["action_kind"]))
			p["action"] = Protocol.Action.IDLE
			p["action_kind"] = "whirl" if float(p["whirl_t"]) > 0.0 else ""


func _player_damage(p: Dictionary, base: float) -> float:
	var bonus := 0.0
	if boss != null:
		bonus = boss.damage_bonus_at(p["pos"])
	if p["class_id"] == "sawtooth":
		bonus += float(p["resource"]) * float(ContentDB.get_class_def("sawtooth").get("passive", {}).get("damage_per_stack", 0.04))
	if float(p["mods"].get("low_hp_damage", 0.0)) > 0.0 and float(p["hp"]) <= float(p["max_hp"]) * 0.5:
		bonus += float(p["mods"].get("low_hp_damage", 0.0))
	if float(p.get("guard_bonus", 0.0)) > 0.0:
		base += float(p["guard_bonus"])
		p["guard_bonus"] = 0.0
	return SimRules.damage(base, 1.0 + float(p["mods"].get("damage_mult", 0.0)) + bonus, 0.0, 1.0, 0.0, 0.0, rules.get("caps", {}))


func _apply_basic_attack(p: Dictionary, atk: Dictionary) -> void:
	var shape := String(atk.get("shape", "arc"))
	if shape == "projectile":
		var pr: Dictionary = atk.get("projectile", {})
		var dir: Vector2 = p["facing"]
		_spawn_projectile(p["pos"] + dir * 20.0, dir * float(pr.get("speed", 500)) * (1.0 + float(p["mods"].get("proj_speed_mult", 0.0))), float(pr.get("radius", 9)), _player_damage(p, float(atk.get("damage", 7)) + float(p["mods"].get("basic_damage_add", 0.0)) + float(p["mods"].get("proj_damage_add", 0.0))), 1, p["id"], float(pr.get("ttl_sec", 0.8)), int(p["mods"].get("pierce_add", 0)), float(atk.get("knockback", 0)), float(atk.get("stagger_sec", 0)))
		projectiles[projectiles.size() - 1]["basic"] = true
		if float(p["mods"].get("proj_bleed", 0.0)) > 0.0:
			projectiles[projectiles.size() - 1]["bleed"] = float(p["mods"]["proj_bleed"])
		events.append({"k": "shoot", "id": p["id"], "x": p["pos"].x, "y": p["pos"].y, "fx": dir.x, "fy": dir.y})
		return
	var hits := 0
	var kb := float(atk.get("knockback", 0)) * (1.0 + float(p["mods"].get("knockback_mult", 0.0)))
	var st := float(atk.get("stagger_sec", 0)) + float(p["mods"].get("stagger_add", 0.0))
	for e: Dictionary in enemies.values():
		if e["ai"] == Protocol.EnemyAI.DEAD:
			continue
		if SimRules.arc_hit(p["pos"], p["facing"], float(atk.get("range", 80)), float(atk.get("angle_deg", 120)), e["pos"], float(e["radius"])):
			_damage_enemy(e, _player_damage(p, float(atk.get("damage", 10)) + float(p["mods"].get("basic_damage_add", 0.0))), p, kb, st)
			_on_basic_hit(p, e)
			hits += 1
	if boss != null:
		hits += boss.on_arc_attack(p, atk)
	events.append({"k": "swing", "id": p["id"], "hits": hits, "x": p["pos"].x, "y": p["pos"].y, "fx": p["facing"].x, "fy": p["facing"].y})


func _apply_cast(p: Dictionary, cdef: Dictionary, kind: String) -> void:
	if kind == "heal":
		p["heal_uses"] = int(p["heal_uses"]) - 1
		var amount := float(p["max_hp"]) * (float(rules.get("heal_fraction", 0.3)) + float(p["mods"].get("heal_fraction_add", 0.0)))
		p["hp"] = minf(float(p["hp"]) + amount, float(p["max_hp"]))
		events.append({"k": "heal", "id": p["id"], "amount": amount})
		return
	var skill: Dictionary = cdef.get("skills", {}).get(kind, {})
	if skill.is_empty():
		return
	var m: Dictionary = p["mods"]
	p["cd"][kind] = float(skill.get("cooldown_sec", 10)) * (1.0 - float(m.get("cdr", 0.0))) * (1.0 - clampf(float(m.get(kind + "_cdr", 0.0)), 0.0, 0.8))
	var eff: Dictionary = skill.get("effect", {})
	var dmg_add := float(m.get(kind + "_damage_add", 0.0))
	var aim: Vector2 = p.get("aim", p["facing"])
	var aim_dir: Vector2 = SimRules.facing_from(aim, p["facing"])
	match String(eff.get("type", "")):
		"front_damage_reduction":
			p["front_guard_t"] = float(skill.get("duration_sec", 3.0)) + float(m.get("q_duration_add", 0.0))
			p["front_guard_value"] = float(m.get("q_value_set", 0.0)) if float(m.get("q_value_set", 0.0)) > 0.0 else float(eff.get("value", 0.5))
			p["front_guard_arc"] = float(eff.get("arc_deg", 150))
		"circle_hit":
			var radius := float(eff.get("radius", 100)) * (1.0 + float(m.get("e_radius_mult", 0.0)))
			var hits := _circle_damage(p, p["pos"], radius, _player_damage(p, float(eff.get("damage", 8)) + dmg_add), float(eff.get("knockback", 100)) * (1.0 + float(m.get("knockback_mult", 0.0))), float(eff.get("stagger_sec", 0.5)) + float(m.get("e_stagger_add", 0.0)) + float(m.get("stagger_add", 0.0)))
			events.append({"k": "circle_hit", "id": p["id"], "hits": hits, "radius": radius})
			if float(m.get("e_double", 0.0)) > 0.0:
				p["delayed"].append({"t": 0.4, "kind": "circle", "radius": radius * 2.0, "damage": _player_damage(p, float(eff.get("damage", 8)) * 0.6 + dmg_add * 0.5), "knockback": 60.0, "stagger": 0.3})
		"party_shield":
			var cap := minf(float(eff.get("max_shield_per_target", 45)) + float(m.get("r_shield_add", 0.0)), float(rules.get("caps", {}).get("shield_max", 60)) + float(m.get("shield_cap_add", 0.0)))
			for o: Dictionary in players.values():
				if o["state"] == Protocol.EntState.ALIVE and (o["pos"] as Vector2).distance_to(p["pos"]) <= float(eff.get("radius", 200)):
					o["shield"] = minf(maxf(float(o["shield"]), float(eff.get("shield", 30)) + float(m.get("r_shield_add", 0.0))), cap)
					o["shield_t"] = maxf(float(o["shield_t"]), float(eff.get("duration_sec", 6)) + float(m.get("r_duration_add", 0.0)) + float(m.get("shield_duration_add", 0.0)))
			if float(m.get("r_heal_tick", 0.0)) > 0.0:
				_add_zone(Protocol.ObKind.FLOOD_ZONE, p["pos"], float(eff.get("radius", 200)), {"owner": p["id"], "life": float(eff.get("duration_sec", 6)) + float(m.get("r_duration_add", 0.0)), "total": float(eff.get("duration_sec", 6)) + float(m.get("r_duration_add", 0.0)), "tick_sec": 1.0, "tick_t": 0.0, "heal": float(m.get("r_heal_tick", 0.0)), "damage": 0.0, "slow_mult": 0.0, "style": 1})
			var root_sec := float(m.get("r_root_sec", 0.0))
			if root_sec > 0.0:
				for e: Dictionary in enemies.values():
					if e["ai"] != Protocol.EnemyAI.DEAD and (e["pos"] as Vector2).distance_to(p["pos"]) <= float(eff.get("radius", 200)):
						_root_enemy(e, root_sec)
		"scatter":
			var pellets := int(eff.get("pellets", 5)) + int(m.get("q_pellets_add", 0))
			var spread := deg_to_rad(float(eff.get("spread_deg", 40)) + float(m.get("q_spread_add", 0)))
			for i in pellets:
				var a := -spread * 0.5 + spread * (float(i) / maxf(pellets - 1, 1))
				var d := aim_dir.rotated(a)
				_spawn_projectile(p["pos"] + d * 20.0, d * float(eff.get("speed", 480)), float(eff.get("radius", 8)), _player_damage(p, float(eff.get("damage", 5)) + dmg_add), 1, p["id"], float(eff.get("ttl_sec", 0.5)), int(m.get("pierce_add", 0)), 20.0, 0.0)
		"trap":
			var max_traps := int(eff.get("max_traps", 1)) + int(m.get("e_max_traps_add", 0))
			var mine: Array = []
			for o: Dictionary in objects.values():
				if o["kind"] == Protocol.ObKind.TRAP and o.get("owner", "") == p["id"]:
					mine.append(o)
			while mine.size() >= max_traps:
				var old: Dictionary = mine.pop_front()
				objects.erase(old["id"])
			var at: Vector2 = p["pos"] + aim.limit_length(float(eff.get("place_range", 140)))
			at = _clamp_in_bounds(at, 20.0)
			_add_object(Protocol.ObKind.TRAP, at, float(eff.get("radius", 52)), {"owner": p["id"], "arm_t": float(eff.get("arm_sec", 0.5)), "life": float(eff.get("lifetime_sec", 20)), "root_sec": float(eff.get("root_sec", 1.5)) + float(m.get("e_root_add", 0.0)), "damage": _player_damage(p, float(eff.get("damage", 8)) + dmg_add), "vuln_sec": float(m.get("e_vuln_sec_add", 0.0)), "vuln_mult": float(m.get("e_vuln_add", 0.0)), "scatter": int(m.get("e_trap_scatter", 0))})
		"volley":
			var at: Vector2 = _clamp_in_bounds(p["pos"] + aim.limit_length(float(eff.get("place_range", 360))), 20.0)
			_add_object(Protocol.ObKind.VOLLEY, at, float(eff.get("radius", 110)) * (1.0 + float(m.get("r_radius_mult", 0.0))), {"owner": p["id"], "life": float(eff.get("duration_sec", 3.0)) + float(m.get("r_duration_add", 0.0)), "tick_sec": float(eff.get("tick_sec", 0.4)), "tick_t": 0.0, "damage": _player_damage(p, float(eff.get("damage", 9)) + dmg_add), "slow_mult": float(m.get("r_slow", 0.0)), "final_burst": _player_damage(p, float(m.get("r_final_burst", 0.0))) if float(m.get("r_final_burst", 0.0)) > 0.0 else 0.0})
		"dash":
			_cast_dash(p, eff, aim_dir, m)
		"heavy_strike":
			var hits := 0
			for e: Dictionary in enemies.values():
				if e["ai"] == Protocol.EnemyAI.DEAD:
					continue
				if SimRules.arc_hit(p["pos"], aim_dir, float(eff.get("range", 96)), float(eff.get("angle_deg", 80)) + float(m.get("e_angle_add", 0.0)), e["pos"], float(e["radius"])):
					e["vuln_t"] = maxf(float(e.get("vuln_t", 0.0)), float(eff.get("vuln_sec", 6.0)) + float(m.get("e_vuln_sec_add", 0.0)))
					e["vuln_mult"] = maxf(float(e.get("vuln_mult", 0.0)), float(eff.get("vuln_mult", 0.25)) + float(m.get("e_vuln_add", 0.0)))
					_damage_enemy(e, _player_damage(p, float(eff.get("damage", 22)) + dmg_add), p, float(eff.get("knockback", 60)) * (1.0 + float(m.get("knockback_mult", 0.0))), float(eff.get("stagger_sec", 0.4)) + float(m.get("stagger_add", 0.0)))
					hits += 1
			p["facing"] = aim_dir
			if boss != null:
				hits += boss.on_arc_attack(p, {"range": eff.get("range", 96), "angle_deg": eff.get("angle_deg", 80), "damage": eff.get("damage", 22), "vuln": true})
			events.append({"k": "heavy_strike", "id": p["id"], "hits": hits, "fx": aim_dir.x, "fy": aim_dir.y})
		"whirl":
			p["whirl_t"] = float(eff.get("duration_sec", 4.0)) + float(m.get("r_duration_add", 0.0))
			p["whirl_tick"] = 0.0
			var wd := eff.duplicate()
			wd["damage"] = float(eff.get("damage", 7)) + dmg_add
			wd["radius"] = float(eff.get("radius", 90)) * (1.0 + float(m.get("r_radius_mult", 0.0)))
			wd["end_knockback"] = float(m.get("r_end_knockback", 0.0))
			p["whirl_def"] = wd
			p["whirl_move_mult"] = float(m.get("r_move_set", 0.0)) if float(m.get("r_move_set", 0.0)) > 0.0 else float(eff.get("move_speed_mult", 0.7))
			p["action_kind"] = "whirl"
		"heal_zone":
			var at: Vector2 = _clamp_in_bounds(p["pos"] + aim.limit_length(float(eff.get("place_range", 220))), 10.0)
			var radius := float(eff.get("radius", 90)) * (1.0 + float(m.get("q_radius_mult", 0.0)))
			var seeds := int(p["resource"]) if p["class_id"] == "sapshaman" else 0
			var amount := float(eff.get("heal", 18)) + float(m.get("q_heal_add", 0.0)) + seeds * float(ContentDB.get_class_def("sapshaman").get("passive", {}).get("heal_per_seed", 3))
			var full := seeds >= int(ContentDB.get_class_def("sapshaman").get("passive", {}).get("max_stacks", 5))
			if full and float(m.get("q_full_seed_bonus", 0.0)) > 0.0:
				amount *= 1.0 + float(m.get("q_full_seed_bonus", 0.0))
			if p["class_id"] == "sapshaman":
				p["resource"] = 0.0
			var healed := 0
			for o: Dictionary in players.values():
				if o["state"] == Protocol.EntState.ALIVE and (o["pos"] as Vector2).distance_to(at) <= radius + float(o["radius"]):
					if _heal_player(o, amount, p) > 0.0:
						healed += 1
			for e: Dictionary in enemies.values():
				if e["ai"] != Protocol.EnemyAI.DEAD and (e["pos"] as Vector2).distance_to(at) <= radius + float(e["radius"]):
					_slow_enemy(e, float(eff.get("slow_mult", 0.35)), float(eff.get("slow_sec", 3.0)))
					var dot := float(m.get("q_damage", 0.0)) + dmg_add
					if dot > 0.0:
						_damage_enemy(e, _player_damage(p, dot), p, 0.0, 0.0)
					if full and float(m.get("q_root_sec", 0.0)) > 0.0:
						_root_enemy(e, float(m.get("q_root_sec", 0.0)))
			events.append({"k": "heal_zone", "id": p["id"], "x": at.x, "y": at.y, "r": radius, "healed": healed, "amount": amount})
		"root_zone":
			var at: Vector2 = _clamp_in_bounds(p["pos"] + aim.limit_length(float(eff.get("place_range", 240))), 10.0)
			var radius := float(eff.get("radius", 70)) * (1.0 + float(m.get("e_radius_mult", 0.0)))
			for e: Dictionary in enemies.values():
				if e["ai"] != Protocol.EnemyAI.DEAD and (e["pos"] as Vector2).distance_to(at) <= radius + float(e["radius"]):
					_root_enemy(e, float(eff.get("root_sec", 1.5)) + float(m.get("e_root_add", 0.0)))
			if boss != null:
				boss.on_circle_attack(p, at, radius, 0.0)
			_add_zone(Protocol.ObKind.ROOT_ZONE, at, radius, {"owner": p["id"], "life": float(eff.get("duration_sec", 3.0)), "total": float(eff.get("duration_sec", 3.0)), "tick_sec": float(eff.get("tick_sec", 0.5)), "tick_t": 0.0, "damage": _player_damage(p, float(eff.get("damage", 4)) + dmg_add)})
		"flood_zone":
			var radius := float(eff.get("radius", 160))
			_add_zone(Protocol.ObKind.FLOOD_ZONE, p["pos"], radius, {"owner": p["id"], "life": float(eff.get("duration_sec", 6.0)) + float(m.get("r_duration_add", 0.0)), "total": float(eff.get("duration_sec", 6.0)), "tick_sec": float(eff.get("tick_sec", 0.5)), "tick_t": 0.0, "heal": float(eff.get("heal", 4)) + float(m.get("r_heal_add", 0.0)), "damage": _player_damage(p, float(eff.get("damage", 3)) + dmg_add), "slow_mult": float(m.get("r_slow_set", 0.0)) if float(m.get("r_slow_set", 0.0)) > 0.0 else float(eff.get("slow_mult", 0.3)), "follow": int(m.get("r_follow", 0))})
		"turret":
			var cost := float(eff.get("cost", 30))
			if float(p["resource"]) < cost:
				events.append({"k": "skill_failed", "id": p["id"], "reason": "charge"})
				p["cd"][kind] = 0.5
				return
			var max_turrets := int(eff.get("max_turrets", 2)) + int(m.get("q_max_turrets_add", 0))
			var mine: Array = []
			var total := 0
			for o: Dictionary in objects.values():
				if o["kind"] == Protocol.ObKind.TURRET:
					total += 1
					if o.get("owner", "") == p["id"]:
						mine.append(o)
			while mine.size() >= max_turrets:
				objects.erase((mine.pop_front() as Dictionary)["id"])
				total -= 1
			if total >= int(rules.get("caps", {}).get("turret_max_per_room", 6)):
				events.append({"k": "skill_failed", "id": p["id"], "reason": "limit"})
				p["cd"][kind] = 0.5
				return
			p["resource"] = float(p["resource"]) - cost
			var at: Vector2 = _clamp_in_bounds(p["pos"] + aim.limit_length(float(eff.get("place_range", 120))), 24.0)
			_add_object(Protocol.ObKind.TURRET, at, 22.0, {"owner": p["id"], "life": float(eff.get("lifetime_sec", 12.0)) + float(m.get("q_duration_add", 0.0)), "total": float(eff.get("lifetime_sec", 12.0)), "hp": float(eff.get("hp", 50)) + float(m.get("q_hp_add", 0.0)), "max_hp": float(eff.get("hp", 50)) + float(m.get("q_hp_add", 0.0)), "range": float(eff.get("range", 260)), "fire_sec": float(eff.get("fire_sec", 0.7)) * (1.0 - float(m.get("q_fire_rate", 0.0))), "fire_t": 0.3, "damage": _player_damage(p, float(eff.get("damage", 5)) + dmg_add), "proj_speed": float(eff.get("proj_speed", 520)), "shots": 1 + int(m.get("q_double_shot", 0)), "shot_slow": float(m.get("q_shot_slow", 0.0))})
			stats["builds"] += 1
		"jet":
			var length := float(eff.get("length", 260)) + float(m.get("e_length_add", 0.0))
			var width := float(eff.get("width", 70))
			var hits := 0
			for e: Dictionary in enemies.values():
				if e["ai"] == Protocol.EnemyAI.DEAD or not _in_line(p["pos"], aim_dir, length, width, e["pos"], float(e["radius"])):
					continue
				_slow_enemy(e, float(eff.get("slow_mult", 0.3)), float(eff.get("slow_sec", 2.0)))
				var kb := (float(eff.get("knockback", 120)) + float(m.get("e_knockback_add", 0.0))) * (1.0 + float(m.get("knockback_mult", 0.0)))
				e["pos"] = SimRules.move(e["pos"], aim_dir, kb, 1.0, bounds, float(e["radius"]), all_obstacles())
				_damage_enemy(e, _player_damage(p, float(eff.get("damage", 6)) + dmg_add), p, 0.0, 0.15)
				hits += 1
			for o: Dictionary in players.values():
				if o["state"] == Protocol.EntState.ALIVE and _in_line(p["pos"], aim_dir, length, width, o["pos"], float(o["radius"])):
					o["haste_t"] = maxf(float(o["haste_t"]), float(eff.get("ally_sec", 2.0)) + float(m.get("e_ally_sec_add", 0.0)))
					o["haste_mult"] = float(eff.get("ally_speed_mult", 0.4))
			if float(m.get("e_self_slide", 0.0)) > 0.0:
				p["pos"] = SimRules.move(p["pos"], aim_dir, float(m.get("e_self_slide", 0.0)), 1.0, bounds, float(p["radius"]), all_obstacles())
			if boss != null:
				boss.on_arc_attack(p, {"range": length, "angle_deg": 30, "damage": eff.get("damage", 6)})
			p["facing"] = aim_dir
			events.append({"k": "jet", "id": p["id"], "hits": hits, "x": p["pos"].x, "y": p["pos"].y, "fx": aim_dir.x, "fy": aim_dir.y, "len": length, "w": width})
		"dam":
			var at: Vector2 = _clamp_in_bounds(p["pos"] + aim.limit_length(float(eff.get("place_range", 120))), 44.0)
			for o: Dictionary in objects.values():
				if o["kind"] == Protocol.ObKind.DAM and o.get("owner", "") == p["id"]:
					_burst_dam(o)
					objects.erase(o["id"])
					break
			for ob: Dictionary in all_obstacles():
				if Vector2(float(ob["x"]), float(ob["y"])).distance_to(at) < float(ob["r"]) + 20.0:
					at = _clamp_in_bounds(p["pos"] + aim_dir * 60.0, 44.0)
					break
			var dam := _add_object(Protocol.ObKind.DAM, at, float(eff.get("radius", 40)), {"owner": p["id"], "life": float(eff.get("lifetime_sec", 12.0)) + float(m.get("r_duration_add", 0.0)), "total": float(eff.get("lifetime_sec", 12.0)), "hp": float(eff.get("hp", 150)) + float(m.get("r_hp_add", 0.0)), "max_hp": float(eff.get("hp", 150)) + float(m.get("r_hp_add", 0.0)), "burst_damage": _player_damage(p, float(eff.get("burst_damage", 25)) + dmg_add), "burst_radius": float(eff.get("burst_radius", 150)) + float(m.get("r_burst_radius_add", 0.0)), "burst_knockback": float(eff.get("burst_knockback", 160)), "burst_shield": float(m.get("r_burst_shield", 0.0))})
			if int(m.get("r_burst_on_place", 0)) > 0:
				_burst_dam(dam)
			stats["builds"] += 1
	events.append({"k": "skill", "id": p["id"], "skill": skill.get("id", kind), "slot": kind, "x": p["pos"].x, "y": p["pos"].y})
	_tutorial_flags["skill"] = true
	_fire_procs(p, "on_skill", {})


## 직선 판정: origin 에서 dir 방향 length, 폭 width 인 사각형에 원이 걸치는가
func _in_line(origin: Vector2, dir: Vector2, length: float, width: float, target: Vector2, target_r: float) -> bool:
	var d := target - origin
	var along := d.dot(dir)
	var side := absf(d.cross(dir))
	return along >= -target_r and along <= length + target_r and side <= width * 0.5 + target_r


func _cast_dash(p: Dictionary, eff: Dictionary, dir: Vector2, m: Dictionary) -> void:
	var dist := float(eff.get("distance", 220)) + float(m.get("q_distance_add", 0.0))
	var half_w := float(eff.get("width", 44)) * 0.5
	var steps := 8
	var hit: Array = []
	var obs := all_obstacles()
	for i in steps:
		p["pos"] = SimRules.move(p["pos"], dir, dist / steps, 1.0, bounds, float(p["radius"]), obs)
		for e: Dictionary in enemies.values():
			if e["ai"] == Protocol.EnemyAI.DEAD or hit.has(e["id"]):
				continue
			if (e["pos"] as Vector2).distance_to(p["pos"]) <= half_w + float(e["radius"]):
				hit.append(e["id"])
				_damage_enemy(e, _player_damage(p, float(eff.get("damage", 14)) + float(m.get("q_damage_add", 0.0))), p, 30.0, float(eff.get("stagger_sec", 0.2)))
				_on_basic_hit(p, e)
	if boss != null:
		boss.on_arc_attack(p, {"range": 60, "angle_deg": 360, "damage": eff.get("damage", 14)})
	if float(m.get("q_ram", 0.0)) > 0.0 and not hit.is_empty():
		var first: Dictionary = enemies.get(hit[0], {})
		if not first.is_empty():
			first["pos"] = SimRules.move(first["pos"], dir, 40.0, 1.0, bounds, float(first["radius"]), obs)
			_damage_enemy(first, _player_damage(p, float(m.get("q_ram", 0.0))), p, 0.0, 1.0)
	p["invuln_t"] = maxf(float(p["invuln_t"]), float(eff.get("invuln_sec", 0.15)) + float(m.get("q_invuln_add", 0.0)))
	p["facing"] = dir
	events.append({"k": "dash", "id": p["id"], "hits": hit.size(), "x": p["pos"].x, "y": p["pos"].y, "fx": dir.x, "fy": dir.y})


func _add_zone(kind: int, at: Vector2, radius: float, extra: Dictionary) -> void:
	var zones := 0
	var oldest: Dictionary = {}
	for o: Dictionary in objects.values():
		if o["kind"] in [Protocol.ObKind.ROOT_ZONE, Protocol.ObKind.FLOOD_ZONE, Protocol.ObKind.VOLLEY]:
			zones += 1
			if oldest.is_empty() or float(o.get("life", 0.0)) < float(oldest.get("life", 0.0)):
				oldest = o
	if zones >= int(rules.get("caps", {}).get("zone_max_per_room", 8)) and not oldest.is_empty():
		objects.erase(oldest["id"])
	_add_object(kind, at, radius, extra)


## 회복 적용. 10초 창 안의 스킬 회복 상한(caps.heal_received_per_10s)을 넘는 만큼은 버린다. 실제 적용량을 돌려준다.
func _heal_player(target: Dictionary, amount: float, source: Dictionary) -> float:
	if target["state"] != Protocol.EntState.ALIVE or amount <= 0.0:
		return 0.0
	var window := float(rules.get("heal_window_sec", 10.0))
	var cap := float(rules.get("caps", {}).get("heal_received_per_10s", 70))
	var log: Array = target["heal_log"]
	var used := 0.0
	var i := log.size() - 1
	while i >= 0:
		if elapsed - float(log[i][0]) > window:
			log.remove_at(i)
		else:
			used += float(log[i][1])
		i -= 1
	amount *= 1.0 + float(source.get("mods", {}).get("heal_mult", 0.0))
	if float(target.get("heal_cut_t", 0.0)) > 0.0:
		amount *= float(target.get("heal_cut_mult", 0.5))   # 검은 수액 정예: 회복 절반
	var allowed := minf(amount, maxf(cap - used, 0.0))
	var applied := minf(allowed, float(target["max_hp"]) - float(target["hp"]))
	if applied <= 0.0:
		return 0.0
	target["hp"] = float(target["hp"]) + applied
	log.append([elapsed, applied])
	if source.get("class_id", "") == "sapshaman":
		_add_seed(source)
	if source.has("stats"):
		source["stats"]["healing"] = float(source["stats"].get("healing", 0.0)) + applied
	events.append({"k": "healed", "id": target["id"], "by": source.get("id", ""), "amount": applied})
	return applied


func _circle_damage(p: Dictionary, center: Vector2, radius: float, dmg: float, knockback: float, stagger: float) -> int:
	var hits := 0
	for e: Dictionary in enemies.values():
		if e["ai"] == Protocol.EnemyAI.DEAD:
			continue
		if SimRules.circle_hit(center, radius, e["pos"], float(e["radius"])):
			if dmg > 0.0:
				_damage_enemy(e, dmg, p, knockback, stagger)
			elif knockback > 0.0:
				var dir: Vector2 = (e["pos"] - center).normalized() if (e["pos"] as Vector2).distance_to(center) > 0.01 else Vector2.RIGHT
				e["pos"] = SimRules.move(e["pos"], dir, knockback, 1.0, bounds, float(e["radius"]), all_obstacles())
			hits += 1
	if boss != null and dmg > 0.0:
		hits += boss.on_circle_attack(p, center, radius, dmg)
	return hits


func _slow_enemy(e: Dictionary, mult: float, sec: float) -> void:
	e["slow_t"] = maxf(float(e.get("slow_t", 0.0)), sec)
	e["slow_mult"] = maxf(float(e.get("slow_mult", 0.0)), mult)


func _add_seed(p: Dictionary) -> void:
	var passive: Dictionary = ContentDB.get_class_def("sapshaman").get("passive", {})
	if elapsed - float(p["resource_t"]) < float(passive.get("min_interval_sec", 0.5)) * (1.0 + float(p["mods"].get("seed_interval_mult", 0.0))):
		return
	p["resource_t"] = elapsed
	p["resource"] = minf(float(p["resource"]) + 1.0, float(passive.get("max_stacks", 5)))


## 기본 공격 명중 시 직업 패시브 자원
func _on_basic_hit(p: Dictionary, _e: Dictionary) -> void:
	match String(p["class_id"]):
		"sawtooth":
			var passive: Dictionary = ContentDB.get_class_def("sawtooth").get("passive", {})
			p["resource"] = minf(float(p["resource"]) + 1.0, float(passive.get("max_stacks", 5)) + float(p["mods"].get("heat_max_add", 0.0)))
			p["resource_t"] = elapsed
			if float(p["mods"].get("heat_bleed", 0.0)) > 0.0 and float(p["resource"]) >= 3.0 and not _e.is_empty():
				_e["bleed_t"] = 3.0
				_e["bleed_dps"] = float(p["mods"].get("heat_bleed", 0.0))
				_e["bleed_by"] = p["id"]
		"sapshaman":
			_add_seed(p)
		"hydro":
			var passive: Dictionary = ContentDB.get_class_def("hydro").get("passive", {})
			p["resource"] = minf(float(p["resource"]) + float(passive.get("per_hit", 8)) + float(p["mods"].get("pressure_per_hit_add", 0.0)), float(passive.get("max", 100)))


func _step_class_passive(p: Dictionary, dt: float) -> void:
	match String(p["class_id"]):
		"sawtooth":
			var passive: Dictionary = ContentDB.get_class_def("sawtooth").get("passive", {})
			if float(p["resource"]) > 0.0 and elapsed - float(p["resource_t"]) > float(passive.get("decay_sec", 3.0)) + float(p["mods"].get("heat_decay_add", 0.0)):
				p["resource"] = 0.0
		"hydro":
			var passive: Dictionary = ContentDB.get_class_def("hydro").get("passive", {})
			p["resource"] = minf(float(p["resource"]) + float(passive.get("regen_per_sec", 2.0)) * dt, float(passive.get("max", 100)))
	if float(p["whirl_t"]) > 0.0:
		p["whirl_t"] = float(p["whirl_t"]) - dt
		p["whirl_tick"] = float(p["whirl_tick"]) - dt
		var eff: Dictionary = p.get("whirl_def", {})
		if float(p["whirl_tick"]) <= 0.0:
			p["whirl_tick"] = float(eff.get("tick_sec", 0.3))
			var radius := float(eff.get("radius", 90))
			for e: Dictionary in enemies.values():
				if e["ai"] != Protocol.EnemyAI.DEAD and (e["pos"] as Vector2).distance_to(p["pos"]) <= radius + float(e["radius"]):
					_damage_enemy(e, _player_damage(p, float(eff.get("damage", 7))), p, 20.0, 0.1)
					_on_basic_hit(p, e)
			if boss != null:
				boss.on_circle_attack(p, p["pos"], radius, _player_damage(p, float(eff.get("damage", 7))))
		if float(p["whirl_t"]) <= 0.0:
			p["whirl_t"] = 0.0
			if p["action_kind"] == "whirl":
				p["action_kind"] = ""
			if float(eff.get("end_knockback", 0.0)) > 0.0:
				_circle_damage(p, p["pos"], float(eff.get("radius", 90)) + 40.0, 0.0, float(eff.get("end_knockback", 0.0)), 0.4)
	var i := (p["delayed"] as Array).size() - 1
	while i >= 0:
		var d: Dictionary = p["delayed"][i]
		d["t"] = float(d["t"]) - dt
		if float(d["t"]) <= 0.0:
			_circle_damage(p, p["pos"], float(d["radius"]), float(d["damage"]), float(d["knockback"]), float(d["stagger"]))
			events.append({"k": "circle_hit", "id": p["id"], "hits": 0, "radius": d["radius"]})
			(p["delayed"] as Array).remove_at(i)
		i -= 1


func _burst_dam(o: Dictionary) -> void:
	var owner: Dictionary = players.get(o.get("owner", ""), {})
	for e: Dictionary in enemies.values():
		if e["ai"] != Protocol.EnemyAI.DEAD and (e["pos"] as Vector2).distance_to(o["pos"]) <= float(o["burst_radius"]) + float(e["radius"]):
			var dir: Vector2 = (e["pos"] - o["pos"]).normalized() if (e["pos"] as Vector2).distance_to(o["pos"]) > 0.01 else Vector2.RIGHT
			e["pos"] = SimRules.move(e["pos"], dir, float(o["burst_knockback"]), 1.0, bounds, float(e["radius"]), obstacles)
			_slow_enemy(e, 0.3, 2.0)
			if not owner.is_empty():
				_damage_enemy(e, float(o["burst_damage"]), owner, 0.0, 0.3)
	if boss != null and not owner.is_empty():
		boss.on_circle_attack(owner, o["pos"], float(o["burst_radius"]), float(o["burst_damage"]))
	if float(o.get("burst_shield", 0.0)) > 0.0:
		for pl: Dictionary in players.values():
			if pl["state"] == Protocol.EntState.ALIVE and (pl["pos"] as Vector2).distance_to(o["pos"]) <= float(o["burst_radius"]):
				pl["shield"] = minf(maxf(float(pl["shield"]), float(o["burst_shield"])), float(rules.get("caps", {}).get("shield_max", 60)))
				pl["shield_t"] = maxf(float(pl["shield_t"]), 6.0)
	events.append({"k": "dam_burst", "x": o["pos"].x, "y": o["pos"].y, "r": o["burst_radius"]})


func _clamp_in_bounds(v: Vector2, margin: float) -> Vector2:
	return Vector2(clampf(v.x, bounds.position.x + margin, bounds.end.x - margin), clampf(v.y, bounds.position.y + margin, bounds.end.y - margin))


const BUILD_KIND_INDEX := {"log_cover": 0, "spike_fence": 1, "sap_lantern": 2}


func set_build_kind(id: String, kind: String) -> void:
	if players.has(id) and (rules.get("build_kinds", {}) as Dictionary).has(kind):
		players[id]["build_kind"] = kind


func _try_build(p: Dictionary) -> void:
	var kinds: Dictionary = rules.get("build_kinds", {})
	var bk: Dictionary = kinds.get(String(p.get("build_kind", "log_cover")), {"cost_wood": rules.get("build_cost_wood", 3), "hp": rules.get("build_hp", 60), "lifetime_sec": rules.get("build_lifetime_sec", 30.0), "radius": 26})
	var cost := maxi(int(bk.get("cost_wood", 3)) + int(p["mods"].get("build_cost_add", 0)), 1)
	var count := 0
	for o: Dictionary in objects.values():
		if o["kind"] == Protocol.ObKind.STRUCTURE:
			count += 1
	if team_wood < cost or count >= int(rules.get("build_max_per_room", 3)):
		events.append({"k": "build_failed", "id": p["id"], "reason": "wood" if team_wood < cost else "limit", "cost": cost})
		return
	var r := float(bk.get("radius", 26))
	var at: Vector2 = _clamp_in_bounds(p["pos"] + (p["facing"] as Vector2) * 48.0, r)
	for ob: Dictionary in all_obstacles():
		if Vector2(float(ob["x"]), float(ob["y"])).distance_to(at) < float(ob["r"]) + r:
			events.append({"k": "build_failed", "id": p["id"], "reason": "blocked"})
			return
	team_wood -= cost   # 서버가 한 번만 처리한다. 음수 목재 없음.
	var kind_id := String(p.get("build_kind", "log_cover"))
	var shp := float(bk.get("hp", 60)) * (1.0 + float(p["mods"].get("structure_hp_mult", 0.0)))
	_add_object(Protocol.ObKind.STRUCTURE, at, r, {"hp": shp, "max_hp": shp, "life": float(bk.get("lifetime_sec", 30.0)), "owner": p["id"], "bkind": kind_id, "state": int(BUILD_KIND_INDEX.get(kind_id, 0)), "contact_damage": float(bk.get("contact_damage", 0)), "contact_slow": float(bk.get("contact_slow", 0)), "heal_radius": float(bk.get("heal_radius", 0)), "heal_per_sec": float(bk.get("heal_per_sec", 0)), "tick_t": 0.0})
	stats["builds"] += 1
	events.append({"k": "build", "id": p["id"], "x": at.x, "y": at.y, "wood": team_wood, "kind": kind_id})


func _find_interactable(p: Dictionary) -> int:
	var best := 0
	var best_d := 1e9
	for o: Dictionary in objects.values():
		if not o["kind"] in [Protocol.ObKind.GNAW_TREE, Protocol.ObKind.DEVICE, Protocol.ObKind.SLUICE_LEVER, Protocol.ObKind.SECRET]:
			continue
		if not bool(o.get("interactable", int(o["state"]) == 0)):
			continue
		var d := (o["pos"] as Vector2).distance_to(p["pos"]) - float(o["r"])
		if d <= float(rules.get("interact_range", 70.0)) and d < best_d:
			best_d = d
			best = int(o["id"])
	if boss != null and best == 0:
		best = boss.find_interactable(p)
	return best


func _complete_object(o: Dictionary, p: Dictionary) -> void:
	match int(o["kind"]):
		Protocol.ObKind.GNAW_TREE:
			o["state"] = 1
			team_wood = mini(team_wood + int(rules.get("gnaw_wood", 3)), int(rules.get("wood_cap", 30)))
			stats["gnaws"] += 1
			stats["wood_gained"] += int(rules.get("gnaw_wood", 3))
			for i in obstacles.size():
				if int(obstacles[i].get("object_id", -1)) == int(o["id"]):
					obstacles.remove_at(i)
					break
			objects.erase(o["id"])
			events.append({"k": "gnaw", "id": p["id"], "wood": team_wood, "x": o["pos"].x, "y": o["pos"].y})
		Protocol.ObKind.DEVICE:
			o["state"] = 1
			p["stats"]["objective"] = float(p["stats"]["objective"]) + 1.0
			events.append({"k": "device_done", "id": p["id"], "oid": o["id"]})
		Protocol.ObKind.SLUICE_LEVER:
			o["progress"] = 0.0
			_toggle_sluice(p)
		Protocol.ObKind.SECRET:
			objects.erase(o["id"])
			(stats["secrets"] as Array).append(String(o.get("secret_id", "")))
			p["stats"]["secrets"] = int(p["stats"].get("secrets", 0)) + 1
			events.append({"k": "secret_found", "id": p["id"], "secret": o.get("secret_id", ""), "name": o.get("name_ko", ""), "x": o["pos"].x, "y": o["pos"].y})
		_:
			if boss != null:
				boss.on_object_complete(o, p)
	_fire_procs(p, "on_interact", {})


func _toggle_sluice(p: Dictionary) -> void:
	if water_zone.is_empty():
		return
	if int(water_zone["state"]) == 1:
		return
	stats["sluice_toggles"] += 1
	if int(water_zone["state"]) == 2:
		water_zone["state"] = 0
		events.append({"k": "sluice", "state": 0, "id": p["id"]})
	else:
		water_zone["state"] = 1  # 경고 후 범람 (9절: 물길이 바뀌기 전에 경고)
		water_zone["t"] = float(rules.get("sluice_warn_sec", 0.8))
		events.append({"k": "sluice", "state": 1, "id": p["id"]})


func _hazard_slow_at(pos: Vector2) -> float:
	var best := 0.0
	for h: Dictionary in hazards:
		if Rect2(float(h["x"]), float(h["y"]), float(h["w"]), float(h["h"])).has_point(pos):
			best = maxf(best, float(h.get("slow", 0.0)))
	return best


func _aura_slow_at(pos: Vector2) -> float:
	var best := 0.0
	for e: Dictionary in enemies.values():
		var aura: Dictionary = e["def"].get("aura", {})
		if e["ai"] == Protocol.EnemyAI.DEAD or float(aura.get("player_slow", 0.0)) <= 0.0:
			continue
		if (e["pos"] as Vector2).distance_to(pos) <= float(aura.get("radius", 150)):
			best = maxf(best, float(aura["player_slow"]))
	return best


## 적 공격의 부가 효과를 플레이어에게 적용 (둔화·속박·출혈). 무적·보호 중이면 피해와 함께 무시된다.
func _apply_hit_status(p: Dictionary, on_hit: Dictionary) -> void:
	if on_hit.is_empty() or p["state"] != Protocol.EntState.ALIVE or float(p["invuln_t"]) > 0.0 or float(p["protect_t"]) > 0.0:
		return
	var resist := 1.0 - clampf(float(p["mods"].get("status_resist", 0.0)), 0.0, 0.8)
	if float(on_hit.get("slow_sec", 0.0)) > 0.0:
		p["slow_t"] = maxf(float(p["slow_t"]), float(on_hit["slow_sec"]) * resist)
		p["slow_mult"] = maxf(float(p["slow_mult"]), float(on_hit.get("slow_mult", 0.3)))
	if float(on_hit.get("root_sec", 0.0)) > 0.0:
		p["root_t"] = maxf(float(p["root_t"]), float(on_hit["root_sec"]) * resist)
		events.append({"k": "player_rooted", "id": p["id"], "sec": on_hit["root_sec"]})
	if float(on_hit.get("bleed_sec", 0.0)) > 0.0:
		p["bleed_t"] = maxf(float(p["bleed_t"]), float(on_hit["bleed_sec"]))
		p["bleed_dps"] = maxf(float(p["bleed_dps"]), float(on_hit.get("bleed_dps", 2.0)))


## 적 정의의 소환·오라 (토템·버섯). 공격 상태와 무관하게 흐른다.
func _step_enemy_passives(e: Dictionary, def: Dictionary, dt: float) -> void:
	var sm: Dictionary = def.get("summon", {})
	if not sm.is_empty():
		e["summon_t"] = float(e["summon_t"]) - dt
		if float(e["summon_t"]) <= 0.0:
			e["summon_t"] = float(sm.get("every_sec", 7.0))
			var alive_mine := 0
			for o: Dictionary in enemies.values():
				if o.get("summoned_by", -1) == e["id"] and o["ai"] != Protocol.EnemyAI.DEAD:
					alive_mine += 1
			var cap := _enemy_cap()
			if alive_mine < int(sm.get("max_alive", 3)) and int(e["summoned"]) < int(sm.get("cap_total", 6)) and _alive_enemy_count() < cap:
				var pos: Vector2 = e["pos"] + Vector2(rng.randf_range(-60, 60), rng.randf_range(-60, 60))
				var child := _spawn_enemy(String(sm.get("id", "sap_snail")), _clamp_in_bounds(pos, 20.0))
				child["summoned_by"] = e["id"]
				e["summoned"] = int(e["summoned"]) + 1
				events.append({"k": "summon", "eid": e["id"], "child": child["id"]})
	var aura: Dictionary = def.get("aura", {})
	if float(aura.get("enemy_heal_per_sec", 0.0)) > 0.0:
		e["aura_t"] = float(e["aura_t"]) - dt
		if float(e["aura_t"]) <= 0.0:
			e["aura_t"] = 1.0
			for o: Dictionary in enemies.values():
				if o["id"] != e["id"] and o["ai"] != Protocol.EnemyAI.DEAD and (o["pos"] as Vector2).distance_to(e["pos"]) <= float(aura.get("radius", 150)):
					o["hp"] = minf(float(o["hp"]) + float(aura["enemy_heal_per_sec"]), float(o["max_hp"]))


static func _path_length(path: Array) -> float:
	var total := 0.0
	for i in range(1, path.size()):
		total += Vector2(path[i - 1][0], path[i - 1][1]).distance_to(Vector2(path[i][0], path[i][1]))
	return maxf(total, 1.0)


func _in_water(pos: Vector2) -> bool:
	if water_zone.is_empty():
		return false
	return Rect2(water_zone["x"], water_zone["y"], water_zone["w"], water_zone["h"]).has_point(pos)


func _step_water(dt: float) -> void:
	if water_zone.is_empty():
		return
	if int(water_zone["state"]) == 1:
		water_zone["t"] = float(water_zone["t"]) - dt
		if float(water_zone["t"]) <= 0.0:
			water_zone["state"] = 2
			events.append({"k": "sluice", "state": 2})
	if int(water_zone["state"]) == 2:
		for e: Dictionary in enemies.values():
			if e["ai"] != Protocol.EnemyAI.DEAD and _in_water(e["pos"]):
				_damage_enemy(e, float(rules.get("sluice_enemy_dps", 4.0)) * dt, {"id": "sluice", "stats": {"damage_dealt": 0.0, "kills": 0}, "pos": e["pos"], "facing": Vector2.RIGHT}, 0.0, 0.0, true)


func _find_rescue_target(p: Dictionary) -> String:
	var best := ""
	var best_d := float(rules.get("rescue_range", 70.0))
	for o: Dictionary in players.values():
		if o["id"] == p["id"] or o["state"] != Protocol.EntState.DOWNED:
			continue
		if int(o["rescued_count"]) >= int(rules.get("max_rescues_per_room_per_player", 3)):
			continue
		var d := (o["pos"] as Vector2).distance_to(p["pos"])
		if d <= best_d:
			best_d = d
			best = o["id"]
	return best


func _rescue(rescuer: Dictionary, target: Dictionary) -> void:
	target["state"] = Protocol.EntState.ALIVE
	target["hp"] = maxf(float(target["max_hp"]) * float(rules.get("rescue_hp_fraction", 0.35)), 1.0)
	target["protect_t"] = float(rules.get("rescue_protect_sec", 2.0)) + float(rescuer["mods"].get("rescue_protect_add", 0.0))
	target["rescued_count"] = int(target["rescued_count"]) + 1
	target["action"] = Protocol.Action.IDLE
	target["action_kind"] = ""
	rescuer["stats"]["rescues"] = int(rescuer["stats"]["rescues"]) + 1
	stats["rescues"] += 1
	events.append({"k": "rescued", "id": target["id"], "by": rescuer["id"]})
	_fire_procs(rescuer, "on_rescue", {"target": target})


func _fire_procs(p: Dictionary, trigger: String, ctx: Dictionary) -> void:
	for proc: Dictionary in p.get("procs", []):
		if String(proc.get("trigger", "")) != trigger:
			continue
		if elapsed - float(proc.get("_last", -1000.0)) < float(proc.get("icd_sec", 0.0)):
			continue
		if proc.has("chance") and rng.randf() > float(proc["chance"]):
			continue
		if proc.has("max_per_run") and int(proc.get("_count", 0)) >= int(proc["max_per_run"]):
			continue
		proc["_last"] = elapsed
		proc["_count"] = int(proc.get("_count", 0)) + 1
		match String(proc.get("effect", "")):
			"heal_charge":
				p["heal_uses"] = int(p["heal_uses"]) + int(proc.get("value", 1))
			"ally_haste":
				for o: Dictionary in players.values():
					if o["state"] == Protocol.EntState.ALIVE and (o["pos"] as Vector2).distance_to(p["pos"]) <= float(proc.get("radius", 160)):
						o["haste_t"] = maxf(float(o["haste_t"]), 2.0)
						o["haste_mult"] = maxf(float(o["haste_mult"]), float(proc.get("value", 0.2)))
			"party_shield":
				for o: Dictionary in players.values():
					if o["state"] == Protocol.EntState.ALIVE:
						o["shield"] = minf(maxf(float(o["shield"]), float(proc.get("value", 10))), float(rules.get("caps", {}).get("shield_max", 60)))
						o["shield_t"] = maxf(float(o["shield_t"]), 6.0)
			"heal":
				_heal_player(p, float(proc.get("value", 0)), p)
			"shield_both":
				for who: Dictionary in [p, ctx.get("target", p)]:
					who["shield"] = minf(maxf(float(who["shield"]), float(proc.get("value", 0))), float(rules.get("caps", {}).get("shield_max", 60)))
					who["shield_t"] = maxf(float(who["shield_t"]), 6.0)
			"aoe_damage":
				for e: Dictionary in enemies.values():
					if e["ai"] != Protocol.EnemyAI.DEAD and (e["pos"] as Vector2).distance_to(p["pos"]) <= float(proc.get("radius", 70)) + float(e["radius"]):
						_damage_enemy(e, _player_damage(p, float(proc.get("value", 6))), p, 30.0, 0.0)
			"reflect":
				var e: Dictionary = ctx.get("enemy", {})
				if not e.is_empty() and e.get("ai", Protocol.EnemyAI.DEAD) != Protocol.EnemyAI.DEAD:
					_damage_enemy(e, _player_damage(p, float(proc.get("value", 10))), p, 40.0, 0.2)
		events.append({"k": "proc", "id": p["id"], "source": proc.get("source", ""), "trigger": trigger})


## 플레이어 피해. source_id 는 원인 ID("e<id>", "p<id>", "hazard"), source_enemy 는 반격용.
func _damage_player(p: Dictionary, amount: float, source_pos: Vector2, source_id: String, source_enemy: Dictionary = {}) -> void:
	if p["state"] != Protocol.EntState.ALIVE or explore:
		return
	if float(p["invuln_t"]) > 0.0 or float(p["protect_t"]) > 0.0:
		events.append({"k": "evaded", "id": p["id"]})
		return
	var reduction := 0.0
	if float(p["front_guard_t"]) > 0.0 and SimRules.in_front_arc(p["pos"], p["facing"], source_pos, float(p.get("front_guard_arc", 150))):
		reduction = float(p.get("front_guard_value", 0.5))
		p["stats"]["guards"] = int(p["stats"]["guards"]) + 1
		p["guard_bonus"] = float(p["mods"].get("guard_bonus_add", 0.0))
		_fire_procs(p, "on_guard", {"enemy": source_enemy})
	reduction = minf(reduction + float(p["mods"].get("damage_reduction", 0.0)), float(rules.get("caps", {}).get("damage_reduction_max", 0.6)))
	var dmg := SimRules.damage(amount, 1.0, 0.0, 1.0, reduction, 0.0, rules.get("caps", {})) * hit_damage_mult
	if float(p["mods"].get("low_hp_taken", 0.0)) > 0.0 and float(p["hp"]) <= float(p["max_hp"]) * 0.5:
		dmg *= 1.0 + float(p["mods"].get("low_hp_taken", 0.0))
	var absorbed := 0.0
	if float(p["shield"]) > 0.0:
		absorbed = minf(float(p["shield"]), dmg)
		p["shield"] = float(p["shield"]) - absorbed
		dmg -= absorbed
	p["hp"] = maxf(float(p["hp"]) - dmg, 0.0)
	p["stats"]["damage_taken"] = float(p["stats"]["damage_taken"]) + dmg
	if p["class_id"] == "sawtooth" and dmg > 0.0:
		p["resource"] = maxf(float(p["resource"]) - float(ContentDB.get_class_def("sawtooth").get("passive", {}).get("lose_on_hit", 1)), 0.0)
	events.append({"k": "hit", "id": p["id"], "by": source_id, "dmg": dmg, "absorbed": absorbed, "guarded": reduction > 0.0})
	if dmg > 0.0 and source_id != "bleed":
		_fire_procs(p, "on_hurt", {"enemy": source_enemy})
		if not source_enemy.is_empty() and String(source_enemy.get("affix", "")) != "":
			_apply_affix_on_hit(p, source_enemy)
	if float(p["hp"]) <= 0.0:
		p["state"] = Protocol.EntState.DOWNED
		p["down_t"] = float(rules.get("down_duration_sec", 25.0))
		p["action"] = Protocol.Action.IDLE
		p["action_kind"] = ""
		p["rescue_t"] = 0.0
		p["interact_target"] = 0
		p["stats"]["downs"] = int(p["stats"]["downs"]) + 1
		stats["downs"] += 1
		events.append({"k": "player_downed", "id": p["id"]})
		if boss != null:
			boss.on_player_downed(p)


func _damage_enemy(e: Dictionary, dmg: float, attacker: Dictionary, knockback: float, stagger: float, silent: bool = false) -> void:
	if e["ai"] == Protocol.EnemyAI.DEAD:
		return
	if float(e.get("vuln_t", 0.0)) > 0.0:
		dmg *= 1.0 + float(e.get("vuln_mult", 0.0))
	if bool(e.get("elite", false)):
		dmg *= 1.0 + float(attacker.get("mods", {}).get("boss_damage_mult", 0.0))
	if knockback > 0.0 and float(attacker.get("mods", {}).get("knockback_slow", 0.0)) > 0.0:
		_slow_enemy(e, float(attacker["mods"]["knockback_slow"]), 2.0)
	var armor: Dictionary = e["def"].get("armor_front", {})
	if not armor.is_empty() and attacker.has("pos") and SimRules.in_front_arc(e["pos"], e["facing"], attacker["pos"], float(armor.get("arc_deg", 150))):
		dmg *= 1.0 - float(armor.get("reduction", 0.5))
		if not silent:
			events.append({"k": "armor_block", "eid": e["id"], "x": e["pos"].x, "y": e["pos"].y})
	e["hp"] = maxf(float(e["hp"]) - dmg, 0.0)
	e["last_hit_t"] = elapsed
	attacker["stats"]["damage_dealt"] = float(attacker["stats"].get("damage_dealt", 0.0)) + dmg
	if not silent and String(e.get("affix", "")) == "thorn_shell" and players.has(attacker.get("id", "")) and attacker.has("pos"):
		var rf: Dictionary = ContentDB.elites.get("affixes", {}).get("thorn_shell", {}).get("reflect", {})
		if (attacker["pos"] as Vector2).distance_to(e["pos"]) <= float(rf.get("range", 90)):
			attacker["bleed_t"] = maxf(float(attacker["bleed_t"]), float(rf.get("bleed_sec", 3.0)))
			attacker["bleed_dps"] = maxf(float(attacker["bleed_dps"]), float(rf.get("bleed_dps", 2.0)))
	if knockback > 0.0:
		var dir: Vector2 = (e["pos"] - attacker["pos"]).normalized() if (e["pos"] as Vector2).distance_to(attacker["pos"]) > 0.01 else attacker["facing"]
		e["pos"] = SimRules.move(e["pos"], dir, knockback, 1.0, bounds, float(e["radius"]), all_obstacles())
	if stagger > 0.0 and float(e["stagger_resist_t"]) <= 0.0:
		e["stagger_t"] = maxf(float(e["stagger_t"]), stagger)
		e["stagger_resist_t"] = float(e["def"].get("stagger_resist_after_sec", 1.0))
		if e["ai"] == Protocol.EnemyAI.WINDUP:
			e["ai"] = Protocol.EnemyAI.STAGGER
			e["telegraph"] = {}
	# 솔방울사수 표식: 같은 대상 연속 명중
	if attacker.get("class_id", "") == "pinecone" and not silent:
		var passive: Dictionary = ContentDB.get_class_def("pinecone").get("passive", {})
		var marks: Dictionary = e.get("marks", {})
		var n := int(marks.get(attacker["id"], 0)) + 1
		if n >= maxi(int(passive.get("mark_hits", 3)) + int(attacker["mods"].get("mark_hits_add", 0)), 2):
			n = 0
			var burst := _player_damage(attacker, float(passive.get("mark_damage", 6)) + float(attacker["mods"].get("mark_damage_add", 0.0)))
			e["hp"] = maxf(float(e["hp"]) - burst, 0.0)
			attacker["stats"]["damage_dealt"] = float(attacker["stats"]["damage_dealt"]) + burst
			events.append({"k": "mark_burst", "eid": e["id"], "by": attacker["id"], "dmg": burst, "x": e["pos"].x, "y": e["pos"].y})
			var splash := float(attacker["mods"].get("mark_splash", 0.0))
			if splash > 0.0:
				for o: Dictionary in enemies.values():
					if o["id"] != e["id"] and o["ai"] != Protocol.EnemyAI.DEAD and (o["pos"] as Vector2).distance_to(e["pos"]) <= 80.0:
						o["hp"] = maxf(float(o["hp"]) - burst * splash, 0.0)
						if float(o["hp"]) <= 0.0:
							_kill_enemy(o, attacker)
		marks[attacker["id"]] = n
		e["marks"] = marks
	if not silent:
		events.append({"k": "enemy_hit", "eid": e["id"], "by": attacker["id"], "dmg": dmg, "x": e["pos"].x, "y": e["pos"].y})
	if float(e["hp"]) <= 0.0:
		_kill_enemy(e, attacker)


func _kill_enemy(e: Dictionary, attacker: Dictionary) -> void:
	if e["ai"] == Protocol.EnemyAI.DEAD:
		return
	e["ai"] = Protocol.EnemyAI.DEAD
	e["death_t"] = 1.0
	e["telegraph"] = {}
	attacker["stats"]["kills"] = int(attacker["stats"].get("kills", 0)) + 1
	stats["enemies_killed"] += 1
	var kbt: Dictionary = stats["kills_by_type"]
	kbt[e["type"]] = int(kbt.get(e["type"], 0)) + 1
	var wood := int(e["def"].get("wood_drop", 0)) * (int(ContentDB.elites.get("spawn", {}).get("wood_mult", 3)) if bool(e.get("elite", false)) else 1)
	if wood > 0:
		team_wood = mini(team_wood + wood, int(rules.get("wood_cap", 30)))
		stats["wood_gained"] += wood
	events.append({"k": "enemy_died", "eid": e["id"], "by": attacker["id"], "type": e["type"], "x": e["pos"].x, "y": e["pos"].y})
	_affix_on_death(e)
	if players.has(attacker.get("id", "")):
		_fire_procs(attacker, "on_kill", {"enemy": e})


func _root_enemy(e: Dictionary, sec: float) -> void:
	if e["ai"] == Protocol.EnemyAI.DEAD:
		return
	e["root_t"] = maxf(float(e.get("root_t", 0.0)), sec)
	if e["ai"] in [Protocol.EnemyAI.WINDUP, Protocol.EnemyAI.ATTACK]:
		e["telegraph"] = {}
	e["ai"] = Protocol.EnemyAI.ROOTED
	events.append({"k": "rooted", "eid": e["id"], "sec": sec})


# ------------------------------------------------------------------ projectiles

func _spawn_projectile(pos: Vector2, vel: Vector2, r: float, dmg: float, kind: int, owner: String, ttl: float, pierce: int, knockback: float, stagger: float) -> void:
	projectiles.append({"pos": pos, "vel": vel, "r": r, "dmg": dmg, "kind": kind, "owner": owner, "ttl": ttl, "pierce": pierce, "hit": [], "kb": knockback, "st": stagger})


func _step_projectiles(dt: float) -> void:
	var i := projectiles.size() - 1
	while i >= 0:
		var pr: Dictionary = projectiles[i]
		pr["ttl"] = float(pr["ttl"]) - dt
		pr["pos"] = pr["pos"] + pr["vel"] * dt
		var pos: Vector2 = pr["pos"]
		var dead := float(pr["ttl"]) <= 0.0 or not bounds.grow(-2).has_point(pos)
		if not dead:
			for ob: Dictionary in obstacles:
				if Vector2(float(ob["x"]), float(ob["y"])).distance_to(pos) <= float(ob["r"]) + float(pr["r"]) * 0.5:
					dead = true
					break
		if not dead and int(pr["kind"]) == 0:
			for o: Dictionary in objects.values():
				if o["kind"] in [Protocol.ObKind.STRUCTURE, Protocol.ObKind.DAM] and (o["pos"] as Vector2).distance_to(pos) <= float(o["r"]) + float(pr["r"]):
					o["hp"] = float(o["hp"]) - float(pr["dmg"])
					dead = true
					break
		if not dead:
			if int(pr["kind"]) == 0:
				for p: Dictionary in players.values():
					if p["state"] != Protocol.EntState.ALIVE or (p["pos"] as Vector2).distance_to(pos) > float(p["radius"]) + float(pr["r"]):
						continue
					if not p["connected"] and float(p["disconnect_t"]) < float(rules.get("disconnect_combat_vulnerable_after_sec", 5.0)):
						continue
					_damage_player(p, float(pr["dmg"]), pos - pr["vel"].normalized() * 10.0, String(pr["owner"]))
					if pr.has("on_hit"):
						_apply_hit_status(p, pr["on_hit"])
					dead = true
					break
			else:
				var attacker: Dictionary = players.get(pr["owner"], {})
				if attacker.is_empty():
					dead = true
				else:
					for e: Dictionary in enemies.values():
						if e["ai"] == Protocol.EnemyAI.DEAD or (pr["hit"] as Array).has(e["id"]):
							continue
						if (e["pos"] as Vector2).distance_to(pos) <= float(e["radius"]) + float(pr["r"]):
							_damage_enemy(e, float(pr["dmg"]), attacker, float(pr["kb"]), float(pr["st"]))
							if float(pr.get("slow", 0.0)) > 0.0:
								_slow_enemy(e, float(pr["slow"]), 1.5)
							if float(pr.get("bleed", 0.0)) > 0.0:
								e["bleed_t"] = 2.0
								e["bleed_dps"] = float(pr["bleed"])
								e["bleed_by"] = attacker["id"]
							if bool(pr.get("basic", false)):
								_on_basic_hit(attacker, e)
							(pr["hit"] as Array).append(e["id"])
							if int(pr["pierce"]) <= 0:
								dead = true
								break
							pr["pierce"] = int(pr["pierce"]) - 1
					if not dead and boss != null and boss.on_projectile(pr, attacker):
						dead = true
		if dead:
			projectiles.remove_at(i)
		i -= 1


# ------------------------------------------------------------------ objects (traps, volleys, structures)

func _step_objects(dt: float) -> void:
	for oid in objects.keys():
		var o: Dictionary = objects[oid]
		match int(o["kind"]):
			Protocol.ObKind.TRAP:
				o["arm_t"] = float(o["arm_t"]) - dt
				o["life"] = float(o["life"]) - dt
				o["state"] = 1 if float(o["arm_t"]) <= 0.0 else 0
				if float(o["life"]) <= 0.0:
					objects.erase(oid)
					continue
				if int(o["state"]) == 1:
					for e: Dictionary in enemies.values():
						if e["ai"] != Protocol.EnemyAI.DEAD and (e["pos"] as Vector2).distance_to(o["pos"]) <= float(o["r"]) + float(e["radius"]):
							var owner: Dictionary = players.get(o.get("owner", ""), {})
							_root_enemy(e, float(o["root_sec"]))
							if float(o.get("vuln_sec", 0.0)) > 0.0:
								e["vuln_t"] = maxf(float(e.get("vuln_t", 0.0)), float(o["vuln_sec"]))
								e["vuln_mult"] = maxf(float(e.get("vuln_mult", 0.0)), float(o["vuln_mult"]))
							if not owner.is_empty():
								_damage_enemy(e, float(o["damage"]), owner, 0.0, 0.0)
								for k in int(o.get("scatter", 0)):
									var d := Vector2.RIGHT.rotated(k * TAU / maxi(int(o["scatter"]), 1))
									_spawn_projectile(o["pos"] + d * 10.0, d * 420.0, 8.0, float(o["damage"]) * 0.4, 1, String(o["owner"]), 0.5, 0, 15.0, 0.0)
							events.append({"k": "trap", "x": o["pos"].x, "y": o["pos"].y})
							objects.erase(oid)
							break
			Protocol.ObKind.VOLLEY:
				o["life"] = float(o["life"]) - dt
				o["tick_t"] = float(o["tick_t"]) - dt
				o["progress"] = 1.0 - clampf(float(o["life"]) / 3.0, 0.0, 1.0)
				if float(o["tick_t"]) <= 0.0:
					o["tick_t"] = float(o["tick_sec"])
					var owner: Dictionary = players.get(o.get("owner", ""), {})
					if not owner.is_empty():
						for e: Dictionary in enemies.values():
							if e["ai"] != Protocol.EnemyAI.DEAD and (e["pos"] as Vector2).distance_to(o["pos"]) <= float(o["r"]) + float(e["radius"]):
								_damage_enemy(e, float(o["damage"]), owner, 0.0, 0.0)
								if float(o.get("slow_mult", 0.0)) > 0.0:
									_slow_enemy(e, float(o["slow_mult"]), 1.0)
						if boss != null:
							boss.on_circle_attack(owner, o["pos"], float(o["r"]), float(o["damage"]))
				if float(o["life"]) <= 0.0:
					var fb := float(o.get("final_burst", 0.0))
					var owner2: Dictionary = players.get(o.get("owner", ""), {})
					if fb > 0.0 and not owner2.is_empty():
						_circle_damage(owner2, o["pos"], float(o["r"]) * 1.3, fb, 80.0, 0.4)
						events.append({"k": "circle_hit", "id": owner2["id"], "hits": 0, "radius": float(o["r"]) * 1.3})
					objects.erase(oid)
			Protocol.ObKind.STRUCTURE:
				o["life"] = float(o["life"]) - dt
				o["progress"] = clampf(float(o["hp"]) / maxf(float(o["max_hp"]), 1.0), 0.0, 1.0)
				var sowner: Dictionary = players.get(o.get("owner", ""), {})
				if float(o.get("contact_damage", 0.0)) > 0.0 and not sowner.is_empty():
					for e: Dictionary in enemies.values():
						if e["ai"] != Protocol.EnemyAI.DEAD and (e["pos"] as Vector2).distance_to(o["pos"]) <= float(o["r"]) + float(e["radius"]) + 10.0:
							_damage_enemy(e, float(o["contact_damage"]) * dt, sowner, 0.0, 0.0, true)
							_slow_enemy(e, float(o.get("contact_slow", 0.0)), 0.3)
							if float(e["hp"]) <= 0.0:
								_kill_enemy(e, sowner)
				if float(o.get("heal_per_sec", 0.0)) > 0.0 and not sowner.is_empty():
					o["tick_t"] = float(o.get("tick_t", 0.0)) - dt
					if float(o["tick_t"]) <= 0.0:
						o["tick_t"] = 1.0
						for pl: Dictionary in players.values():
							if pl["state"] == Protocol.EntState.ALIVE and (pl["pos"] as Vector2).distance_to(o["pos"]) <= float(o["heal_radius"]):
								_heal_player(pl, float(o["heal_per_sec"]), sowner)
				if float(o["life"]) <= 0.0 or float(o["hp"]) <= 0.0:
					objects.erase(oid)
					events.append({"k": "structure_destroyed", "x": o["pos"].x, "y": o["pos"].y})
			Protocol.ObKind.TURRET:
				o["life"] = float(o["life"]) - dt
				o["fire_t"] = float(o["fire_t"]) - dt
				o["progress"] = clampf(float(o["life"]) / maxf(float(o["total"]), 1.0), 0.0, 1.0)
				var owner: Dictionary = players.get(o.get("owner", ""), {})
				if float(o["life"]) <= 0.0 or float(o["hp"]) <= 0.0 or owner.is_empty():
					objects.erase(oid)
					events.append({"k": "turret_gone", "x": o["pos"].x, "y": o["pos"].y})
					continue
				if float(o["fire_t"]) <= 0.0:
					var best: Dictionary = {}
					var best_d := float(o["range"])
					for e: Dictionary in enemies.values():
						if e["ai"] == Protocol.EnemyAI.DEAD:
							continue
						var d := (e["pos"] as Vector2).distance_to(o["pos"])
						if d <= best_d:
							best_d = d
							best = e
					var target_pos := Vector2.ZERO
					if not best.is_empty():
						target_pos = best["pos"]
					elif boss != null and boss.alive() and (boss.pos as Vector2).distance_to(o["pos"]) <= float(o["range"]):
						target_pos = boss.pos
					if target_pos != Vector2.ZERO:
						o["fire_t"] = float(o["fire_sec"])
						var dir: Vector2 = (target_pos - o["pos"]).normalized()
						o["state"] = 1
						# 포탑 투사체는 기본 공격이 아니므로 수압을 충전하지 않는다 (재귀 발동 금지)
						for si in int(o.get("shots", 1)):
							_spawn_projectile(o["pos"] + dir * 16.0, dir.rotated((si - 0.5 * (int(o.get("shots", 1)) - 1)) * 0.12) * float(o["proj_speed"]), 8.0, float(o["damage"]), 1, String(o["owner"]), float(o["range"]) / float(o["proj_speed"]) + 0.1, 0, 15.0, 0.0)
							projectiles[projectiles.size() - 1]["slow"] = float(o.get("shot_slow", 0.0))
						events.append({"k": "turret_shot", "x": o["pos"].x, "y": o["pos"].y, "fx": dir.x, "fy": dir.y})
					else:
						o["state"] = 0
			Protocol.ObKind.DAM:
				o["life"] = float(o["life"]) - dt
				o["progress"] = clampf(float(o["hp"]) / maxf(float(o["max_hp"]), 1.0), 0.0, 1.0)
				if float(o["life"]) <= 0.0 or float(o["hp"]) <= 0.0:
					_burst_dam(o)
					objects.erase(oid)
			Protocol.ObKind.ROOT_ZONE, Protocol.ObKind.FLOOD_ZONE:
				o["life"] = float(o["life"]) - dt
				o["tick_t"] = float(o["tick_t"]) - dt
				if int(o.get("follow", 0)) > 0 and players.has(o.get("owner", "")):
					o["pos"] = players[o["owner"]]["pos"]
				o["progress"] = 1.0 - clampf(float(o["life"]) / maxf(float(o["total"]), 1.0), 0.0, 1.0)
				if float(o["tick_t"]) <= 0.0:
					o["tick_t"] = float(o["tick_sec"])
					var owner: Dictionary = players.get(o.get("owner", ""), {})
					if not owner.is_empty():
						for e: Dictionary in enemies.values():
							if e["ai"] != Protocol.EnemyAI.DEAD and (e["pos"] as Vector2).distance_to(o["pos"]) <= float(o["r"]) + float(e["radius"]):
								if float(o.get("slow_mult", 0.0)) > 0.0:
									_slow_enemy(e, float(o["slow_mult"]), float(o["tick_sec"]) + 0.2)
								_damage_enemy(e, float(o["damage"]), owner, 0.0, 0.0, true)
								if float(e["hp"]) <= 0.0:
									_kill_enemy(e, owner)
						if boss != null and float(o["damage"]) > 0.0:
							boss.on_circle_attack(owner, o["pos"], float(o["r"]), float(o["damage"]))
						if float(o.get("heal", 0.0)) > 0.0:
							for pl: Dictionary in players.values():
								if pl["state"] == Protocol.EntState.ALIVE and (pl["pos"] as Vector2).distance_to(o["pos"]) <= float(o["r"]) + float(pl["radius"]):
									_heal_player(pl, float(o["heal"]), owner)
				if float(o["life"]) <= 0.0:
					objects.erase(oid)


# ------------------------------------------------------------------ enemies

func _spawn_enemy(type_id: String, pos: Vector2, elite: Dictionary = {}, opts: Dictionary = {}) -> Dictionary:
	var def: Dictionary = ContentDB.get_enemy_def(type_id)
	var affix := ""
	var espawn: Dictionary = ContentDB.elites.get("spawn", {})
	var affix_ids: Array = ContentDB.affix_ids()
	if elite.is_empty() and not bool(opts.get("no_affix", false)) and not affix_ids.is_empty() and String(def.get("role", "")) != "dummy":
		# RoR2 식 정예: 일반 스폰이 profile.elite_chance 로 접두 정예가 된다 (웨이브당 상한)
		var chance := float(profile.get("elite_chance", 0.0))
		var forced := bool(profile.get("force_elite", false)) and not _forced_elite_done
		if forced or (chance > 0.0 and _affix_elites_this_wave < int(espawn.get("max_affix_elites_per_wave", 1)) and rng.randf() < chance):
			_forced_elite_done = _forced_elite_done or forced
			_affix_elites_this_wave += 1
			affix = String(affix_ids[rng.randi() % affix_ids.size()])
			elite = {"hp_mult": float(espawn.get("hp_mult", 2.2)), "damage_mult": float(espawn.get("damage_mult", 1.3)), "scale": float(espawn.get("scale", 1.25)), "name_ko": "%s %s" % [ContentDB.elites["affixes"][affix].get("name_ko", affix), def.get("name_ko", type_id)]}
	elif not elite.is_empty() and not affix_ids.is_empty() and String(elite.get("affix", "")) == "" and not bool(opts.get("no_affix", false)):
		affix = String(affix_ids[rng.randi() % affix_ids.size()])   # 정예방의 고정 정예에도 접두 하나
	elif not elite.is_empty():
		affix = String(elite.get("affix", ""))
	var max_hp := float(def.get("hp", 30)) * float(profile.get("enemy_hp_mult", 1.0)) * float(elite.get("hp_mult", 1.0)) * float(opts.get("hp_frac", 1.0))
	var e := {
		"id": next_enemy_id, "type": type_id, "def": def, "role": String(def.get("role", "approach")), "pos": pos, "facing": Vector2(-1, 0), "hp": max_hp, "max_hp": max_hp,
		"radius": float(def.get("radius", 20)), "speed": float(def.get("move_speed", 60)), "ai": Protocol.EnemyAI.SEEK,
		"t": 0.0, "cooldown_t": 0.0, "target": "", "stagger_t": 0.0, "stagger_resist_t": 0.0, "telegraph": {}, "death_t": 0.0, "hit_done": false, "root_t": 0.0, "charge_hit": [], "marks": {},
		"slow_t": 0.0, "slow_mult": 0.0, "vuln_t": 0.0, "vuln_mult": 0.0,
		"elite": not elite.is_empty(), "damage_mult": float(elite.get("damage_mult", 1.0)), "summon_t": float(def.get("summon", {}).get("every_sec", 0.0)), "summoned": 0, "combo_left": 0, "aura_t": 0.0,
		"affix": affix, "last_hit_t": -100.0, "split_depth": int(opts.get("split_depth", 0)),
	}
	if float(opts.get("scale", 1.0)) != 1.0:
		e["radius"] = float(e["radius"]) * float(opts.get("scale", 1.0))
	if not elite.is_empty():
		e["radius"] = float(e["radius"]) * float(elite.get("scale", 1.3))
		e["name_ko"] = String(elite.get("name_ko", def.get("name_ko", type_id)))
		if affix != "" and not String(e["name_ko"]).begins_with(String(ContentDB.elites["affixes"][affix].get("name_ko", ""))):
			e["name_ko"] = "%s %s" % [ContentDB.elites["affixes"][affix].get("name_ko", affix), e["name_ko"]]
		events.append({"k": "elite_spawn", "eid": e["id"], "name": e["name_ko"], "affix": affix, "affix_desc": ContentDB.elites.get("affixes", {}).get(affix, {}).get("desc_ko", ""), "x": pos.x, "y": pos.y})
	next_enemy_id += 1
	enemies[e["id"]] = e
	stats["enemies_spawned"] += 1
	events.append({"k": "enemy_spawn", "eid": e["id"], "type": type_id, "x": pos.x, "y": pos.y})
	return e


func _enemy_move(e: Dictionary, dir: Vector2, dt: float, speed_mult: float = 1.0) -> void:
	var speed := float(e["speed"]) * speed_mult
	if int(water_zone.get("state", 0)) == 2 and _in_water(e["pos"]):
		speed *= 1.0 - float(rules.get("sluice_enemy_slow", 0.5))
	if float(e.get("slow_t", 0.0)) > 0.0:
		speed *= 1.0 - minf(float(e.get("slow_mult", 0.0)), float(rules.get("caps", {}).get("slow_max", 0.5)))
	speed *= 1.0 - _hazard_slow_at(e["pos"])
	var before: Vector2 = e["pos"]
	e["pos"] = SimRules.move(e["pos"], dir, speed, dt, bounds, float(e["radius"]), all_obstacles())
	# 구조물에 막히면 구조물을 공격한다
	if (e["pos"] as Vector2).distance_to(before) < speed * dt * 0.3:
		for o: Dictionary in objects.values():
			if o["kind"] in [Protocol.ObKind.STRUCTURE, Protocol.ObKind.DAM] and (o["pos"] as Vector2).distance_to(e["pos"]) <= float(o["r"]) + float(e["radius"]) + 8.0:
				o["hp"] = float(o["hp"]) - float(rules.get("structure_enemy_dps", 6.0)) * float(e["def"].get("structure_dps_mult", 1.0)) * dt
				break


func _step_enemy(e: Dictionary, dt: float) -> void:
	if e["ai"] == Protocol.EnemyAI.DEAD:
		e["death_t"] = float(e["death_t"]) - dt
		return
	if e["ai"] == Protocol.EnemyAI.RETREAT:
		e["t"] = float(e["t"]) - dt
		_enemy_move(e, e["facing"], dt, 2.0)
		if float(e["t"]) <= 0.0:
			e["ai"] = Protocol.EnemyAI.DEAD
			e["death_t"] = 0.0
		return
	e["cooldown_t"] = maxf(float(e["cooldown_t"]) - dt, 0.0)
	e["stagger_resist_t"] = maxf(float(e["stagger_resist_t"]) - dt, 0.0)
	if String(e.get("affix", "")) == "regen_shell":
		var rg: Dictionary = ContentDB.elites.get("affixes", {}).get("regen_shell", {}).get("regen", {})
		if elapsed - float(e.get("last_hit_t", -100.0)) >= float(rg.get("idle_sec", 2.5)) and float(e["hp"]) < float(e["max_hp"]):
			e["hp"] = minf(float(e["hp"]) + float(e["max_hp"]) * float(rg.get("per_sec", 0.04)) * dt, float(e["max_hp"]))
	e["slow_t"] = maxf(float(e.get("slow_t", 0.0)) - dt, 0.0)
	e["vuln_t"] = maxf(float(e.get("vuln_t", 0.0)) - dt, 0.0)
	if float(e.get("bleed_t", 0.0)) > 0.0:
		e["bleed_t"] = float(e["bleed_t"]) - dt
		var by: Dictionary = players.get(e.get("bleed_by", ""), {})
		if not by.is_empty():
			_damage_enemy(e, float(e["bleed_dps"]) * dt, by, 0.0, 0.0, true)
			if float(e["hp"]) <= 0.0:
				_kill_enemy(e, by)
				return
	if e["ai"] == Protocol.EnemyAI.ROOTED:
		e["root_t"] = float(e["root_t"]) - dt
		if float(e["root_t"]) <= 0.0:
			e["ai"] = Protocol.EnemyAI.SEEK
		return
	if float(e["stagger_t"]) > 0.0:
		e["stagger_t"] = float(e["stagger_t"]) - dt
		e["telegraph"] = {}
		if float(e["stagger_t"]) <= 0.0:
			e["ai"] = Protocol.EnemyAI.SEEK
		return
	var def: Dictionary = e["def"]
	var atk: Dictionary = def.get("attack", {})
	_step_enemy_passives(e, def, dt)
	if String(e["role"]) == "dummy":
		e["ai"] = Protocol.EnemyAI.IDLE
		return
	match e["ai"]:
		Protocol.EnemyAI.IDLE, Protocol.EnemyAI.SEEK:
			var t := _nearest_alive_player(e["pos"], float(def.get("aggro_range", 500)))
			if t != "":
				e["target"] = t
				e["ai"] = Protocol.EnemyAI.CHASE
			else:
				e["ai"] = Protocol.EnemyAI.IDLE
		Protocol.EnemyAI.CHASE:
			var tp: Dictionary = players.get(e["target"], {})
			if tp.is_empty() or tp["state"] != Protocol.EntState.ALIVE:
				e["ai"] = Protocol.EnemyAI.SEEK
				return
			var to: Vector2 = tp["pos"] - e["pos"]
			var dist := to.length()
			if dist > 0.01:
				e["facing"] = to.normalized()
			match String(e["role"]):
				"charger":
					if dist <= float(atk.get("trigger_range", 330)) and float(e["cooldown_t"]) <= 0.0:
						_enemy_begin_windup(e, atk)
					else:
						_enemy_move(e, to.normalized(), dt)
				"stationary":
					if dist <= float(atk.get("radius", 90)) + float(tp["radius"]) + 20.0 and float(e["cooldown_t"]) <= 0.0:
						_enemy_begin_windup(e, atk)
				"leaper":
					if dist <= float(atk.get("leap_range", 320)) and dist > 60.0 and float(e["cooldown_t"]) <= 0.0:
						_enemy_begin_windup(e, atk)
					else:
						_enemy_move(e, to.normalized(), dt)
				"ranged":
					var pmin := float(atk.get("preferred_min", 200))
					var pmax := float(atk.get("preferred_max", 320))
					if dist < pmin:
						_enemy_move(e, -to.normalized(), dt)
					elif dist > pmax:
						_enemy_move(e, to.normalized(), dt)
					elif float(e["cooldown_t"]) <= 0.0:
						_enemy_begin_windup(e, atk)
				_:
					var reach := float(atk.get("forward_offset", 28)) + float(atk.get("radius", 40)) * 0.6
					if dist > reach:
						_enemy_move(e, to.normalized(), dt)
					elif float(e["cooldown_t"]) <= 0.0:
						_enemy_begin_windup(e, atk)
		Protocol.EnemyAI.WINDUP:
			e["t"] = float(e["t"]) - dt
			if float(e["t"]) <= 0.0:
				e["ai"] = Protocol.EnemyAI.ATTACK
				e["t"] = float(atk.get("active_sec", 0.15))
				e["charge_hit"] = []
				_enemy_attack_begin(e, atk)
		Protocol.EnemyAI.ATTACK:
			e["t"] = float(e["t"]) - dt
			if String(atk.get("shape", "circle")) == "line":
				_enemy_charge_step(e, atk, dt)
			if float(e["t"]) <= 0.0:
				if int(e.get("combo_left", 0)) > 0:
					# 연속 공격: 짧은 예고 뒤 같은 공격을 한 번 더
					e["combo_left"] = int(e["combo_left"]) - 1
					e["ai"] = Protocol.EnemyAI.WINDUP
					e["t"] = float(atk.get("combo_windup_sec", 0.35))
					e["hit_done"] = false
					var center: Vector2 = e["pos"] + e["facing"] * float(atk.get("forward_offset", 28))
					e["telegraph"] = {"type": 0, "x": center.x, "y": center.y, "r": float(atk.get("radius", 40)), "total": float(atk.get("combo_windup_sec", 0.35)), "asset": atk.get("telegraph_asset", "vfx.telegraph_circle")}
					return
				e["ai"] = Protocol.EnemyAI.RECOVER
				e["t"] = float(atk.get("recovery_sec", 0.5))
				e["telegraph"] = {}
		Protocol.EnemyAI.RECOVER:
			e["t"] = float(e["t"]) - dt
			if float(e["t"]) <= 0.0:
				e["cooldown_t"] = float(atk.get("cooldown_sec", 1.5))
				e["ai"] = Protocol.EnemyAI.SEEK
		Protocol.EnemyAI.STAGGER:
			e["telegraph"] = {}
			e["ai"] = Protocol.EnemyAI.SEEK


func _enemy_begin_windup(e: Dictionary, atk: Dictionary) -> void:
	# 강공격은 동시 상한(프로필)을 넘기지 않는다
	if bool(atk.get("heavy", false)):
		var heavy := 0
		for o: Dictionary in enemies.values():
			if o["ai"] == Protocol.EnemyAI.WINDUP and bool(o["def"].get("attack", {}).get("heavy", false)):
				heavy += 1
		if heavy >= int(profile.get("max_concurrent_heavy_telegraphs", 1)):
			return
	e["ai"] = Protocol.EnemyAI.WINDUP
	var windup := float(atk.get("windup_sec", 0.7))
	if bool(atk.get("heavy", false)):
		windup = maxf(windup, float(rules.get("telegraph_min_sec", 0.7)))
	e["t"] = windup
	e["hit_done"] = false
	e["combo_left"] = maxi(int(atk.get("combo", 1)) - 1, 0)
	match String(atk.get("shape", "circle")):
		"leap":
			var tp: Dictionary = players.get(e["target"], {})
			var land: Vector2 = tp["pos"] if not tp.is_empty() else e["pos"]
			e["telegraph"] = {"type": 0, "x": land.x, "y": land.y, "r": float(atk.get("radius", 60)), "total": windup, "asset": atk.get("telegraph_asset", "vfx.telegraph_circle")}
		"line":
			e["telegraph"] = {"type": 1, "x": e["pos"].x, "y": e["pos"].y, "len": float(atk.get("length", 380)), "w": float(atk.get("width", 64)), "dx": e["facing"].x, "dy": e["facing"].y, "total": windup, "asset": atk.get("telegraph_asset", "vfx.telegraph_line")}
		"projectile":
			e["telegraph"] = {"type": 0, "x": e["pos"].x, "y": e["pos"].y, "r": 30.0, "total": windup, "asset": atk.get("telegraph_asset", "vfx.telegraph_circle")}
		_:
			var center: Vector2 = e["pos"] + e["facing"] * float(atk.get("forward_offset", 28))
			e["telegraph"] = {"type": 0, "x": center.x, "y": center.y, "r": float(atk.get("radius", 40)), "total": windup, "asset": atk.get("telegraph_asset", "vfx.telegraph_circle")}


func _enemy_attack_begin(e: Dictionary, atk: Dictionary) -> void:
	var dmg_mult := float(e.get("damage_mult", 1.0))
	match String(atk.get("shape", "circle")):
		"leap":
			var tg: Dictionary = e["telegraph"]
			var land := Vector2(float(tg.get("x", e["pos"].x)), float(tg.get("y", e["pos"].y)))
			e["pos"] = _clamp_in_bounds(land, float(e["radius"]))
			var r := float(tg.get("r", atk.get("radius", 60)))
			for p: Dictionary in players.values():
				if p["state"] != Protocol.EntState.ALIVE:
					continue
				if SimRules.circle_hit(land, r, p["pos"], float(p["radius"])):
					_damage_player(p, float(atk.get("damage", 12)) * dmg_mult, e["pos"], "e%d" % int(e["id"]), e)
					_apply_hit_status(p, atk.get("on_hit", {}))
			events.append({"k": "enemy_attack", "eid": e["id"], "x": land.x, "y": land.y, "r": r, "leap": true})
		"line":
			e["charge_from"] = e["pos"]
			e["charge_dir"] = Vector2(float(e["telegraph"].get("dx", 1)), float(e["telegraph"].get("dy", 0)))
			events.append({"k": "enemy_charge", "eid": e["id"]})
		"projectile":
			var pr: Dictionary = atk.get("projectile", {})
			var tp: Dictionary = players.get(e["target"], {})
			var dir: Vector2 = e["facing"]
			if not tp.is_empty():
				dir = ((tp["pos"] as Vector2) - (e["pos"] as Vector2)).normalized()
			_spawn_projectile(e["pos"] + dir * 18.0, dir * float(pr.get("speed", 340)), float(pr.get("radius", 10)), float(pr.get("damage", 9)) * dmg_mult, 0, "e%d" % int(e["id"]), float(pr.get("ttl_sec", 1.7)), 0, 0.0, 0.0)
			if pr.has("on_hit"):
				projectiles[projectiles.size() - 1]["on_hit"] = pr["on_hit"]
			e["telegraph"] = {}
			events.append({"k": "enemy_shoot", "eid": e["id"], "x": e["pos"].x, "y": e["pos"].y})
		_:
			var tg: Dictionary = e["telegraph"]
			var center := Vector2(float(tg.get("x", e["pos"].x)), float(tg.get("y", e["pos"].y)))
			var r := float(tg.get("r", atk.get("radius", 40)))
			for p: Dictionary in players.values():
				if p["state"] != Protocol.EntState.ALIVE:
					continue
				if not p["connected"] and float(p["disconnect_t"]) < float(rules.get("disconnect_combat_vulnerable_after_sec", 5.0)):
					continue
				if SimRules.circle_hit(center, r, p["pos"], float(p["radius"])):
					_damage_player(p, float(atk.get("damage", 10)) * dmg_mult, e["pos"], "e%d" % int(e["id"]), e)
					_apply_hit_status(p, atk.get("on_hit", {}))
			events.append({"k": "enemy_attack", "eid": e["id"], "x": center.x, "y": center.y, "r": r})


func _enemy_charge_step(e: Dictionary, atk: Dictionary, dt: float) -> void:
	var dir: Vector2 = e["charge_dir"]
	e["pos"] = SimRules.move(e["pos"], dir, float(atk.get("charge_speed", 500)), dt, bounds, float(e["radius"]), all_obstacles())
	var half_w := float(atk.get("width", 64)) * 0.5
	for p: Dictionary in players.values():
		if p["state"] != Protocol.EntState.ALIVE or (e["charge_hit"] as Array).has(p["id"]):
			continue
		if (p["pos"] as Vector2).distance_to(e["pos"]) <= half_w + float(p["radius"]):
			(e["charge_hit"] as Array).append(p["id"])
			_damage_player(p, float(atk.get("damage", 14)) * float(e.get("damage_mult", 1.0)), e["pos"], "e%d" % int(e["id"]), e)
			var kb := float(atk.get("knockback", 100))
			if p["state"] == Protocol.EntState.ALIVE and kb > 0.0:
				p["pos"] = SimRules.move(p["pos"], dir, kb, 1.0, bounds, float(p["radius"]), obstacles)
	for o: Dictionary in objects.values():
		if o["kind"] == Protocol.ObKind.STRUCTURE and (o["pos"] as Vector2).distance_to(e["pos"]) <= float(o["r"]) + float(e["radius"]) + 4.0:
			o["hp"] = float(o["hp"]) - 30.0
			e["t"] = 0.0  # 구조물에 부딪히면 돌진이 멈춘다


func _nearest_alive_player(from: Vector2, max_range: float) -> String:
	var best := ""
	var best_d := max_range
	for p: Dictionary in players.values():
		if p["state"] != Protocol.EntState.ALIVE:
			continue
		var d := (p["pos"] as Vector2).distance_to(from)
		if d <= best_d:
			best_d = d
			best = p["id"]
	return best


func _separate_enemies() -> void:
	var list := enemies.values()
	for i in list.size():
		var a: Dictionary = list[i]
		if a["ai"] in [Protocol.EnemyAI.DEAD, Protocol.EnemyAI.ATTACK]:
			continue
		for j in range(i + 1, list.size()):
			var b: Dictionary = list[j]
			if b["ai"] in [Protocol.EnemyAI.DEAD, Protocol.EnemyAI.ATTACK]:
				continue
			var d: Vector2 = b["pos"] - a["pos"]
			var min_d := float(a["radius"]) + float(b["radius"])
			var len := d.length()
			if len < min_d and len > 0.001:
				var push := d.normalized() * (min_d - len) * 0.5
				a["pos"] = SimRules.move(a["pos"], -push, 1.0, 1.0, bounds, float(a["radius"]), obstacles)
				b["pos"] = SimRules.move(b["pos"], push, 1.0, 1.0, bounds, float(b["radius"]), obstacles)


# ------------------------------------------------------------------ waves & objectives

func _spawn_wave() -> void:
	if wave_index >= wave_count:
		_all_spawned = true
		return
	var budget := wave_budget_total / float(wave_count)
	_affix_elites_this_wave = 0
	var spawns: Array = room_def.get("enemy_spawns", [[900, 400]])
	var elite_def: Dictionary = room_def.get("elite", {})
	if not elite_def.is_empty() and not elite_spawned:
		elite_spawned = true
		var esp: Array = spawns[0]
		_spawn_enemy(String(elite_def.get("id", "thorn_boar")), Vector2(esp[0], esp[1]), elite_def)
	var cap := _enemy_cap()
	var spawned := 0
	var guard := 0
	var alive := _alive_enemy_count()
	while budget > 0.0 and guard < 64 and alive + spawned < cap:
		guard += 1
		var pick: Dictionary = _weighted_pick(enemy_pool)
		var def := ContentDB.get_enemy_def(String(pick.get("id", "")))
		if def.is_empty() or not bool(def.get("implemented", false)):
			break
		var cost := float(def.get("threat_cost", 1.0))
		if cost > budget + 0.001:
			# 남은 예산으로 가장 싼 적을 시도
			var cheapest := _cheapest_affordable(budget)
			if cheapest.is_empty():
				break
			def = cheapest
			cost = float(def.get("threat_cost", 1.0))
		budget -= cost
		var sp: Array = spawns[(wave_index * 3 + spawned) % spawns.size()]
		var pos := Vector2(sp[0], sp[1]) + Vector2(rng.randf_range(-30, 30), rng.randf_range(-30, 30))
		_spawn_enemy(String(def["id"]), pos)
		spawned += 1
	wave_index += 1
	_wave_gap_t = float(room_def.get("waves", {}).get("wave_gap_sec", 2.0))
	events.append({"k": "wave", "index": wave_index, "count": wave_count, "spawned": spawned})
	if wave_index >= wave_count:
		_all_spawned = true


func _cheapest_affordable(budget: float) -> Dictionary:
	var best: Dictionary = {}
	for pick: Dictionary in enemy_pool:
		var def := ContentDB.get_enemy_def(String(pick.get("id", "")))
		if def.is_empty() or not bool(def.get("implemented", false)):
			continue
		if float(def.get("threat_cost", 1.0)) <= budget + 0.001 and (best.is_empty() or float(def["threat_cost"]) < float(best["threat_cost"])):
			best = def
	return best


func _weighted_pick(pool: Array) -> Dictionary:
	var total := 0.0
	for p: Dictionary in pool:
		total += float(p.get("weight", 1.0))
	var r := rng.randf() * total
	for p: Dictionary in pool:
		r -= float(p.get("weight", 1.0))
		if r <= 0.0:
			return p
	return pool[pool.size() - 1]


func _alive_enemy_count() -> int:
	var c := 0
	for e: Dictionary in enemies.values():
		if not e["ai"] in [Protocol.EnemyAI.DEAD, Protocol.EnemyAI.RETREAT]:
			c += 1
	return c


func _step_waves(dt: float) -> void:
	for k in enemies.keys():
		if enemies[k]["ai"] == Protocol.EnemyAI.DEAD and float(enemies[k]["death_t"]) <= 0.0:
			enemies.erase(k)
	if _all_spawned:
		_step_director(dt)
	if _all_spawned or objective_done or objective == "boss":
		return
	_wave_gap_t -= dt
	var threshold := int(room_def.get("waves", {}).get("next_wave_when_alive_at_most", 1))
	if _wave_gap_t <= 0.0 and _alive_enemy_count() <= threshold:
		_spawn_wave()


## RoR2 디렉터: 웨이브가 다 나온 뒤 남은 예산(reserve)을 초당 크레딧으로 풀어, 적이 적을 때 소규모로 증원한다. 예산이 다하면 끝.
func _step_director(dt: float) -> void:
	if _director_reserve <= 0.0 or objective_done or objective in ["boss", "tutorial"]:
		return
	var dr: Dictionary = rules.get("director", {})
	if _alive_enemy_count() > int(dr.get("reinforce_when_alive_at_most", 3)):
		return
	_director_credits += wave_budget_total * float(dr.get("credit_per_sec_frac", 0.08)) * dt
	if _cheapest_affordable(_director_reserve).is_empty():
		_director_reserve = 0.0   # 남은 예산으로 살 수 있는 적이 없으면 증원 종료 (방이 반드시 끝나도록)
		return
	var cheapest := _cheapest_affordable(minf(_director_credits, _director_reserve))
	if cheapest.is_empty():
		return
	var spawns: Array = room_def.get("enemy_spawns", [[900, 400]])
	var cap := _enemy_cap()
	var n := 0
	while n < int(dr.get("group_max", 3)) and _director_reserve > 0.0 and _alive_enemy_count() < cap:
		var pick: Dictionary = _weighted_pick(enemy_pool)
		var def := ContentDB.get_enemy_def(String(pick.get("id", "")))
		if def.is_empty() or not bool(def.get("implemented", false)):
			break
		var cost := float(def.get("threat_cost", 1.0))
		if cost > _director_credits + 0.001:
			def = _cheapest_affordable(_director_credits)
			if def.is_empty():
				break
			cost = float(def.get("threat_cost", 1.0))
		_director_credits -= cost
		_director_reserve -= cost
		var sp: Array = spawns[(wave_index * 5 + n + int(elapsed)) % spawns.size()]
		_spawn_enemy(String(def["id"]), Vector2(sp[0], sp[1]) + Vector2(rng.randf_range(-30, 30), rng.randf_range(-30, 30)))
		n += 1
	if n > 0:
		events.append({"k": "reinforce", "count": n})


func _step_objective(dt: float) -> void:
	if objective_done:
		return
	match objective:
		"hold_point":
			for o: Dictionary in objects.values():
				if o["kind"] != Protocol.ObKind.HOLD_ZONE:
					continue
				var inside := false
				for p: Dictionary in players.values():
					if p["state"] == Protocol.EntState.ALIVE and (p["pos"] as Vector2).distance_to(o["pos"]) <= float(o["r"]):
						inside = true
						p["stats"]["objective"] = float(p["stats"]["objective"]) + dt
				var contested := false
				for e: Dictionary in enemies.values():
					if not e["ai"] in [Protocol.EnemyAI.DEAD, Protocol.EnemyAI.RETREAT] and (e["pos"] as Vector2).distance_to(o["pos"]) <= float(o["contest_radius"]):
						contested = true
				o["state"] = 2 if contested else (1 if inside else 0)
				if inside and not contested:
					o["progress"] = minf(float(o["progress"]) + dt / float(o["required"]), 1.0)
				objective_progress = float(o["progress"])
				if float(o["progress"]) >= 1.0:
					_objective_complete()
		"device":
			var total := 0
			var done := 0
			for o: Dictionary in objects.values():
				if o["kind"] == Protocol.ObKind.DEVICE:
					total += 1
					if int(o["state"]) == 1:
						done += 1
			objective_progress = float(done) / maxf(total, 1)
			if total > 0 and done == total:
				_objective_complete()
		"tutorial":
			_step_tutorial(dt)
		"escort":
			for o: Dictionary in objects.values():
				if o["kind"] != Protocol.ObKind.RAFT:
					continue
				var near := false
				for p: Dictionary in players.values():
					if p["state"] == Protocol.EntState.ALIVE and (p["pos"] as Vector2).distance_to(o["pos"]) <= float(o["radius"]):
						near = true
						p["stats"]["objective"] = float(p["stats"]["objective"]) + dt
				var contested := false
				for e: Dictionary in enemies.values():
					if not e["ai"] in [Protocol.EnemyAI.DEAD, Protocol.EnemyAI.RETREAT] and (e["pos"] as Vector2).distance_to(o["pos"]) <= float(o["contest_radius"]):
						contested = true
						o["hp"] = maxf(float(o["hp"]) - float(rules.get("escort_enemy_dps", 3.0)) * dt, 0.0)
				o["state"] = 2 if contested else (1 if near else 0)
				if near and not contested:
					var path: Array = o["path"]
					var seg := int(o["seg"])
					if seg < path.size() - 1:
						var target := Vector2(path[seg + 1][0], path[seg + 1][1])
						var step := float(o["speed"]) * dt
						var d := (o["pos"] as Vector2).distance_to(target)
						if d <= step:
							o["pos"] = target
							o["seg"] = seg + 1
						else:
							o["pos"] = (o["pos"] as Vector2) + (target - o["pos"]).normalized() * step
						o["done_len"] = float(o["done_len"]) + minf(step, d)
				objective_progress = clampf(float(o["done_len"]) / float(o["total_len"]), 0.0, 1.0)
				o["progress"] = objective_progress
				if int(o["seg"]) >= (o["path"] as Array).size() - 1:
					_objective_complete()
				elif float(o["hp"]) <= 0.0 and outcome == Protocol.Outcome.NONE:
					outcome = Protocol.Outcome.WIPE
					events.append({"k": "escort_lost"})
		"boss":
			if boss != null and boss.is_defeated():
				objective_progress = 1.0
				_objective_complete()
			elif boss != null:
				objective_progress = boss.hp_fraction()
		_:
			objective_progress = float(stats["enemies_killed"]) / maxf(float(stats["enemies_spawned"]), 1.0)


## 튜토리얼: 이동 → 공격 → 회피 → 스킬 → 구조(설명) → 갉기 → 건설 → 수문 순서 (18절). 각 단계는 실제 행동으로 넘어간다.
func _step_tutorial(dt: float) -> void:
	var steps: Array = rules.get("tutorial_steps", [])
	if tutorial_step >= steps.size():
		return
	var sid := String(steps[tutorial_step].get("id", ""))
	var done := false
	match sid:
		"move":
			for p: Dictionary in players.values():
				_tutorial_moved += (p["pos"] as Vector2).distance_to(p.get("_tut_last", p["pos"]))
				p["_tut_last"] = p["pos"]
			done = _tutorial_moved >= 200.0
		"attack": done = int(stats["enemies_killed"]) >= 1
		"dodge": done = bool(_tutorial_flags.get("dodge", false))
		"skill": done = bool(_tutorial_flags.get("skill", false))
		"rescue":
			# 혼자면 설명만 보고 3초 뒤 넘어간다. 2인 이상은 실제 구조 또는 6초 대기
			_tutorial_flags["rescue_t"] = float(_tutorial_flags.get("rescue_t", 0.0)) + dt
			done = int(stats["rescues"]) >= 1 or float(_tutorial_flags["rescue_t"]) >= (3.0 if players.size() == 1 else 6.0)
		"gnaw": done = int(stats["gnaws"]) >= 1
		"build": done = int(stats["builds"]) >= 1
		"sluice": done = int(stats["sluice_toggles"]) >= 1
	if done:
		tutorial_step += 1
		objective_progress = float(tutorial_step) / maxf(steps.size(), 1)
		if tutorial_step < steps.size():
			events.append({"k": "tutorial_step", "index": tutorial_step, "total": steps.size(), "text": steps[tutorial_step].get("text_ko", "")})
			if String(steps[tutorial_step].get("id", "")) == "build":
				team_wood = maxi(team_wood, 6)
		else:
			events.append({"k": "tutorial_done"})
			_objective_complete()


func tutorial_skip() -> void:
	if objective != "tutorial" or objective_done:
		return
	tutorial_step = (rules.get("tutorial_steps", []) as Array).size()
	objective_progress = 1.0
	events.append({"k": "tutorial_done", "skipped": true})
	_objective_complete()


func _objective_complete() -> void:
	objective_done = true
	# 남은 적은 후퇴한다 (보상 없음). 목표를 빨리 달성하면 일찍 끝난다 (4절)
	for e: Dictionary in enemies.values():
		if e["ai"] != Protocol.EnemyAI.DEAD:
			e["ai"] = Protocol.EnemyAI.RETREAT
			e["t"] = 1.2
			e["telegraph"] = {}
			var center := bounds.get_center()
			e["facing"] = ((e["pos"] as Vector2) - center).normalized() if (e["pos"] as Vector2).distance_to(center) > 1.0 else Vector2.RIGHT
	events.append({"k": "objective_done", "objective": objective})


func _check_outcome() -> void:
	var any_alive := false
	for p: Dictionary in players.values():
		if p["state"] == Protocol.EntState.ALIVE:
			any_alive = true
			break
	if not any_alive:
		outcome = Protocol.Outcome.WIPE
		events.append({"k": "wipe"})
		return
	if objective_done:
		if _alive_enemy_count() == 0 or objective == "tutorial":
			outcome = Protocol.Outcome.VICTORY
			events.append({"k": "room_clear", "elapsed": elapsed})
		return
	if objective == "annihilate" and _all_spawned and _director_reserve <= 0.001 and _alive_enemy_count() == 0:
		outcome = Protocol.Outcome.VICTORY
		events.append({"k": "room_clear", "elapsed": elapsed})


# ------------------------------------------------------------------ snapshot

func snapshot() -> Dictionary:
	var ps: Array = []
	for p: Dictionary in players.values():
		var v := PackedFloat32Array([
			p["pos"].x, p["pos"].y, p["facing"].x, p["facing"].y, p["hp"], p["state"], p["action"], p["dodge_charges"], p["shield"], p["down_t"],
			p["cd"]["q"], p["cd"]["e"], p["cd"]["r"], 1.0 if (float(p["invuln_t"]) > 0.0 or float(p["protect_t"]) > 0.0) else 0.0, p["rescue_t"], p["heal_uses"],
			1.0 if p["connected"] else 0.0, 1.0 if float(p["front_guard_t"]) > 0.0 else 0.0, float(Protocol.ACTION_KIND_CODES.get(String(p["action_kind"]), 0)),
			float(p["resource"]), float((Protocol.ST_HASTE if float(p["haste_t"]) > 0.0 else 0) | (Protocol.ST_WHIRL if float(p["whirl_t"]) > 0.0 else 0) | (Protocol.ST_SLOW if float(p["slow_t"]) > 0.0 else 0) | (Protocol.ST_ROOT if float(p["root_t"]) > 0.0 else 0) | (Protocol.ST_BLEED if float(p["bleed_t"]) > 0.0 else 0))])
		ps.append([p["id"], v])
	var es: Array = []
	var tgs: Array = []
	for e: Dictionary in enemies.values():
		var est := (Protocol.ST_SLOW if float(e.get("slow_t", 0.0)) > 0.0 else 0) | (Protocol.ST_ROOT if e["ai"] == Protocol.EnemyAI.ROOTED else 0) | (Protocol.ST_VULN if float(e.get("vuln_t", 0.0)) > 0.0 else 0) | (Protocol.ST_ELITE if bool(e.get("elite", false)) else 0)
		es.append([e["id"], ContentDB.enemy_index(String(e["type"])), PackedFloat32Array([e["pos"].x, e["pos"].y, e["facing"].x, e["facing"].y, e["hp"], e["max_hp"], e["ai"], float(est)])])
		var tg: Dictionary = e["telegraph"]
		if not tg.is_empty() and e["ai"] == Protocol.EnemyAI.WINDUP:
			if int(tg.get("type", 0)) == 1:
				tgs.append(PackedFloat32Array([1, tg["x"], tg["y"], tg["len"], e["t"], tg["total"], tg["dx"], tg["dy"], tg["w"]]))
			else:
				tgs.append(PackedFloat32Array([0, tg["x"], tg["y"], tg["r"], e["t"], tg["total"], 0, 0, 0]))
	var prs: Array = []
	for pr: Dictionary in projectiles:
		prs.append(PackedFloat32Array([pr["pos"].x, pr["pos"].y, pr["vel"].x, pr["vel"].y, pr["r"], pr["kind"]]))
	var obs: Array = []
	for o: Dictionary in objects.values():
		obs.append(PackedFloat32Array([o["id"], o["kind"], o["pos"].x, o["pos"].y, o["r"], o["progress"], o["state"]]))
	var snap := {"t": tick, "wave": [wave_index, wave_count], "p": ps, "e": es, "tg": tgs, "pr": prs, "ob": obs, "wood": team_wood, "obj": [objective, objective_progress, 1 if objective_done else 0]}
	if not water_zone.is_empty():
		snap["wz"] = PackedFloat32Array([water_zone["x"], water_zone["y"], water_zone["w"], water_zone["h"], water_zone["state"]])
	if not hazards.is_empty():
		var hz: Array = []
		for h: Dictionary in hazards:
			hz.append(PackedFloat32Array([h["x"], h["y"], h["w"], h["h"], float(h.get("slow", 0.0))]))
		snap["hz"] = hz
	if boss != null:
		snap["boss"] = boss.snapshot()
		for tg in boss.telegraphs():
			tgs.append(tg)
	return snap


func result_summary() -> Dictionary:
	var per: Dictionary = {}
	for p: Dictionary in players.values():
		per[p["id"]] = p["stats"].duplicate()
		per[p["id"]]["hp"] = p["hp"]
		per[p["id"]]["max_hp"] = p["max_hp"]
		per[p["id"]]["heal_uses"] = p["heal_uses"]
		per[p["id"]]["state"] = p["state"]
	var mech_ok: Array = []
	var boss_id := ""
	if boss != null:
		boss_id = String(boss.def.get("id", ""))
		for entry: Dictionary in boss.log:
			if String(entry.get("event", "")) == "success":
				mech_ok.append(String(entry.get("mechanic", "")))
	return {"outcome": outcome, "elapsed": elapsed, "ticks": tick, "seed": seed_value, "n": n_players, "objective": objective, "stats": stats.duplicate(true), "players": per, "team_wood": team_wood, "boss_id": boss_id, "mechanics_succeeded": mech_ok, "room_id": String(room_def.get("id", "")), "elite": room_def.has("elite")}


# ------------------------------------------------------------------ 정예 접두 (data/elites.json)

func _apply_affix_on_hit(p: Dictionary, e: Dictionary) -> void:
	var a: Dictionary = ContentDB.elites.get("affixes", {}).get(String(e.get("affix", "")), {})
	var oh: Dictionary = a.get("on_hit", {})
	if oh.is_empty():
		return
	if oh.has("slow_mult"):
		p["slow_t"] = maxf(float(p["slow_t"]), float(oh.get("slow_sec", 2.0)))
		p["slow_mult"] = maxf(float(p["slow_mult"]), float(oh.get("slow_mult", 0.4)))
		events.append({"k": "player_slowed", "id": p["id"], "sec": oh.get("slow_sec", 2.0)})
	if oh.has("heal_cut_sec"):
		p["heal_cut_t"] = maxf(float(p.get("heal_cut_t", 0.0)), float(oh.get("heal_cut_sec", 5.0)))
		p["heal_cut_mult"] = float(oh.get("heal_cut_mult", 0.5))
		events.append({"k": "heal_cut", "id": p["id"], "sec": oh.get("heal_cut_sec", 5.0)})


func _affix_on_death(e: Dictionary) -> void:
	var affix := String(e.get("affix", ""))
	if affix == "":
		return
	var a: Dictionary = ContentDB.elites.get("affixes", {}).get(affix, {})
	var od: Dictionary = a.get("on_death", {})
	if od.has("hazard_slow"):
		var r := float(od.get("hazard_r", 70))
		hazards.append({"x": e["pos"].x - r, "y": e["pos"].y - r, "w": r * 2, "h": r * 2, "slow": float(od.get("hazard_slow", 0.35)), "life": float(od.get("hazard_sec", 6.0))})
	var sp: Dictionary = a.get("split", {})
	if not sp.is_empty() and int(e.get("split_depth", 0)) < int(sp.get("max_depth", 1)):
		for i in int(sp.get("count", 2)):
			var off := Vector2.RIGHT.rotated(i * TAU / maxi(int(sp.get("count", 2)), 1)) * 26.0
			_spawn_enemy(String(e["type"]), (e["pos"] as Vector2) + off, {}, {"no_affix": true, "hp_frac": float(sp.get("hp_frac", 0.3)), "scale": float(sp.get("scale", 0.75)), "split_depth": int(e.get("split_depth", 0)) + 1})
		events.append({"k": "split", "eid": e["id"], "x": e["pos"].x, "y": e["pos"].y})


## 동시 적 상한: 기본값 + 추가 인원당 가산 (party_scaling.screen_caps)
func _enemy_cap() -> int:
	var caps: Dictionary = ContentDB.party_scaling.get("screen_caps", {})
	return int(caps.get("max_enemies_on_screen", 16)) + int(caps.get("per_extra_player", 4)) * maxi(n_players - 1, 0)

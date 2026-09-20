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
var stats := {"enemies_spawned": 0, "enemies_killed": 0, "downs": 0, "rescues": 0, "deaths": 0, "kills_by_type": {}, "wood_gained": 0, "builds": 0, "sluice_toggles": 0, "gnaws": 0}
var hit_damage_mult: float = 1.0
var team_wood: int = 0
var water_zone: Dictionary = {}   # {x,y,w,h,state(0 low,1 warning,2 high), t}
var enemy_pool: Array = []
var boss: RefCounted = null        # 보스방일 때 BossController (단계 2-3)
var _retreat_t: float = -1.0


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
	hit_damage_mult = float(profile.get("hit_damage_mult", 1.0))
	objective = String(def.get("objective", "annihilate"))
	enemy_pool = opts.get("enemy_pool", def.get("enemy_pool", [{"id": "sap_snail", "weight": 1.0}]))
	team_wood = int(opts.get("team_wood", 0))
	var w: Dictionary = def.get("waves", {})
	wave_count = maxi(int(w.get("wave_count", 1)), 1)
	wave_budget_total = (float(w.get("base_budget", 4.0)) + float(opts.get("budget_add", 0.0))) * float(profile.get("wave_budget_mult", 1.0))
	var spawns: Array = def.get("player_spawns", [[100, 100]])
	var i := 0
	for m: Dictionary in members:
		add_player(m, spawns[i % spawns.size()])
		i += 1
	_setup_objects()
	if objective != "boss":
		_spawn_wave()


# ------------------------------------------------------------------ setup

func _setup_objects() -> void:
	for t: Array in room_def.get("gnaw_trees", []):
		var o := _add_object(Protocol.ObKind.GNAW_TREE, Vector2(t[0], t[1]), 30.0, {"hold_sec": float(rules.get("gnaw_hold_sec", 1.2))})
		obstacles.append({"shape": "circle", "x": o["pos"].x, "y": o["pos"].y, "r": 30, "object_id": o["id"]})
	for d: Dictionary in room_def.get("devices", []):
		_add_object(Protocol.ObKind.DEVICE, Vector2(float(d["x"]), float(d["y"])), 34.0, {"hold_sec": float(d.get("hold_sec", 4.0))})
	var hz: Dictionary = room_def.get("hold_zone", {})
	if not hz.is_empty():
		_add_object(Protocol.ObKind.HOLD_ZONE, Vector2(float(hz["x"]), float(hz["y"])), float(hz.get("r", 120)), {"required": float(hz.get("required_sec", 20)), "contest_radius": float(hz.get("contest_radius", 140))})
	var sl: Variant = room_def.get("sluice", null)
	if sl is Dictionary:
		var lever: Array = sl["lever"]
		_add_object(Protocol.ObKind.SLUICE_LEVER, Vector2(lever[0], lever[1]), 28.0, {"hold_sec": float(sl.get("hold_sec", 1.5))})
		var z: Dictionary = sl["zone"]
		water_zone = {"x": float(z["x"]), "y": float(z["y"]), "w": float(z["w"]), "h": float(z["h"]), "state": 0, "t": 0.0}


func _add_object(kind: int, pos: Vector2, r: float, extra: Dictionary) -> Dictionary:
	var o := {"id": next_object_id, "kind": kind, "pos": pos, "r": r, "progress": 0.0, "state": 0, "hold_sec": 1.0}
	o.merge(extra, true)
	next_object_id += 1
	objects[o["id"]] = o
	return o


func add_player(m: Dictionary, spawn: Array) -> Dictionary:
	var cdef: Dictionary = ContentDB.get_class_def(String(m.get("class_id", "guardian")))
	var mods: Dictionary = m.get("mods", RunMods.empty())
	var max_hp := float(cdef.get("base_hp", 100)) + float(mods.get("max_hp_add", 0.0))
	var p := {
		"id": m["account_id"], "nick": m.get("nickname", ""), "class_id": cdef.get("id", "guardian"),
		"pos": Vector2(spawn[0], spawn[1]), "facing": Vector2(1, 0), "speed": float(cdef.get("move_speed", 180)) * (1.0 + float(mods.get("speed_mult", 0.0))),
		"radius": float(cdef.get("radius", 18)), "hp": maxf(minf(float(m.get("hp", max_hp)), max_hp), 1.0) if m.has("hp") else max_hp, "max_hp": max_hp, "state": Protocol.EntState.ALIVE,
		"action": Protocol.Action.IDLE, "action_kind": "", "action_t": 0.0, "action_total": 0.0, "hit_applied": false,
		"cd": {"q": 0.0, "e": 0.0, "r": 0.0}, "dodge_max": int(rules.get("dodge_charges", 2)) + int(mods.get("dodge_charges_add", 0)), "dodge_charges": 0, "dodge_recharge_t": 0.0,
		"invuln_t": 0.0, "protect_t": 0.0, "shield": 0.0, "shield_t": 0.0, "front_guard_t": 0.0, "stagger_t": 0.0,
		"down_t": 0.0, "rescue_target": "", "rescue_t": 0.0, "rescued_count": 0, "heal_uses": int(m.get("heal_uses", rules.get("heal_uses_per_expedition", 2))),
		"connected": bool(m.get("connected", true)), "disconnect_t": 0.0, "inputs": [], "last_seq": 0, "prev_buttons": 0, "move_dir": Vector2.ZERO,
		"mods": mods, "procs": m.get("procs", []), "interact_target": 0, "grab_t": 0.0,
		"stats": {"damage_dealt": 0.0, "damage_taken": 0.0, "kills": 0, "downs": 0, "rescues": 0, "deaths": 0, "objective": 0.0, "guards": 0},
	}
	p["dodge_charges"] = p["dodge_max"]
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
		if o["kind"] == Protocol.ObKind.STRUCTURE:
			out.append({"shape": "circle", "x": o["pos"].x, "y": o["pos"].y, "r": o["r"]})
	return out


# ------------------------------------------------------------------ tick

func step(dt: float) -> Array:
	events.clear()
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
	_step_water(dt)
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
		if float(p["dodge_recharge_t"]) >= float(rules.get("dodge_recharge_sec", 4.0)):
			p["dodge_recharge_t"] = 0.0
			p["dodge_charges"] = int(p["dodge_charges"]) + 1
	p["invuln_t"] = maxf(float(p["invuln_t"]) - dt, 0.0)
	p["protect_t"] = maxf(float(p["protect_t"]) - dt, 0.0)
	p["front_guard_t"] = maxf(float(p["front_guard_t"]) - dt, 0.0)
	p["stagger_t"] = maxf(float(p["stagger_t"]) - dt, 0.0)
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
	return p["action"] == Protocol.Action.IDLE and float(p["stagger_t"]) <= 0.0


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
		p["invuln_t"] = float(rules.get("dodge_invuln_sec", 0.2))
		p["dodge_dir"] = mv.normalized() if mv.length_squared() > 0.01 else p["facing"]
		p["rescue_t"] = 0.0
		p["interact_target"] = 0
		events.append({"k": "dodge", "id": p["id"]})
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
			if float(p["rescue_t"]) >= float(rules.get("rescue_hold_sec", 3.0)):
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
			o["progress"] = minf(float(o["progress"]) + dt / maxf(float(o.get("hold_sec", 1.0)), 0.05), 1.0)
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
	var can_move := action in [Protocol.Action.IDLE, Protocol.Action.RECOVERY] and float(p["stagger_t"]) <= 0.0
	var slow := 1.0
	if _in_water(p["pos"]) and water_zone.get("state", 0) == 2:
		slow = 1.0 - float(rules.get("sluice_player_slow", 0.3))
	if action == Protocol.Action.DODGE:
		p["pos"] = SimRules.move(p["pos"], p["dodge_dir"], float(p["speed"]) * float(rules.get("dodge_speed_mult", 3.0)), dt, bounds, float(p["radius"]), obstacles)
	elif can_move and mv.length_squared() > 0.0001:
		var speed := float(p["speed"]) * (0.6 if action == Protocol.Action.RECOVERY else 1.0) * slow
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
			p["action_total"] = float(atk.get("recovery_sec", 0.3))
			p["action_t"] = p["action_total"]
		Protocol.Action.RECOVERY, Protocol.Action.DODGE:
			p["action"] = Protocol.Action.IDLE
			p["action_kind"] = ""
		Protocol.Action.CAST:
			_apply_cast(p, cdef, String(p["action_kind"]))
			p["action"] = Protocol.Action.IDLE
			p["action_kind"] = ""


func _player_damage(p: Dictionary, base: float) -> float:
	var bonus := 0.0
	if boss != null:
		bonus = boss.damage_bonus_at(p["pos"])
	return SimRules.damage(base, 1.0 + float(p["mods"].get("damage_mult", 0.0)) + bonus, 0.0, 1.0, 0.0, 0.0, rules.get("caps", {}))


func _apply_basic_attack(p: Dictionary, atk: Dictionary) -> void:
	var shape := String(atk.get("shape", "arc"))
	if shape == "projectile":
		var pr: Dictionary = atk.get("projectile", {})
		var dir: Vector2 = p["facing"]
		_spawn_projectile(p["pos"] + dir * 20.0, dir * float(pr.get("speed", 500)), float(pr.get("radius", 9)), _player_damage(p, float(atk.get("damage", 7))), 1, p["id"], float(pr.get("ttl_sec", 0.8)), int(p["mods"].get("pierce_add", 0)), float(atk.get("knockback", 0)), float(atk.get("stagger_sec", 0)))
		events.append({"k": "shoot", "id": p["id"], "x": p["pos"].x, "y": p["pos"].y, "fx": dir.x, "fy": dir.y})
		return
	var hits := 0
	var kb := float(atk.get("knockback", 0)) * (1.0 + float(p["mods"].get("knockback_mult", 0.0)))
	var st := float(atk.get("stagger_sec", 0)) + float(p["mods"].get("stagger_add", 0.0))
	for e: Dictionary in enemies.values():
		if e["ai"] == Protocol.EnemyAI.DEAD:
			continue
		if SimRules.arc_hit(p["pos"], p["facing"], float(atk.get("range", 80)), float(atk.get("angle_deg", 120)), e["pos"], float(e["radius"])):
			_damage_enemy(e, _player_damage(p, float(atk.get("damage", 10))), p, kb, st)
			hits += 1
	if boss != null:
		hits += boss.on_arc_attack(p, atk)
	events.append({"k": "swing", "id": p["id"], "hits": hits, "x": p["pos"].x, "y": p["pos"].y, "fx": p["facing"].x, "fy": p["facing"].y})


func _apply_cast(p: Dictionary, cdef: Dictionary, kind: String) -> void:
	if kind == "heal":
		p["heal_uses"] = int(p["heal_uses"]) - 1
		var amount := float(p["max_hp"]) * float(rules.get("heal_fraction", 0.3))
		p["hp"] = minf(float(p["hp"]) + amount, float(p["max_hp"]))
		events.append({"k": "heal", "id": p["id"], "amount": amount})
		return
	var skill: Dictionary = cdef.get("skills", {}).get(kind, {})
	if skill.is_empty():
		return
	var m: Dictionary = p["mods"]
	p["cd"][kind] = float(skill.get("cooldown_sec", 10)) * (1.0 - float(m.get("cdr", 0.0)))
	var eff: Dictionary = skill.get("effect", {})
	var aim: Vector2 = p.get("aim", p["facing"])
	var aim_dir: Vector2 = SimRules.facing_from(aim, p["facing"])
	match String(eff.get("type", "")):
		"front_damage_reduction":
			p["front_guard_t"] = float(skill.get("duration_sec", 3.0)) + float(m.get("q_duration_add", 0.0))
			p["front_guard_value"] = float(m.get("q_value_set", 0.0)) if float(m.get("q_value_set", 0.0)) > 0.0 else float(eff.get("value", 0.5))
			p["front_guard_arc"] = float(eff.get("arc_deg", 150))
		"circle_hit":
			var radius := float(eff.get("radius", 100)) * (1.0 + float(m.get("e_radius_mult", 0.0)))
			var hits := 0
			for e: Dictionary in enemies.values():
				if e["ai"] == Protocol.EnemyAI.DEAD:
					continue
				if SimRules.circle_hit(p["pos"], radius, e["pos"], float(e["radius"])):
					_damage_enemy(e, _player_damage(p, float(eff.get("damage", 8))), p, float(eff.get("knockback", 100)) * (1.0 + float(m.get("knockback_mult", 0.0))), float(eff.get("stagger_sec", 0.5)) + float(m.get("e_stagger_add", 0.0)) + float(m.get("stagger_add", 0.0)))
					hits += 1
			if boss != null:
				hits += boss.on_circle_attack(p, p["pos"], radius, _player_damage(p, float(eff.get("damage", 8))))
			events.append({"k": "circle_hit", "id": p["id"], "hits": hits, "radius": radius})
		"party_shield":
			var cap := float(eff.get("max_shield_per_target", 45))
			for o: Dictionary in players.values():
				if o["state"] == Protocol.EntState.ALIVE and (o["pos"] as Vector2).distance_to(p["pos"]) <= float(eff.get("radius", 200)):
					o["shield"] = minf(maxf(float(o["shield"]), float(eff.get("shield", 30))), cap)
					o["shield_t"] = maxf(float(o["shield_t"]), float(eff.get("duration_sec", 6)))
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
				_spawn_projectile(p["pos"] + d * 20.0, d * float(eff.get("speed", 480)), float(eff.get("radius", 8)), _player_damage(p, float(eff.get("damage", 5))), 1, p["id"], float(eff.get("ttl_sec", 0.5)), int(m.get("pierce_add", 0)), 20.0, 0.0)
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
			_add_object(Protocol.ObKind.TRAP, at, float(eff.get("radius", 52)), {"owner": p["id"], "arm_t": float(eff.get("arm_sec", 0.5)), "life": float(eff.get("lifetime_sec", 20)), "root_sec": float(eff.get("root_sec", 1.5)) + float(m.get("e_root_add", 0.0)), "damage": _player_damage(p, float(eff.get("damage", 8)))})
		"volley":
			var at: Vector2 = _clamp_in_bounds(p["pos"] + aim.limit_length(float(eff.get("place_range", 360))), 20.0)
			_add_object(Protocol.ObKind.VOLLEY, at, float(eff.get("radius", 110)), {"owner": p["id"], "life": float(eff.get("duration_sec", 3.0)) + float(m.get("r_duration_add", 0.0)), "tick_sec": float(eff.get("tick_sec", 0.4)), "tick_t": 0.0, "damage": _player_damage(p, float(eff.get("damage", 9)))})
	events.append({"k": "skill", "id": p["id"], "skill": skill.get("id", kind), "slot": kind, "x": p["pos"].x, "y": p["pos"].y})


func _clamp_in_bounds(v: Vector2, margin: float) -> Vector2:
	return Vector2(clampf(v.x, bounds.position.x + margin, bounds.end.x - margin), clampf(v.y, bounds.position.y + margin, bounds.end.y - margin))


func _try_build(p: Dictionary) -> void:
	var cost := int(rules.get("build_cost_wood", 3))
	var count := 0
	for o: Dictionary in objects.values():
		if o["kind"] == Protocol.ObKind.STRUCTURE:
			count += 1
	if team_wood < cost or count >= int(rules.get("build_max_per_room", 3)):
		events.append({"k": "build_failed", "id": p["id"], "reason": "wood" if team_wood < cost else "limit"})
		return
	var at: Vector2 = _clamp_in_bounds(p["pos"] + (p["facing"] as Vector2) * 48.0, 26.0)
	for ob: Dictionary in all_obstacles():
		if Vector2(float(ob["x"]), float(ob["y"])).distance_to(at) < float(ob["r"]) + 26.0:
			events.append({"k": "build_failed", "id": p["id"], "reason": "blocked"})
			return
	team_wood -= cost   # 서버가 한 번만 처리한다. 음수 목재 없음.
	_add_object(Protocol.ObKind.STRUCTURE, at, 26.0, {"hp": float(rules.get("build_hp", 60)), "max_hp": float(rules.get("build_hp", 60)), "life": float(rules.get("build_lifetime_sec", 30.0)), "owner": p["id"]})
	stats["builds"] += 1
	events.append({"k": "build", "id": p["id"], "x": at.x, "y": at.y, "wood": team_wood})


func _find_interactable(p: Dictionary) -> int:
	var best := 0
	var best_d := 1e9
	for o: Dictionary in objects.values():
		if not o["kind"] in [Protocol.ObKind.GNAW_TREE, Protocol.ObKind.DEVICE, Protocol.ObKind.SLUICE_LEVER]:
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
		_:
			if boss != null:
				boss.on_object_complete(o, p)


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
	target["protect_t"] = float(rules.get("rescue_protect_sec", 2.0))
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
		proc["_last"] = elapsed
		match String(proc.get("effect", "")):
			"heal":
				p["hp"] = minf(float(p["hp"]) + float(proc.get("value", 0)), float(p["max_hp"]))
			"shield_both":
				for who: Dictionary in [p, ctx.get("target", p)]:
					who["shield"] = maxf(float(who["shield"]), float(proc.get("value", 0)))
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
	if p["state"] != Protocol.EntState.ALIVE:
		return
	if float(p["invuln_t"]) > 0.0 or float(p["protect_t"]) > 0.0:
		events.append({"k": "evaded", "id": p["id"]})
		return
	var reduction := 0.0
	if float(p["front_guard_t"]) > 0.0 and SimRules.in_front_arc(p["pos"], p["facing"], source_pos, float(p.get("front_guard_arc", 150))):
		reduction = float(p.get("front_guard_value", 0.5))
		p["stats"]["guards"] = int(p["stats"]["guards"]) + 1
		_fire_procs(p, "on_guard", {"enemy": source_enemy})
	var dmg := SimRules.damage(amount, 1.0, 0.0, 1.0, reduction, 0.0, rules.get("caps", {})) * hit_damage_mult
	var absorbed := 0.0
	if float(p["shield"]) > 0.0:
		absorbed = minf(float(p["shield"]), dmg)
		p["shield"] = float(p["shield"]) - absorbed
		dmg -= absorbed
	p["hp"] = maxf(float(p["hp"]) - dmg, 0.0)
	p["stats"]["damage_taken"] = float(p["stats"]["damage_taken"]) + dmg
	events.append({"k": "hit", "id": p["id"], "by": source_id, "dmg": dmg, "absorbed": absorbed, "guarded": reduction > 0.0})
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
	e["hp"] = maxf(float(e["hp"]) - dmg, 0.0)
	attacker["stats"]["damage_dealt"] = float(attacker["stats"].get("damage_dealt", 0.0)) + dmg
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
		if n >= int(passive.get("mark_hits", 3)):
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
	var wood := int(e["def"].get("wood_drop", 0))
	if wood > 0:
		team_wood = mini(team_wood + wood, int(rules.get("wood_cap", 30)))
		stats["wood_gained"] += wood
	events.append({"k": "enemy_died", "eid": e["id"], "by": attacker["id"], "type": e["type"], "x": e["pos"].x, "y": e["pos"].y})
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
				if o["kind"] == Protocol.ObKind.STRUCTURE and (o["pos"] as Vector2).distance_to(pos) <= float(o["r"]) + float(pr["r"]):
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
							if not owner.is_empty():
								_damage_enemy(e, float(o["damage"]), owner, 0.0, 0.0)
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
						if boss != null:
							boss.on_circle_attack(owner, o["pos"], float(o["r"]), float(o["damage"]))
				if float(o["life"]) <= 0.0:
					objects.erase(oid)
			Protocol.ObKind.STRUCTURE:
				o["life"] = float(o["life"]) - dt
				o["progress"] = clampf(float(o["hp"]) / maxf(float(o["max_hp"]), 1.0), 0.0, 1.0)
				if float(o["life"]) <= 0.0 or float(o["hp"]) <= 0.0:
					objects.erase(oid)
					events.append({"k": "structure_destroyed", "x": o["pos"].x, "y": o["pos"].y})


# ------------------------------------------------------------------ enemies

func _spawn_enemy(type_id: String, pos: Vector2) -> Dictionary:
	var def: Dictionary = ContentDB.get_enemy_def(type_id)
	var max_hp := float(def.get("hp", 30)) * float(profile.get("enemy_hp_mult", 1.0))
	var e := {
		"id": next_enemy_id, "type": type_id, "def": def, "role": String(def.get("role", "approach")), "pos": pos, "facing": Vector2(-1, 0), "hp": max_hp, "max_hp": max_hp,
		"radius": float(def.get("radius", 20)), "speed": float(def.get("move_speed", 60)), "ai": Protocol.EnemyAI.SEEK,
		"t": 0.0, "cooldown_t": 0.0, "target": "", "stagger_t": 0.0, "stagger_resist_t": 0.0, "telegraph": {}, "death_t": 0.0, "hit_done": false, "root_t": 0.0, "charge_hit": [], "marks": {},
	}
	next_enemy_id += 1
	enemies[e["id"]] = e
	stats["enemies_spawned"] += 1
	events.append({"k": "enemy_spawn", "eid": e["id"], "type": type_id, "x": pos.x, "y": pos.y})
	return e


func _enemy_move(e: Dictionary, dir: Vector2, dt: float, speed_mult: float = 1.0) -> void:
	var speed := float(e["speed"]) * speed_mult
	if int(water_zone.get("state", 0)) == 2 and _in_water(e["pos"]):
		speed *= 1.0 - float(rules.get("sluice_enemy_slow", 0.5))
	var before: Vector2 = e["pos"]
	e["pos"] = SimRules.move(e["pos"], dir, speed, dt, bounds, float(e["radius"]), all_obstacles())
	# 구조물에 막히면 구조물을 공격한다
	if (e["pos"] as Vector2).distance_to(before) < speed * dt * 0.3:
		for o: Dictionary in objects.values():
			if o["kind"] == Protocol.ObKind.STRUCTURE and (o["pos"] as Vector2).distance_to(e["pos"]) <= float(o["r"]) + float(e["radius"]) + 8.0:
				o["hp"] = float(o["hp"]) - float(rules.get("structure_enemy_dps", 6.0)) * dt
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
	match String(atk.get("shape", "circle")):
		"line":
			e["telegraph"] = {"type": 1, "x": e["pos"].x, "y": e["pos"].y, "len": float(atk.get("length", 380)), "w": float(atk.get("width", 64)), "dx": e["facing"].x, "dy": e["facing"].y, "total": windup, "asset": atk.get("telegraph_asset", "vfx.telegraph_line")}
		"projectile":
			e["telegraph"] = {"type": 0, "x": e["pos"].x, "y": e["pos"].y, "r": 30.0, "total": windup, "asset": atk.get("telegraph_asset", "vfx.telegraph_circle")}
		_:
			var center: Vector2 = e["pos"] + e["facing"] * float(atk.get("forward_offset", 28))
			e["telegraph"] = {"type": 0, "x": center.x, "y": center.y, "r": float(atk.get("radius", 40)), "total": windup, "asset": atk.get("telegraph_asset", "vfx.telegraph_circle")}


func _enemy_attack_begin(e: Dictionary, atk: Dictionary) -> void:
	match String(atk.get("shape", "circle")):
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
			_spawn_projectile(e["pos"] + dir * 18.0, dir * float(pr.get("speed", 340)), float(pr.get("radius", 10)), float(pr.get("damage", 9)), 0, "e%d" % int(e["id"]), float(pr.get("ttl_sec", 1.7)), 0, 0.0, 0.0)
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
					_damage_player(p, float(atk.get("damage", 10)), e["pos"], "e%d" % int(e["id"]), e)
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
			_damage_player(p, float(atk.get("damage", 14)), e["pos"], "e%d" % int(e["id"]), e)
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
	var spawns: Array = room_def.get("enemy_spawns", [[900, 400]])
	var cap := int(ContentDB.party_scaling.get("screen_caps", {}).get("max_enemies_on_screen", 12))
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
	if _all_spawned or objective_done or objective == "boss":
		return
	_wave_gap_t -= dt
	var threshold := int(room_def.get("waves", {}).get("next_wave_when_alive_at_most", 1))
	if _wave_gap_t <= 0.0 and _alive_enemy_count() <= threshold:
		_spawn_wave()


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
		"boss":
			if boss != null and boss.is_defeated():
				objective_progress = 1.0
				_objective_complete()
			elif boss != null:
				objective_progress = boss.hp_fraction()
		_:
			objective_progress = float(stats["enemies_killed"]) / maxf(float(stats["enemies_spawned"]), 1.0)


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
		if _alive_enemy_count() == 0:
			outcome = Protocol.Outcome.VICTORY
			events.append({"k": "room_clear", "elapsed": elapsed})
		return
	if objective == "annihilate" and _all_spawned and _alive_enemy_count() == 0:
		outcome = Protocol.Outcome.VICTORY
		events.append({"k": "room_clear", "elapsed": elapsed})


# ------------------------------------------------------------------ snapshot

func snapshot() -> Dictionary:
	var ps: Array = []
	for p: Dictionary in players.values():
		var v := PackedFloat32Array([
			p["pos"].x, p["pos"].y, p["facing"].x, p["facing"].y, p["hp"], p["state"], p["action"], p["dodge_charges"], p["shield"], p["down_t"],
			p["cd"]["q"], p["cd"]["e"], p["cd"]["r"], 1.0 if (float(p["invuln_t"]) > 0.0 or float(p["protect_t"]) > 0.0) else 0.0, p["rescue_t"], p["heal_uses"],
			1.0 if p["connected"] else 0.0, 1.0 if float(p["front_guard_t"]) > 0.0 else 0.0])
		ps.append([p["id"], v])
	var es: Array = []
	var tgs: Array = []
	for e: Dictionary in enemies.values():
		es.append([e["id"], e["type"], PackedFloat32Array([e["pos"].x, e["pos"].y, e["facing"].x, e["facing"].y, e["hp"], e["max_hp"], e["ai"]])])
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
	return {"outcome": outcome, "elapsed": elapsed, "ticks": tick, "seed": seed_value, "n": n_players, "objective": objective, "stats": stats.duplicate(true), "players": per, "team_wood": team_wood}

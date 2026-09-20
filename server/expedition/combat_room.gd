class_name CombatRoom
extends RefCounted
## 서버 권위 전투방 시뮬레이션. 노드·렌더링에 의존하지 않는 순수 상태 기계.
## 이동·공격·피격·회피·다운·구조·전멸·웨이브를 서버 시간(tick)으로 판정한다.
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
var next_enemy_id: int = 1
var bounds: Rect2
var obstacles: Array = []
var outcome: int = Protocol.Outcome.NONE
var wave_index: int = 0
var wave_count: int = 1
var wave_budget_total: float = 0.0
var _wave_gap_t: float = 0.0
var _all_spawned: bool = false
var events: Array = []
var stats := {"enemies_spawned": 0, "enemies_killed": 0, "downs": 0, "rescues": 0, "deaths": 0}
var hit_damage_mult: float = 1.0


func _init(def: Dictionary, party_profile: Dictionary, game_rules: Dictionary, seed_: int, members: Array) -> void:
	room_def = def
	profile = party_profile
	rules = game_rules
	seed_value = seed_
	rng.seed = seed_
	n_players = clampi(int(party_profile.get("n", members.size())), 1, Protocol.MAX_PARTY_SIZE)
	var b: Dictionary = def.get("bounds", {"x": 0, "y": 0, "w": 1200, "h": 800})
	bounds = Rect2(b["x"], b["y"], b["w"], b["h"])
	obstacles = def.get("obstacles", [])
	hit_damage_mult = float(profile.get("hit_damage_mult", 1.0))
	var w: Dictionary = def.get("waves", {})
	wave_count = maxi(int(w.get("wave_count", 1)), 1)
	wave_budget_total = float(w.get("base_budget", 4.0)) * float(profile.get("wave_budget_mult", 1.0))
	var spawns: Array = def.get("player_spawns", [[100, 100]])
	var i := 0
	for m: Dictionary in members:
		add_player(m, spawns[i % spawns.size()])
		i += 1
	_spawn_wave()


func add_player(m: Dictionary, spawn: Array) -> Dictionary:
	var cdef: Dictionary = ContentDB.get_class_def(String(m.get("class_id", "guardian")))
	var max_hp := float(cdef.get("base_hp", 100)) + float(m.get("bonus_hp", 0))
	var p := {
		"id": m["account_id"], "nick": m.get("nickname", ""), "class_id": cdef.get("id", "guardian"),
		"pos": Vector2(spawn[0], spawn[1]), "facing": Vector2(1, 0), "speed": float(cdef.get("move_speed", 180)),
		"radius": float(cdef.get("radius", 18)), "hp": max_hp, "max_hp": max_hp, "state": Protocol.EntState.ALIVE,
		"action": Protocol.Action.IDLE, "action_kind": "", "action_t": 0.0, "action_total": 0.0, "hit_applied": false,
		"cd": {"q": 0.0, "e": 0.0, "r": 0.0}, "dodge_charges": int(rules.get("dodge_charges", 2)), "dodge_recharge_t": 0.0,
		"invuln_t": 0.0, "protect_t": 0.0, "shield": 0.0, "shield_t": 0.0, "front_guard_t": 0.0, "stagger_t": 0.0,
		"down_t": 0.0, "rescue_target": "", "rescue_t": 0.0, "rescued_count": 0, "heal_uses": int(m.get("heal_uses", rules.get("heal_uses_per_expedition", 2))),
		"connected": bool(m.get("connected", true)), "disconnect_t": 0.0, "inputs": [], "last_seq": 0, "prev_buttons": 0, "move_dir": Vector2.ZERO,
		"stats": {"damage_dealt": 0.0, "damage_taken": 0.0, "kills": 0, "downs": 0, "rescues": 0, "deaths": 0},
	}
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
	_step_waves(dt)
	_check_outcome()
	return events


func _step_player(p: Dictionary, dt: float) -> void:
	# 타이머
	for k in ["q", "e", "r"]:
		p["cd"][k] = maxf(float(p["cd"][k]) - dt, 0.0)
	if int(p["dodge_charges"]) < int(rules.get("dodge_charges", 2)):
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
	# 입력 처리 (틱당 최대 N개)
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
	var action: int = p["action"]
	if action == Protocol.Action.IDLE or action == Protocol.Action.RECOVERY:
		p["facing"] = SimRules.facing_from(aim, p["facing"] if mv.length_squared() < 0.01 else mv.normalized())
	# 회피: 충전이 있으면 대부분의 상태에서 가능 (회복 구간 취소 허용)
	if pressed & Protocol.BTN_DODGE and int(p["dodge_charges"]) > 0 and action in [Protocol.Action.IDLE, Protocol.Action.RECOVERY] and float(p["stagger_t"]) <= 0.0:
		p["dodge_charges"] = int(p["dodge_charges"]) - 1
		p["action"] = Protocol.Action.DODGE
		p["action_kind"] = "dodge"
		p["action_total"] = float(rules.get("dodge_duration_sec", 0.22))
		p["action_t"] = p["action_total"]
		p["invuln_t"] = float(rules.get("dodge_invuln_sec", 0.2))
		p["dodge_dir"] = mv.normalized() if mv.length_squared() > 0.01 else p["facing"]
		p["rescue_t"] = 0.0
		events.append({"k": "dodge", "id": p["id"]})
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
		elif btn & Protocol.BTN_INTERACT:
			var target := _find_rescue_target(p)
			if target != "":
				p["action"] = Protocol.Action.RESCUING
				p["action_kind"] = "rescue"
				p["rescue_target"] = target
		action = p["action"]
	# 구조 유지 판정: 버튼을 놓거나 거리를 벗어나면 진행도 초기화
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
	# 이동
	var can_move := action in [Protocol.Action.IDLE, Protocol.Action.RECOVERY] and float(p["stagger_t"]) <= 0.0
	if action == Protocol.Action.DODGE:
		p["pos"] = SimRules.move(p["pos"], p["dodge_dir"], float(p["speed"]) * float(rules.get("dodge_speed_mult", 3.0)), dt, bounds, float(p["radius"]), obstacles)
	elif can_move and mv.length_squared() > 0.0001:
		var speed := float(p["speed"]) * (0.6 if action == Protocol.Action.RECOVERY else 1.0)
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
	if action in [Protocol.Action.IDLE, Protocol.Action.RESCUING]:
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


func _apply_basic_attack(p: Dictionary, atk: Dictionary) -> void:
	var hits := 0
	for e: Dictionary in enemies.values():
		if e["ai"] == Protocol.EnemyAI.DEAD:
			continue
		if SimRules.arc_hit(p["pos"], p["facing"], float(atk.get("range", 80)), float(atk.get("angle_deg", 120)), e["pos"], float(e["radius"])):
			var dmg := SimRules.damage(float(atk.get("damage", 10)), 1.0, 0.0, 1.0, 0.0, 0.0, rules.get("caps", {}))
			_damage_enemy(e, dmg, p, float(atk.get("knockback", 0)), float(atk.get("stagger_sec", 0)))
			hits += 1
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
	p["cd"][kind] = float(skill.get("cooldown_sec", 10))
	var eff: Dictionary = skill.get("effect", {})
	match String(eff.get("type", "")):
		"front_damage_reduction":
			p["front_guard_t"] = float(skill.get("duration_sec", 3.0))
			p["front_guard_value"] = float(eff.get("value", 0.5))
			p["front_guard_arc"] = float(eff.get("arc_deg", 150))
		"circle_hit":
			var hits := 0
			for e: Dictionary in enemies.values():
				if e["ai"] == Protocol.EnemyAI.DEAD:
					continue
				if SimRules.circle_hit(p["pos"], float(eff.get("radius", 100)), e["pos"], float(e["radius"])):
					_damage_enemy(e, SimRules.damage(float(eff.get("damage", 8)), 1.0, 0.0, 1.0, 0.0, 0.0, rules.get("caps", {})), p, float(eff.get("knockback", 100)), float(eff.get("stagger_sec", 0.5)))
					hits += 1
			events.append({"k": "circle_hit", "id": p["id"], "hits": hits, "radius": eff.get("radius", 100)})
		"party_shield":
			var cap := float(eff.get("max_shield_per_target", 45))
			for o: Dictionary in players.values():
				if o["state"] == Protocol.EntState.ALIVE and (o["pos"] as Vector2).distance_to(p["pos"]) <= float(eff.get("radius", 200)):
					# 같은 이름의 강화는 강한 값 하나만 적용, 지속시간 갱신 상한 (6절)
					o["shield"] = minf(maxf(float(o["shield"]), float(eff.get("shield", 30))), cap)
					o["shield_t"] = maxf(float(o["shield_t"]), float(eff.get("duration_sec", 6)))
	events.append({"k": "skill", "id": p["id"], "skill": skill.get("id", kind), "slot": kind, "x": p["pos"].x, "y": p["pos"].y})


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


func _damage_player(p: Dictionary, amount: float, source_pos: Vector2, source_id: String) -> void:
	if p["state"] != Protocol.EntState.ALIVE:
		return
	if float(p["invuln_t"]) > 0.0 or float(p["protect_t"]) > 0.0:
		events.append({"k": "evaded", "id": p["id"]})
		return
	var reduction := 0.0
	if float(p["front_guard_t"]) > 0.0 and SimRules.in_front_arc(p["pos"], p["facing"], source_pos, float(p.get("front_guard_arc", 150))):
		reduction = float(p.get("front_guard_value", 0.5))
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
		p["stats"]["downs"] = int(p["stats"]["downs"]) + 1
		stats["downs"] += 1
		events.append({"k": "player_downed", "id": p["id"]})


func _damage_enemy(e: Dictionary, dmg: float, attacker: Dictionary, knockback: float, stagger: float) -> void:
	e["hp"] = maxf(float(e["hp"]) - dmg, 0.0)
	attacker["stats"]["damage_dealt"] = float(attacker["stats"]["damage_dealt"]) + dmg
	if knockback > 0.0:
		var dir: Vector2 = (e["pos"] - attacker["pos"]).normalized() if (e["pos"] as Vector2).distance_to(attacker["pos"]) > 0.01 else attacker["facing"]
		e["pos"] = SimRules.move(e["pos"], dir, knockback, 1.0, bounds, float(e["radius"]), obstacles)
	if stagger > 0.0 and float(e["stagger_resist_t"]) <= 0.0:
		e["stagger_t"] = maxf(float(e["stagger_t"]), stagger)
		e["stagger_resist_t"] = float(e["def"].get("stagger_resist_after_sec", 1.0))
		if e["ai"] in [Protocol.EnemyAI.WINDUP]:
			e["ai"] = Protocol.EnemyAI.STAGGER
	events.append({"k": "enemy_hit", "eid": e["id"], "by": attacker["id"], "dmg": dmg, "x": e["pos"].x, "y": e["pos"].y})
	if float(e["hp"]) <= 0.0 and e["ai"] != Protocol.EnemyAI.DEAD:
		e["ai"] = Protocol.EnemyAI.DEAD
		e["death_t"] = 1.0
		attacker["stats"]["kills"] = int(attacker["stats"]["kills"]) + 1
		stats["enemies_killed"] += 1
		events.append({"k": "enemy_died", "eid": e["id"], "by": attacker["id"], "type": e["type"]})


# ------------------------------------------------------------------ enemies

func _spawn_enemy(type_id: String, pos: Vector2) -> Dictionary:
	var def: Dictionary = ContentDB.get_enemy_def(type_id)
	var max_hp := float(def.get("hp", 30)) * float(profile.get("enemy_hp_mult", 1.0))
	var e := {
		"id": next_enemy_id, "type": type_id, "def": def, "pos": pos, "facing": Vector2(-1, 0), "hp": max_hp, "max_hp": max_hp,
		"radius": float(def.get("radius", 20)), "speed": float(def.get("move_speed", 60)), "ai": Protocol.EnemyAI.SEEK,
		"t": 0.0, "cooldown_t": 0.0, "target": "", "stagger_t": 0.0, "stagger_resist_t": 0.0, "telegraph": {}, "death_t": 0.0, "hit_done": false,
	}
	next_enemy_id += 1
	enemies[e["id"]] = e
	stats["enemies_spawned"] += 1
	events.append({"k": "enemy_spawn", "eid": e["id"], "type": type_id, "x": pos.x, "y": pos.y})
	return e


func _step_enemy(e: Dictionary, dt: float) -> void:
	if e["ai"] == Protocol.EnemyAI.DEAD:
		e["death_t"] = float(e["death_t"]) - dt
		return
	e["cooldown_t"] = maxf(float(e["cooldown_t"]) - dt, 0.0)
	e["stagger_resist_t"] = maxf(float(e["stagger_resist_t"]) - dt, 0.0)
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
			var reach := float(atk.get("forward_offset", 28)) + float(atk.get("radius", 40)) * 0.6
			if to.length() > 0.01:
				e["facing"] = to.normalized()
			if to.length() > reach:
				e["pos"] = SimRules.move(e["pos"], to.normalized(), float(e["speed"]), dt, bounds, float(e["radius"]), obstacles)
			elif float(e["cooldown_t"]) <= 0.0:
				e["ai"] = Protocol.EnemyAI.WINDUP
				e["t"] = maxf(float(atk.get("windup_sec", 0.7)), float(rules.get("telegraph_min_sec", 0.7)) if atk.get("heavy", false) else float(atk.get("windup_sec", 0.7)))
				var center: Vector2 = e["pos"] + e["facing"] * float(atk.get("forward_offset", 28))
				e["telegraph"] = {"x": center.x, "y": center.y, "r": float(atk.get("radius", 40)), "total": e["t"], "asset": atk.get("telegraph_asset", "vfx.telegraph_circle")}
				e["hit_done"] = false
		Protocol.EnemyAI.WINDUP:
			e["t"] = float(e["t"]) - dt
			if float(e["t"]) <= 0.0:
				e["ai"] = Protocol.EnemyAI.ATTACK
				e["t"] = float(atk.get("active_sec", 0.15))
				_enemy_attack_hit(e, atk)
		Protocol.EnemyAI.ATTACK:
			e["t"] = float(e["t"]) - dt
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


func _enemy_attack_hit(e: Dictionary, atk: Dictionary) -> void:
	var tg: Dictionary = e["telegraph"]
	var center := Vector2(float(tg.get("x", e["pos"].x)), float(tg.get("y", e["pos"].y)))
	var r := float(tg.get("r", atk.get("radius", 40)))
	for p: Dictionary in players.values():
		if p["state"] != Protocol.EntState.ALIVE:
			continue
		if not p["connected"] and float(p["disconnect_t"]) < float(rules.get("disconnect_combat_vulnerable_after_sec", 5.0)):
			continue
		if SimRules.circle_hit(center, r, p["pos"], float(p["radius"])):
			_damage_player(p, float(atk.get("damage", 10)), e["pos"], "e%d" % int(e["id"]))
	events.append({"k": "enemy_attack", "eid": e["id"], "x": center.x, "y": center.y, "r": r})


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
		if a["ai"] == Protocol.EnemyAI.DEAD:
			continue
		for j in range(i + 1, list.size()):
			var b: Dictionary = list[j]
			if b["ai"] == Protocol.EnemyAI.DEAD:
				continue
			var d: Vector2 = b["pos"] - a["pos"]
			var min_d := float(a["radius"]) + float(b["radius"])
			var len := d.length()
			if len < min_d and len > 0.001:
				var push := d.normalized() * (min_d - len) * 0.5
				a["pos"] = SimRules.move(a["pos"], -push, 1.0, 1.0, bounds, float(a["radius"]), obstacles)
				b["pos"] = SimRules.move(b["pos"], push, 1.0, 1.0, bounds, float(b["radius"]), obstacles)


# ------------------------------------------------------------------ waves

func _spawn_wave() -> void:
	if wave_index >= wave_count:
		_all_spawned = true
		return
	var budget := wave_budget_total / float(wave_count)
	var pool: Array = room_def.get("enemy_pool", [{"id": "sap_snail", "weight": 1.0}])
	var spawns: Array = room_def.get("enemy_spawns", [[900, 400]])
	var cap := int(ContentDB.party_scaling.get("screen_caps", {}).get("max_enemies_on_screen", 12))
	var spawned := 0
	var guard := 0
	var alive := _alive_enemy_count()
	while budget > 0.0 and guard < 64 and alive + spawned < cap:
		guard += 1
		var pick: Dictionary = _weighted_pick(pool)
		var def := ContentDB.get_enemy_def(String(pick.get("id", "")))
		if def.is_empty():
			break
		var cost := float(def.get("threat_cost", 1.0))
		if cost > budget + 0.001:
			break
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
		if e["ai"] != Protocol.EnemyAI.DEAD:
			c += 1
	return c


func _step_waves(dt: float) -> void:
	# 죽은 적 정리
	for k in enemies.keys():
		if enemies[k]["ai"] == Protocol.EnemyAI.DEAD and float(enemies[k]["death_t"]) <= 0.0:
			enemies.erase(k)
	if _all_spawned:
		return
	_wave_gap_t -= dt
	var threshold := int(room_def.get("waves", {}).get("next_wave_when_alive_at_most", 1))
	if _wave_gap_t <= 0.0 and _alive_enemy_count() <= threshold:
		_spawn_wave()


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
	if _all_spawned and _alive_enemy_count() == 0:
		outcome = Protocol.Outcome.VICTORY
		events.append({"k": "room_clear", "elapsed": elapsed})


# ------------------------------------------------------------------ snapshot

func snapshot() -> Dictionary:
	# 크기를 줄이기 위해 수치는 PackedFloat32Array 로 보낸다. 인덱스 의미는 Protocol.SNAP_P / SNAP_E 참고.
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
			tgs.append(PackedFloat32Array([tg["x"], tg["y"], tg["r"], e["t"], tg["total"]]))
	return {"t": tick, "wave": [wave_index, wave_count], "p": ps, "e": es, "tg": tgs}


func result_summary() -> Dictionary:
	var per: Dictionary = {}
	for p: Dictionary in players.values():
		per[p["id"]] = p["stats"].duplicate()
	return {"outcome": outcome, "elapsed": elapsed, "ticks": tick, "seed": seed_value, "n": n_players, "stats": stats.duplicate(), "players": per}

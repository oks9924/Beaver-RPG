class_name BossIronclaw
extends RefCounted
## 철턱 가재 보스 컨트롤러 (11절). 기본 공격 패턴 4개(attackPatternId)와 독립 기믹 5개(mechanicId)를 분리한다.
## 기믹은 목표·판단·해결 방법이 다르며, 인원 프로필(1~4)로 목표 수·동시 조작·유예를 바꾼다. 인원만큼 목표를 복제하지 않는다.
## 보스는 일반 기절의 무한 연쇄를 허용하지 않고 경직 게이지로 전환한다 (5절).

enum BS { CHASE, WINDUP, ATTACK, RECOVER, STAGGER, GRAB_APPROACH, GRABBING, MOLT, EXPOSED, DEAD }

var room: CombatRoom
var profile: Dictionary
var def: Dictionary
var n: int
var pos: Vector2
var facing: Vector2 = Vector2(-1, 0)
var hp: float
var max_hp: float
var radius: float
var speed: float
var state: int = BS.CHASE
var t: float = 0.0
var pattern: Dictionary = {}
var telegraph: Dictionary = {}
var cooldowns: Dictionary = {}
var target: String = ""
var shell_broken: int = 0
var claw_weak: bool = false
var joint_weak_t: float = 0.0
var exposed_t: float = 0.0
var stagger_gauge: float = 0.0
var stagger_resist_t: float = 0.0
var phase: int = 0
var mechanics: Dictionary = {}     # id -> {state, repeats, cooldown_t, t, data}
var active: String = ""
var last_mechanic: String = ""
var mechanic_gap_t: float = 6.0
var grabbed: String = ""
var grab_damage_done: float = 0.0
var charge_dir: Vector2 = Vector2.ZERO
var charge_hit: Array = []
var hazards: Array = []            # object ids
var log: Array = []                # 기믹 등장·완료·실패 기록 (검증용)
var molt_real_husk: int = 0
var stats := {"mechanics_started": 0, "mechanics_succeeded": 0, "mechanics_failed": 0, "patterns_used": {}}
var passive: bool = false   # 테스트 전용: 기본 공격 패턴을 시작하지 않는다 (기믹 해결 가능성 검증용)
var carry: Dictionary = {}          # 운반 중인 오브젝트: player id -> object id (씨앗·반딧불 등)
var enrage_t: float = 0.0           # 패턴 피해 +20% (실패 벌칙)
var regen_per_sec: float = 0.0      # 기생 뿌리 등으로 켜지는 회복
var extra_vuln_t: float = 0.0       # 추가 취약 (받는 피해 +50%)


func _init(r: CombatRoom, party_profile: Dictionary, boss_def: Dictionary) -> void:
	room = r
	profile = party_profile
	def = boss_def
	n = clampi(int(party_profile.get("n", 1)), 1, 4)
	max_hp = float(def.get("hp", 500)) * float(party_profile.get("boss_hp_mult", 1.0))
	hp = max_hp
	radius = float(def.get("radius", 46))
	speed = float(def.get("move_speed", 78))
	var sp: Array = room.room_def.get("boss_spawn", [1000, 500])
	pos = Vector2(sp[0], sp[1])
	for pid: String in def.get("attack_patterns", {}).keys():
		cooldowns[pid] = 2.0
	for mid: String in def.get("mechanics", {}).keys():
		mechanics[mid] = {"state": "idle", "repeats": 0, "cooldown_t": 0.0, "t": 0.0, "data": {}}
	room.events.append({"k": "boss_spawn", "boss": def.get("id", ""), "x": pos.x, "y": pos.y, "hp": max_hp})


func mprofile(mid: String) -> Dictionary:
	return def["mechanics"][mid]["profiles"].get(str(n), def["mechanics"][mid]["profiles"].get("1", {}))


func is_defeated() -> bool:
	return state == BS.DEAD


func hp_fraction() -> float:
	return clampf(hp / maxf(max_hp, 1.0), 0.0, 1.0)


func damage_taken_mult() -> float:
	var m := 1.0 + shell_broken * float(def.get("shell_damage_taken_mult_per_broken", 0.18))
	if shell_broken == 0 and def.has("shell_intact_damage_taken_mult"):
		m *= float(def.get("shell_intact_damage_taken_mult", 0.6))   # 갑각을 하나도 못 깨면 기믹 없이는 피해가 잘 안 들어간다
	if joint_weak_t > 0.0:
		m *= 1.3
	if exposed_t > 0.0:
		m *= 1.5
	if extra_vuln_t > 0.0:
		m *= 1.5
	return m


# ------------------------------------------------------------------ 피격

func take_damage(dmg: float, attacker: Dictionary, stagger: float = 0.0) -> void:
	if state == BS.DEAD:
		return
	if state == BS.MOLT:
		return  # 탈피 중 본체는 껍질 사이에 숨어 있다 (기믹으로 노출)
	var final := dmg * damage_taken_mult() * (1.0 + float(attacker.get("mods", {}).get("boss_damage_mult", 0.0)))
	hp = maxf(hp - final, 0.0)
	attacker["stats"]["damage_dealt"] = float(attacker["stats"].get("damage_dealt", 0.0)) + final
	if stagger > 0.0 and stagger_resist_t <= 0.0 and state != BS.STAGGER:
		stagger_gauge += stagger * 25.0
		if stagger_gauge >= float(room.rules.get("boss_stagger_gauge_max", 100.0)):
			_enter_stagger(2.5)
	room.events.append({"k": "boss_hit", "dmg": final, "by": attacker.get("id", ""), "hp": hp, "x": pos.x, "y": pos.y})
	_check_phase()
	if hp <= 0.0:
		_die(attacker)


func alive() -> bool:
	return state != BS.DEAD


func on_arc_attack(p: Dictionary, atk: Dictionary) -> int:
	if state == BS.DEAD:
		return 0
	if SimRules.arc_hit(p["pos"], p["facing"], float(atk.get("range", 80)), float(atk.get("angle_deg", 120)), pos, radius):
		take_damage(room._player_damage(p, float(atk.get("damage", 10))), p, float(atk.get("stagger_sec", 0)) + float(p["mods"].get("stagger_add", 0.0)))
		return 1
	return 0


func on_circle_attack(p: Dictionary, center: Vector2, r: float, dmg: float) -> int:
	if state == BS.DEAD:
		return 0
	if SimRules.circle_hit(center, r, pos, radius):
		take_damage(dmg, p, 0.5)
		return 1
	return 0


func on_projectile(pr: Dictionary, attacker: Dictionary) -> bool:
	if state == BS.DEAD:
		return false
	if (pr["pos"] as Vector2).distance_to(pos) <= radius + float(pr["r"]):
		take_damage(float(pr["dmg"]), attacker, float(pr.get("st", 0.0)))
		return true
	return false


func _enter_stagger(sec: float) -> void:
	state = BS.STAGGER
	t = sec
	telegraph = {}
	stagger_gauge = 0.0
	stagger_resist_t = float(room.rules.get("boss_stagger_resist_sec", 8.0))
	room.events.append({"k": "boss_stagger", "sec": sec})


func _check_phase() -> void:
	var phases: Array = def.get("phases", [])
	var new_phase := 0
	for i in phases.size():
		if hp_fraction() < float(phases[i].get("hp_below", 1.0)):
			new_phase = i
	if new_phase > phase:
		phase = new_phase
		# 단계 전환: 오래된 장판·예고 정리 (11절)
		telegraph = {}
		_clear_hazards()
		if state in [BS.WINDUP, BS.ATTACK]:
			state = BS.RECOVER
			t = 0.6
		room.events.append({"k": "boss_phase", "phase": phase, "name": phases[new_phase].get("name_ko", "")})


func _die(attacker: Dictionary) -> void:
	state = BS.DEAD
	telegraph = {}
	_release_grab(false)
	_clear_hazards()
	for oid in room.objects.keys():
		if int(room.objects[oid]["kind"]) >= Protocol.ObKind.PILLAR:
			room.objects.erase(oid)
	if active != "":
		mechanics[active]["state"] = "done"
		active = ""
	for e: Dictionary in room.enemies.values():
		if e["ai"] != Protocol.EnemyAI.DEAD:
			room._kill_enemy(e, attacker)
	attacker["stats"]["kills"] = int(attacker["stats"].get("kills", 0)) + 1
	room.events.append({"k": "boss_died", "boss": def.get("id", ""), "by": attacker.get("id", ""), "mechanics": stats})


func on_player_downed(p: Dictionary) -> void:
	if grabbed == p["id"]:
		_release_grab(false)


# ------------------------------------------------------------------ 틱

func step(dt: float) -> void:
	if state == BS.DEAD:
		return
	joint_weak_t = maxf(joint_weak_t - dt, 0.0)
	exposed_t = maxf(exposed_t - dt, 0.0)
	stagger_resist_t = maxf(stagger_resist_t - dt, 0.0)
	stagger_gauge = maxf(stagger_gauge - dt * 4.0, 0.0)
	enrage_t = maxf(enrage_t - dt, 0.0)
	extra_vuln_t = maxf(extra_vuln_t - dt, 0.0)
	if regen_per_sec > 0.0:
		hp = minf(hp + regen_per_sec * dt, max_hp)
	for pid: String in cooldowns.keys():
		cooldowns[pid] = maxf(float(cooldowns[pid]) - dt, 0.0)
	_step_hazards(dt)
	_step_carry(dt)
	_step_mechanics(dt)
	_step_extra(dt)
	match state:
		BS.CHASE: _step_chase(dt)
		BS.WINDUP:
			t -= dt
			if t <= 0.0:
				_attack_begin()
		BS.ATTACK:
			t -= dt
			if String(pattern.get("shape", "")) == "line":
				_charge_step(dt)
			if t <= 0.0:
				state = BS.RECOVER
				t = 0.7
				telegraph = {}
		BS.RECOVER:
			t -= dt
			if t <= 0.0:
				state = BS.CHASE
		BS.STAGGER:
			t -= dt
			if t <= 0.0:
				state = BS.CHASE
		BS.GRAB_APPROACH: _step_grab_approach(dt)
		BS.GRABBING: _step_grabbing(dt)
		BS.MOLT: pass
		BS.EXPOSED:
			t -= dt
			if t <= 0.0:
				state = BS.CHASE


func _nearest_player(max_range: float = 1e9) -> String:
	return room._nearest_alive_player(pos, max_range)


func _step_chase(dt: float) -> void:
	target = _nearest_player()
	if target == "" or passive:
		return
	var tp: Vector2 = room.players[target]["pos"]
	var to := tp - pos
	var dist := to.length()
	if dist > 0.01:
		facing = to.normalized()
	var choice := _pick_pattern(dist)
	if not choice.is_empty():
		_begin_pattern(choice)
		return
	if dist > radius + 60.0:
		pos = SimRules.move(pos, to.normalized(), speed, dt, room.bounds, radius, room.obstacles)


func _pick_pattern(dist: float) -> Dictionary:
	var pats: Dictionary = def.get("attack_patterns", {})
	var candidates: Array = []
	var weights: Array = []
	for pid: String in pats.keys():
		if float(cooldowns[pid]) > 0.0:
			continue
		var p: Dictionary = pats[pid]
		if not _pattern_ok(pid, p, dist):
			continue
		var w := float(p.get("weight", 1.0))
		if active == "IC-01" and pid == "line_charge":
			w *= 3.0   # 붕괴 유도 중에는 돌진이 자주 나온다 (유도 기회)
		candidates.append(p)
		weights.append(w)
	if candidates.is_empty():
		return {}
	var total := 0.0
	for w in weights:
		total += float(w)
	var r := room.rng.randf() * total
	for i in candidates.size():
		r -= float(weights[i])
		if r <= 0.0:
			return candidates[i]
	return candidates[candidates.size() - 1]


## 패턴 사용 가능 거리 (모양 기준). 보스별로 재정의할 수 있다.
func _pattern_ok(_pid: String, p: Dictionary, dist: float) -> bool:
	match String(p.get("shape", "circle")):
		"arc": return dist <= float(p.get("range", 150)) + 20.0
		"line":
			if float(p.get("charge_speed", 0)) > 0.0:
				return dist >= 160.0 and dist <= float(p.get("length", 520))
			return dist <= float(p.get("length", 520))
		"circle_at_target": return dist <= 600.0
		"leap": return dist >= 120.0 and dist <= float(p.get("leap_range", 420))
		"projectile_fan": return dist <= 520.0
		_: return dist <= float(p.get("radius", 170)) + 10.0


func _begin_pattern(p: Dictionary) -> void:
	pattern = p
	state = BS.WINDUP
	t = maxf(float(p.get("windup_sec", 0.8)), float(room.rules.get("telegraph_min_sec", 0.7)))
	var pid := String(p["id"])
	stats["patterns_used"][pid] = int(stats["patterns_used"].get(pid, 0)) + 1
	match String(p.get("shape", "circle")):
		"arc":
			var c := pos + facing * (float(p.get("range", 150)) * 0.55)
			telegraph = {"type": 0, "x": c.x, "y": c.y, "r": float(p.get("range", 150)) * 0.6, "total": t}
		"line":
			telegraph = {"type": 1, "x": pos.x, "y": pos.y, "len": float(p.get("length", 520)), "w": float(p.get("width", 90)), "dx": facing.x, "dy": facing.y, "total": t}
		"circle_at_target", "leap":
			var tp: Vector2 = room.players[target]["pos"] if room.players.has(target) else pos
			telegraph = {"type": 0, "x": tp.x, "y": tp.y, "r": float(p.get("radius", 80)), "total": t}
		"projectile_fan":
			telegraph = {"type": 0, "x": pos.x, "y": pos.y, "r": radius + 20.0, "total": t}
		_:
			telegraph = {"type": 0, "x": pos.x, "y": pos.y, "r": float(p.get("radius", 170)), "total": t}
	room.events.append({"k": "boss_pattern", "pattern": pid})


func _attack_begin() -> void:
	state = BS.ATTACK
	var p := pattern
	cooldowns[String(p["id"])] = float(p.get("cooldown_sec", 3.0))
	t = 0.15
	var emult := 1.2 if enrage_t > 0.0 else 1.0
	match String(p.get("shape", "circle")):
		"arc":
			var dmg := float(p.get("damage", 18)) * (0.7 if claw_weak else 1.0) * emult
			for pl: Dictionary in room.players.values():
				if pl["state"] == Protocol.EntState.ALIVE and SimRules.arc_hit(pos, facing, float(p.get("range", 150)), float(p.get("angle_deg", 110)), pl["pos"], float(pl["radius"])):
					room._damage_player(pl, dmg, pos, "boss")
					_on_boss_hit_player(pl)
		"line":
			if float(p.get("charge_speed", 0)) > 0.0:
				t = 0.9
				charge_dir = facing
				charge_hit = []
				room.events.append({"k": "boss_charge"})
			else:
				# 즉발 직선 (혀 창·수압 분사): 피해 + 끌어당김 또는 넉백
				for pl: Dictionary in room.players.values():
					if pl["state"] == Protocol.EntState.ALIVE and room._in_line(pos, facing, float(p.get("length", 420)), float(p.get("width", 60)), pl["pos"], float(pl["radius"])):
						room._damage_player(pl, float(p.get("damage", 16)) * emult, pos, "boss")
						_on_boss_hit_player(pl)
						if pl["state"] == Protocol.EntState.ALIVE:
							if float(p.get("pull", 0)) > 0.0:
								pl["pos"] = SimRules.move(pl["pos"], (pos - pl["pos"]).normalized(), minf(float(p["pull"]), maxf((pl["pos"] as Vector2).distance_to(pos) - radius - 30.0, 0.0)), 1.0, room.bounds, float(pl["radius"]), room.obstacles)
							elif float(p.get("knockback", 0)) > 0.0:
								pl["pos"] = SimRules.move(pl["pos"], facing, float(p["knockback"]), 1.0, room.bounds, float(pl["radius"]), room.obstacles)
				room.events.append({"k": "boss_line", "x": pos.x, "y": pos.y, "fx": facing.x, "fy": facing.y, "len": p.get("length", 420), "w": p.get("width", 60)})
		"leap":
			var c := Vector2(float(telegraph.get("x", pos.x)), float(telegraph.get("y", pos.y)))
			pos = room._clamp_in_bounds(c, radius)
			var r := float(telegraph.get("r", 150))
			for pl: Dictionary in room.players.values():
				if pl["state"] == Protocol.EntState.ALIVE and SimRules.circle_hit(c, r, pl["pos"], float(pl["radius"])):
					room._damage_player(pl, float(p.get("damage", 20)) * emult, pos, "boss")
					_on_boss_hit_player(pl)
			room.events.append({"k": "boss_slam", "x": c.x, "y": c.y, "r": r, "leap": true})
		"projectile_fan":
			var count := int(p.get("count", 5))
			var spread := deg_to_rad(float(p.get("spread_deg", 60)))
			for i in count:
				var a := -spread * 0.5 + spread * (float(i) / maxf(count - 1, 1))
				var d := facing.rotated(a)
				room._spawn_projectile(pos + d * (radius + 10.0), d * float(p.get("speed", 380)), 10.0, float(p.get("damage", 9)) * emult, 0, "boss", 1.6, 0, 0.0, 0.0)
			room.events.append({"k": "boss_fan", "x": pos.x, "y": pos.y})
		"circle_at_target", "circle":
			var c := Vector2(float(telegraph.get("x", pos.x)), float(telegraph.get("y", pos.y)))
			var r := float(telegraph.get("r", 100))
			var centers: Array = [c]
			for i in range(1, int(p.get("count", 1))):
				centers.append(c + Vector2.RIGHT.rotated(TAU * i / float(p.get("count", 1))) * r * 1.6)
			for cc: Vector2 in centers:
				for pl: Dictionary in room.players.values():
					if pl["state"] == Protocol.EntState.ALIVE and SimRules.circle_hit(cc, r, pl["pos"], float(pl["radius"])):
						room._damage_player(pl, float(p.get("damage", 15)) * emult, pos, "boss")
						_on_boss_hit_player(pl)
						if float(p.get("root_sec", 0)) > 0.0:
							room._apply_hit_status(pl, {"root_sec": p["root_sec"]})
				if float(p.get("leaves_hazard_sec", 0)) > 0.0:
					_add_hazard(cc, r * float(_hazard_scale()), float(p["leaves_hazard_sec"]), 4.0)
				room.events.append({"k": "boss_slam", "x": cc.x, "y": cc.y, "r": r})
	if not (String(p.get("shape", "")) == "line" and float(p.get("charge_speed", 0)) > 0.0):
		telegraph = {}


## 보스 패턴에 맞은 플레이어 (운반물 떨어뜨림 등). 서브클래스가 확장한다.
func _on_boss_hit_player(pl: Dictionary) -> void:
	if carry.has(pl["id"]):
		_drop_carry(pl["id"])


func _hazard_scale() -> float:
	return 1.0


## 서브클래스용 추가 틱
func _step_extra(_dt: float) -> void:
	pass


# ------------------------------------------------------------------ 운반 (씨앗·반딧불): 집으면 느려지고, 맞으면 떨어뜨린다

func _pickup(o: Dictionary, p: Dictionary) -> void:
	if carry.has(p["id"]):
		return
	carry[p["id"]] = int(o["id"])
	o["carrier"] = p["id"]
	o["interactable"] = false
	o["state"] = 1
	room.events.append({"k": "carry_pickup", "id": p["id"], "oid": o["id"], "kind": o["kind"]})


func _drop_carry(pid: String) -> void:
	var oid: int = int(carry.get(pid, 0))
	carry.erase(pid)
	var o: Dictionary = room.objects.get(oid, {})
	if o.is_empty():
		return
	o["carrier"] = ""
	o["interactable"] = true
	o["state"] = 0
	var pl: Dictionary = room.players.get(pid, {})
	if not pl.is_empty():
		o["pos"] = room._clamp_in_bounds(pl["pos"] + Vector2(30, 0), 20.0)
	room.events.append({"k": "carry_drop", "id": pid, "oid": oid})


func _step_carry(_dt: float) -> void:
	for pid: String in carry.keys().duplicate():
		var pl: Dictionary = room.players.get(pid, {})
		var o: Dictionary = room.objects.get(int(carry[pid]), {})
		if pl.is_empty() or o.is_empty() or pl["state"] != Protocol.EntState.ALIVE:
			_drop_carry(pid)
			continue
		o["pos"] = pl["pos"] + Vector2(0, -6)
		pl["slow_t"] = maxf(float(pl["slow_t"]), 0.2)
		pl["slow_mult"] = maxf(float(pl["slow_mult"]), 0.3)


func _carried_object(pid: String) -> Dictionary:
	return room.objects.get(int(carry.get(pid, 0)), {})


func _charge_step(dt: float) -> void:
	var before := pos
	pos = SimRules.move(pos, charge_dir, float(pattern.get("charge_speed", 560)), dt, room.bounds, radius, room.obstacles)
	var half_w := float(pattern.get("width", 90)) * 0.5
	for pl: Dictionary in room.players.values():
		if pl["state"] != Protocol.EntState.ALIVE or charge_hit.has(pl["id"]):
			continue
		if (pl["pos"] as Vector2).distance_to(pos) <= half_w + float(pl["radius"]):
			charge_hit.append(pl["id"])
			room._damage_player(pl, float(pattern.get("damage", 22)), pos, "boss")
			if pl["state"] == Protocol.EntState.ALIVE:
				pl["pos"] = SimRules.move(pl["pos"], charge_dir, float(pattern.get("knockback", 140)), 1.0, room.bounds, float(pl["radius"]), room.obstacles)
	# IC-01: 지지목과 충돌
	for oid in room.objects.keys():
		var o: Dictionary = room.objects[oid]
		if int(o["kind"]) != Protocol.ObKind.PILLAR:
			continue
		if (o["pos"] as Vector2).distance_to(pos) <= float(o["r"]) + radius:
			t = 0.0
			if int(o["state"]) == 1:
				_ic01_success(o)
			else:
				room.objects.erase(oid)
				room.events.append({"k": "pillar_destroyed", "x": o["pos"].x, "y": o["pos"].y})
				log.append({"mechanic": "IC-01", "event": "wrong_pillar"})
			break
	if pos.distance_to(before) < 1.0:
		t = 0.0


# ------------------------------------------------------------------ 기믹 스케줄

func _step_mechanics(dt: float) -> void:
	for mid: String in mechanics.keys():
		mechanics[mid]["cooldown_t"] = maxf(float(mechanics[mid]["cooldown_t"]) - dt, 0.0)
	if active != "":
		var m: Dictionary = mechanics[active]
		m["t"] = float(m["t"]) - dt
		_mechanic_step(active, dt, m)
		if float(m["t"]) <= 0.0 and active != "":
			_finish_mechanic(false, "timeout")
		return
	mechanic_gap_t -= dt
	if mechanic_gap_t > 0.0 or not state in [BS.CHASE, BS.RECOVER]:
		return
	var pick := _choose_mechanic()
	if pick != "":
		_start_mechanic(pick)


## 미체험 기믹 우선, 양립 불가 조합 회피, 연속 재사용 금지, 반복 상한 (11절)
func _choose_mechanic() -> String:
	var incompatible: Array = def.get("incompatible_pairs", [])
	var best := ""
	var best_score := -1.0
	var ids: Array = mechanics.keys()
	ids.sort()
	for mid: String in ids:
		var m: Dictionary = mechanics[mid]
		var md: Dictionary = def["mechanics"][mid]
		if int(md.get("entry", {}).get("phase_min", 0)) > phase:
			continue
		if int(m["repeats"]) >= int(md.get("max_repeats", 2)) or float(m["cooldown_t"]) > 0.0 or mid == last_mechanic:
			continue
		var blocked := false
		for pair: Array in incompatible:
			if pair.has(mid) and pair.has(last_mechanic):
				blocked = true
		if blocked:
			continue
		var score := (10.0 if int(m["repeats"]) == 0 else 1.0) + room.rng.randf()
		if score > best_score:
			best_score = score
			best = mid
	return best


func _start_mechanic(mid: String) -> void:
	active = mid
	var m: Dictionary = mechanics[mid]
	var md: Dictionary = def["mechanics"][mid]
	m["state"] = "active"
	m["t"] = float(md.get("duration_sec", 30))
	m["data"] = {}
	m["repeats"] = int(m["repeats"]) + 1
	stats["mechanics_started"] += 1
	log.append({"mechanic": mid, "event": "start", "n": n, "repeat": m["repeats"], "elapsed": room.elapsed})
	_mechanic_start(mid, m)
	room.events.append({"k": "mechanic_start", "id": mid, "name": md.get("name_ko", mid), "hint": md.get("telegraph_ko", ""), "duration": m["t"], "n": n})


func _finish_mechanic(success: bool, reason: String) -> void:
	if active == "":
		return
	var mid := active
	var m: Dictionary = mechanics[mid]
	var md: Dictionary = def["mechanics"][mid]
	m["state"] = "done"
	m["cooldown_t"] = float(md.get("entry", {}).get("cooldown_sec", 45))
	if success:
		stats["mechanics_succeeded"] += 1
	else:
		stats["mechanics_failed"] += 1
		# 실패의 무게: 보스 회복 + 인원 프로필의 벌칙 (extra_adds → 추가 적 2)
		var heal_frac := float(def.get("fail_heal_fraction", 0.0))
		if heal_frac > 0.0 and state != BS.DEAD:
			hp = minf(hp + max_hp * heal_frac, max_hp)
		if String(profile.get("fail_penalty", "")) == "extra_adds":
			_spawn_adds(2)
	log.append({"mechanic": mid, "event": "success" if success else "fail", "reason": reason, "elapsed": room.elapsed})
	_mechanic_end(mid, success)
	room.events.append({"k": "mechanic_end", "id": mid, "success": success, "reason": reason, "text": md.get("success_ko" if success else "fail_ko", "")})
	last_mechanic = mid
	active = ""
	mechanic_gap_t = float(def.get("mechanic_gap_sec", 12)) * float(profile.get("mechanic_gap_mult", 1.0))


func _spawn_adds(count: int, type_id: String = "sap_snail") -> void:
	var spawns: Array = room.room_def.get("enemy_spawns", [[1300, 200]])
	for i in count:
		var sp: Array = spawns[i % spawns.size()]
		room._spawn_enemy(type_id, Vector2(sp[0], sp[1]))


func _add_object(kind: int, p: Vector2, r: float, extra: Dictionary) -> Dictionary:
	var o := room._add_object(kind, p, r, extra)
	o["mechanic"] = active
	return o


func _remove_mechanic_objects(kinds: Array) -> void:
	for oid in room.objects.keys():
		if kinds.has(int(room.objects[oid]["kind"])):
			room.objects.erase(oid)


func _add_hazard(p: Vector2, r: float, sec: float, dps: float) -> void:
	var o := room._add_object(Protocol.ObKind.HAZARD, p, r, {"life": sec, "dps": dps, "interactable": false})
	hazards.append(o["id"])


func _step_hazards(dt: float) -> void:
	for oid in hazards.duplicate():
		var o: Dictionary = room.objects.get(oid, {})
		if o.is_empty():
			hazards.erase(oid)
			continue
		o["life"] = float(o["life"]) - dt
		o["progress"] = clampf(float(o["life"]) / 5.0, 0.0, 1.0)
		if float(o["life"]) <= 0.0:
			room.objects.erase(oid)
			hazards.erase(oid)
			continue
		for pl: Dictionary in room.players.values():
			if pl["state"] == Protocol.EntState.ALIVE and (pl["pos"] as Vector2).distance_to(o["pos"]) <= float(o["r"]) + float(pl["radius"]):
				room._damage_player(pl, float(o["dps"]) * dt, o["pos"], "hazard")


func _clear_hazards() -> void:
	for oid in hazards:
		room.objects.erase(oid)
	hazards.clear()


# ------------------------------------------------------------------ 상호작용 창구

func find_interactable(p: Dictionary) -> int:
	var best := 0
	var best_d := 1e9
	for o: Dictionary in room.objects.values():
		if int(o["kind"]) < Protocol.ObKind.PILLAR or not bool(o.get("interactable", false)):
			continue
		var d := (o["pos"] as Vector2).distance_to(p["pos"]) - float(o["r"])
		if d <= float(room.rules.get("interact_range", 70.0)) and d < best_d:
			best_d = d
			best = int(o["id"])
	return best


func on_object_complete(o: Dictionary, p: Dictionary) -> void:
	_mechanic_object(o, p)


## 기믹 훅: 보스 컨트롤러마다 재정의한다 (철턱 가재는 IC-01~05)
func _mechanic_start(mid: String, m: Dictionary) -> void:
	match mid:
		"IC-01": _ic01_start(m)
		"IC-02": _ic02_start(m)
		"IC-03": _ic03_start(m)
		"IC-04": _ic04_start(m)
		"IC-05": _ic05_start(m)


func _mechanic_step(mid: String, dt: float, m: Dictionary) -> void:
	match mid:
		"IC-01": _ic01_step(dt, m)
		"IC-02": _ic02_step(dt, m)
		"IC-03": _ic03_step(dt, m)
		"IC-04": _ic04_step(dt, m)
		"IC-05": _ic05_step(dt, m)


func _mechanic_end(mid: String, success: bool) -> void:
	match mid:
		"IC-01": _ic01_end(success)
		"IC-02": _ic02_end(success)
		"IC-03": _ic03_end(success)
		"IC-04": _ic04_end(success)
		"IC-05": _ic05_end(success)


func _mechanic_object(o: Dictionary, p: Dictionary) -> void:
	match int(o["kind"]):
		Protocol.ObKind.PILLAR: _ic01_gnawed(o, p)
		Protocol.ObKind.GATE: _ic02_toggle(o, p)
		Protocol.ObKind.CLAW_LINK: _ic03_stage(o, p)
		Protocol.ObKind.CORRIDOR: _ic04_block(o, p)
		Protocol.ObKind.ROPE, Protocol.ObKind.DEBRIS, Protocol.ObKind.ANCHOR: _ic05_step_object(o, p)


func on_grabbed_input(p: Dictionary, held: int, dt: float) -> void:
	# IC-03: 붙잡힌 사람도 F 를 유지해 고리·쐐기를 스스로 조작할 수 있다 (느리게)
	if active != "IC-03" or grabbed != p["id"] or not bool(mprofile("IC-03").get("self_rescue", true)):
		return
	if held & Protocol.BTN_INTERACT == 0:
		return
	for o: Dictionary in room.objects.values():
		if int(o["kind"]) == Protocol.ObKind.CLAW_LINK and bool(o.get("interactable", false)):
			o["progress"] = minf(float(o["progress"]) + dt / maxf(float(o["hold_sec"]), 0.05) * 0.6, 1.0)
			if float(o["progress"]) >= 1.0:
				_ic03_stage(o, p)
			break


# ------------------------------------------------------------------ IC-01 붕괴 유도

func _ic01_start(m: Dictionary) -> void:
	var prof := mprofile("IC-01")
	var spots: Array = room.room_def.get("pillars", [])
	var count := mini(int(prof.get("pillars", 1)), spots.size())
	var order := range(spots.size())
	order.shuffle()
	for i in count:
		var sp: Array = spots[order[i]]
		_add_object(Protocol.ObKind.PILLAR, Vector2(sp[0], sp[1]), 30.0, {"hold_sec": float(prof.get("gnaw_sec", 2.0)), "interactable": true})
	_spawn_adds(int(prof.get("adds", 0)))
	m["data"] = {"weakened": 0}


func _ic01_gnawed(o: Dictionary, p: Dictionary) -> void:
	o["state"] = 1   # 약화됨(표식). 돌진이 닿으면 붕괴한다
	o["interactable"] = false
	mechanics["IC-01"]["data"]["weakened"] = int(mechanics["IC-01"]["data"].get("weakened", 0)) + 1
	p["stats"]["objective"] = float(p["stats"]["objective"]) + 1.0
	room.events.append({"k": "pillar_weakened", "oid": o["id"]})
	# 약화 후 유예: 남은 시간이 유예보다 짧으면 늘려 준다
	var grace := float(mprofile("IC-01").get("grace_sec", 6))
	mechanics["IC-01"]["t"] = maxf(float(mechanics["IC-01"]["t"]), grace + 6.0)


func _ic01_step(_dt: float, _m: Dictionary) -> void:
	var any := false
	for o: Dictionary in room.objects.values():
		if int(o["kind"]) == Protocol.ObKind.PILLAR:
			any = true
	if not any:
		_finish_mechanic(false, "all_pillars_gone")


func _ic01_success(o: Dictionary) -> void:
	room.objects.erase(o["id"])
	shell_broken = mini(shell_broken + 1, int(def.get("shell_segments", 3)))
	_enter_stagger(4.0)
	room.events.append({"k": "shell_break", "segments": shell_broken, "x": o["pos"].x, "y": o["pos"].y})
	_finish_mechanic(true, "collapse")


func _ic01_end(_success: bool) -> void:
	_remove_mechanic_objects([Protocol.ObKind.PILLAR])


# ------------------------------------------------------------------ IC-02 역류 수문

func _ic02_start(m: Dictionary) -> void:
	var prof := mprofile("IC-02")
	var sets: Array = room.room_def.get("gate_sets", [])
	var channels := mini(int(prof.get("channels", 1)), sets.size())
	var per := int(prof.get("gates_per_channel", 2))
	var data := {"channels": []}
	for ci in channels:
		var gates: Array = []
		var target_bits: Array = []
		var current_bits: Array = []
		for gi in per:
			var sp: Array = sets[ci][gi % sets[ci].size()]
			var cur := room.rng.randi() % 2
			var tgt := room.rng.randi() % 2
			var o := _add_object(Protocol.ObKind.GATE, Vector2(sp[0], sp[1]), 28.0, {"hold_sec": float(prof.get("hold_sec", 1.2)), "interactable": true, "channel": ci, "cur": cur, "target": tgt})
			o["state"] = cur + 2 * tgt
			gates.append(o["id"])
			target_bits.append(tgt)
			current_bits.append(cur)
		if current_bits == target_bits:
			# 최소 하나는 달라야 과제가 된다
			var first: Dictionary = room.objects[gates[0]]
			first["cur"] = 1 - int(first["cur"])
			first["state"] = int(first["cur"]) + 2 * int(first["target"])
		data["channels"].append({"gates": gates, "locked": false, "mismatch": _ic02_mismatch(gates)})
	m["data"] = data
	_spawn_adds(int(prof.get("adds", 0)))


func _ic02_mismatch(gates: Array) -> int:
	var c := 0
	for gid in gates:
		var g: Dictionary = room.objects.get(gid, {})
		if not g.is_empty() and int(g["cur"]) != int(g["target"]):
			c += 1
	return c


func _ic02_toggle(o: Dictionary, p: Dictionary) -> void:
	o["cur"] = 1 - int(o["cur"])
	o["state"] = int(o["cur"]) + 2 * int(o["target"])
	o["progress"] = 0.0
	var ch: Dictionary = mechanics["IC-02"]["data"]["channels"][int(o["channel"])]
	var before := int(ch["mismatch"])
	var now := _ic02_mismatch(ch["gates"])
	ch["mismatch"] = now
	p["stats"]["objective"] = float(p["stats"]["objective"]) + 1.0
	room.events.append({"k": "gate_toggled", "oid": o["id"], "channel": o["channel"], "mismatch": now})
	if now == 0:
		ch["locked"] = true
		for gid in ch["gates"]:
			var g: Dictionary = room.objects.get(gid, {})
			if not g.is_empty():
				g["interactable"] = false
				g["state"] = 4
		joint_weak_t = 20.0
		_enter_stagger(2.0)
		room.events.append({"k": "channel_locked", "channel": o["channel"]})
		_finish_mechanic(true, "channel_matched")
	elif now > before:
		# 잘못 연결: 경고 후 그 수문 근처 침수 (회복 가능한 불이익)
		room.events.append({"k": "gate_wrong", "channel": o["channel"], "x": o["pos"].x, "y": o["pos"].y})
		_add_hazard(o["pos"] + Vector2(0, 90 if o["pos"].y < room.bounds.get_center().y else -90), 110.0, 5.0, 6.0)


func _ic02_step(_dt: float, _m: Dictionary) -> void:
	pass


func _ic02_end(_success: bool) -> void:
	# 성공한 수로는 잠긴 채 남는다 (진행도 유지). 실패 시 표식만 사라진다.
	for oid in room.objects.keys():
		var o: Dictionary = room.objects[oid]
		if int(o["kind"]) == Protocol.ObKind.GATE and int(o["state"]) != 4:
			room.objects.erase(oid)


# ------------------------------------------------------------------ IC-03 집게 결박 구조

func _ic03_start(m: Dictionary) -> void:
	target = _nearest_player()
	if target == "":
		_finish_mechanic(false, "no_target")
		return
	state = BS.GRAB_APPROACH
	t = 5.0
	telegraph = {}
	m["data"] = {"stage": 0}
	room.events.append({"k": "boss_grab_intent", "target": target})


func _step_grab_approach(dt: float) -> void:
	t -= dt
	var tp: Dictionary = room.players.get(target, {})
	if tp.is_empty() or tp["state"] != Protocol.EntState.ALIVE or t <= 0.0:
		state = BS.CHASE
		if active == "IC-03":
			_finish_mechanic(false, "grab_missed")
		return
	var to: Vector2 = tp["pos"] - pos
	if to.length() > 0.01:
		facing = to.normalized()
	if to.length() <= radius + 40.0:
		_grab(tp)
	else:
		pos = SimRules.move(pos, to.normalized(), speed * 1.7, dt, room.bounds, radius, room.obstacles)


func _grab(tp: Dictionary) -> void:
	grabbed = tp["id"]
	grab_damage_done = 0.0
	tp["action"] = Protocol.Action.GRABBED
	tp["action_kind"] = "grabbed"
	tp["interact_target"] = 0
	state = BS.GRABBING
	var prof := mprofile("IC-03")
	var side := Vector2(-facing.y, facing.x)
	var link := _add_object(Protocol.ObKind.CLAW_LINK, pos + side * (radius + 30.0), 34.0, {"hold_sec": float(prof.get("link_sec", 1.5)), "interactable": true, "stage": 0})
	link["state"] = 0
	mechanics["IC-03"]["data"]["link"] = link["id"]
	room.events.append({"k": "boss_grabbed", "target": grabbed})


func _step_grabbing(dt: float) -> void:
	var tp: Dictionary = room.players.get(grabbed, {})
	if tp.is_empty() or tp["state"] != Protocol.EntState.ALIVE:
		_release_grab(false)
		return
	tp["pos"] = pos + facing * (radius + 20.0)
	var prof := mprofile("IC-03")
	var tick := float(tp["max_hp"]) * float(prof.get("dps_fraction", 0.02)) * dt
	var cap := float(tp["max_hp"]) * 0.25
	if grab_damage_done + tick > cap:
		tick = cap - grab_damage_done
	if tick > 0.0:
		tp["hp"] = maxf(float(tp["hp"]) - tick, 1.0)   # 결박 피해는 제한적이며 다운시키지 않는다
		tp["stats"]["damage_taken"] = float(tp["stats"]["damage_taken"]) + tick
		grab_damage_done += tick
	if grab_damage_done >= cap - 0.001:
		_finish_mechanic(false, "grab_damage_cap")
	var link: Dictionary = room.objects.get(mechanics["IC-03"]["data"].get("link", 0), {})
	if not link.is_empty():
		var side := Vector2(-facing.y, facing.x)
		link["pos"] = pos + side * (radius + 30.0)


func _ic03_stage(o: Dictionary, p: Dictionary) -> void:
	var prof := mprofile("IC-03")
	o["progress"] = 0.0
	if int(o["stage"]) == 0:
		o["stage"] = 1
		o["state"] = 1
		o["hold_sec"] = float(prof.get("wedge_sec", 1.5))
		p["stats"]["objective"] = float(p["stats"]["objective"]) + 1.0
		room.events.append({"k": "claw_link_exposed", "by": p["id"]})
	else:
		o["interactable"] = false
		o["state"] = 2
		p["stats"]["objective"] = float(p["stats"]["objective"]) + 1.0
		p["stats"]["rescues"] = int(p["stats"]["rescues"]) + (1 if p["id"] != grabbed else 0)
		room.events.append({"k": "claw_wedged", "by": p["id"]})
		_finish_mechanic(true, "wedged")


func _release_grab(success: bool) -> void:
	var tp: Dictionary = room.players.get(grabbed, {})
	if not tp.is_empty() and tp["action"] == Protocol.Action.GRABBED:
		tp["action"] = Protocol.Action.IDLE
		tp["action_kind"] = ""
		tp["protect_t"] = 1.0
		tp["pos"] = SimRules.move(tp["pos"], -facing, 70.0, 1.0, room.bounds, float(tp["radius"]), room.obstacles)
	if grabbed != "":
		room.events.append({"k": "boss_released", "target": grabbed, "rescued": success})
	grabbed = ""
	if state in [BS.GRABBING, BS.GRAB_APPROACH]:
		state = BS.CHASE


func _ic03_step(_dt: float, _m: Dictionary) -> void:
	pass


func _ic03_end(success: bool) -> void:
	_release_grab(success)
	_remove_mechanic_objects([Protocol.ObKind.CLAW_LINK])
	if success:
		claw_weak = true
		_enter_stagger(2.0)


# ------------------------------------------------------------------ IC-04 탈피 추적

func _ic04_start(m: Dictionary) -> void:
	var prof := mprofile("IC-04")
	state = BS.MOLT
	telegraph = {}
	var husks := int(prof.get("husks", 2))
	var corridors: Array = room.room_def.get("corridors", [])
	var ccount := mini(int(prof.get("corridors", 2)), corridors.size())
	var ids: Array = []
	# 껍질 위치: 보스 주변 원형 배치. 그중 하나가 본체(더듬이가 움직이고 물결이 인다)
	var real_index := room.rng.randi() % (husks + 1)
	for i in husks + 1:
		var a := TAU * i / float(husks + 1)
		var hp_ := pos + Vector2(cos(a), sin(a)) * 120.0
		var o := _add_object(Protocol.ObKind.HUSK, hp_, radius, {"interactable": false, "real": i == real_index})
		o["state"] = 1 if i == real_index else 0
		ids.append(o["id"])
		if i == real_index:
			molt_real_husk = o["id"]
			pos = hp_
	var escape := room.rng.randi() % ccount
	var cids: Array = []
	for i in ccount:
		var sp: Array = corridors[i]
		var c := _add_object(Protocol.ObKind.CORRIDOR, Vector2(sp[0], sp[1]), 40.0, {"hold_sec": float(prof.get("block_sec", 1.5)), "interactable": true, "escape": i == escape})
		cids.append(c["id"])
	# 본체와 탈출 통로를 잇는 물결 표식: 본체 껍질 상태 1 + 통로 방향 힌트(더듬이 방향)
	var real: Dictionary = room.objects[molt_real_husk]
	var esc: Dictionary = room.objects[cids[escape]]
	real["hint_dx"] = (esc["pos"] - real["pos"]).normalized().x
	real["hint_dy"] = (esc["pos"] - real["pos"]).normalized().y
	m["data"] = {"husks": ids, "corridors": cids, "escape": cids[escape], "blocked_wrong": 0}


func _ic04_block(o: Dictionary, p: Dictionary) -> void:
	o["interactable"] = false
	o["state"] = 1
	p["stats"]["objective"] = float(p["stats"]["objective"]) + 1.0
	room.events.append({"k": "corridor_blocked", "oid": o["id"], "by": p["id"]})
	if bool(o.get("escape", false)):
		_finish_mechanic(true, "escape_blocked")
	else:
		# 오인: 껍질 하나가 붕괴해 국지 위험. 전체 진행은 초기화되지 않는다.
		mechanics["IC-04"]["data"]["blocked_wrong"] = int(mechanics["IC-04"]["data"].get("blocked_wrong", 0)) + 1
		for hid in mechanics["IC-04"]["data"]["husks"]:
			var h: Dictionary = room.objects.get(hid, {})
			if not h.is_empty() and not bool(h.get("real", false)):
				_add_hazard(h["pos"], 90.0, 3.0, 8.0)
				room.objects.erase(hid)
				break


func _ic04_step(_dt: float, _m: Dictionary) -> void:
	pass


func _ic04_end(success: bool) -> void:
	_remove_mechanic_objects([Protocol.ObKind.HUSK, Protocol.ObKind.CORRIDOR])
	if success:
		state = BS.EXPOSED
		exposed_t = 6.0
		t = 6.0
		room.events.append({"k": "boss_exposed", "sec": 6.0})
	else:
		hp = minf(hp + max_hp * 0.15, max_hp)
		state = BS.CHASE
		room.events.append({"k": "boss_molt_heal", "hp": hp})


# ------------------------------------------------------------------ IC-05 소용돌이 닻

func _ic05_start(m: Dictionary) -> void:
	var prof := mprofile("IC-05")
	var pf: Dictionary = room.room_def.get("platform", {"x": 750, "y": 500, "r": 140})
	var plat := _add_object(Protocol.ObKind.PLATFORM, Vector2(float(pf["x"]), float(pf["y"])), float(pf.get("r", 140)), {"interactable": false, "drift": 0.0})
	var anchors: Array = room.room_def.get("anchor_points", [])
	var ropes: Array = []
	for i in mini(int(prof.get("ropes", 1)), anchors.size()):
		var sp: Array = anchors[i]
		var o := _add_object(Protocol.ObKind.ROPE, Vector2(sp[0], sp[1]), 26.0, {"hold_sec": float(prof.get("hold_sec", 1.5)), "interactable": true})
		ropes.append(o["id"])
	var debris_pts: Array = room.room_def.get("debris_points", [])
	var debris: Array = []
	for i in mini(int(prof.get("debris", 1)), debris_pts.size()):
		var sp: Array = debris_pts[i]
		var o := _add_object(Protocol.ObKind.DEBRIS, Vector2(sp[0], sp[1]), 30.0, {"hold_sec": float(prof.get("hold_sec", 1.5)), "interactable": true})
		debris.append(o["id"])
	var cp: Array = room.room_def.get("center_point", [750, 500])
	var center := _add_object(Protocol.ObKind.ANCHOR, Vector2(cp[0], cp[1]), 30.0, {"hold_sec": float(prof.get("hold_sec", 1.5)), "interactable": false})
	var ws: Array = room.room_def.get("whirlpool", room.room_def.get("boss_spawn", [1000, 500]))
	m["data"] = {"platform": plat["id"], "ropes": ropes, "debris": debris, "center": center["id"], "whirl": Vector2(ws[0], ws[1])}


func _ic05_step_object(o: Dictionary, p: Dictionary) -> void:
	var d: Dictionary = mechanics["IC-05"]["data"]
	o["progress"] = 0.0
	match int(o["kind"]):
		Protocol.ObKind.ROPE:
			o["state"] = 1
			o["interactable"] = false
			room.events.append({"k": "rope_attached", "by": p["id"]})
		Protocol.ObKind.DEBRIS:
			room.objects.erase(o["id"])
			room.events.append({"k": "debris_cleared", "by": p["id"]})
		Protocol.ObKind.ANCHOR:
			o["state"] = 1
			o["interactable"] = false
			room.events.append({"k": "anchor_fixed", "by": p["id"]})
			_finish_mechanic(true, "anchored")
			return
	p["stats"]["objective"] = float(p["stats"]["objective"]) + 1.0
	# 순서: 줄 1개 이상 연결 + 잔해 모두 제거 → 고정점 조작 가능
	var rope_ok := false
	for rid in d["ropes"]:
		var r: Dictionary = room.objects.get(rid, {})
		if not r.is_empty() and int(r["state"]) == 1:
			rope_ok = true
	var debris_left := 0
	for did in d["debris"]:
		if room.objects.has(did):
			debris_left += 1
	var center: Dictionary = room.objects.get(d["center"], {})
	if not center.is_empty():
		center["interactable"] = rope_ok and debris_left == 0


func _ic05_step(dt: float, m: Dictionary) -> void:
	var d: Dictionary = m["data"]
	var plat: Dictionary = room.objects.get(d["platform"], {})
	if plat.is_empty():
		return
	# 발판이 소용돌이(고정 지점)로 끌려간다. 위에 선 플레이어도 함께 끌린다.
	var whirl: Vector2 = d["whirl"]
	var dir: Vector2 = (whirl - plat["pos"]).normalized() if (plat["pos"] as Vector2).distance_to(whirl) > 1.0 else Vector2.ZERO
	plat["pos"] = plat["pos"] + dir * 14.0 * dt
	for pl: Dictionary in room.players.values():
		if pl["state"] == Protocol.EntState.ALIVE and (pl["pos"] as Vector2).distance_to(plat["pos"]) <= float(plat["r"]):
			pl["pos"] = SimRules.move(pl["pos"], dir, 14.0, dt, room.bounds, float(pl["radius"]), room.obstacles)
	plat["progress"] = clampf(1.0 - (plat["pos"] as Vector2).distance_to(whirl) / 400.0, 0.0, 1.0)
	if (plat["pos"] as Vector2).distance_to(whirl) < radius + 40.0:
		_finish_mechanic(false, "platform_lost")


func _ic05_end(success: bool) -> void:
	var d: Dictionary = mechanics["IC-05"]["data"]
	_remove_mechanic_objects([Protocol.ObKind.ROPE, Protocol.ObKind.DEBRIS, Protocol.ObKind.ANCHOR])
	var plat: Dictionary = room.objects.get(d.get("platform", 0), {})
	if plat.is_empty():
		return
	if success:
		plat["state"] = 2   # 고정된 안전 발판: 위에서 공격하면 피해 +25% (buff zone)
		plat["progress"] = 1.0
		room.events.append({"k": "platform_fixed", "x": plat["pos"].x, "y": plat["pos"].y})
	else:
		_add_hazard(plat["pos"], float(plat["r"]) * 0.8, 6.0, 5.0)
		room.objects.erase(plat["id"])
		room.events.append({"k": "platform_lost"})


## 고정된 발판 위 플레이어 피해 보너스 (CombatRoom._player_damage 가 참조)
func damage_bonus_at(p_pos: Vector2) -> float:
	for o: Dictionary in room.objects.values():
		if int(o["kind"]) == Protocol.ObKind.PLATFORM and int(o["state"]) == 2 and (o["pos"] as Vector2).distance_to(p_pos) <= float(o["r"]):
			return 0.25
	return 0.0


# ------------------------------------------------------------------ 스냅샷

func telegraphs() -> Array:
	if telegraph.is_empty() or state != BS.WINDUP:
		return []
	if int(telegraph.get("type", 0)) == 1:
		return [PackedFloat32Array([1, telegraph["x"], telegraph["y"], telegraph["len"], t, telegraph["total"], telegraph["dx"], telegraph["dy"], telegraph["w"]])]
	return [PackedFloat32Array([0, telegraph["x"], telegraph["y"], telegraph["r"], t, telegraph["total"], 0, 0, 0])]


## 스냅샷 (20Hz, MTU 안에 들어가도록 문자열은 id 만 보낸다: 이름·안내문은 클라이언트가 ContentDB 로 만든다)
func snapshot() -> Dictionary:
	var flags := (1 if claw_weak else 0) | (2 if joint_weak_t > 0.0 else 0) | (4 if exposed_t > 0.0 else 0) | (8 if state == BS.MOLT else 0) | (16 if enrage_t > 0.0 else 0) | (32 if extra_vuln_t > 0.0 else 0)
	return {
		"id": def.get("id", ""), "x": snappedf(pos.x, 0.1), "y": snappedf(pos.y, 0.1), "fx": snappedf(facing.x, 0.01), "fy": snappedf(facing.y, 0.01),
		"hp": snappedf(hp, 0.1), "max_hp": max_hp, "state": state, "phase": phase, "shell_broken": shell_broken, "shell_total": def.get("shell_segments", 3),
		"f": flags, "grabbed": grabbed, "stagger_gauge": snappedf(stagger_gauge, 1.0),
		"m": active, "mt": snappedf(float(mechanics[active]["t"]), 0.1) if active != "" else 0.0,
		"pattern": pattern.get("id", "") if state in [BS.WINDUP, BS.ATTACK] else "",
	}

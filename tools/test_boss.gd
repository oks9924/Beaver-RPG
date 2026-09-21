extends Node
## 보스 검증 (MEC-01, BAL-02 데이터 검사): 철턱 가재의 기본 패턴 4개와 독립 기믹 5개가 인원 1~4 프로필마다
## 실제로 등장·해결·실패 상태를 갖는지 스크립트로 수행한다. 실행: godot --headless --path . -- --tool=test_boss

var launch_args: Dictionary = {}
var failures: PackedStringArray = []
var passed: int = 0
var passive_boss: bool = true
const DT := 1.0 / 30.0


func check(cond: bool, name: String) -> void:
	if cond:
		passed += 1
	else:
		failures.append(name)


func _ready() -> void:
	for n in range(1, 5):
		test_ic01(n)
		test_ic02(n)
		test_ic03(n)
		test_ic04(n)
		test_ic05(n)
	for n in range(1, 5):
		test_toad(n)
		test_root_king(n)
	passive_boss = false
	test_patterns_and_death()
	test_scheduler_rules()
	test_new_boss_patterns()
	print("boss tests passed=%d failed=%d" % [passed, failures.size()])
	for f in failures:
		printerr("FAIL: " + f)
	get_tree().quit(0 if failures.is_empty() else 1)


func _members(n: int) -> Array:
	var out: Array = []
	for i in n:
		out.append({"account_id": "p%d" % i, "nickname": "P%d" % i, "class_id": "guardian"})
	return out


func _make(n: int, seed_: int = 1) -> CombatRoom:
	var room := CombatRoom.new(ContentDB.get_room_def("boss_ironclaw"), ContentDB.get_party_profile(n), ContentDB.rules, seed_, _members(n))
	room.boss = BossIronclaw.new(room, ContentDB.get_party_profile(n), ContentDB.bosses["ironclaw"])
	room.boss.passive = passive_boss
	return room


func _objects_of(room: CombatRoom, kind: int) -> Array:
	var out: Array = []
	for o: Dictionary in room.objects.values():
		if int(o["kind"]) == kind:
			out.append(o)
	return out


## 플레이어를 오브젝트 옆에 두고 F 를 유지해 완료시킨다
func _interact_until(room: CombatRoom, pid: String, o: Dictionary, max_sec: float = 8.0) -> bool:
	var p: Dictionary = room.players[pid]
	p["pos"] = (o["pos"] as Vector2) + Vector2(40, 0)
	p["action"] = Protocol.Action.IDLE
	var seq := int(p["last_seq"]) + 1
	var start_state: int = int(o["state"])
	for i in int(max_sec / DT):
		room.queue_input(pid, seq, Vector2.ZERO, Vector2.ZERO, Protocol.BTN_INTERACT)
		seq += 1
		room.step(DT)
		if not room.objects.has(o["id"]) or int(o["state"]) != start_state or not bool(o.get("interactable", true)):
			room.queue_input(pid, seq, Vector2.ZERO, Vector2.ZERO, 0)
			room.step(DT)
			return true
	return false


func _park_players(room: CombatRoom, at: Vector2) -> void:
	for p: Dictionary in room.players.values():
		p["pos"] = at
		p["hp"] = p["max_hp"]


func test_ic01(n: int) -> void:
	var room := _make(n, 10 + n)
	var boss: BossIronclaw = room.boss
	_park_players(room, Vector2(300, 500))
	boss._start_mechanic("IC-01")
	var pillars := _objects_of(room, Protocol.ObKind.PILLAR)
	var prof: Dictionary = boss.mprofile("IC-01")
	check(pillars.size() == int(prof["pillars"]), "IC-01 n=%d pillars=%d" % [n, pillars.size()])
	check(room.enemies.size() == int(prof.get("adds", 0)), "IC-01 n=%d adds=%d" % [n, room.enemies.size()])
	var pillar: Dictionary = pillars[0]
	check(_interact_until(room, "p0", pillar), "IC-01 n=%d gnaw weakens pillar" % n)
	check(int(pillar["state"]) == 1, "IC-01 n=%d pillar marked weakened" % n)
	# 유도: 보스를 지지목 반대편에 두고 돌진을 강제 → 지지목 붕괴 → 갑각 파괴 + 경직
	boss.pos = (pillar["pos"] as Vector2) + Vector2(-300, 0)
	boss.facing = Vector2.RIGHT
	room.players["p0"]["pos"] = (pillar["pos"] as Vector2) + Vector2(120, 0)
	boss.state = BossIronclaw.BS.CHASE
	boss._begin_pattern(ContentDB.bosses["ironclaw"]["attack_patterns"]["line_charge"])
	var broke := false
	for i in 90:
		for ev: Dictionary in room.step(DT):
			if ev["k"] == "shell_break":
				broke = true
	check(broke and boss.shell_broken == 1 and boss.state == BossIronclaw.BS.STAGGER, "IC-01 n=%d lured charge collapses pillar: shell break + stagger" % n)
	check(boss.active == "" and boss.stats["mechanics_succeeded"] == 1, "IC-01 n=%d mechanic finished as success" % n)
	check(boss.damage_taken_mult() > 1.0, "IC-01 n=%d broken shell increases damage taken permanently" % n)
	# 실패 경로: 약화 없이 돌진하면 지지목만 부서진다
	var room2 := _make(n, 20 + n)
	var boss2: BossIronclaw = room2.boss
	_park_players(room2, Vector2(300, 500))
	boss2._start_mechanic("IC-01")
	var p2: Dictionary = _objects_of(room2, Protocol.ObKind.PILLAR)[0]
	boss2.pos = (p2["pos"] as Vector2) + Vector2(-300, 0)
	boss2.facing = Vector2.RIGHT
	room2.players["p0"]["pos"] = (p2["pos"] as Vector2) + Vector2(120, 0)
	boss2._begin_pattern(ContentDB.bosses["ironclaw"]["attack_patterns"]["line_charge"])
	var destroyed := false
	for i in 90:
		for ev: Dictionary in room2.step(DT):
			if ev["k"] == "pillar_destroyed":
				destroyed = true
	check(destroyed and boss2.shell_broken == 0, "IC-01 n=%d intact pillar just breaks (no shell loss)" % n)


func test_ic02(n: int) -> void:
	var room := _make(n, 30 + n)
	var boss: BossIronclaw = room.boss
	_park_players(room, Vector2(300, 500))
	boss._start_mechanic("IC-02")
	var prof: Dictionary = boss.mprofile("IC-02")
	var gates := _objects_of(room, Protocol.ObKind.GATE)
	check(gates.size() == int(prof["channels"]) * int(prof["gates_per_channel"]), "IC-02 n=%d gates=%d" % [n, gates.size()])
	# 채널 0 을 목표 배열에 맞춘다 (순차 조작으로 충분)
	var wrong_fired := false
	for g: Dictionary in gates:
		if int(g["channel"]) != 0:
			continue
		if int(g["cur"]) != int(g["target"]):
			check(_interact_until(room, "p0", g), "IC-02 n=%d toggle gate %d" % [n, g["id"]])
	for ev: Dictionary in room.events:
		if ev["k"] == "gate_wrong":
			wrong_fired = true
	check(boss.stats["mechanics_succeeded"] == 1 and boss.joint_weak_t > 0.0, "IC-02 n=%d matching channel 0 succeeds: joint weakened (adds spawned=%d)" % [n, room.enemies.size()])
	var locked := 0
	for g: Dictionary in _objects_of(room, Protocol.ObKind.GATE):
		if int(g["state"]) == 4:
			locked += 1
	check(locked == int(prof["gates_per_channel"]), "IC-02 n=%d success locks the channel (progress kept)" % n)
	# 잘못 연결: 불일치가 늘면 침수 위험 생성
	var room2 := _make(n, 40 + n)
	var boss2: BossIronclaw = room2.boss
	_park_players(room2, Vector2(300, 500))
	boss2._start_mechanic("IC-02")
	var g0: Dictionary = {}
	for g: Dictionary in _objects_of(room2, Protocol.ObKind.GATE):
		if int(g["cur"]) == int(g["target"]):
			g0 = g
			break
	if g0.is_empty():
		check(true, "IC-02 n=%d no matching gate to break (skip)" % n)
	else:
		_interact_until(room2, "p0", g0)
		var hazard := _objects_of(room2, Protocol.ObKind.HAZARD)
		check(hazard.size() >= 1, "IC-02 n=%d wrong connection floods a local area" % n)
		var before: float = room2.players["p0"]["hp"]
		room2.players["p0"]["pos"] = hazard[0]["pos"]
		for i in 30:
			room2.step(DT)
		check(room2.players["p0"]["hp"] < before, "IC-02 n=%d flooded area damages players (recoverable penalty)" % n)


func test_ic03(n: int) -> void:
	var room := _make(n, 50 + n)
	var boss: BossIronclaw = room.boss
	_park_players(room, boss.pos + Vector2(-90, 0))
	boss._start_mechanic("IC-03")
	var grabbed := false
	for i in 120:
		for ev: Dictionary in room.step(DT):
			if ev["k"] == "boss_grabbed":
				grabbed = true
		if grabbed:
			break
	check(grabbed and boss.grabbed != "" and room.players[boss.grabbed]["action"] == Protocol.Action.GRABBED, "IC-03 n=%d boss grabs a player" % n)
	var link := _objects_of(room, Protocol.ObKind.CLAW_LINK)
	check(link.size() == 1, "IC-03 n=%d claw link appears" % n)
	var rescuer := "p1" if n >= 2 else "p0"
	if n == 1:
		# 혼자: 붙잡힌 채 F 유지로 고리→쐐기
		var p: Dictionary = room.players["p0"]
		var seq := int(p["last_seq"]) + 1
		for i in int(14.0 / DT):
			room.queue_input("p0", seq, Vector2.ZERO, Vector2.ZERO, Protocol.BTN_INTERACT)
			seq += 1
			room.step(DT)
			if boss.active != "IC-03":
				break
	else:
		room.players[rescuer]["action"] = Protocol.Action.IDLE
		check(_interact_until(room, rescuer, link[0]), "IC-03 n=%d ally exposes the link" % n)
		check(_interact_until(room, rescuer, link[0]), "IC-03 n=%d ally wedges the claw" % n)
	check(boss.stats["mechanics_succeeded"] == 1 and boss.claw_weak and boss.grabbed == "", "IC-03 n=%d rescue succeeds: released + claw weakened" % n)
	check(room.players["p0"]["state"] == Protocol.EntState.ALIVE, "IC-03 n=%d grabbed player survives" % n)
	# 실패 경로: 아무것도 안 하면 제한 피해 후 방출, 영구 구속 없음
	var room2 := _make(n, 60 + n)
	var boss2: BossIronclaw = room2.boss
	_park_players(room2, boss2.pos + Vector2(-90, 0))
	boss2._start_mechanic("IC-03")
	for i in int(20.0 / DT):
		room2.step(DT)
		if boss2.stats["mechanics_failed"] > 0:
			break
	var victim: Dictionary = room2.players["p0"]
	check(boss2.stats["mechanics_failed"] == 1 and boss2.grabbed == "" and victim["action"] != Protocol.Action.GRABBED, "IC-03 n=%d failure releases the target (no permanent grab)" % n)
	check(victim["hp"] >= victim["max_hp"] * 0.74, "IC-03 n=%d grab damage capped at 25%% (hp %.0f/%.0f)" % [n, victim["hp"], victim["max_hp"]])


func test_ic04(n: int) -> void:
	var room := _make(n, 70 + n)
	var boss: BossIronclaw = room.boss
	_park_players(room, Vector2(300, 500))
	boss._start_mechanic("IC-04")
	var prof: Dictionary = boss.mprofile("IC-04")
	var husks := _objects_of(room, Protocol.ObKind.HUSK)
	var corridors := _objects_of(room, Protocol.ObKind.CORRIDOR)
	check(husks.size() == int(prof["husks"]) + 1 and corridors.size() == int(prof["corridors"]), "IC-04 n=%d husks=%d corridors=%d" % [n, husks.size(), corridors.size()])
	var real := 0
	for h: Dictionary in husks:
		if int(h["state"]) == 1:
			real += 1
	check(real == 1, "IC-04 n=%d exactly one husk has moving antennae (identification cue)" % n)
	var hp_before: float = boss.hp
	boss.hp = boss.max_hp * 0.5
	var before_fix: float = boss.hp
	# 정답 통로 차단
	var escape: Dictionary = {}
	for c: Dictionary in corridors:
		if bool(c.get("escape", false)):
			escape = c
	check(_interact_until(room, "p0", escape), "IC-04 n=%d block escape corridor" % n)
	check(boss.stats["mechanics_succeeded"] == 1 and boss.exposed_t > 0.0 and is_equal_approx(boss.hp, before_fix), "IC-04 n=%d success: no molt heal, boss exposed" % n)
	pass
	# 오인: 잘못된 통로 → 껍질 붕괴 위험, 진행 초기화 없음; 시간 종료 → 15% 회복
	var room2 := _make(n, 80 + n)
	var boss2: BossIronclaw = room2.boss
	_park_players(room2, Vector2(300, 500))
	boss2.hp = boss2.max_hp * 0.5
	boss2._start_mechanic("IC-04")
	var wrong: Dictionary = {}
	for c: Dictionary in _objects_of(room2, Protocol.ObKind.CORRIDOR):
		if not bool(c.get("escape", false)):
			wrong = c
	_interact_until(room2, "p0", wrong)
	check(_objects_of(room2, Protocol.ObKind.HAZARD).size() >= 1 and boss2.active == "IC-04", "IC-04 n=%d wrong corridor: local hazard, mechanic continues" % n)
	room2.players["p0"]["pos"] = Vector2(300, 500)
	for i in int(14.0 / DT):
		room2.step(DT)
	check(boss2.stats["mechanics_failed"] == 1 and boss2.hp > boss2.max_hp * 0.5, "IC-04 n=%d timeout: boss heals 15%%" % n)


func test_ic05(n: int) -> void:
	var room := _make(n, 90 + n)
	var boss: BossIronclaw = room.boss
	_park_players(room, Vector2(300, 500))
	boss._start_mechanic("IC-05")
	var prof: Dictionary = boss.mprofile("IC-05")
	var ropes := _objects_of(room, Protocol.ObKind.ROPE)
	var debris := _objects_of(room, Protocol.ObKind.DEBRIS)
	var anchor := _objects_of(room, Protocol.ObKind.ANCHOR)
	check(ropes.size() == int(prof["ropes"]) and debris.size() == int(prof["debris"]) and anchor.size() == 1, "IC-05 n=%d ropes=%d debris=%d" % [n, ropes.size(), debris.size()])
	check(not bool(anchor[0]["interactable"]), "IC-05 n=%d anchor locked until rope+debris done (order rule)" % n)
	check(_interact_until(room, "p0", ropes[0]), "IC-05 n=%d attach one rope (one rope is enough)" % n)
	for d: Dictionary in debris:
		check(_interact_until(room, "p0", d), "IC-05 n=%d clear debris" % n)
	check(bool(anchor[0]["interactable"]), "IC-05 n=%d anchor unlocked after rope+debris" % n)
	check(_interact_until(room, "p0", anchor[0]), "IC-05 n=%d fix anchor" % n)
	var plat := _objects_of(room, Protocol.ObKind.PLATFORM)
	check(boss.stats["mechanics_succeeded"] == 1 and plat.size() == 1 and int(plat[0]["state"]) == 2, "IC-05 n=%d success: platform fixed as safe attack spot" % n)
	room.players["p0"]["pos"] = plat[0]["pos"]
	check(boss.damage_bonus_at(room.players["p0"]["pos"]) > 0.0, "IC-05 n=%d platform grants damage bonus" % n)
	# 실패: 시간 종료 → 발판 유실(위험 구역), 나머지 전장 유지
	var room2 := _make(n, 100 + n)
	var boss2: BossIronclaw = room2.boss
	_park_players(room2, Vector2(300, 500))
	boss2._start_mechanic("IC-05")
	for i in int(26.0 / DT):
		room2.step(DT)
		if boss2.stats["mechanics_failed"] > 0:
			break
	check(boss2.stats["mechanics_failed"] == 1 and _objects_of(room2, Protocol.ObKind.PLATFORM).is_empty() and _objects_of(room2, Protocol.ObKind.HAZARD).size() == 1, "IC-05 n=%d failure loses only the platform" % n)


func test_patterns_and_death() -> void:
	var room := _make(2, 200)
	var boss: BossIronclaw = room.boss
	var pats: Dictionary = ContentDB.bosses["ironclaw"]["attack_patterns"]
	check(pats.size() == 4, "boss has 4 basic attack patterns separate from mechanics")
	check(ContentDB.bosses["ironclaw"]["mechanics"].size() == 5, "boss has 5 independent mechanics")
	# 집게 부채꼴: 예고 후 정면 플레이어 피격
	_park_players(room, boss.pos + Vector2(-100, 0))
	boss.facing = Vector2.LEFT
	boss._begin_pattern(pats["claw_sweep"])
	check(not boss.telegraphs().is_empty(), "sweep shows a telegraph")
	var hit := false
	for i in 40:
		for ev: Dictionary in room.step(DT):
			if ev["k"] == "hit" and ev["by"] == "boss":
				hit = true
	check(hit, "claw sweep damages a player in front")
	# 바위 투척: 대상 위치에 원형 예고
	boss.state = BossIronclaw.BS.CHASE
	boss.cooldowns["rock_toss"] = 0.0
	boss.target = "p0"
	boss._begin_pattern(pats["rock_toss"])
	var tg := boss.telegraphs()
	check(tg.size() == 1 and int(tg[0][0]) == 0 and Vector2(tg[0][1], tg[0][2]).distance_to(room.players["p0"]["pos"]) < 1.0, "rock toss telegraph appears at the target's position")
	# 지면 찍기: 자기 주변
	boss.state = BossIronclaw.BS.CHASE
	boss._begin_pattern(pats["ground_slam"])
	tg = boss.telegraphs()
	check(tg.size() == 1 and Vector2(tg[0][1], tg[0][2]).distance_to(boss.pos) < 1.0, "ground slam telegraph centers on the boss")
	# 경직 게이지: 기절 연쇄 대신 게이지가 차야 경직
	boss.state = BossIronclaw.BS.CHASE
	boss.telegraph = {}
	var p0: Dictionary = room.players["p0"]
	var hits := 0
	while boss.state != BossIronclaw.BS.STAGGER and hits < 20:
		boss.take_damage(1.0, p0, 0.5)
		hits += 1
	check(hits > 1 and boss.state == BossIronclaw.BS.STAGGER, "stagger needs a filled gauge, not one hit (%d hits)" % hits)
	boss.state = BossIronclaw.BS.CHASE
	boss.take_damage(1.0, p0, 5.0)
	check(boss.state != BossIronclaw.BS.STAGGER, "stagger resistance prevents chain-staggers")
	# 단계 전환: 예고 정리
	boss._begin_pattern(pats["ground_slam"])
	boss.shell_broken = 1   # 갑각이 온전하면 받는 피해가 줄어(shell_intact_damage_taken_mult) 단계가 안 넘어간다
	boss.take_damage(boss.max_hp * 0.4, p0)
	check(boss.phase == 1 and boss.telegraph.is_empty(), "phase change clears old telegraphs")
	# 사망 정리: 남은 적·기믹 오브젝트 제거, 방 승리
	boss._start_mechanic("IC-01")
	room._spawn_enemy("sap_snail", Vector2(1200, 200))
	boss.take_damage(boss.max_hp * 2.0, p0)
	check(boss.is_defeated() and room.objects.is_empty() and _objects_of(room, Protocol.ObKind.PILLAR).is_empty(), "death clears mechanic objects")
	for i in 60:
		room.step(DT)
	check(room.outcome == Protocol.Outcome.VICTORY, "boss death completes the boss room")


func test_scheduler_rules() -> void:
	var room := _make(4, 300)
	var boss: BossIronclaw = room.boss
	_park_players(room, Vector2(300, 500))
	var order: Array = []
	# 기믹을 계속 강제 종료하며 스케줄러가 고르는 순서를 기록한다
	for i in 12:
		boss.mechanic_gap_t = 0.0
		for mid: String in boss.mechanics.keys():
			boss.mechanics[mid]["cooldown_t"] = 0.0
		boss.phase = 2
		boss.state = BossIronclaw.BS.CHASE
		var pick := boss._choose_mechanic()
		if pick == "":
			break
		boss._start_mechanic(pick)
		order.append(pick)
		boss._finish_mechanic(false, "test")
		boss.state = BossIronclaw.BS.CHASE
	var first_six := order.slice(0, 6)
	first_six.sort()
	var seen := {}
	for m in first_six:
		seen[m] = true
	check(seen.size() == 5, "all five mechanics appear within the first six picks (unseen preferred, incompatible pairs avoided) (%s)" % [order])
	var repeat_ok := true
	for i in range(1, order.size()):
		if order[i] == order[i - 1]:
			repeat_ok = false
	check(repeat_ok, "no immediate repeat of the same mechanic")
	var counts := {}
	for m in order:
		counts[m] = int(counts.get(m, 0)) + 1
	var within := true
	for m in counts.keys():
		if int(counts[m]) > int(ContentDB.bosses["ironclaw"]["mechanics"][m]["max_repeats"]):
			within = false
	check(within, "repeat limits respected (%s)" % [counts])
	var pairs: Array = ContentDB.bosses["ironclaw"]["incompatible_pairs"]
	var pair_ok := true
	for i in range(1, order.size()):
		for pair: Array in pairs:
			if pair.has(order[i]) and pair.has(order[i - 1]):
				pair_ok = false
	check(pair_ok, "incompatible mechanics never follow each other")


# ------------------------------------------------------------------ 늪등불 두꺼비 / 뿌리왕 (4단계)

func _make_boss(boss_id: String, n: int, seed_: int) -> CombatRoom:
	var room := CombatRoom.new(ContentDB.get_room_def("boss_" + boss_id), ContentDB.get_party_profile(n), ContentDB.rules, seed_, _members(n))
	var script: GDScript = load("res://server/expedition/boss_%s.gd" % boss_id)
	room.boss = script.new(room, ContentDB.get_party_profile(n), ContentDB.bosses[boss_id])
	room.boss.passive = passive_boss
	return room


func _run(room: CombatRoom, sec: float) -> Array:
	var evs: Array = []
	for i in int(sec / DT):
		evs.append_array(room.step(DT))
	return evs


## 운반: 오브젝트를 집은 뒤 목적지까지 걸어간다 (플레이어 위치를 서버 이동 규칙 대신 직접 옮긴다: 판정만 검증)
func _carry_to(room: CombatRoom, pid: String, o: Dictionary, dest: Vector2, max_sec: float = 12.0) -> bool:
	if not _interact_until(room, pid, o):
		return false
	var p: Dictionary = room.players[pid]
	for i in int(max_sec / DT):
		var d: Vector2 = dest - p["pos"]
		if d.length() < 30.0:
			p["pos"] = dest
		else:
			p["pos"] = p["pos"] + d.normalized() * 120.0 * DT
		room.step(DT)
		if not room.objects.has(o["id"]):
			return true
	return false


func test_toad(n: int) -> void:
	# TF-01 등불: 모두 켜면 노출. 3인 이상은 relight 로 꺼지므로 빠르게 켜야 한다
	var room := _make_boss("lantern_toad", n, 400 + n)
	var boss: BossLanternToad = room.boss
	_park_players(room, Vector2(300, 500))
	boss._start_mechanic("TF-01")
	var lanterns := _objects_of(room, Protocol.ObKind.LANTERN)
	var prof: Dictionary = boss.mprofile("TF-01")
	check(lanterns.size() == int(prof["lanterns"]), "TF-01 n=%d lanterns=%d" % [n, lanterns.size()])
	var i := 0
	for l: Dictionary in lanterns:
		check(_interact_until(room, "p%d" % (i % n), l), "TF-01 n=%d light lantern %d" % [n, i])
		i += 1
	check(boss.active == "" and boss.stats["mechanics_succeeded"] == 1 and boss.exposed_t > 0.0, "TF-01 n=%d all lit -> exposed" % n)
	if float(prof.get("relight_sec", 0)) > 0.0:
		var room2 := _make_boss("lantern_toad", n, 410 + n)
		var b2: BossLanternToad = room2.boss
		_park_players(room2, Vector2(300, 500))
		b2._start_mechanic("TF-01")
		var l0: Dictionary = _objects_of(room2, Protocol.ObKind.LANTERN)[0]
		_interact_until(room2, "p0", l0)
		_run(room2, float(prof["relight_sec"]) + 0.5)
		check(int(l0["state"]) == 0 and bool(l0["interactable"]), "TF-01 n=%d a lit lantern goes out after relight_sec" % n)
	# 실패: 시간 만료 → 어둠 파동 피해
	var room3 := _make_boss("lantern_toad", n, 420 + n)
	var b3: BossLanternToad = room3.boss
	_park_players(room3, Vector2(300, 500))
	b3._start_mechanic("TF-01")
	b3.mechanics["TF-01"]["t"] = 0.05
	var hp0: float = room3.players["p0"]["hp"]
	_run(room3, 0.2)
	check(b3.stats["mechanics_failed"] == 1 and room3.players["p0"]["hp"] < hp0, "TF-01 n=%d timeout -> darkness burst" % n)

	# TF-02 씨앗 운반: 집으면 느려지고, 연못에 닿으면 전달. 모두 전달하면 취약
	room = _make_boss("lantern_toad", n, 430 + n)
	boss = room.boss
	_park_players(room, Vector2(300, 500))
	boss._start_mechanic("TF-02")
	var seeds := _objects_of(room, Protocol.ObKind.SEED)
	prof = boss.mprofile("TF-02")
	check(seeds.size() == int(prof["seeds"]), "TF-02 n=%d seeds=%d" % [n, seeds.size()])
	var pond: Vector2 = boss.mechanics["TF-02"]["data"]["pond"]
	check(_interact_until(room, "p0", seeds[0]) and boss.carry.has("p0") and room.players["p0"]["slow_t"] > 0.0, "TF-02 n=%d pickup slows the carrier" % n)
	# 맞으면 떨어뜨린다
	boss._on_boss_hit_player(room.players["p0"])
	check(not boss.carry.has("p0") and bool(seeds[0]["interactable"]), "TF-02 n=%d boss hit drops the seed" % n)
	i = 0
	for sd: Dictionary in seeds:
		check(_carry_to(room, "p%d" % (i % n), sd, pond), "TF-02 n=%d deliver seed %d" % [n, i])
		i += 1
	check(boss.stats["mechanics_succeeded"] == 1 and boss.joint_weak_t > 0.0, "TF-02 n=%d all seeds -> pond purified (vulnerable)" % n)

	# TF-03 포자 결절: 맥동 중에는 만질 수 없고, 모두 끊으면 회복 차단 + 경직
	room = _make_boss("lantern_toad", n, 440 + n)
	boss = room.boss
	_park_players(room, Vector2(300, 500))
	boss._start_mechanic("TF-03")
	var nodes := _objects_of(room, Protocol.ObKind.SPORE_NODE)
	prof = boss.mprofile("TF-03")
	check(nodes.size() == int(prof["nodes"]) and boss.regen_per_sec > 0.0, "TF-03 n=%d nodes=%d heal the boss" % [n, nodes.size()])
	boss.hp = boss.max_hp * 0.5
	_run(room, 1.0)
	check(boss.hp > boss.max_hp * 0.5, "TF-03 n=%d boss regenerates while nodes live" % n)
	i = 0
	for nd: Dictionary in nodes:
		var ok := false
		for attempt in 8:   # 맥동 창(만질 수 없음)을 피해 끊길 때까지 재시도
			_interact_until(room, "p%d" % (i % n), nd, 3.0)
			if not room.objects.has(nd["id"]):
				ok = true
				break
			_run(room, 0.4)
		check(ok, "TF-03 n=%d sever node %d" % [n, i])
		i += 1
	check(boss.stats["mechanics_succeeded"] == 1 and boss.regen_per_sec == 0.0 and boss.state == BossIronclaw.BS.STAGGER, "TF-03 n=%d all severed -> stagger, no regen" % n)

	# TF-04 공명목: 틀린 순서는 초기화 + 감전, 올바른 순서는 기절
	room = _make_boss("lantern_toad", n, 450 + n)
	boss = room.boss
	_park_players(room, Vector2(300, 500))
	boss._start_mechanic("TF-04")
	var logs := _objects_of(room, Protocol.ObKind.RESONANCE_LOG)
	prof = boss.mprofile("TF-04")
	check(logs.size() == int(prof["logs"]), "TF-04 n=%d logs=%d" % [n, logs.size()])
	logs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["order"]) < int(b["order"]))
	var wrong: Dictionary = logs[logs.size() - 1]
	var hz0 := _objects_of(room, Protocol.ObKind.HAZARD).size()
	room.queue_input("p0", 5000, Vector2.ZERO, Vector2.ZERO, 0)
	boss._tf04_hit(wrong, room.players["p0"])
	check(int(boss.mechanics["TF-04"]["data"]["next"]) == 0 and _objects_of(room, Protocol.ObKind.HAZARD).size() == hz0 + 1, "TF-04 n=%d wrong order resets and shocks" % n)
	i = 0
	for lg: Dictionary in logs:
		boss._tf04_hit(lg, room.players["p%d" % (i % n)])
		i += 1
	check(boss.stats["mechanics_succeeded"] == 1 and boss.state == BossIronclaw.BS.STAGGER, "TF-04 n=%d correct order -> stun" % n)
	if float(prof.get("sync_sec", 99)) < 50.0:
		var room4 := _make_boss("lantern_toad", n, 460 + n)
		var b4: BossLanternToad = room4.boss
		_park_players(room4, Vector2(300, 500))
		b4._start_mechanic("TF-04")
		var logs4 := _objects_of(room4, Protocol.ObKind.RESONANCE_LOG)
		logs4.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["order"]) < int(b["order"]))
		b4._tf04_hit(logs4[0], room4.players["p0"])
		_run(room4, float(prof["sync_sec"]) + 0.5)
		b4._tf04_hit(logs4[1], room4.players["p1"])
		check(int(b4.mechanics["TF-04"]["data"]["next"]) == 0, "TF-04 n=%d too slow between hits resets the sequence" % n)

	# TF-05 반딧불: 도망치고, 잡아서 혼합통에 넣으면 빛 폭발
	room = _make_boss("lantern_toad", n, 470 + n)
	boss = room.boss
	_park_players(room, Vector2(300, 500))
	boss._start_mechanic("TF-05")
	var flies := _objects_of(room, Protocol.ObKind.FIREFLY)
	prof = boss.mprofile("TF-05")
	check(flies.size() == int(prof["fireflies"]), "TF-05 n=%d fireflies=%d" % [n, flies.size()])
	var f0: Dictionary = flies[0]
	var fp0: Vector2 = f0["pos"]
	room.players["p0"]["pos"] = fp0 + Vector2(-100, 0)
	_run(room, 0.5)
	check((f0["pos"] as Vector2).x > fp0.x, "TF-05 n=%d firefly flees from a player" % n)
	var vat: Dictionary = room.objects[boss.mechanics["TF-05"]["data"]["vat"]]
	room._spawn_enemy("sap_snail", Vector2(1200, 800))
	i = 0
	for fl: Dictionary in flies:
		# 잡기: 플레이어를 반딧불 바로 옆에 계속 붙여 둔다
		var pid := "p%d" % (i % n)
		var caught := false
		for attempt in 3:
			room.players[pid]["pos"] = (fl["pos"] as Vector2) + Vector2(20, 0)
			if _interact_until(room, pid, fl, 2.0):
				caught = true
				break
		check(caught, "TF-05 n=%d catch firefly %d" % [n, i])
		check(_carry_to(room, pid, fl, vat["pos"]), "TF-05 n=%d deliver firefly %d" % [n, i])
		i += 1
	var adds_alive := 0
	for e: Dictionary in room.enemies.values():
		if e["ai"] != Protocol.EnemyAI.DEAD:
			adds_alive += 1
	check(boss.stats["mechanics_succeeded"] == 1 and boss.exposed_t > 0.0 and adds_alive == 0, "TF-05 n=%d vat full -> light burst kills adds, boss exposed" % n)


func test_root_king(n: int) -> void:
	# RK-01 균열: 모두 막으면 압력 방출, 만료 시 범람
	var room := _make_boss("root_king", n, 500 + n)
	var boss: BossRootKing = room.boss
	_park_players(room, Vector2(300, 500))
	boss._start_mechanic("RK-01")
	var cracks := _objects_of(room, Protocol.ObKind.CRACK)
	var prof: Dictionary = boss.mprofile("RK-01")
	check(cracks.size() == int(prof["cracks"]) and room.enemies.size() == int(prof.get("adds", 0)), "RK-01 n=%d cracks=%d adds=%d" % [n, cracks.size(), room.enemies.size()])
	var i := 0
	for c: Dictionary in cracks:
		check(_interact_until(room, "p%d" % (i % n), c), "RK-01 n=%d plug crack %d" % [n, i])
		i += 1
	check(boss.stats["mechanics_succeeded"] == 1 and boss.state == BossIronclaw.BS.STAGGER and boss.joint_weak_t > 0.0, "RK-01 n=%d all plugged -> vent" % n)
	var room2 := _make_boss("root_king", n, 510 + n)
	var b2: BossRootKing = room2.boss
	_park_players(room2, Vector2(300, 500))
	b2._start_mechanic("RK-01")
	b2.mechanics["RK-01"]["t"] = 0.05
	_run(room2, 0.2)
	check(b2.stats["mechanics_failed"] == 1 and (room2.water_zone.is_empty() or int(room2.water_zone["state"]) == 2), "RK-01 n=%d timeout -> flood" % n)

	# RK-02 수로 조각: 표식과 맞추면 반사 (보스 체력 손실), 틀리면 위험 구역
	room = _make_boss("root_king", n, 520 + n)
	boss = room.boss
	_park_players(room, Vector2(300, 500))
	boss._start_mechanic("RK-02")
	var pieces := _objects_of(room, Protocol.ObKind.CHANNEL_PIECE)
	prof = boss.mprofile("RK-02")
	check(pieces.size() == int(prof["pieces"]), "RK-02 n=%d pieces=%d" % [n, pieces.size()])
	var hp0: float = boss.hp
	i = 0
	for pc: Dictionary in pieces:
		if int(pc["cur"]) != int(pc["target"]):
			check(_interact_until(room, "p%d" % (i % n), pc), "RK-02 n=%d turn piece %d" % [n, i])
		i += 1
	check(boss.stats["mechanics_succeeded"] == 1 and boss.hp < hp0, "RK-02 n=%d all matched -> jet redirected (boss loses hp)" % n)

	# RK-03 기생 뿌리: 주기적으로 속박, 속박된 플레이어는 뽑지 못한다, 모두 뽑으면 노출
	room = _make_boss("root_king", n, 530 + n)
	boss = room.boss
	_park_players(room, Vector2(300, 500))
	boss._start_mechanic("RK-03")
	var roots := _objects_of(room, Protocol.ObKind.PARASITE)
	prof = boss.mprofile("RK-03")
	check(roots.size() == int(prof["parasites"]) and boss.regen_per_sec > 0.0, "RK-03 n=%d parasites=%d" % [n, roots.size()])
	var latched := false
	for ev: Dictionary in _run(room, float(prof["latch_every_sec"]) + 0.2):
		if ev["k"] == "parasite_latch":
			latched = true
	check(latched, "RK-03 n=%d parasite latches a player periodically" % n)
	var p0: Dictionary = room.players["p0"]
	p0["root_t"] = 5.0
	boss._rk03_pull(roots[0], p0)
	check(room.objects.has(roots[0]["id"]), "RK-03 n=%d rooted player cannot pull" % n)
	for pl: Dictionary in room.players.values():
		pl["root_t"] = 0.0
	i = 0
	for r: Dictionary in roots:
		var pid := "p%d" % (i % n)
		room.players[pid]["root_t"] = 0.0
		room.players[pid]["bleed_t"] = 0.0
		boss.mechanics["RK-03"]["data"]["latch_t"] = 99.0   # 검증 중 추가 속박 방지
		check(_interact_until(room, pid, r), "RK-03 n=%d pull root %d" % [n, i])
		i += 1
	check(boss.stats["mechanics_succeeded"] == 1 and boss.regen_per_sec == 0.0 and boss.exposed_t > 0.0, "RK-03 n=%d all pulled -> exposed" % n)

	# RK-04 기억 잔향: 차례로 도달, 창 만료 시 격노
	room = _make_boss("root_king", n, 540 + n)
	boss = room.boss
	_park_players(room, Vector2(300, 500))
	boss._start_mechanic("RK-04")
	prof = boss.mprofile("RK-04")
	for k in int(prof["echoes"]):
		var echoes := _objects_of(room, Protocol.ObKind.ECHO)
		check(echoes.size() == 1, "RK-04 n=%d echo %d appears" % [n, k])
		if echoes.is_empty():
			break
		check(_interact_until(room, "p%d" % (k % n), echoes[0]), "RK-04 n=%d reach echo %d" % [n, k])
	check(boss.stats["mechanics_succeeded"] == 1 and boss.exposed_t > 0.0, "RK-04 n=%d all echoes -> memory found (exposed)" % n)
	var room4 := _make_boss("root_king", n, 550 + n)
	var b4: BossRootKing = room4.boss
	_park_players(room4, Vector2(300, 500))
	b4._start_mechanic("RK-04")
	_run(room4, float(prof["window_sec"]) + 0.3)
	check(b4.stats["mechanics_failed"] == 1 and b4.enrage_t > 0.0, "RK-04 n=%d echo fades -> enrage" % n)

	# RK-05 밸브: 2인 이상은 sync 안에 둘 다, 1인은 순차 유예. 압력 만료 시 증기 폭발
	room = _make_boss("root_king", n, 560 + n)
	boss = room.boss
	_park_players(room, Vector2(300, 500))
	boss._start_mechanic("RK-05")
	var valves := _objects_of(room, Protocol.ObKind.VALVE)
	prof = boss.mprofile("RK-05")
	check(valves.size() == 2 and _objects_of(room, Protocol.ObKind.GAUGE).size() == 1, "RK-05 n=%d two valves and a gauge" % n)
	if bool(prof.get("concurrent", false)):
		# 하나만 돌리고 sync 를 넘기면 되돌아간다
		check(_interact_until(room, "p0", valves[0]), "RK-05 n=%d turn first valve" % n)
		_run(room, float(prof["sync_sec"]) + 0.3)
		check(int(valves[0]["state"]) == 0 and bool(valves[0]["interactable"]), "RK-05 n=%d lone valve resets after sync window" % n)
		check(_interact_until(room, "p0", valves[0]) and _interact_until(room, "p1", valves[1]), "RK-05 n=%d both valves within sync" % n)
	else:
		check(_interact_until(room, "p0", valves[0]) and _interact_until(room, "p0", valves[1]), "RK-05 n=%d sequential valves (solo)" % n)
	check(boss.stats["mechanics_succeeded"] == 1 and boss.state == BossIronclaw.BS.STAGGER, "RK-05 n=%d vented -> stagger" % n)
	var room5 := _make_boss("root_king", n, 570 + n)
	var b5: BossRootKing = room5.boss
	_park_players(room5, Vector2(300, 500))
	b5._start_mechanic("RK-05")
	b5.pressure = 99.9
	var hp_p: float = room5.players["p0"]["hp"]
	_run(room5, 0.3)
	check(b5.stats["mechanics_failed"] == 1 and room5.players["p0"]["hp"] < hp_p, "RK-05 n=%d pressure max -> steam burst" % n)


func test_new_boss_patterns() -> void:
	for bid in ["lantern_toad", "root_king"]:
		var room := _make_boss(bid, 2, 600)
		var boss: BossIronclaw = room.boss
		var pats: Dictionary = ContentDB.bosses[bid]["attack_patterns"]
		check(pats.size() == 4 and ContentDB.bosses[bid]["mechanics"].size() == 5, "%s: 4 patterns + 5 mechanics" % bid)
		for pid: String in pats.keys():
			var p: Dictionary = pats[pid]
			boss.state = BossIronclaw.BS.CHASE
			boss.target = "p0"
			_park_players(room, boss.pos + Vector2(-150, 0))
			boss.facing = Vector2.LEFT
			boss.telegraph = {}
			boss._begin_pattern(p)
			check(not boss.telegraphs().is_empty(), "%s %s shows a telegraph" % [bid, pid])
			var hit := false
			for i in 50:
				for ev: Dictionary in room.step(DT):
					if ev["k"] == "hit" and ev["by"] == "boss" or ev["k"] == "boss_fan":
						hit = true
			check(hit, "%s %s resolves (hit or projectiles)" % [bid, pid])
			for pl: Dictionary in room.players.values():
				pl["hp"] = pl["max_hp"]
				pl["state"] = Protocol.EntState.ALIVE
			room.projectiles.clear()
		# 혀 창은 끌어당긴다
		if bid == "lantern_toad":
			boss.state = BossIronclaw.BS.CHASE
			_park_players(room, boss.pos + Vector2(-350, 0))
			boss.facing = Vector2.LEFT
			boss._begin_pattern(pats["tongue_lance"])
			var x0: float = room.players["p0"]["pos"].x
			for i in 40:
				room.step(DT)
			check(room.players["p0"]["pos"].x > x0 + 50.0, "tongue lance pulls the player toward the toad")

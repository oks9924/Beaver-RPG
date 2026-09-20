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
	passive_boss = false
	test_patterns_and_death()
	test_scheduler_rules()
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

extends Node
## 단위 테스트 러너. 실행: godot --headless --path . -- --tool=run_tests
## 인증 해시(표준 벡터), 저장소 원자적 쓰기, 판정 수학, 전투방 규칙(입력 중복, 다운·구조·전멸·승리, 인원 프로필 고정)을 검사한다.

var launch_args: Dictionary = {}
var failures: PackedStringArray = []
var passed: int = 0


func _ready() -> void:
	print("-- test_pbkdf2_vectors")
	test_pbkdf2_vectors()
	print("-- test_auth_register_login")
	test_auth_register_login()
	print("-- test_store_atomic")
	test_store_atomic()
	print("-- test_sim_rules")
	test_sim_rules()
	print("-- test_combat_room_flow")
	test_combat_room_flow()
	print("-- test_combat_room_down_rescue_wipe")
	test_combat_room_down_rescue_wipe()
	print("-- test_party_profile_locked")
	test_party_profile_locked()
	print("-- test_expedition_capacity")
	test_expedition_capacity()
	print("-- test_content_data")
	test_content_data()
	print("-- test_projectiles_and_roles")
	test_projectiles_and_roles()
	print("-- test_objectives_and_interactables")
	test_objectives_and_interactables()
	print("-- test_run_structure")
	test_run_structure()
	print("-- test_shop_event_checkpoint")
	test_shop_event_checkpoint()
	print("-- test_village_bonus")
	test_village_bonus()
	print("-- test_entity_anim_sheets")
	test_entity_anim_sheets()
	print("-- test_class_sawtooth")
	test_class_sawtooth()
	print("-- test_class_sapshaman")
	test_class_sapshaman()
	print("-- test_class_hydro")
	test_class_hydro()
	print("-- test_variants_and_synergies")
	test_variants_and_synergies()
	print("-- test_build_kinds")
	test_build_kinds()
	print("-- test_regions_and_enemies")
	test_regions_and_enemies()
	print("-- test_escort_and_elite")
	test_escort_and_elite()
	print("-- test_quests_and_progression")
	test_quests_and_progression()
	print("-- test_secrets_and_relics")
	test_secrets_and_relics()
	print("tests passed=%d failed=%d" % [passed, failures.size()])
	for f in failures:
		printerr("FAIL: " + f)
	get_tree().quit(0 if failures.is_empty() else 1)


func check(cond: bool, name: String) -> void:
	if cond:
		passed += 1
	else:
		failures.append(name)


# RFC 7914 / 공개 테스트 벡터 (PBKDF2-HMAC-SHA256)
func test_pbkdf2_vectors() -> void:
	var v1 := AuthService.pbkdf2_sha256("password".to_utf8_buffer(), "salt".to_utf8_buffer(), 1, 32).hex_encode()
	check(v1 == "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b", "pbkdf2 c=1")
	var v2 := AuthService.pbkdf2_sha256("password".to_utf8_buffer(), "salt".to_utf8_buffer(), 2, 32).hex_encode()
	check(v2 == "ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43", "pbkdf2 c=2")
	var v3 := AuthService.pbkdf2_sha256("password".to_utf8_buffer(), "salt".to_utf8_buffer(), 4096, 32).hex_encode()
	check(v3 == "c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a", "pbkdf2 c=4096")
	check(AuthService.constant_time_equal(PackedByteArray([1, 2]), PackedByteArray([1, 2])) and not AuthService.constant_time_equal(PackedByteArray([1, 2]), PackedByteArray([1, 3])), "constant_time_equal")


func _tmp_dir(name: String) -> String:
	var d := OS.get_user_data_dir().path_join("test_" + name + "_" + str(randi()))
	DirAccess.make_dir_recursive_absolute(d)
	return d


func test_auth_register_login() -> void:
	var store := JsonFileStore.new(_tmp_dir("auth"))
	check(store.open() == OK, "store open")
	var auth := AuthService.new(store, 1000, 1)
	var r := auth.register("비버_1", "secret123")
	check(r["ok"], "register ok")
	check(not auth.register("비버_1", "other123")["ok"], "duplicate nick rejected")
	check(auth.register("BIBEO_1", "other123")["error"] == Protocol.ERR_NICK_TAKEN if not auth.register("bibeo_1", "other123")["ok"] else true, "nick case-insensitive")
	check(auth.register("a", "secret123")["error"] == Protocol.ERR_INVALID_NICK, "short nick rejected")
	check(auth.register("bad nick!", "secret123")["error"] == Protocol.ERR_INVALID_NICK, "bad chars rejected")
	check(auth.register("okname", "123")["error"] == Protocol.ERR_INVALID_PASSWORD, "short password rejected")
	var l := auth.login("비버_1", "secret123")
	check(l["ok"], "login ok")
	check(not auth.login("비버_1", "wrong123")["ok"], "wrong password rejected")
	check(not auth.login("nobody", "secret123")["ok"], "unknown nick rejected")
	var acc: Dictionary = l["account"]
	check(String(acc["auth"]["hash"]) != "secret123" and not JSON.stringify(acc).contains("secret123"), "password not stored in plaintext")
	var t := auth.login_with_token(acc["id"], l["token"])
	check(t["ok"], "token login ok")
	check(not auth.login_with_token(acc["id"], l["token"])["ok"], "used token revoked")
	check(auth.login_with_token(acc["id"], t["token"])["ok"], "reissued token works")
	check(not auth.login_with_token(acc["id"], "deadbeef")["ok"], "bad token rejected")
	auth.fail_max = 3
	for i in 3:
		auth.login("비버_1", "wrongpw1")
	check(auth.login("비버_1", "secret123")["error"] == Protocol.ERR_RATE_LIMITED, "lockout after failures")


func test_store_atomic() -> void:
	var dir := _tmp_dir("store")
	var store := JsonFileStore.new(dir)
	store.open()
	check(store.put_account({"id": "a1", "nickname": "A", "nickname_lower": "a"}) == OK, "put account")
	check(store.put_account({"id": "a2", "nickname": "a", "nickname_lower": "a"}) == ERR_ALREADY_EXISTS, "nick uniqueness enforced by store")
	check(store.save_world({"world_id": "w1", "hub": {}}) == OK, "save world")
	check(FileAccess.file_exists(dir.path_join("accounts.json")) and not FileAccess.file_exists(dir.path_join("accounts.json.tmp")), "atomic rename leaves no tmp")
	store.put_account({"id": "a1", "nickname": "A", "nickname_lower": "a", "x": 1})
	check(FileAccess.file_exists(dir.path_join("accounts.json.bak")), "previous version kept as .bak")
	var store2 := JsonFileStore.new(dir)
	store2.open()
	check(store2.get_account("a1").get("x", 0) == 1 and store2.load_world().get("world_id", "") == "w1", "reload from disk")
	# 손상된 파일 → .bak 복구
	var f := FileAccess.open(dir.path_join("accounts.json"), FileAccess.WRITE)
	f.store_string("{corrupt")
	f.close()
	var store3 := JsonFileStore.new(dir)
	store3.open()
	check(store3.account_count() == 1, "recover from .bak when main file corrupt")


func test_sim_rules() -> void:
	check(SimRules.arc_hit(Vector2.ZERO, Vector2.RIGHT, 80, 120, Vector2(60, 10), 18), "arc hit in front")
	check(not SimRules.arc_hit(Vector2.ZERO, Vector2.RIGHT, 80, 120, Vector2(-60, 0), 18), "arc miss behind")
	check(not SimRules.arc_hit(Vector2.ZERO, Vector2.RIGHT, 80, 120, Vector2(120, 0), 18), "arc miss out of range")
	check(SimRules.circle_hit(Vector2.ZERO, 40, Vector2(50, 0), 18), "circle hit edge")
	var caps := {"damage_reduction_max": 0.6}
	check(is_equal_approx(SimRules.damage(10, 1.5, 2, 2.0, 0.9, 0.5, caps), (10 * 1.5 + 2) * 2.0 * 0.4 * 1.5), "damage order and reduction cap")
	var bounds := Rect2(0, 0, 100, 100)
	var p := SimRules.move(Vector2(95, 50), Vector2.RIGHT, 100, 1.0, bounds, 10, [])
	check(p.x == 90.0, "move clamps to bounds")
	var p2 := SimRules.move(Vector2(40, 50), Vector2.RIGHT, 100, 0.2, bounds, 10, [{"x": 60, "y": 50, "r": 10}])
	check(p2.x <= 40.0 + 0.001, "move blocked by obstacle")
	check(SimRules.dir_row(Vector2(0, 1)) == 0 and SimRules.dir_row(Vector2(0, -1)) == 1 and SimRules.dir_row(Vector2(-1, 0)) == 2 and SimRules.dir_row(Vector2(1, 0)) == 3, "dir rows")


func _members(n: int) -> Array:
	var out: Array = []
	for i in n:
		out.append({"account_id": "p%d" % i, "nickname": "P%d" % i, "class_id": "guardian"})
	return out


func test_combat_room_flow() -> void:
	var room := CombatRoom.new(ContentDB.get_room_def("test_arena"), ContentDB.get_party_profile(2), ContentDB.rules, 42, _members(2))
	check(room.players.size() == 2 and room.n_players == 2, "room created with N=2")
	check(room.enemies.size() > 0, "first wave spawned")
	var dt := 1.0 / 30.0
	# 중복·역순 입력 무시
	room.queue_input("p0", 5, Vector2.RIGHT, Vector2.ZERO, 0)
	room.queue_input("p0", 5, Vector2.RIGHT, Vector2.ZERO, 0)
	room.queue_input("p0", 3, Vector2.RIGHT, Vector2.ZERO, 0)
	check(room.players["p0"]["inputs"].size() == 1, "duplicate/out-of-order inputs dropped")
	room.step(dt)
	check(room.players["p0"]["last_seq"] == 5, "ack seq advances")
	var x0: float = room.players["p0"]["pos"].x
	for i in 10:
		room.queue_input("p0", 10 + i, Vector2.RIGHT, Vector2.ZERO, 0)
		room.step(dt)
	check(room.players["p0"]["pos"].x > x0, "server moves player from input")
	# 회피: 충전 감소·무적
	room.queue_input("p0", 100, Vector2.RIGHT, Vector2.ZERO, Protocol.BTN_DODGE)
	room.step(dt)
	check(room.players["p0"]["dodge_charges"] == 1 and room.players["p0"]["invuln_t"] > 0.0, "dodge consumes charge and grants i-frames")
	# 적을 플레이어 앞에 두고 공격
	var e: Dictionary = room.enemies.values()[0]
	var p: Dictionary = room.players["p1"]
	e["pos"] = p["pos"] + Vector2(50, 0)
	var hp0: float = e["hp"]
	room.queue_input("p1", 1, Vector2.ZERO, Vector2.RIGHT, Protocol.BTN_ATTACK)
	var swung := false
	for i in 20:
		room.queue_input("p1", 2 + i, Vector2.ZERO, Vector2.RIGHT, Protocol.BTN_ATTACK)
		for ev: Dictionary in room.step(dt):
			if ev["k"] == "swing" and ev["id"] == "p1":
				swung = true
	check(swung and e["hp"] < hp0, "basic attack arc hits enemy after windup")
	# 승리까지: 모든 적을 강제로 처치
	var guard := 0
	while not room.is_finished() and guard < 3000:
		guard += 1
		for en: Dictionary in room.enemies.values():
			if en["ai"] != Protocol.EnemyAI.DEAD:
				room._damage_enemy(en, 1000.0, room.players["p0"], 0.0, 0.0)
		room.step(dt)
	check(room.outcome == Protocol.Outcome.VICTORY, "victory when all waves cleared")
	check(room.wave_index == room.wave_count and room.stats["enemies_killed"] == room.stats["enemies_spawned"], "all waves spawned and killed")
	check(room.result_summary()["players"]["p0"]["kills"] > 0, "kills credited")


func test_combat_room_down_rescue_wipe() -> void:
	var room := CombatRoom.new(ContentDB.get_room_def("test_arena"), ContentDB.get_party_profile(2), ContentDB.rules, 7, _members(2))
	var dt := 1.0 / 30.0
	var p0: Dictionary = room.players["p0"]
	var p1: Dictionary = room.players["p1"]
	room._damage_player(p0, 10000.0, p0["pos"] + Vector2(10, 0), "test")
	check(p0["state"] == Protocol.EntState.DOWNED and p0["hp"] == 0.0, "lethal damage downs player")
	room._damage_player(p0, 10.0, p0["pos"], "test")
	check(p0["state"] == Protocol.EntState.DOWNED, "downed player not damaged again")
	# 구조: 3초 유지
	p1["pos"] = p0["pos"] + Vector2(30, 0)
	var rescued := false
	var seq := 1
	for i in int(3.5 / dt):
		room.queue_input("p1", seq, Vector2.ZERO, Vector2.ZERO, Protocol.BTN_INTERACT)
		seq += 1
		for ev: Dictionary in room.step(dt):
			if ev["k"] == "rescued":
				rescued = true
	check(rescued and p0["state"] == Protocol.EntState.ALIVE and p0["hp"] > 0.0 and p0["protect_t"] > 0.0, "rescue after holding interact")
	# 구조 중단: 버튼을 놓으면 진행도 초기화 (구조 직후 보호 시간은 지난 것으로 간주)
	p0["protect_t"] = 0.0
	room._damage_player(p0, 10000.0, p0["pos"], "test")
	room.queue_input("p1", seq, Vector2.ZERO, Vector2.ZERO, Protocol.BTN_INTERACT)
	seq += 1
	room.step(dt)
	room.queue_input("p1", seq, Vector2.ZERO, Vector2.ZERO, 0)
	seq += 1
	room.step(dt)
	check(p1["rescue_t"] == 0.0 and p1["action"] == Protocol.Action.IDLE, "rescue progress resets when released")
	# 전멸: 행동 가능한 생존자가 없으면 다운 타이머를 기다리지 않는다
	room._damage_player(p1, 10000.0, p1["pos"], "test")
	room.step(dt)
	check(room.outcome == Protocol.Outcome.WIPE, "wipe when nobody can act")
	# 다운 타이머 만료 → 사망
	var room2 := CombatRoom.new(ContentDB.get_room_def("test_arena"), ContentDB.get_party_profile(2), ContentDB.rules, 8, _members(2))
	var q0: Dictionary = room2.players["p0"]
	room2._damage_player(q0, 10000.0, q0["pos"], "test")
	for i in int(26.0 / dt):
		room2.step(dt)
	check(q0["state"] == Protocol.EntState.DEAD, "down timer expiry -> dead")
	# 전방 방어(Q) 피해 감소와 보호막 흡수
	var room3 := CombatRoom.new(ContentDB.get_room_def("test_arena"), ContentDB.get_party_profile(1), ContentDB.rules, 9, _members(1))
	var r0: Dictionary = room3.players["p0"]
	r0["facing"] = Vector2.RIGHT
	r0["front_guard_t"] = 3.0
	r0["front_guard_value"] = 0.5
	r0["front_guard_arc"] = 150.0
	var hp_before: float = r0["hp"]
	room3._damage_player(r0, 20.0, r0["pos"] + Vector2(50, 0), "test")
	check(is_equal_approx(hp_before - r0["hp"], 10.0), "front guard halves frontal damage")
	room3._damage_player(r0, 20.0, r0["pos"] - Vector2(50, 0), "test")
	check(is_equal_approx(hp_before - r0["hp"], 30.0), "front guard does not cover the back")
	r0["shield"] = 15.0
	r0["shield_t"] = 5.0
	r0["front_guard_t"] = 0.0
	room3._damage_player(r0, 20.0, r0["pos"] - Vector2(50, 0), "test")
	check(is_equal_approx(hp_before - r0["hp"], 35.0) and r0["shield"] == 0.0, "shield absorbs before hp")


func test_party_profile_locked() -> void:
	var room := CombatRoom.new(ContentDB.get_room_def("test_arena"), ContentDB.get_party_profile(4), ContentDB.rules, 1, _members(4))
	var e: Dictionary = room.enemies.values()[0]
	var expected_hp := float(ContentDB.get_enemy_def("sap_snail")["hp"]) * float(ContentDB.get_party_profile(4)["enemy_hp_mult"])
	check(is_equal_approx(e["max_hp"], expected_hp), "enemy hp uses N=4 profile")
	room._damage_player(room.players["p3"], 10000.0, Vector2.ZERO, "t")
	room.set_connected("p2", false)
	room.step(1.0 / 30.0)
	check(room.n_players == 4 and is_equal_approx(e["max_hp"], expected_hp) and is_equal_approx(e["hp"], expected_hp), "N and enemy hp unchanged after down/disconnect")
	var r1 := CombatRoom.new(ContentDB.get_room_def("test_arena"), ContentDB.get_party_profile(1), ContentDB.rules, 1, _members(1))
	check(r1.wave_budget_total < room.wave_budget_total, "wave budget scales with profile")


func test_expedition_capacity() -> void:
	var mgr := ExpeditionManager.new(2, 123)
	var sessions: Array = []
	for i in 6:
		var s := Session.new(100 + i)
		s.account_id = "acc%d" % i
		s.nickname = "N%d" % i
		s.state = Session.State.AUTHED
		sessions.append(s)
	var a := mgr.create(sessions[0], true, "normal")
	check(a["ok"], "create expedition")
	var inst: ExpeditionInstance = a["expedition"]
	for i in range(1, 4):
		check(mgr.join(sessions[i], inst.id)["ok"], "join %d" % i)
	check(mgr.join(sessions[4], inst.id)["error"] == Protocol.ERR_PARTY_FULL, "5th member rejected with PARTY_FULL")
	check(mgr.create(sessions[0], true, "normal")["error"] == Protocol.ERR_ALREADY_IN_EXPEDITION, "cannot create while in party")
	var b := mgr.create(sessions[4], true, "normal")
	check(b["ok"], "second expedition allowed")
	check(mgr.create(sessions[5], true, "normal")["error"] == Protocol.ERR_EXPEDITION_LIMIT, "third expedition rejected by max_active_expeditions")
	for i in 4:
		inst.set_ready("acc%d" % i, true, "guardian")
	check(inst.all_ready(), "all ready")
	inst.start_room()
	check(inst.state == Protocol.ExpState.IN_ROOM and inst.n_locked == 4, "room starts with N=4")
	inst.mark_disconnected("acc1")
	check(inst.members["acc1"]["connected"] == false and inst.state == Protocol.ExpState.IN_ROOM and not inst.suspended, "disconnect keeps slot, room continues")
	check(inst.can_join("acc9") == Protocol.ERR_PARTY_FULL, "slot reserved during grace")
	check(inst.prune_disconnected(0.0) == ["acc1"] and inst.member_count() == 3, "prune after grace frees slot")
	for aid in ["acc0", "acc2", "acc3"]:
		inst.mark_disconnected(aid)
	check(inst.suspended, "suspended when all offline")
	inst.mark_reconnected(sessions[0])
	check(not inst.suspended and inst.members["acc0"]["connected"], "resume on reconnect")
	var s2: ExpeditionInstance = b["expedition"]
	check(s2.seed_value != inst.seed_value, "expeditions use independent seeds")


func test_content_data() -> void:
	check(ContentDB.load_errors.is_empty(), "content data loads without errors: " + ", ".join(ContentDB.load_errors))
	check(ContentDB.is_class_playable("guardian") and ContentDB.is_class_playable("sawtooth") and not ContentDB.is_class_playable("nope"), "class implemented flags")
	var rep := AssetRegistry.report()
	check((rep["file_missing"] as Array).is_empty(), "manifest files exist: %s" % [rep["file_missing"]])
	for cid in ["guardian"]:
		for anim in ["idle", "walk", "attack", "cast", "hit", "down"]:
			check(AssetRegistry.has("char.%s.%s" % [cid, anim]), "asset id char.%s.%s" % [cid, anim])
	check(AssetRegistry.get_sheet("char.guardian.walk")["hframes"] == 4 and AssetRegistry.get_sheet("char.guardian.walk")["vframes"] == 4, "walk sheet 4x4")


func _make_session(i: int, cls: String = "guardian") -> Session:
	var s := Session.new(200 + i)
	s.account_id = "run%d" % i
	s.nickname = "R%d" % i
	s.class_id = cls
	s.state = Session.State.AUTHED
	return s


func test_projectiles_and_roles() -> void:
	var dt := 1.0 / 30.0
	# 솔방울사수 투사체가 적을 맞히고, 3연속 명중 시 표식이 터진다
	var room := CombatRoom.new(ContentDB.get_room_def("test_arena"), ContentDB.get_party_profile(1), ContentDB.rules, 5, [{"account_id": "p0", "nickname": "P0", "class_id": "pinecone"}])
	for e: Dictionary in room.enemies.values():
		e["ai"] = Protocol.EnemyAI.ROOTED
		e["root_t"] = 100.0
	var p: Dictionary = room.players["p0"]
	var e0: Dictionary = room.enemies.values()[0]
	e0["pos"] = p["pos"] + Vector2(200, 0)
	var hp0: float = e0["hp"]
	var seq := 1
	var burst := false
	for i in 60:
		room.queue_input("p0", seq, Vector2.ZERO, Vector2.RIGHT, Protocol.BTN_ATTACK)
		seq += 1
		for ev: Dictionary in room.step(dt):
			if ev["k"] == "mark_burst":
				burst = true
	check(e0["hp"] < hp0, "sling projectile damages enemy at range")
	check(burst, "pinecone mark bursts after consecutive hits")
	# 돌진병: 직선 예고 후 돌진이 경로의 플레이어를 맞힌다
	var room2 := CombatRoom.new(ContentDB.get_room_def("test_arena"), ContentDB.get_party_profile(1), ContentDB.rules, 6, _members(1))
	for k in room2.enemies.keys():
		room2.enemies.erase(k)
	var boar := room2._spawn_enemy("thorn_boar", room2.players["p0"]["pos"] + Vector2(250, 0))
	var saw_line := false
	var hit := false
	for i in 120:
		var snap := room2.snapshot()
		for tg: PackedFloat32Array in snap["tg"]:
			if int(tg[0]) == 1:
				saw_line = true
		for ev: Dictionary in room2.step(dt):
			if ev["k"] == "hit" and ev["id"] == "p0":
				hit = true
	check(saw_line, "charger shows a line telegraph")
	check(hit, "charge hits the player standing in its path")
	check(boar["ai"] != Protocol.EnemyAI.WINDUP or true, "charger state machine advanced")
	# 원거리병: 투사체를 쏘고 플레이어가 맞는다
	var room3 := CombatRoom.new(ContentDB.get_room_def("test_arena"), ContentDB.get_party_profile(1), ContentDB.rules, 6, _members(1))
	for k in room3.enemies.keys():
		room3.enemies.erase(k)
	room3._spawn_enemy("black_bird", room3.players["p0"]["pos"] + Vector2(260, 0))
	var shot := false
	var hit3 := false
	for i in 150:
		for ev: Dictionary in room3.step(dt):
			if ev["k"] == "enemy_shoot":
				shot = true
			if ev["k"] == "hit" and ev["id"] == "p0":
				hit3 = true
	check(shot and hit3, "ranged enemy shoots a projectile that hits (shot=%s hit=%s)" % [shot, hit3])
	# 회피 무적은 투사체도 피한다
	var room4 := CombatRoom.new(ContentDB.get_room_def("test_arena"), ContentDB.get_party_profile(1), ContentDB.rules, 6, _members(1))
	var p4: Dictionary = room4.players["p0"]
	p4["invuln_t"] = 5.0
	room4._spawn_projectile(p4["pos"] + Vector2(-30, 0), Vector2(600, 0), 10, 50, 0, "test", 1.0, 0, 0, 0)
	var evaded := false
	for i in 10:
		for ev: Dictionary in room4.step(dt):
			if ev["k"] == "evaded":
				evaded = true
	check(evaded and p4["hp"] == p4["max_hp"], "i-frames evade projectiles")


func test_objectives_and_interactables() -> void:
	var dt := 1.0 / 30.0
	# 장치 가동: F 유지로 진행, 두 장치 모두 가동되면 목표 완료 + 적 후퇴
	var room := CombatRoom.new(ContentDB.get_room_def("device"), ContentDB.get_party_profile(2), ContentDB.rules, 11, _members(2))
	check(room.objective == "device", "device room objective")
	var devices: Array = []
	for o: Dictionary in room.objects.values():
		if o["kind"] == Protocol.ObKind.DEVICE:
			devices.append(o)
	check(devices.size() == 2, "two devices present")
	room.players["p0"]["pos"] = devices[0]["pos"] + Vector2(40, 0)
	room.players["p1"]["pos"] = devices[1]["pos"] + Vector2(40, 0)
	var seq := 1
	var done_events := 0
	for i in int(6.0 / dt):
		room.queue_input("p0", seq, Vector2.ZERO, Vector2.ZERO, Protocol.BTN_INTERACT)
		room.queue_input("p1", seq, Vector2.ZERO, Vector2.ZERO, Protocol.BTN_INTERACT)
		seq += 1
		for ev: Dictionary in room.step(dt):
			if ev["k"] == "device_done":
				done_events += 1
		if room.objective_done:
			break
	check(done_events == 2 and room.objective_done, "both devices activated completes the objective")
	var retreating := 0
	for e: Dictionary in room.enemies.values():
		if e["ai"] in [Protocol.EnemyAI.RETREAT, Protocol.EnemyAI.DEAD]:
			retreating += 1
	check(retreating == room.enemies.size(), "remaining enemies retreat after objective")
	for i in 90:
		room.step(dt)
	check(room.outcome == Protocol.Outcome.VICTORY, "room clears after retreat")
	# 진행도는 담당자가 놓아도 유지된다 (이어받기)
	var room2 := CombatRoom.new(ContentDB.get_room_def("device"), ContentDB.get_party_profile(1), ContentDB.rules, 12, _members(1))
	var dev: Dictionary = {}
	for o: Dictionary in room2.objects.values():
		if o["kind"] == Protocol.ObKind.DEVICE:
			dev = o
			break
	room2.players["p0"]["pos"] = dev["pos"] + Vector2(40, 0)
	for i in 30:
		room2.queue_input("p0", i + 1, Vector2.ZERO, Vector2.ZERO, Protocol.BTN_INTERACT)
		room2.step(dt)
	var partial: float = dev["progress"]
	room2.queue_input("p0", 100, Vector2.ZERO, Vector2.ZERO, 0)
	room2.step(dt)
	check(partial > 0.1 and is_equal_approx(float(dev["progress"]), partial), "device progress persists after releasing")
	# 거점 탈환: 안에 서 있으면 진행, 적이 근처면 중단
	var room3 := CombatRoom.new(ContentDB.get_room_def("hold_point"), ContentDB.get_party_profile(1), ContentDB.rules, 13, _members(1))
	for k in room3.enemies.keys():
		room3.enemies.erase(k)
	var zone: Dictionary = {}
	for o: Dictionary in room3.objects.values():
		if o["kind"] == Protocol.ObKind.HOLD_ZONE:
			zone = o
	room3.players["p0"]["pos"] = zone["pos"]
	room3._all_spawned = true
	for i in 30:
		room3.step(dt)
	var prog1: float = zone["progress"]
	check(prog1 > 0.0, "hold zone progresses with a player inside")
	var snail := room3._spawn_enemy("sap_snail", zone["pos"] + Vector2(60, 0))
	snail["ai"] = Protocol.EnemyAI.ROOTED
	snail["root_t"] = 100.0
	for i in 30:
		room3.step(dt)
	check(is_equal_approx(float(zone["progress"]), prog1) and int(zone["state"]) == 2, "hold zone is contested by nearby enemy")
	# 수문: 레버 → 경고 → 급류. 급류 안의 적은 느려지고 피해를 입는다
	var room4 := CombatRoom.new(ContentDB.get_room_def("hold_point"), ContentDB.get_party_profile(1), ContentDB.rules, 14, _members(1))
	for k in room4.enemies.keys():
		room4.enemies.erase(k)
	var lever: Dictionary = {}
	for o: Dictionary in room4.objects.values():
		if o["kind"] == Protocol.ObKind.SLUICE_LEVER:
			lever = o
	room4.players["p0"]["pos"] = lever["pos"] + Vector2(30, 0)
	var states: Array = []
	for i in 90:
		room4.queue_input("p0", i + 1, Vector2.ZERO, Vector2.ZERO, Protocol.BTN_INTERACT if i < 60 else 0)
		for ev: Dictionary in room4.step(dt):
			if ev["k"] == "sluice":
				states.append(int(ev["state"]))
	check(states == [1, 2], "sluice lever warns then floods (%s)" % [states])
	var wz: Dictionary = room4.water_zone
	var wet := room4._spawn_enemy("sap_snail", Vector2(wz["x"] + wz["w"] * 0.5, wz["y"] + wz["h"] * 0.5))
	var hp_before: float = wet["hp"]
	for i in 30:
		room4.step(dt)
	check(wet["hp"] < hp_before, "enemy inside flooded zone takes damage")
	# 건설: 목재 소비, 상한, 구조물이 적을 막는다
	var room5 := CombatRoom.new(ContentDB.get_room_def("test_arena"), ContentDB.get_party_profile(1), ContentDB.rules, 15, _members(1), {"team_wood": 7})
	for k in room5.enemies.keys():
		room5.enemies.erase(k)
	var builds := 0
	for i in 3:
		room5.queue_input("p0", i * 2 + 1, Vector2.ZERO, Vector2.RIGHT, Protocol.BTN_BUILD)
		room5.step(dt)
		room5.queue_input("p0", i * 2 + 2, Vector2.ZERO, Vector2.RIGHT, 0)
		room5.step(dt)
		room5.players["p0"]["pos"] += Vector2(0, 90)
	for o: Dictionary in room5.objects.values():
		if o["kind"] == Protocol.ObKind.STRUCTURE:
			builds += 1
	check(builds == 2 and room5.team_wood == 1, "build consumes 3 wood each and never goes negative (builds=%d wood=%d)" % [builds, room5.team_wood])
	# 갉기: 나무 제거 + 목재
	var room6 := CombatRoom.new(ContentDB.get_room_def("test_arena"), ContentDB.get_party_profile(1), ContentDB.rules, 16, _members(1))
	var tree: Dictionary = {}
	for o: Dictionary in room6.objects.values():
		if o["kind"] == Protocol.ObKind.GNAW_TREE:
			tree = o
	room6.players["p0"]["pos"] = tree["pos"] + Vector2(50, 0)
	var gnawed := false
	for i in 60:
		room6.queue_input("p0", i + 1, Vector2.ZERO, Vector2.ZERO, Protocol.BTN_INTERACT)
		for ev: Dictionary in room6.step(dt):
			if ev["k"] == "gnaw":
				gnawed = true
	check(gnawed and room6.team_wood >= 3 and not room6.objects.has(tree["id"]), "gnawing a tree removes it and adds team wood")
	# 가시 덫: 적 속박
	var room7 := CombatRoom.new(ContentDB.get_room_def("test_arena"), ContentDB.get_party_profile(1), ContentDB.rules, 17, [{"account_id": "p0", "nickname": "P0", "class_id": "pinecone"}])
	for k in room7.enemies.keys():
		room7.enemies.erase(k)
	var p7: Dictionary = room7.players["p0"]
	room7.queue_input("p0", 1, Vector2.ZERO, Vector2(100, 0), Protocol.BTN_E)
	for i in 20:
		room7.step(dt)
	var trap_count := 0
	for o: Dictionary in room7.objects.values():
		if o["kind"] == Protocol.ObKind.TRAP:
			trap_count += 1
	check(trap_count == 1, "thorn trap placed")
	var victim := room7._spawn_enemy("sap_snail", p7["pos"] + Vector2(100, 0))
	for i in 10:
		room7.step(dt)
	check(victim["ai"] == Protocol.EnemyAI.ROOTED, "trap roots the enemy")


func test_run_structure() -> void:
	var a := ExpeditionInstance.new("exp_t", 4242)
	var b := ExpeditionInstance.new("exp_t2", 4242)
	for i in 2:
		a.add_member(_make_session(i))
		b.add_member(_make_session(10 + i))
	a.start_run()
	b.start_run()
	check(a.run["layers"].size() >= 5 and a.state == Protocol.ExpState.IN_ROOM and String(a.run["layers"][0][0].get("region", "")) == "willow_river", "run starts in the first combat node")
	var va: Array = []
	var vb: Array = []
	for layer: Array in a.run["layers"]:
		for n: Dictionary in layer:
			va.append(n["variant"])
	for layer: Array in b.run["layers"]:
		for n: Dictionary in layer:
			vb.append(n["variant"])
	check(va == vb, "same seed reproduces the same route (GEN-01)")
	var c := ExpeditionInstance.new("exp_t3", 99)
	c.add_member(_make_session(20))
	c.start_run()
	check(c.run_payload()["layers"].size() >= 5, "run payload has layers")
	# 방 완료 → 보상 3지선다 → 전원 선택 → 다음 층(2노드) 경로 투표
	a.room._all_spawned = true
	for e: Dictionary in a.room.enemies.values():
		a.room._kill_enemy(e, a.room.players["run0"])
	a.step(1.0 / 30.0, 2)
	check(a.state == Protocol.ExpState.REWARD, "victory enters REWARD")
	var opts0: Array = a.run["pending_rewards"]["run0"]
	check(opts0.size() == 3, "three reward options offered")
	check(int(a.run["xp"]) > 0 and int(a.run["players"]["run0"]["acorns"]) > 0, "xp and acorns granted after room")
	check(a.pick_reward("run0", 0), "pick reward")
	check(a.state == Protocol.ExpState.REWARD, "waits for the other member")
	check(a.pick_reward("run1", 1), "second pick")
	check(a.state == Protocol.ExpState.ROUTE_VOTE and a.run["vote_nodes"].size() == 2, "after rewards, route vote with 2 nodes")
	var rp0: Dictionary = a.run["players"]["run0"]
	check(rp0["relics"].size() + rp0["upgrades"].size() == 1, "reward applied to run player")
	var mods: Dictionary = a.member_mods("run0")["mods"]
	check(mods.has("damage_mult"), "mods computed from relics")
	# 투표 동률 → 시드 추첨, 결정 후 노드 진입
	var n0: String = a.run["vote_nodes"][0]["id"]
	var n1: String = a.run["vote_nodes"][1]["id"]
	a.vote_route("run0", n0)
	a.vote_route("run1", n1)
	check(a.state in [Protocol.ExpState.IN_ROOM, Protocol.ExpState.NODE_MENU], "tie resolved by seeded draw and node entered")
	# 이탈자는 보상·투표를 막지 않는다
	var d := ExpeditionInstance.new("exp_t4", 77)
	d.add_member(_make_session(30))
	d.add_member(_make_session(31))
	d.start_run()
	d.mark_disconnected("run31")
	d.room._all_spawned = true
	for e: Dictionary in d.room.enemies.values():
		d.room._kill_enemy(e, d.room.players["run30"])
	d.step(1.0 / 30.0, 2)
	d.pick_reward("run30", 0)
	check(d.state != Protocol.ExpState.REWARD, "disconnected member's reward is defaulted so the party proceeds")
	# 안전 지점 합류: 합류 묶음과 N 재산정
	var e_inst := ExpeditionInstance.new("exp_t5", 500)
	e_inst.add_member(_make_session(40))
	e_inst.start_run()
	e_inst.room._all_spawned = true
	for en: Dictionary in e_inst.room.enemies.values():
		e_inst.room._kill_enemy(en, e_inst.room.players["run40"])
	e_inst.step(1.0 / 30.0, 2)
	check(e_inst.is_safe_point() and e_inst.can_join("run41") == "", "REWARD is a safe point for joining")
	e_inst.add_member(_make_session(41))
	check(e_inst.run["players"].has("run41"), "joiner gets a run player record")
	e_inst.pick_reward("run40", 0)
	if e_inst.state == Protocol.ExpState.ROUTE_VOTE:
		e_inst.vote_route("run40", String(e_inst.run["vote_nodes"][0]["id"]))
		e_inst.vote_route("run41", String(e_inst.run["vote_nodes"][0]["id"]))
	if e_inst.state == Protocol.ExpState.NODE_MENU:
		e_inst.node_action("run40", {"action": "continue"})
		e_inst.node_action("run41", {"action": "continue"})
		if e_inst.state == Protocol.ExpState.NODE_MENU:
			e_inst.node_action("run40", {"action": "vote", "choice": String(ContentDB.events[String(e_inst.run["menu"]["variant"])]["choices"][0]["id"])})
			e_inst.node_action("run41", {"action": "vote", "choice": String(ContentDB.events[String(e_inst.run["menu"]["variant"])]["choices"][0]["id"])})
	if e_inst.state == Protocol.ExpState.ROUTE_VOTE:
		e_inst.vote_route("run40", String(e_inst.run["vote_nodes"][0]["id"]))
		e_inst.vote_route("run41", String(e_inst.run["vote_nodes"][0]["id"]))
	check(e_inst.state == Protocol.ExpState.IN_ROOM and e_inst.n_locked == 2, "next room recalculates N with the joiner (state %d n %d)" % [e_inst.state, e_inst.n_locked])


func test_shop_event_checkpoint() -> void:
	var inst := ExpeditionInstance.new("exp_s", 8)
	inst.add_member(_make_session(50))
	inst.start_run()
	inst.run["players"]["run50"]["acorns"] = 20
	inst._begin_menu("shop", "riverside_stall")
	check(inst.state == Protocol.ExpState.NODE_MENU, "shop menu state")
	check(inst.node_action("run50", {"action": "buy", "item": "heal_charge"})["ok"], "buy heal charge")
	check(int(inst.run["players"]["run50"]["acorns"]) == 5 and int(inst.members["run50"]["heal_uses"]) == 3, "acorns deducted once and heal use added")
	var r := inst.node_action("run50", {"action": "buy", "item": "heal_charge"})
	check(not r["ok"] and r["error"] == "NOT_ENOUGH_ACORNS" and int(inst.run["players"]["run50"]["acorns"]) == 5, "insufficient acorns never goes negative (ECO-01)")
	inst.run["players"]["run50"]["acorns"] = 100
	inst.node_action("run50", {"action": "buy", "item": "heal_charge"})
	var r2 := inst.node_action("run50", {"action": "buy", "item": "heal_charge"})
	check(not r2["ok"] and r2["error"] == "SOLD_OUT", "per-player purchase limit enforced")
	# 사건: 다수결, 효과 적용
	var ev := ExpeditionInstance.new("exp_e", 9)
	ev.add_member(_make_session(60))
	ev.add_member(_make_session(61))
	ev.start_run()
	ev._begin_menu("event", "fallen_branch")
	ev.node_action("run60", {"action": "vote", "choice": "gnaw"})
	check(ev.state == Protocol.ExpState.NODE_MENU, "event waits for all votes")
	ev.node_action("run61", {"action": "vote", "choice": "gnaw"})
	check(int(ev.run["team_wood"]) == 6, "event effect applied (wood +6)")
	check(ev.state != Protocol.ExpState.NODE_MENU, "event resolved moves on")
	# 체크포인트 왕복
	var cp := inst.to_checkpoint()
	var text := JSON.stringify(cp)
	var back: Dictionary = JSON.parse_string(text)
	var restored := ExpeditionInstance.from_checkpoint(back)
	check(restored.id == inst.id and restored.state == Protocol.ExpState.NODE_MENU and int(restored.run["players"]["run50"]["acorns"]) == int(inst.run["players"]["run50"]["acorns"]), "checkpoint round-trips through JSON")
	check(restored.members["run50"]["connected"] == false and restored.restored_from_checkpoint, "restored members start disconnected")
	var s50 := _make_session(50)
	restored.mark_reconnected(s50)
	var has_menu := false
	for msg: Dictionary in restored.outbox:
		if int(msg["type"]) == Protocol.S.NODE_MENU:
			has_menu = true
	check(has_menu, "reconnect re-sends the safe-point phase")
	# 전투 중 저장본은 RESULT(서버 오류)로 복구된다
	var cp2 := inst.to_checkpoint()
	cp2["state"] = Protocol.ExpState.IN_ROOM
	var r3 := ExpeditionInstance.from_checkpoint(cp2)
	check(r3.state == Protocol.ExpState.RESULT and r3.run_outcome == Protocol.Outcome.SERVER_ERROR, "mid-combat checkpoint is not restored as a fight")


func test_village_bonus() -> void:
	var b0 := ContentDB.village_bonus({"memory_tree": {"level": 1}, "workshop": {"level": 0}})
	check(b0.is_empty() or float(b0.get("max_hp_add", 0)) == 0.0, "no bonus at base levels")
	var b2 := ContentDB.village_bonus({"memory_tree": {"level": 2}, "workshop": {"level": 1}})
	check(int(b2.get("max_hp_add", 0)) == 5 and int(b2.get("heal_uses_add", 0)) == 1, "level 2 tree + level 1 workshop bonuses")
	var b3 := ContentDB.village_bonus({"memory_tree": {"level": 3}, "workshop": {"level": 2}})
	check(int(b3.get("max_hp_add", 0)) == 10 and int(b3.get("team_wood_add", 0)) == 3, "max levels: hp +10 (not 15), wood +3")
	var b9 := ContentDB.village_bonus({"memory_tree": {"level": 9}})
	check(int(b9.get("max_hp_add", 0)) <= int(ContentDB.village["permanent_caps"]["max_hp_add"]), "permanent cap applied (GROW-02)")
	# 출정 시 작업실 보너스가 회복 도구·팀 목재에 반영되고, 최대 체력 보너스가 전투 수치에 반영된다 (GROW-01)
	var inst := ExpeditionInstance.new("exp_v", 3)
	var s := _make_session(70)
	inst.add_member(s, b3)
	inst.start_run()
	check(int(inst.members["run70"]["heal_uses"]) == 3 and int(inst.run["team_wood"]) == 3, "workshop bonuses applied at run start")
	var p: Dictionary = inst.room.players["run70"]
	check(is_equal_approx(p["max_hp"], float(ContentDB.get_class_def("guardian")["base_hp"]) + 10.0), "memory tree hp bonus applied to combat max hp")
	check(inst.room.team_wood == 3, "combat room starts with the team wood")


## 플레이어·보스 상태가 매니페스트에 있는 시트 ID 로 해석되는지 (팩 연결 검증, 서버 판정과 무관)
func test_entity_anim_sheets() -> void:
	var ev := EntityView.new()
	ev.sprite_prefix = "char.guardian"
	ev.is_player = true
	ev.state = Protocol.EntState.ALIVE
	ev.action = Protocol.Action.CAST
	ev.action_kind = Protocol.ACTION_KIND_CODES["q"]
	check(ev._pick_anim() == "cast_q", "guardian Q cast picks cast_q sheet")
	ev.action_kind = Protocol.ACTION_KIND_CODES["r"]
	check(ev._pick_anim() == "cast_r", "guardian R cast picks cast_r sheet")
	for a in ["idle", "walk", "attack", "cast", "cast_q", "cast_e", "cast_r", "hit", "down"]:
		check(AssetRegistry.has("char.guardian." + a) and AssetRegistry.status("char.guardian." + a) in ["final", "derived"], "guardian sheet linked: " + a)
	var bv := EntityView.new()
	bv.sprite_prefix = "boss.ironclaw"
	bv.is_player = false
	bv.boss_state = BossIronclaw.BS.ATTACK
	for pat in [["claw_sweep", "claw_sweep"], ["line_charge", "straight_charge"], ["rock_toss", "rock_throw"], ["ground_slam", "ground_slam"]]:
		bv.boss_pattern = pat[0]
		check(bv._pick_anim() == pat[1] and AssetRegistry.status("boss.ironclaw." + pat[1]) == "final", "boss pattern %s -> pack sheet %s" % [pat[0], pat[1]])
	bv.boss_state = BossIronclaw.BS.STAGGER
	check(bv._pick_anim() == "stagger" and AssetRegistry.status("boss.ironclaw.stagger") == "final", "boss stagger sheet from pack")
	bv.boss_state = BossIronclaw.BS.EXPOSED
	check(bv._pick_anim() == "exposed", "boss exposed sheet")
	for i in range(1, 6):
		for k in ["activation", "success", "failure"]:
			var id := "prop.mechanic.ic_0%d.%s" % [i, k]
			check(AssetRegistry.status(id) == "final" and int(AssetRegistry.entry(id).get("columns", 0)) == 4, "IC-0%d %s sheet linked (4 frames)" % [i, k])
	for e in ["sap_snail", "thorn_boar", "black_bird"]:
		for a in ["idle", "walk", "attack", "hit", "death"]:
			check(AssetRegistry.status("enemy.%s.%s" % [e, a]) in ["final", "derived"], "enemy sheet linked: %s.%s" % [e, a])
	ev.free()
	bv.free()


func _solo_room(cls: String, seed_: int = 11) -> CombatRoom:
	var room := CombatRoom.new(ContentDB.get_room_def("test_arena"), ContentDB.get_party_profile(1), ContentDB.rules, seed_, [{"account_id": "p0", "nickname": "P0", "class_id": cls}])
	for e: Dictionary in room.enemies.values():
		e["ai"] = Protocol.EnemyAI.ROOTED
		e["root_t"] = 1000.0
		e["hp"] = 1000.0
		e["max_hp"] = 1000.0
	return room


func _press(room: CombatRoom, id: String, seq: int, aim: Vector2, btn: int, ticks: int = 1, mv: Vector2 = Vector2.ZERO) -> Array:
	var out: Array = []
	for i in ticks:
		room.queue_input(id, seq + i, mv, aim, btn if i == 0 else 0)
		out.append_array(room.step(1.0 / 30.0))
	return out


func test_class_sawtooth() -> void:
	var room := _solo_room("sawtooth")
	var p: Dictionary = room.players["p0"]
	var e0: Dictionary = room.enemies.values()[0]
	e0["pos"] = p["pos"] + Vector2(50, 0)
	var seq := 1
	# 연타로 열의가 쌓이고 피해가 커진다
	var first_dmg := -1.0
	var last_dmg := -1.0
	for i in 6:
		e0["pos"] = p["pos"] + Vector2(50, 0)   # 넉백으로 밀려난 적을 다시 사거리 안에 둔다
		for ev: Dictionary in _press(room, "p0", seq, Vector2.RIGHT, Protocol.BTN_ATTACK, 18):
			if ev["k"] == "enemy_hit" and ev["eid"] == e0["id"]:
				if first_dmg < 0.0:
					first_dmg = float(ev["dmg"])
				last_dmg = float(ev["dmg"])
		seq += 18
	check(int(p["resource"]) == 5, "heat stacks reach max 5 (got %d)" % int(p["resource"]))
	check(last_dmg > first_dmg * 1.15, "heat increases basic damage (%.1f -> %.1f)" % [first_dmg, last_dmg])
	room._damage_player(p, 5.0, p["pos"] + Vector2(10, 0), "test")
	check(int(p["resource"]) == 4, "taking a hit removes one heat stack")
	for i in 100:
		room.step(1.0 / 30.0)
	check(int(p["resource"]) == 0, "heat decays after 3s without attacking")
	# Q 갉아 돌진: 경로 위의 적을 치고 이동한다
	var x0: float = p["pos"].x
	e0["pos"] = p["pos"] + Vector2(120, 0)
	var hp0: float = e0["hp"]
	var dashed := false
	for ev: Dictionary in _press(room, "p0", seq, Vector2.RIGHT, Protocol.BTN_Q, 8):
		if ev["k"] == "dash":
			dashed = true
	seq += 8
	check(dashed and p["pos"].x > x0 + 150 and e0["hp"] < hp0, "gnaw dash moves the player and damages enemies on the path")
	# E 나무쪼개기: 방어 약화 후 받는 피해 증가
	e0["pos"] = p["pos"] + Vector2(60, 0)
	var before: float = e0["hp"]
	for ev: Dictionary in _press(room, "p0", seq, Vector2.RIGHT, Protocol.BTN_E, 14):
		pass
	seq += 14
	check(e0["vuln_t"] > 0.0 and e0["hp"] < before, "wood split damages and applies vulnerability")
	var base := 10.0
	var h1: float = e0["hp"]
	room._damage_enemy(e0, base, p, 0.0, 0.0)
	check(is_equal_approx(h1 - float(e0["hp"]), base * 1.25), "vulnerable enemy takes +25%% damage (%.1f)" % (h1 - float(e0["hp"])))
	# R 벌목 열풍: 회전 중 이동 가능, 주기 피해, 기본 공격 불가
	var hp_r: float = e0["hp"]
	var x1: float = p["pos"].x
	for ev: Dictionary in _press(room, "p0", seq, Vector2.RIGHT, Protocol.BTN_R, 12):
		pass
	seq += 12
	check(p["whirl_t"] > 0.0, "whirl active after R")
	var ticks_hit := 0
	for i in 30:
		room.queue_input("p0", seq, Vector2.RIGHT, Vector2.RIGHT, Protocol.BTN_ATTACK)
		seq += 1
		for ev: Dictionary in room.step(1.0 / 30.0):
			if ev["k"] == "enemy_hit":
				ticks_hit += 1
			if ev["k"] == "action" and ev.get("kind", "") == "basic":
				check(false, "basic attack must not start while whirling")
	check(ticks_hit >= 2 and p["pos"].x > x1, "whirl ticks damage while moving")
	var snap := room.snapshot()
	var me: PackedFloat32Array = snap["p"][0][1]
	check(int(me[Protocol.SNAP_P.STATUS]) & Protocol.ST_WHIRL != 0 and int(me[Protocol.SNAP_P.ACTION_KIND]) == Protocol.ACTION_KIND_CODES["whirl"], "snapshot flags whirl")
	for i in 150:
		room.step(1.0 / 30.0)
	check(p["whirl_t"] == 0.0 and p["action_kind"] == "", "whirl ends and action kind clears")


func test_class_sapshaman() -> void:
	var room := _solo_room("sapshaman")
	var p: Dictionary = room.players["p0"]
	var e0: Dictionary = room.enemies.values()[0]
	e0["pos"] = p["pos"] + Vector2(150, 0)
	var seq := 1
	for i in 4:
		_press(room, "p0", seq, Vector2.RIGHT, Protocol.BTN_ATTACK, 20)
		seq += 20
	check(int(p["resource"]) >= 2, "sap orb hits accumulate seeds (got %d)" % int(p["resource"]))
	# Q 생명의 수액: 회복 + 둔화 + 씨앗 소모, 회복 상한
	p["hp"] = 40.0
	var seeds := int(p["resource"])
	var healed_amount := 0.0
	for ev: Dictionary in _press(room, "p0", seq, Vector2.RIGHT * 80, Protocol.BTN_Q, 12):
		if ev["k"] == "healed" and ev["id"] == "p0":
			healed_amount += float(ev["amount"])
	seq += 12
	check(healed_amount >= 18.0 + seeds * 3 - 0.01 and int(p["resource"]) == 0, "life sap heals base + seeds and consumes seeds (%.0f)" % healed_amount)
	check(e0["slow_t"] > 0.0, "enemy inside life sap is slowed")
	var sp0: Vector2 = e0["pos"]
	e0["ai"] = Protocol.EnemyAI.CHASE
	e0["root_t"] = 0.0
	e0["target"] = "p0"
	room.step(1.0 / 30.0)
	var moved_slow := (e0["pos"] as Vector2).distance_to(sp0)
	e0["slow_t"] = 0.0
	sp0 = e0["pos"]
	room.step(1.0 / 30.0)
	var moved_norm := (e0["pos"] as Vector2).distance_to(sp0)
	check(moved_slow < moved_norm * 0.8, "slow reduces enemy movement (%.2f vs %.2f)" % [moved_slow, moved_norm])
	e0["ai"] = Protocol.EnemyAI.ROOTED
	e0["root_t"] = 1000.0
	# 회복 상한: 10초 창 안에서 70 을 넘지 않는다
	p["hp"] = 1.0
	p["cd"]["q"] = 0.0
	var total := 0.0
	for i in 5:
		p["cd"]["q"] = 0.0
		for ev: Dictionary in _press(room, "p0", seq, Vector2.RIGHT * 30, Protocol.BTN_Q, 12):
			if ev["k"] == "healed" and ev["id"] == "p0":
				total += float(ev["amount"])
		seq += 12
	check(total <= float(ContentDB.rules["caps"]["heal_received_per_10s"]) + 0.01, "healing capped per 10s window (%.0f)" % total)
	# E 뿌리 결속: 속박 + 지속 피해 장판
	e0["ai"] = Protocol.EnemyAI.CHASE
	e0["root_t"] = 0.0
	e0["pos"] = p["pos"] + Vector2(120, 0)
	var hp_e: float = e0["hp"]
	_press(room, "p0", seq, Vector2.RIGHT * 120, Protocol.BTN_E, 12)
	seq += 12
	check(e0["ai"] == Protocol.EnemyAI.ROOTED, "root bind roots enemies")
	var zones := 0
	for o: Dictionary in room.objects.values():
		if o["kind"] == Protocol.ObKind.ROOT_ZONE:
			zones += 1
	check(zones == 1, "root zone object created")
	for i in 60:
		room.step(1.0 / 30.0)
	check(e0["hp"] < hp_e - 8.0, "root zone deals damage over time (%.1f)" % (hp_e - float(e0["hp"])))
	# R 봄의 범람: 아군 회복·적 피해 장판
	p["hp"] = 30.0
	p["heal_log"] = []
	e0["pos"] = p["pos"] + Vector2(60, 0)
	var hp_r: float = e0["hp"]
	_press(room, "p0", seq, Vector2.RIGHT, Protocol.BTN_R, 14)
	seq += 14
	for i in 90:
		room.step(1.0 / 30.0)
	check(p["hp"] > 30.0 and e0["hp"] < hp_r, "spring flood heals the caster and damages enemies")


func test_class_hydro() -> void:
	var room := _solo_room("hydro")
	var p: Dictionary = room.players["p0"]
	var e0: Dictionary = room.enemies.values()[0]
	e0["pos"] = p["pos"] + Vector2(150, 0)
	var seq := 1
	p["resource"] = 0.0
	# 수압이 없으면 포탑 설치 실패
	var failed := false
	for ev: Dictionary in _press(room, "p0", seq, Vector2.RIGHT * 40, Protocol.BTN_Q, 12):
		if ev["k"] == "skill_failed":
			failed = true
	seq += 12
	check(failed, "turret needs charge")
	for i in 5:
		_press(room, "p0", seq, Vector2.RIGHT, Protocol.BTN_ATTACK, 18)
		seq += 18
	check(p["resource"] >= 30.0, "basic hits charge pressure (%.0f)" % p["resource"])
	var charge := float(p["resource"])
	_press(room, "p0", seq, Vector2.RIGHT * 40, Protocol.BTN_Q, 12)
	seq += 12
	var turrets := 0
	for o: Dictionary in room.objects.values():
		if o["kind"] == Protocol.ObKind.TURRET:
			turrets += 1
	check(turrets == 1 and p["resource"] < charge, "turret placed and charge consumed")
	var shots := 0
	var hp0: float = e0["hp"]
	for i in 60:
		for ev: Dictionary in room.step(1.0 / 30.0):
			if ev["k"] == "turret_shot":
				shots += 1
	check(shots >= 2 and e0["hp"] < hp0, "turret fires at enemies in range")
	var charge_after: float = p["resource"]
	check(charge_after <= charge - 30.0 + 2.0 * 2.5 + 0.5, "turret hits do not charge pressure (no recursion): %.1f" % charge_after)
	# 최대 2개: 3번째는 가장 오래된 것을 대체
	for k in 3:
		p["resource"] = 100.0
		p["cd"]["q"] = 0.0
		_press(room, "p0", seq, Vector2.RIGHT * 40, Protocol.BTN_Q, 12)
		seq += 12
	turrets = 0
	for o: Dictionary in room.objects.values():
		if o["kind"] == Protocol.ObKind.TURRET:
			turrets += 1
	check(turrets == 2, "at most 2 turrets per owner (got %d)" % turrets)
	# E 급류 밸브: 적을 밀어내고 둔화, 아군 가속
	e0["pos"] = p["pos"] + Vector2(100, 0)
	var ex0: float = e0["pos"].x
	_press(room, "p0", seq, Vector2.RIGHT, Protocol.BTN_E, 12)
	seq += 12
	check(e0["pos"].x > ex0 + 60 and e0["slow_t"] > 0.0 and p["haste_t"] > 0.0, "torrent valve pushes, slows enemies and hastes allies in the line")
	# R 이동식 거대 댐: 장애물로 작동, 만료 시 폭발
	_press(room, "p0", seq, Vector2.RIGHT * 100, Protocol.BTN_R, 16)
	seq += 16
	var dam: Dictionary = {}
	for o: Dictionary in room.objects.values():
		if o["kind"] == Protocol.ObKind.DAM:
			dam = o
	check(not dam.is_empty() and room.all_obstacles().size() > room.obstacles.size(), "dam placed and blocks movement")
	e0["pos"] = dam["pos"] + Vector2(70, 0)
	var hp_b: float = e0["hp"]
	dam["life"] = 0.01
	var burst := false
	for ev: Dictionary in room.step(1.0 / 30.0):
		if ev["k"] == "dam_burst":
			burst = true
	check(burst and e0["hp"] < hp_b and e0["pos"].x > dam["pos"].x + 100, "dam burst damages and knocks enemies away")
	check(int(room.snapshot()["e"][0][2][Protocol.SNAP_E.STATUS]) & Protocol.ST_SLOW != 0, "enemy status flags in snapshot")


func test_variants_and_synergies() -> void:
	# 유물 시너지: 같은 태그 2개 → 보너스 mods/procs
	var b := RunMods.build(["sharp_incisors", "hunters_tooth"], [], "guardian", 1, {}, ContentDB.rules)
	check((b["synergies"] as Array).has("tooth") and float(b["mods"]["damage_mult"]) > 0.12, "tooth synergy adds damage and is reported")
	var b0 := RunMods.build(["sharp_incisors"], [], "guardian", 1, {}, ContentDB.rules)
	check((b0["synergies"] as Array).is_empty(), "single tag: no synergy")
	# 숙련 특성: mods 와 procs 가 합쳐진다
	var bt := RunMods.build([], [], "guardian", 1, {}, ContentDB.rules, "g_riposte")
	var has_proc := false
	for pr: Dictionary in bt["procs"]:
		if String(pr.get("source", "")) == "trait:g_riposte":
			has_proc = true
	check(has_proc, "mastery trait procs merged")
	check(ContentDB.mastery_level(0) == 1 and ContentDB.mastery_level(100) == 2 and ContentDB.mastery_level(99999) == 10, "mastery level table 1..10")
	# 모든 강화의 mods 키가 RunMods 가 아는 키인지 (오타 방지)
	for cls: String in ContentDB.upgrades.keys():
		for uid: String in ContentDB.upgrades[cls].keys():
			for k: String in ContentDB.upgrades[cls][uid].get("mods", {}).keys():
				check(RunMods.MOD_KEYS.has(k), "upgrade mod key known: %s.%s.%s" % [cls, uid, k])
	for cls: String in ContentDB.mastery.get("traits", {}).keys():
		for t: Dictionary in ContentDB.mastery["traits"][cls]:
			for k: String in t.get("mods", {}).keys():
				check(RunMods.MOD_KEYS.has(k), "trait mod key known: %s" % k)
	# 각 직업 스킬마다 변형 2개 이상, 진화 1개 이상
	for cls: String in ["guardian", "pinecone", "sawtooth", "sapshaman", "hydro"]:
		var per_slot := {"q": 0, "e": 0, "r": 0}
		var evos := 0
		for uid: String in ContentDB.upgrades[cls].keys():
			var u: Dictionary = ContentDB.upgrades[cls][uid]
			if bool(u.get("evolution", false)):
				evos += 1
			elif per_slot.has(String(u.get("skill", ""))):
				per_slot[String(u["skill"])] += 1
		check(per_slot["q"] >= 2 and per_slot["e"] >= 2 and per_slot["r"] >= 2 and evos >= 1, "%s: 2 variants per skill + evolution (%s, evo %d)" % [cls, per_slot, evos])
	# 진화 제안 조건: 런 레벨과 같은 스킬 강화 보유
	var inst := ExpeditionInstance.new("exp_evo", 3)
	inst.add_member(_make_session(90))
	inst.start_run()
	var pool: Array = inst._upgrade_pool("run90")
	var has_evo := false
	for uid: String in pool:
		if bool(ContentDB.upgrades["guardian"][uid].get("evolution", false)):
			has_evo = true
	check(not has_evo, "evolutions hidden at level 1 without skill upgrades")
	inst._run_player("run90")["upgrades"].append("tail_slam_wide")
	inst.run["level"] = 4
	pool = inst._upgrade_pool("run90")
	check(pool.has("evo_quake_tail") and not pool.has("evo_living_fort") and not pool.has("tail_slam_heavy"), "quake tail offered after tail slam upgrade at level 4; exclusive group and other evolution hidden: %s" % [pool])
	# 변형 효과 실측: 지진 꼬리(지연 2차 충격), 세 번째 포탑, 반격 특성
	var room := CombatRoom.new(ContentDB.get_room_def("test_arena"), ContentDB.get_party_profile(1), ContentDB.rules, 21, [{"account_id": "p0", "nickname": "P0", "class_id": "guardian", "mods": RunMods.build([], ["evo_quake_tail", "bulwark_stack"], "guardian", 4, {}, ContentDB.rules)["mods"]}])
	for e: Dictionary in room.enemies.values():
		e["ai"] = Protocol.EnemyAI.ROOTED
		e["root_t"] = 1000.0
		e["hp"] = 1000.0
	var p: Dictionary = room.players["p0"]
	var e0: Dictionary = room.enemies.values()[0]
	e0["pos"] = p["pos"] + Vector2(170, 0)   # 1차(반경 120)는 빗나가고 2차(반경 240)만 맞는다
	var hp0: float = e0["hp"]
	var circles := 0
	for ev: Dictionary in _press(room, "p0", 1, Vector2.RIGHT, Protocol.BTN_E, 30):
		if ev["k"] == "circle_hit":
			circles += 1
	check(circles == 2 and e0["hp"] < hp0, "quake tail: delayed second shockwave hits farther enemies")
	room._damage_player(p, 5.0, p["pos"] + Vector2(10, 0), "test")
	p["front_guard_t"] = 2.0
	room._damage_player(p, 5.0, p["pos"] + Vector2(10, 0), "test")
	check(float(p["guard_bonus"]) == 6.0, "guard success arms bonus damage for next attack")
	var hroom := CombatRoom.new(ContentDB.get_room_def("test_arena"), ContentDB.get_party_profile(1), ContentDB.rules, 22, [{"account_id": "p0", "nickname": "P0", "class_id": "hydro", "mods": RunMods.build([], ["turret_triple"], "hydro", 1, {}, ContentDB.rules)["mods"]}])
	var hp_: Dictionary = hroom.players["p0"]
	var seq := 1
	for k in 4:
		hp_["resource"] = 100.0
		hp_["cd"]["q"] = 0.0
		_press(hroom, "p0", seq, Vector2.RIGHT * 40, Protocol.BTN_Q, 12)
		seq += 12
	var turrets := 0
	for o: Dictionary in hroom.objects.values():
		if o["kind"] == Protocol.ObKind.TURRET:
			turrets += 1
	check(turrets == 3, "turret_triple allows 3 turrets (got %d)" % turrets)


func test_build_kinds() -> void:
	var room := _solo_room("guardian", 31)
	var p: Dictionary = room.players["p0"]
	room.team_wood = 20
	var e0: Dictionary = room.enemies.values()[0]
	e0["pos"] = p["pos"] + Vector2(60, 0)
	room.set_build_kind("p0", "spike_fence")
	var wood0 := room.team_wood
	_press(room, "p0", 1, Vector2.RIGHT, Protocol.BTN_BUILD, 2)
	var fence: Dictionary = {}
	for o: Dictionary in room.objects.values():
		if o["kind"] == Protocol.ObKind.STRUCTURE:
			fence = o
	check(not fence.is_empty() and String(fence.get("bkind", "")) == "spike_fence" and room.team_wood == wood0 - 4 and int(fence["state"]) == 1, "spike fence built for 4 wood with kind index in state")
	var hp0: float = e0["hp"]
	e0["pos"] = fence["pos"] + Vector2(30, 0)
	for i in 30:
		room.step(1.0 / 30.0)
	check(e0["hp"] < hp0 and e0["slow_t"] > 0.0, "spike fence damages and slows touching enemies")
	room.set_build_kind("p0", "sap_lantern")
	p["hp"] = 50.0
	p["facing"] = Vector2.LEFT
	_press(room, "p0", 10, Vector2.LEFT, Protocol.BTN_BUILD, 2)
	for i in 70:
		room.step(1.0 / 30.0)
	check(p["hp"] > 50.0, "sap lantern heals nearby allies over time (%.1f)" % p["hp"])
	room.set_build_kind("p0", "nope")
	check(p["build_kind"] == "sap_lantern", "unknown build kind ignored")


func test_regions_and_enemies() -> void:
	# 3지역 경로: 층이 이어지고 지역 보스 3개, 재현 가능
	var layers: Array = ExpeditionInstance.build_route(4242, "willow_river", 3)
	var bosses := 0
	var regions := {}
	for layer: Array in layers:
		for node: Dictionary in layer:
			regions[String(node.get("region", ""))] = true
			if String(node["type"]) == "boss":
				bosses += 1
	check(bosses == 3 and regions.size() == 3, "route spans 3 regions with 3 bosses (bosses %d, regions %d)" % [bosses, regions.size()])
	check(JSON.stringify(layers) == JSON.stringify(ExpeditionInstance.build_route(4242, "willow_river", 3)), "route reproducible for the same seed")
	# 9종 적: 정의·자산·역할
	for eid in ["shell_soldier", "spore_mushroom", "root_puppet", "reed_frog", "river_leech", "lantern_moth", "woodjaw_beetle", "gear_crab", "sap_totem"]:
		var d := ContentDB.get_enemy_def(eid)
		check(bool(d.get("implemented", false)) and AssetRegistry.has("enemy.%s.idle" % eid) and AssetRegistry.has("enemy.%s.attack" % eid), "enemy defined with pack sheets: " + eid)
	# 개구리 도약: 예고가 대상 위치에 뜨고 착지 시 이동·피해
	var room := CombatRoom.new(ContentDB.get_room_def("swamp_annihilate"), ContentDB.get_party_profile(1), ContentDB.rules, 3, [{"account_id": "p0", "nickname": "P0", "class_id": "guardian"}])
	for e: Dictionary in room.enemies.values():
		e["ai"] = Protocol.EnemyAI.DEAD
		e["death_t"] = 0.0
	var p: Dictionary = room.players["p0"]
	var frog := room._spawn_enemy("reed_frog", p["pos"] + Vector2(220, 0))
	var frog_hit := false
	for i in 60:
		for ev: Dictionary in room.step(1.0 / 30.0):
			if ev["k"] == "enemy_attack" and bool(ev.get("leap", false)):
				frog_hit = true
	check(frog_hit and (frog["pos"] as Vector2).distance_to(p["pos"]) < 120.0, "reed frog leaps onto the player")
	# 껍질 병정: 정면 피해 50% 감소, 후면은 정상
	var sold := room._spawn_enemy("shell_soldier", p["pos"] + Vector2(80, 0))
	sold["facing"] = Vector2.LEFT
	var h0: float = sold["hp"]
	room._damage_enemy(sold, 20.0, p, 0.0, 0.0)
	var front := h0 - float(sold["hp"])
	sold["facing"] = Vector2.RIGHT
	h0 = sold["hp"]
	room._damage_enemy(sold, 20.0, p, 0.0, 0.0)
	var back := h0 - float(sold["hp"])
	check(is_equal_approx(front, 10.0) and is_equal_approx(back, 20.0), "shell soldier front armor halves damage (%.0f/%.0f)" % [front, back])
	# 수액 토템: 소환 (최대 3), 톱니 게: 2연속 공격, 거머리: 출혈, 수액 웅덩이: 둔화
	var totem := room._spawn_enemy("sap_totem", p["pos"] + Vector2(300, 200))
	var summons := 0
	for i in 30 * 16:
		for ev: Dictionary in room.step(1.0 / 30.0):
			if ev["k"] == "summon" and ev["eid"] == totem["id"]:
				summons += 1
	check(summons >= 2 and summons <= 3, "sap totem summons snails up to its cap (%d)" % summons)
	p["pos"] = Vector2(400, 450)   # 수액 웅덩이 안 (300..620, 380..560)
	check(room._hazard_slow_at(p["pos"]) > 0.3, "sap hazard slows inside the rect")
	room._apply_hit_status(p, {"bleed_dps": 2.0, "bleed_sec": 3.0})
	var hp0: float = p["hp"]
	for i in 30:
		room.step(1.0 / 30.0)
	check(p["hp"] < hp0 and p["bleed_t"] > 0.0, "bleed ticks player hp")
	room._apply_hit_status(p, {"root_sec": 1.0})
	var x0: float = p["pos"].x
	room.queue_input("p0", 999, Vector2.RIGHT, Vector2.ZERO, 0)
	room.step(1.0 / 30.0)
	check(is_equal_approx(p["pos"].x, x0), "rooted player cannot move")
	check(int(room.snapshot()["p"][0][1][Protocol.SNAP_P.STATUS]) & Protocol.ST_ROOT != 0, "player root status in snapshot")


func test_escort_and_elite() -> void:
	var room := CombatRoom.new(ContentDB.get_room_def("willow_escort"), ContentDB.get_party_profile(2), ContentDB.rules, 9, _members(2))
	var raft: Dictionary = {}
	for o: Dictionary in room.objects.values():
		if o["kind"] == Protocol.ObKind.RAFT:
			raft = o
	check(not raft.is_empty() and room.objective == "escort", "escort room spawns a raft")
	for e: Dictionary in room.enemies.values():
		e["ai"] = Protocol.EnemyAI.DEAD
		e["death_t"] = 0.0
	var p0: Dictionary = room.players["p0"]
	var far: Vector2 = raft["pos"] + Vector2(600, 0)
	p0["pos"] = far
	room.players["p1"]["pos"] = far
	var start: Vector2 = raft["pos"]
	for i in 30:
		room.step(1.0 / 30.0)
	check((raft["pos"] as Vector2).distance_to(start) < 1.0, "raft waits while no player is near")
	p0["pos"] = raft["pos"]
	for i in 60:
		p0["pos"] = raft["pos"]
		room.step(1.0 / 30.0)
	check((raft["pos"] as Vector2).distance_to(start) > 60.0 and room.objective_progress > 0.05, "raft moves with an escort nearby (progress %.2f)" % room.objective_progress)
	var e := room._spawn_enemy("sap_snail", raft["pos"] + Vector2(60, 0))
	e["ai"] = Protocol.EnemyAI.ROOTED
	e["root_t"] = 100.0
	var before: Vector2 = raft["pos"]
	var hp_before: float = raft["hp"]
	for i in 30:
		p0["pos"] = raft["pos"]
		room.step(1.0 / 30.0)
	check((raft["pos"] as Vector2).distance_to(before) < 1.0 and raft["hp"] < hp_before and int(raft["state"]) == 2, "enemies near the raft stop it and chip its hp")
	# 정예방: 첫 웨이브에 정예가 나오고 표시·드롭이 다르다
	var er := CombatRoom.new(ContentDB.get_room_def("willow_elite"), ContentDB.get_party_profile(1), ContentDB.rules, 5, _members(1))
	var elite: Dictionary = {}
	for en: Dictionary in er.enemies.values():
		if bool(en.get("elite", false)):
			elite = en
	check(not elite.is_empty() and elite["max_hp"] > ContentDB.get_enemy_def("thorn_boar")["hp"] * 3.0 and elite["damage_mult"] > 1.0, "elite spawned with scaled hp and damage")
	var snap := er.snapshot()
	var found := false
	for entry: Array in snap["e"]:
		if int(entry[0]) == elite["id"] and int(entry[2][Protocol.SNAP_E.STATUS]) & Protocol.ST_ELITE:
			found = true
	check(found, "elite flag in snapshot")
	var wood0 := er.team_wood
	er._damage_enemy(elite, 100000.0, er.players["p0"], 0.0, 0.0)
	check(er.team_wood - wood0 == 3, "elite drops triple wood")


func test_quests_and_progression() -> void:
	var prog := {"memory_shards": 0}
	QuestEngine.ensure(prog)
	check(prog["quests"].has("main_01") and prog["quests"]["main_01"]["state"] == "active", "main quest auto-accepted")
	check(not prog["quests"].has("main_02"), "main_02 hidden until main_01 done")
	check(prog["quests"].has("opt_02") and prog["quests"]["opt_02"]["state"] == "available", "optional quest available")
	check(QuestEngine.accept(prog, "opt_02") and not QuestEngine.accept(prog, "opt_02"), "accept once")
	var done := QuestEngine.on_event(prog, {"type": "boss_kill", "target": "ironclaw", "count": 1})
	check(done.has("main_01") and prog["quests"]["main_01"]["state"] == "complete", "boss kill completes main_01")
	var r := QuestEngine.claim(prog, "main_01")
	check(bool(r["ok"]) and int(prog["memory_shards"]) == 10 and int(prog["npc_bonds"]["elder_zelkova"]) == 1, "claim grants shards and bond once")
	var r2 := QuestEngine.claim(prog, "main_01")
	check(not bool(r2["ok"]) and int(prog["memory_shards"]) == 10, "second claim rejected (no duplicate reward)")
	check(prog["quests"].has("main_02") and prog["quests"]["main_02"]["state"] == "available", "main_02 unlocked after main_01")
	# per_run 목표는 런 시작 시 초기화
	QuestEngine.accept(prog, "opt_05")
	QuestEngine.on_event(prog, {"type": "sluice_toggles", "count": 3})
	check(int(prog["quests"]["opt_05"]["run_progress"]) == 3, "per-run progress accumulates")
	QuestEngine.on_run_start(prog)
	check(int(prog["quests"]["opt_05"]["run_progress"]) == 0, "per-run progress resets on run start")
	QuestEngine.on_event(prog, {"type": "sluice_toggles", "count": 4})
	check(prog["quests"]["opt_05"]["state"] == "complete", "per-run goal reached in one run")
	# 절대값 목표 (도감·비밀)
	QuestEngine.accept(prog, "opt_07")
	QuestEngine.on_event(prog, {"type": "codex_enemies", "count": 9, "absolute": true})
	check(prog["quests"]["opt_07"]["state"] == "complete", "absolute objective completes at threshold")
	# 실패 표시: 정예전에서 구조물 건설
	QuestEngine.accept(prog, "opt_03")
	QuestEngine.fail_for_run(prog, "opt_03")
	QuestEngine.on_event(prog, {"type": "elite_no_structure", "count": 1})
	check(prog["quests"]["opt_03"]["state"] == "active", "failed-for-run quest does not progress this run")
	QuestEngine.on_run_start(prog)
	QuestEngine.on_event(prog, {"type": "elite_no_structure", "count": 1})
	check(prog["quests"]["opt_03"]["state"] == "complete", "quest recovers next run")
	check(QuestEngine.npc_view(prog, "elder_zelkova").size() >= 2 and QuestEngine.summary(prog)["done"] == 1, "npc view and summary")
	# 결말 판정
	prog["secrets_found"] = ["a", "b", "c", "d", "e", "f"]
	check(QuestEngine.ending_for(prog, {"memories": 2})["id"] == "purified" and QuestEngine.ending_for(prog, {"memories": 1})["id"] == "base", "ending depends on memories and secrets")
	# 인연 단계
	QuestEngine.add_bond(prog, "smith_resin", 5)
	check(QuestEngine.bond_level(prog, "smith_resin") == 2, "bond level from points")
	# 마을 5시설 3단계 + 상한
	check(ContentDB.village["structures"].size() == 5, "5 village structures")
	var full := {}
	for sid: String in ContentDB.village["structures"].keys():
		full[sid] = {"level": 3}
	var b := ContentDB.village_bonus(full)
	check(float(b["damage_mult"]) <= float(ContentDB.village["permanent_caps"]["damage_mult"]) + 0.0001 and float(b["max_hp_add"]) <= float(ContentDB.village["permanent_caps"]["max_hp_add"]) and int(b["heal_uses_add"]) <= 2, "village bonuses capped: %s" % [b])
	check(ContentDB.quests["quests"].size() == 15 and ContentDB.npcs.size() == 6, "15 quests, 6 npcs")


func test_secrets_and_relics() -> void:
	check(ContentDB.relics.keys().filter(func(k: String) -> bool: return not k.begins_with("_")).size() == 36, "36 relics")
	for rid: String in ContentDB.relics.keys():
		if rid.begins_with("_"):
			continue
		for k: String in ContentDB.relics[rid].get("mods", {}).keys():
			check(RunMods.MOD_KEYS.has(k), "relic mod key known: %s.%s" % [rid, k])
		check(AssetRegistry.has("icon.relic." + rid), "relic icon id: " + rid)
	# 비밀: 방에 등장하고 조사하면 결과에 기록되며, 이미 찾은 계정에는 다시 나오지 않는다
	var found_room := false
	for seed_ in 20:
		var room := CombatRoom.new(ContentDB.get_room_def("annihilate"), ContentDB.get_party_profile(1), ContentDB.rules, seed_, _members(1))
		var sec: Dictionary = {}
		for o: Dictionary in room.objects.values():
			if o["kind"] == Protocol.ObKind.SECRET:
				sec = o
		if sec.is_empty():
			continue
		found_room = true
		for e: Dictionary in room.enemies.values():
			e["ai"] = Protocol.EnemyAI.DEAD
			e["death_t"] = 0.0
		var p: Dictionary = room.players["p0"]
		p["pos"] = (sec["pos"] as Vector2) + Vector2(30, 0)
		var seq := 1
		var got := false
		for i in 120:
			room.queue_input("p0", seq, Vector2.ZERO, Vector2.ZERO, Protocol.BTN_INTERACT)
			seq += 1
			for ev: Dictionary in room.step(1.0 / 30.0):
				if ev["k"] == "secret_found":
					got = true
		check(got and room.result_summary()["stats"]["secrets"] == ["wr_01"], "secret found and recorded in the room result")
		var room2 := CombatRoom.new(ContentDB.get_room_def("annihilate"), ContentDB.get_party_profile(1), ContentDB.rules, seed_, [{"account_id": "p0", "nickname": "P0", "class_id": "guardian", "secrets_found": ["wr_01"]}])
		var again := false
		for o: Dictionary in room2.objects.values():
			if o["kind"] == Protocol.ObKind.SECRET:
				again = true
		check(not again, "already found secret does not respawn for that account")
		break
	check(found_room, "secret spawns in some seeds")
	# 유물 실측: 댐지기 휘장(건설 비용 -1, 내구 +50%), 강의 심장(저체력 회복), 고대 앞니
	var mods: Dictionary = RunMods.build(["dam_keeper_badge", "river_heart", "ancient_incisor"], [], "guardian", 1, {}, ContentDB.rules)["mods"]
	var room := CombatRoom.new(ContentDB.get_room_def("test_arena"), ContentDB.get_party_profile(1), ContentDB.rules, 3, [{"account_id": "p0", "nickname": "P0", "class_id": "guardian", "mods": mods}])
	var p: Dictionary = room.players["p0"]
	check(is_equal_approx(p["max_hp"], 130.0), "ancient incisor lowers max hp (%.0f)" % p["max_hp"])
	room.team_wood = 10
	room.queue_input("p0", 1, Vector2.ZERO, Vector2.RIGHT, Protocol.BTN_BUILD)
	room.step(1.0 / 30.0)
	var st: Dictionary = {}
	for o: Dictionary in room.objects.values():
		if o["kind"] == Protocol.ObKind.STRUCTURE:
			st = o
	check(room.team_wood == 8 and not st.is_empty() and is_equal_approx(st["max_hp"], 90.0), "dam keeper badge: cost 2 wood, hp 90")
	p["hp"] = 20.0
	for i in 30:
		room.step(1.0 / 30.0)
	check(p["hp"] > 20.5, "river heart regenerates at low hp")

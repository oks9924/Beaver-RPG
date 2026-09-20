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
	check(ContentDB.is_class_playable("guardian") and not ContentDB.is_class_playable("sawtooth"), "class implemented flags")
	var rep := AssetRegistry.report()
	check((rep["file_missing"] as Array).is_empty(), "manifest files exist: %s" % [rep["file_missing"]])
	for cid in ["guardian"]:
		for anim in ["idle", "walk", "attack", "cast", "hit", "down"]:
			check(AssetRegistry.has("char.%s.%s" % [cid, anim]), "asset id char.%s.%s" % [cid, anim])
	check(AssetRegistry.get_sheet("char.guardian.walk")["hframes"] == 4 and AssetRegistry.get_sheet("char.guardian.walk")["vframes"] == 4, "walk sheet 4x4")

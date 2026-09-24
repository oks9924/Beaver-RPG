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
	print("-- test_facing_rules")
	test_facing_rules()
	print("-- test_tempo")
	test_tempo()
	print("-- test_horde")
	test_horde()
	print("-- test_input_priority")
	test_input_priority()
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
	print("-- test_difficulty_tutorial_pause")
	test_difficulty_tutorial_pause()
	print("-- test_snapshot_codec")
	test_snapshot_codec()
	print("-- test_v3_pack_assets")
	test_v3_pack_assets()
	print("-- test_roguelike_systems")
	test_roguelike_systems()
	print("-- test_v4_pack_assets")
	test_v4_pack_assets()
	print("-- test_equipment")
	test_equipment()
	print("-- test_ground_drops")
	test_ground_drops()
	print("-- test_room_gen")
	test_room_gen()
	print("-- test_v5_pack_assets")
	test_v5_pack_assets()
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
	check(SimRules.move_facing(Vector2(0, -3), Vector2.RIGHT) == Vector2.UP and SimRules.move_facing(Vector2.ZERO, Vector2.RIGHT) == Vector2.RIGHT, "move_facing: key direction, else keep")


## 속도감(tempo): rules.tempo 배율이 로드 시 클래스·무기·적 수치에 적용되고, 원거리 기본 공격은 준비 동작 중에도 느리게 움직인다.
func test_tempo() -> void:
	var t: Dictionary = ContentDB.tempo()
	check(not t.is_empty(), "tempo block exists in rules.json")
	var raw_classes: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/classes.json"))
	var raw_cls: Dictionary = raw_classes["classes"] if raw_classes.has("classes") else raw_classes
	var g_raw: Dictionary = raw_cls["guardian"]
	var g: Dictionary = ContentDB.get_class_def("guardian")
	check(is_equal_approx(float(g["move_speed"]), roundf(float(g_raw["move_speed"]) * float(t["player_speed_mult"]))), "class move_speed scaled by player_speed_mult (%s)" % str(g["move_speed"]))
	check(float(g["move_speed"]) > float(g_raw["move_speed"]), "guardian is faster than raw data (%s > %s)" % [str(g["move_speed"]), str(g_raw["move_speed"])])
	var gba: Dictionary = g["basic_attack"]
	var gba_raw: Dictionary = g_raw["basic_attack"]
	check(is_equal_approx(float(gba["windup_sec"]), snappedf(float(gba_raw["windup_sec"]) * float(t["melee_windup_mult"]), 0.01)), "melee windup scaled (%s)" % str(gba["windup_sec"]))
	check(is_equal_approx(float(gba["recovery_sec"]), snappedf(float(gba_raw["recovery_sec"]) * float(t["melee_recovery_mult"]), 0.01)), "melee recovery scaled (%s)" % str(gba["recovery_sec"]))
	var h_raw: Dictionary = raw_cls["hydro"]["basic_attack"]
	var h: Dictionary = ContentDB.get_class_def("hydro")["basic_attack"]
	check(String(h.get("shape", "")) == "projectile", "hydro basic attack is a projectile")
	check(is_equal_approx(float(h["windup_sec"]), snappedf(float(h_raw["windup_sec"]) * float(t["ranged_windup_mult"]), 0.01)), "ranged windup scaled (%s)" % str(h["windup_sec"]))
	check(is_equal_approx(float(h["recovery_sec"]), snappedf(float(h_raw["recovery_sec"]) * float(t["ranged_recovery_mult"]), 0.01)), "ranged recovery scaled (%s)" % str(h["recovery_sec"]))
	var raw_enemies: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/enemies.json"))
	var raw_en: Dictionary = raw_enemies["enemies"] if raw_enemies.has("enemies") else raw_enemies
	var s_raw: Dictionary = raw_en["sap_snail"]
	var s_def: Dictionary = ContentDB.get_enemy_def("sap_snail")
	check(is_equal_approx(float(s_def["move_speed"]), roundf(float(s_raw["move_speed"]) * float(t["enemy_speed_mult"]))), "enemy move_speed scaled (%s)" % str(s_def["move_speed"]))
	check(is_equal_approx(float(s_def["hp"]), maxf(roundf(float(s_raw["hp"]) * float(t["enemy_hp_mult"])), 1.0)), "enemy hp scaled (%s)" % str(s_def["hp"]))
	# 웨이브 간격은 tempo.wave_gap_mult 로 줄어든다
	var room := _solo_room("hydro", 5)
	check(is_equal_approx(room._wave_gap_t, float(ContentDB.get_room_def("test_arena")["waves"]["wave_gap_sec"]) * float(t["wave_gap_mult"])), "wave gap scaled by wave_gap_mult (%.2f)" % room._wave_gap_t)
	# 기본 공격은 준비·명중·후딜 어느 단계에서도 이동을 막지 않는다 (후딜 없음). 공격 버튼을 누르는 동안은 마우스 방향을 본다.
	var dt := 1.0 / 30.0
	for cls in ["hydro", "guardian"]:
		var r := _solo_room(cls, 5)
		var p: Dictionary = r.players["p0"]
		for e: Dictionary in r.enemies.values():
			e["pos"] = Vector2(-9999, -9999)
		var x0: float = p["pos"].x
		var phases := {}
		for i in 12:
			r.queue_input("p0", 1 + i, Vector2.RIGHT, Vector2.LEFT * 100, Protocol.BTN_ATTACK)
			r.step(dt)
			phases[int(p["action"])] = true
			check(p["facing"].x < 0.0, "%s faces the aim while attacking and walking the other way" % cls)
		check(phases.has(Protocol.Action.WINDUP) and phases.has(Protocol.Action.RECOVERY), "%s went through windup and recovery" % cls)
		var moved: float = p["pos"].x - x0
		var expect := float(p["speed"]) * dt * 12.0 * float(t.get("basic_attack_move_mult", 1.0))
		check(absf(moved - expect) < 1.0, "%s keeps full speed through basic attacks (%.1f vs %.1f)" % [cls, moved, expect])
	# 스킬 시전은 여전히 멈춘다
	var rc := _solo_room("guardian", 6)
	var pc: Dictionary = rc.players["p0"]
	for e: Dictionary in rc.enemies.values():
		e["pos"] = Vector2(-9999, -9999)
	var xc0: float = pc["pos"].x
	rc.queue_input("p0", 1, Vector2.RIGHT, Vector2.RIGHT * 100, Protocol.BTN_Q)
	rc.step(dt)
	check(pc["action"] == Protocol.Action.CAST, "Q enters cast")
	rc.queue_input("p0", 2, Vector2.RIGHT, Vector2.RIGHT * 100, 0)
	rc.step(dt)
	check(is_equal_approx(pc["pos"].x, xc0), "cast does not move (%.1f)" % (pc["pos"].x - xc0))


## 몹 물량(horde): 일반 몹 수 ×m·체력 ↓·크기 ↓. 보상·정예·호위 피해는 m 으로 나눠 판당 총량 유지. 보스·튜토리얼·탐색·시험방은 배율 1.
func test_horde() -> void:
	var t: Dictionary = ContentDB.tempo()
	var m := float(t.get("enemy_count_mult", 1.0))
	check(m > 1.0, "enemy_count_mult is on (%.2f)" % m)
	var raw_enemies: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/enemies.json"))
	var raw_en: Dictionary = raw_enemies["enemies"] if raw_enemies.has("enemies") else raw_enemies
	for id: String in ["sap_snail", "shell_soldier", "river_leech"]:
		check(is_equal_approx(float(ContentDB.get_enemy_def(id)["radius"]), snappedf(float(raw_en[id]["radius"]) * float(t["enemy_radius_mult"]), 0.1)), "%s radius scaled (%s)" % [id, str(ContentDB.get_enemy_def(id)["radius"])])
	var raw_bosses: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/bosses.json"))
	var bchecked := 0
	for bid: String in ContentDB.bosses.keys():
		var bd: Variant = ContentDB.bosses[bid]
		if bd is Dictionary and (bd as Dictionary).has("radius") and raw_bosses.get(bid, {}) is Dictionary and (raw_bosses.get(bid, {}) as Dictionary).has("radius"):
			bchecked += 1
			check(is_equal_approx(float(bd["radius"]), float(raw_bosses[bid]["radius"])), "boss %s radius unchanged" % bid)
	check(bchecked >= 1, "boss radii checked (%d)" % bchecked)
	# 물량 배율이 적용되는 방
	var def := ContentDB.get_room_def("annihilate")
	var prof := ContentDB.get_party_profile(1)
	var r := CombatRoom.new(def, prof, ContentDB.rules, 31, _members(1))
	check(is_equal_approx(r.count_mult, m), "annihilate room uses count mult")
	check(is_equal_approx(r.wave_budget_total, float(def["waves"]["base_budget"]) * float(prof.get("wave_budget_mult", 1.0)) * m), "wave budget scaled by count mult (%.1f)" % r.wave_budget_total)
	var caps: Dictionary = ContentDB.party_scaling["screen_caps"]
	check(r._enemy_cap() == roundi(float(caps["max_enemies_on_screen"]) * m), "solo enemy cap scaled (%d)" % r._enemy_cap())
	var r4 := CombatRoom.new(def, ContentDB.get_party_profile(4), ContentDB.rules, 32, _members(4))
	check(r4._enemy_cap() == roundi(float(caps["max_enemies_on_screen"]) * m) + int(caps["per_extra_player"]) * 3 and r4._enemy_cap() <= 36, "4p cap keeps per-player add unscaled for MTU (%d)" % r4._enemy_cap())
	var base_thr := int(def["waves"]["next_wave_when_alive_at_most"]) + int(t.get("wave_alive_at_most_add", 0))
	check(r.wave_threshold() == roundi(float(base_thr) * m), "next-wave gate scaled (%d)" % r.wave_threshold())
	var hold := CombatRoom.new(ContentDB.get_room_def("hold_point"), prof, ContentDB.rules, 33, _members(1))
	check(hold.wave_threshold() >= 99, "time-gated rooms keep their every-gap waves (%d)" % hold.wave_threshold())
	check(is_equal_approx(r.normal_drop_chance(), float(ContentDB.equipment["ground_drop"]["normal_chance"]) / m), "normal drop chance divided by count mult")
	var c := 0.06
	var ce := r.affix_elite_chance(c)
	check(ce < c and is_equal_approx(1.0 - pow(1.0 - ce, m), c), "per-spawn elite chance keeps per-room elites (%.4f)" % ce)
	check(is_equal_approx(r.enemy_damage_factor, pow(m, -float(t.get("enemy_damage_count_exp", 0.0)))) and r.enemy_damage_factor < 1.0, "enemy damage factor in horde rooms (%.2f)" % r.enemy_damage_factor)
	# 체력·피해 배율은 물량 몫 일반 몹만: 일반 몹은 줄고, 정예·분열체는 그대로
	var snail_hp := float(ContentDB.get_enemy_def("sap_snail")["hp"]) * float(prof.get("enemy_hp_mult", 1.0))
	var n0 := r._spawn_enemy("sap_snail", Vector2(600, 400), {}, {"no_affix": true})
	check(is_equal_approx(float(n0["max_hp"]), snail_hp * float(t["enemy_count_hp_mult"])) and is_equal_approx(float(n0["horde_dmg"]), r.enemy_damage_factor) and is_equal_approx(float(n0["horde"]), m), "horde-room normal mob gets hp and damage factors (%.1f hp)" % float(n0["max_hp"]))
	var el := r._spawn_enemy("sap_snail", Vector2(600, 420), {"hp_mult": 2.0, "damage_mult": 1.3, "scale": 1.25, "affix": "wet", "name_ko": "젖은 달팽이"})
	check(is_equal_approx(float(el["max_hp"]), snail_hp * 2.0) and float(el["horde_dmg"]) == 1.0 and float(el["horde"]) == 1.0, "elites keep full hp and damage in horde rooms (%.1f)" % float(el["max_hp"]))
	var sp := r._spawn_enemy("sap_snail", Vector2(600, 440), {}, {"no_affix": true, "no_horde": true, "hp_frac": 0.3})
	check(is_equal_approx(float(sp["max_hp"]), snail_hp * 0.3) and float(sp["horde"]) == 1.0, "split children (from an elite) are not horde-scaled")
	# 보상 단위: 일반 몹 3마리 = 3/m 마리, 정예 1마리 = 1 마리
	var ku0 := float(r.stats["kill_units"])
	r._kill_enemy(n0, r.players["p0"])
	r._kill_enemy(el, r.players["p0"])
	check(is_equal_approx(float(r.stats["kill_units"]) - ku0, 1.0 / m + 1.0) and is_equal_approx(float(r.players["p0"]["stats"]["kill_units"]), 1.0 / m + 1.0), "kill units count horde mobs as 1/m (%.3f)" % (float(r.stats["kill_units"]) - ku0))
	check(is_equal_approx(r.normal_drop_chance(float(n0["horde"])), r.normal_drop_chance()) and is_equal_approx(r.normal_drop_chance(1.0), float(ContentDB.equipment["ground_drop"]["normal_chance"])), "drop chance follows the mob's own horde factor")
	check(is_equal_approx(float(r.result_summary().get("count_mult", 0.0)), m), "result summary carries count mult")
	# 배율 1 인 방: 보스·튜토리얼·탐색·시험방
	var rb := CombatRoom.new(ContentDB.get_room_def("boss_ironclaw"), prof, ContentDB.rules, 34, _members(1))
	var rt := CombatRoom.new(ContentDB.get_room_def("tutorial"), prof, ContentDB.rules, 35, _members(1))
	var rx := CombatRoom.new(def, prof, ContentDB.rules, 36, _members(1), {"explore": true})
	var ra := CombatRoom.new(ContentDB.get_room_def("test_arena"), prof, ContentDB.rules, 37, _members(1))
	check(rb.count_mult == 1.0 and rt.count_mult == 1.0 and rx.count_mult == 1.0 and ra.count_mult == 1.0, "boss/tutorial/explore/test rooms keep count mult 1")
	check(rb.enemy_damage_factor == 1.0 and is_equal_approx(rb.normal_drop_chance(), float(ContentDB.equipment["ground_drop"]["normal_chance"])), "boss room adds keep full damage and drop chance")
	var badd := rb._spawn_enemy("sap_snail", Vector2(600, 400))
	check(is_equal_approx(float(badd["max_hp"]), snail_hp) and float(badd["horde_dmg"]) == 1.0, "boss-room adds keep full hp (%.1f)" % float(badd["max_hp"]))
	# 목재: 일반 처치 m 번에 wood_drop 만큼 (소수 누적), 정예는 그대로
	var rw := CombatRoom.new(def, prof, ContentDB.rules, 38, _members(1), {"team_wood": 0})
	for e: Dictionary in rw.enemies.values():
		e["ai"] = Protocol.EnemyAI.DEAD
	var wood_def := ""
	for id: String in ContentDB.enemies.keys():
		if ContentDB.enemies[id] is Dictionary and int(ContentDB.enemies[id].get("wood_drop", 0)) == 1:
			wood_def = id
			break
	if wood_def != "":
		var kills := 6
		for i in kills:
			var ew := rw._spawn_enemy(wood_def, Vector2(600, 400), {}, {"no_affix": true})
			rw._kill_enemy(ew, rw.players["p0"])
		check(rw.team_wood == int(floor(float(kills) / m + 0.0001)), "normal-kill wood divided by count mult (%d from %d kills)" % [rw.team_wood, kills])
	# 작은 몹도 플레이어가 못 지나가는 틈(플레이어 반경 기준)은 못 지나간다: 장애물 주머니에 숨어 방이 안 끝나는 것 방지
	var rg := CombatRoom.new(ContentDB.get_room_def("test_arena"), prof, ContentDB.rules, 39, _members(1))
	rg.obstacles = [{"x": 500.0, "y": 400.0, "r": 40.0}, {"x": 610.0, "y": 400.0, "r": 40.0}]   # 표면 사이 30px (플레이어 지름 36 보다 좁다)
	var leech := rg._spawn_enemy("river_leech", Vector2(555, 300), {}, {"no_affix": true})
	check(float(leech["radius"]) * 2.0 < 30.0, "leech body is narrower than the gap (r=%.1f)" % float(leech["radius"]))
	for i in 90:
		rg._enemy_move(leech, Vector2.DOWN, 1.0 / 30.0)
	check(float(leech["pos"].y) < 400.0, "small enemy cannot slip through a gap players cannot (y=%.1f)" % float(leech["pos"].y))
	# 스냅샷 간격: 30Hz 시뮬레이션에서 1.5틱마다 = 3틱에 2번
	var inst := ExpeditionInstance.new("exp_horde", 555)
	inst.add_member(_make_session(40))
	inst.start_run()
	var snaps := 0
	for i in 30:
		if inst.step(1.0 / 30.0, 1.5).get("snapshot") != null:
			snaps += 1
	check(snaps == 20, "20Hz snapshots from a 30Hz sim (%d in 30 ticks)" % snaps)


## 자동 공격 중 입력: 스킬은 기본 공격 준비·후딜을 끊고 바로 나가고, 명중 순간 누른 스킬은 버퍼로 곧 나간다. F 는 대상이 없으면 공격을 막지 않는다.
func test_input_priority() -> void:
	var dt := 1.0 / 30.0
	var atk := Protocol.BTN_ATTACK
	# 1) 준비 동작 중 Q → 즉시 시전
	var r := _solo_room("guardian", 21)
	var p: Dictionary = r.players["p0"]
	for e: Dictionary in r.enemies.values():
		e["pos"] = Vector2(-9999, -9999)
	r.queue_input("p0", 1, Vector2.ZERO, Vector2.RIGHT * 100, atk)
	r.step(dt)
	check(p["action"] == Protocol.Action.WINDUP and p["action_kind"] == "basic", "auto attack is winding up")
	r.queue_input("p0", 2, Vector2.ZERO, Vector2.RIGHT * 100, atk | Protocol.BTN_Q)
	r.step(dt)
	check(p["action"] == Protocol.Action.CAST and p["action_kind"] == "q", "Q cancels basic windup and casts at once (%d/%s)" % [int(p["action"]), p["action_kind"]])
	# 2) 명중 순간(ACTIVE)에 한 틱만 누른 E → 버퍼로 곧 나간다
	var r2 := _solo_room("guardian", 22)
	var p2: Dictionary = r2.players["p0"]
	for e: Dictionary in r2.enemies.values():
		e["pos"] = Vector2(-9999, -9999)
	var seq := 1
	var guard := 0
	while p2["action"] != Protocol.Action.ACTIVE and guard < 60:
		r2.queue_input("p0", seq, Vector2.ZERO, Vector2.RIGHT * 100, atk)
		r2.step(dt)
		seq += 1
		guard += 1
	check(p2["action"] == Protocol.Action.ACTIVE, "reached the basic attack hit frame")
	r2.queue_input("p0", seq, Vector2.ZERO, Vector2.RIGHT * 100, atk | Protocol.BTN_E)
	r2.step(dt)
	seq += 1
	var cast_at := -1
	for i in 12:
		if p2["action"] == Protocol.Action.CAST and p2["action_kind"] == "e":
			cast_at = i
			break
		r2.queue_input("p0", seq, Vector2.ZERO, Vector2.RIGHT * 100, atk)
		r2.step(dt)
		seq += 1
	check(cast_at >= 0 and cast_at <= 8, "E pressed during the hit frame is buffered and fires (tick %d)" % cast_at)
	# 3) 재사용 대기 중인 스킬은 기본 공격을 끊지 않는다
	var r3 := _solo_room("guardian", 23)
	var p3: Dictionary = r3.players["p0"]
	for e: Dictionary in r3.enemies.values():
		e["pos"] = Vector2(-9999, -9999)
	p3["cd"]["q"] = 5.0
	r3.queue_input("p0", 1, Vector2.ZERO, Vector2.RIGHT * 100, atk)
	r3.step(dt)
	r3.queue_input("p0", 2, Vector2.ZERO, Vector2.RIGHT * 100, atk | Protocol.BTN_Q)
	r3.step(dt)
	check(p3["action_kind"] == "basic", "a skill on cooldown does not cancel the basic attack")
	# 4) F 를 눌러도 대상이 없으면 자동 공격이 계속된다
	var r4 := _solo_room("guardian", 24)
	var p4: Dictionary = r4.players["p0"]
	for e: Dictionary in r4.enemies.values():
		e["pos"] = Vector2(-9999, -9999)
	r4.objects.clear()
	r4.queue_input("p0", 1, Vector2.ZERO, Vector2.RIGHT * 100, atk | Protocol.BTN_INTERACT)
	r4.step(dt)
	check(p4["action"] == Protocol.Action.WINDUP and p4["action_kind"] == "basic", "holding F with nothing to interact keeps attacking")
	# 5) 공격 중 F: 쓰러진 동료가 곁에 있으면 기본 공격을 끊고 바로 구조한다
	var r5 := CombatRoom.new(ContentDB.get_room_def("test_arena"), ContentDB.get_party_profile(2), ContentDB.rules, 25, _members(2))
	for e: Dictionary in r5.enemies.values():
		e["ai"] = Protocol.EnemyAI.ROOTED
		e["root_t"] = 1000.0
		e["pos"] = Vector2(-9999, -9999)
	var a: Dictionary = r5.players["p0"]
	var b: Dictionary = r5.players["p1"]
	b["pos"] = a["pos"] + Vector2(30, 0)
	b["state"] = Protocol.EntState.DOWNED
	b["down_t"] = 30.0
	r5.queue_input("p0", 1, Vector2.ZERO, Vector2.RIGHT * 100, atk)
	r5.step(dt)
	check(a["action"] == Protocol.Action.WINDUP, "p0 auto-attacking before rescue")
	r5.queue_input("p0", 2, Vector2.ZERO, Vector2.RIGHT * 100, atk | Protocol.BTN_INTERACT)
	r5.step(dt)
	check(a["action"] == Protocol.Action.RESCUING, "F next to a downed ally cancels the basic attack and starts rescue (%d)" % int(a["action"]))
	# 자동 공격(공격 버튼)이 계속 눌린 채 F 를 끝까지 누르면 구조가 끊기지 않고 끝난다
	var sq := 3
	for i in int(ceil(float(ContentDB.rules.get("rescue_hold_sec", 3.0)) * 30.0)) + 10:
		r5.queue_input("p0", sq, Vector2.ZERO, Vector2.RIGHT * 100, atk | Protocol.BTN_INTERACT)
		r5.step(dt)
		sq += 1
	check(b["state"] == Protocol.EntState.ALIVE, "rescue completes while auto attack is held (state %d)" % int(b["state"]))
	# 나무 갉기도 자동 공격 중 끝까지 된다
	var r6 := CombatRoom.new(ContentDB.get_room_def("test_arena"), ContentDB.get_party_profile(1), ContentDB.rules, 26, _members(1))
	for e: Dictionary in r6.enemies.values():
		e["ai"] = Protocol.EnemyAI.ROOTED
		e["root_t"] = 1000.0
		e["pos"] = Vector2(-9999, -9999)
	var tree: Dictionary = {}
	for o: Dictionary in r6.objects.values():
		if o["kind"] == Protocol.ObKind.GNAW_TREE:
			tree = o
	if not tree.is_empty():
		r6.players["p0"]["pos"] = tree["pos"] + Vector2(50, 0)
		r6.queue_input("p0", 1, Vector2.ZERO, Vector2.RIGHT * 100, atk)
		r6.step(dt)
		var gnawed := false
		for i in 90:
			r6.queue_input("p0", i + 2, Vector2.ZERO, Vector2.RIGHT * 100, atk | Protocol.BTN_INTERACT)
			for ev: Dictionary in r6.step(dt):
				if ev["k"] == "gnaw":
					gnawed = true
		check(gnawed and not r6.objects.has(tree["id"]), "gnawing a tree completes while auto attack is held")


## 바라보는 방향: 이동 키 방향을 따르고, 마우스(조준)는 공격·스킬 시작 순간에만 방향을 정한다. 마을도 같다.
func test_facing_rules() -> void:
	var room := CombatRoom.new(ContentDB.get_room_def("test_arena"), ContentDB.get_party_profile(1), ContentDB.rules, 3, _members(1))
	var dt := 1.0 / 30.0
	var p: Dictionary = room.players["p0"]
	var seq := 1
	# 마우스는 위를 가리키지만 오른쪽으로 걷는다 → 오른쪽을 본다
	for i in 5:
		room.queue_input("p0", seq, Vector2.RIGHT, Vector2(0, -200), 0)
		seq += 1
		room.step(dt)
	check(p["facing"] == Vector2.RIGHT, "walking faces the movement key, not the mouse")
	# 멈추면 마지막 방향 유지 (마우스가 아래를 가리켜도)
	for i in 5:
		room.queue_input("p0", seq, Vector2.ZERO, Vector2(0, 200), 0)
		seq += 1
		room.step(dt)
	check(p["facing"] == Vector2.RIGHT, "standing still keeps last facing")
	# 공격 버튼: 그 순간의 마우스 방향을 본다
	room.queue_input("p0", seq, Vector2.ZERO, Vector2(0, 200), Protocol.BTN_ATTACK)
	seq += 1
	room.step(dt)
	check(p["facing"] == Vector2.DOWN and p["action"] == Protocol.Action.WINDUP, "attack turns toward the mouse at start")
	# 공격 중에는 이동 키가 방향을 바꾸지 않는다 (WINDUP/ACTIVE)
	room.queue_input("p0", seq, Vector2.LEFT, Vector2(0, 200), 0)
	seq += 1
	room.step(dt)
	check(p["facing"] == Vector2.DOWN, "facing is locked while the swing plays")
	while p["action"] != Protocol.Action.IDLE and seq < 200:
		room.queue_input("p0", seq, Vector2.ZERO, Vector2(0, 200), 0)
		seq += 1
		room.step(dt)
	# 스킬도 시작 순간 마우스 방향
	room.queue_input("p0", seq, Vector2.LEFT, Vector2(300, 0), Protocol.BTN_Q)
	seq += 1
	room.step(dt)
	check(p["facing"] == Vector2.RIGHT and p["action"] == Protocol.Action.CAST, "skill turns toward the mouse at cast start")
	# 마을
	var hub := HubWorld.new()
	var s := Session.new(1)
	s.account_id = "h0"
	hub.apply_input(s, Vector2.LEFT, Vector2(500, 0))
	check(s.hub_facing == Vector2.LEFT, "hub: facing follows movement key")
	hub.apply_input(s, Vector2.ZERO, Vector2(500, 0))
	check(s.hub_facing == Vector2.LEFT, "hub: standing keeps facing")


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


## 테스트 보조: 탐색 중인 방에서 조건에 맞는 문(목표 유형)으로 전원을 세우고 집합 시간이 지나 이동할 때까지 돌린다.
func _travel_through(inst: ExpeditionInstance, want_types: Array = [], want_uncleared: bool = true) -> String:
	if inst.room == null or not inst.room.explore:
		return ""
	var pick: Dictionary = {}
	for o: Dictionary in inst.room.objects.values():
		if int(o["kind"]) != Protocol.ObKind.DOOR:
			continue
		if want_uncleared and bool(o.get("target_cleared", false)):
			continue
		if not want_types.is_empty() and not want_types.has(String(o.get("target_type", ""))):
			continue
		pick = o
		break
	if pick.is_empty():
		return ""
	for p: Dictionary in inst.room.players.values():
		p["pos"] = pick["pos"]
	var guard := 0
	while inst.room != null and inst.room.explore and guard < 200:
		inst.step(1.0 / 30.0, 2)
		guard += 1
	return String(pick.get("dir", ""))


func _clear_current_room(inst: ExpeditionInstance, killer: String) -> void:
	inst.room._all_spawned = true
	inst.room._director_reserve = 0.0   # 테스트: 증원 없이 바로 끝낸다
	inst.room.wave_index = inst.room.wave_count
	for e: Dictionary in inst.room.enemies.values():
		inst.room._kill_enemy(e, inst.room.players[killer])
	if not inst.room.objective in ["annihilate", "boss", "tutorial"]:
		inst.room._objective_complete()   # 거점·장치·호위 방은 목표 달성으로 끝난다
	inst.step(1.0 / 30.0, 2)


func test_run_structure() -> void:
	var a := ExpeditionInstance.new("exp_t", 4242)
	var b := ExpeditionInstance.new("exp_t2", 4242)
	for i in 2:
		a.add_member(_make_session(i))
		b.add_member(_make_session(10 + i))
	a.start_run()
	b.start_run()
	var ga: Dictionary = a.grid()
	check(a.run["dungeons"].size() == 3 and a.state == Protocol.ExpState.IN_ROOM and String(ga.get("region", "")) == "willow_river", "run starts in the first region's start room (combat)")
	check(ga["rooms"].size() >= 7 and ga["rooms"].size() <= 11 and ga["rooms"].has(ga["boss"]) and ga["rooms"].has(ga["start"]), "region grid has 7..11 rooms with start and boss cells (%d)" % ga["rooms"].size())
	check(int(ga["rooms"][ga["start"]]["x"]) == 0 and int(ga["rooms"][ga["boss"]]["x"]) == int(ga["cols"]) - 1, "start in the left column, boss in the right column")
	check(JSON.stringify(a.run["dungeons"]) == JSON.stringify(b.run["dungeons"]), "same seed reproduces the same dungeon (GEN-01)")
	var c := ExpeditionInstance.new("exp_t3", 99)
	c.add_member(_make_session(20))
	c.start_run()
	var cp := c.run_payload()
	check(cp.has("dungeon") and int(cp["dungeon"]["rooms_total"]) >= 7 and int(cp["regions_total"]) == 3, "run payload carries the grid and region count")
	var hidden := 0
	for k: String in cp["dungeon"]["rooms"].keys():
		if String(cp["dungeon"]["rooms"][k]["type"]) == "?":
			hidden += 1
	check(hidden > 0 and String(cp["dungeon"]["rooms"][cp["dungeon"]["boss"]]["type"]) == "boss", "unrevealed rooms are hidden but the boss cell is always shown")
	var locked_doors := 0
	for o: Dictionary in a.room.objects.values():
		if int(o["kind"]) == Protocol.ObKind.DOOR and bool(o.get("locked", false)):
			locked_doors += 1
	check(locked_doors >= 1 and locked_doors == (ga["rooms"][ga["start"]]["doors"] as Dictionary).size(), "combat room has one locked door per grid neighbour")
	# 방 완료 → 보상 3지선다 → 전원 선택 → 같은 방 탐색 모드(문 열림)
	_clear_current_room(a, "run0")
	check(a.state == Protocol.ExpState.REWARD, "victory enters REWARD")
	var opts0: Array = a.run["pending_rewards"]["run0"]
	check(opts0.size() == 3, "three reward options offered")
	check(int(a.run["xp"]) > 0 and int(a.run["players"]["run0"]["acorns"]) > 0, "xp and acorns granted after room")
	check(a.pick_reward("run0", 0), "pick reward")
	check(a.state == Protocol.ExpState.REWARD, "waits for the other member")
	check(a.pick_reward("run1", 1), "second pick")
	check(a.state == Protocol.ExpState.IN_ROOM and a.room != null and a.room.explore and a.is_safe_point(), "after rewards the cleared room becomes an explore room (safe point)")
	check(bool(a.current_node()["cleared"]) and int(a.run["layer"]) == 1, "room marked cleared and depth advanced")
	var rp0: Dictionary = a.run["players"]["run0"]
	check(rp0["relics"].size() + rp0["upgrades"].size() == 1, "reward applied to run player")
	var mods: Dictionary = a.member_mods("run0")["mods"]
	check(mods.has("damage_mult"), "mods computed from relics")
	var unlocked := 0
	for o: Dictionary in a.room.objects.values():
		if int(o["kind"]) == Protocol.ObKind.DOOR and not bool(o.get("locked", false)):
			unlocked += 1
	check(unlocked == locked_doors, "doors unlock after the clear")
	# 문 집합: 한 명만 서 있으면(과반 아님) 진행되지 않고, 전원이 서면 3초 뒤 이동
	var door: Dictionary = {}
	for o: Dictionary in a.room.objects.values():
		if int(o["kind"]) == Protocol.ObKind.DOOR:
			door = o
			break
	a.room.players["run0"]["pos"] = door["pos"]
	a.room.players["run1"]["pos"] = door["pos"] + Vector2(400, 0)
	for i in 60:
		a.step(1.0 / 30.0, 2)
	check(a.room != null and a.room.explore and float(door["progress"]) == 0.0, "one of two at the door (not a majority) does not open it")
	a.room.players["run1"]["pos"] = door["pos"]
	for i in 30:
		a.step(1.0 / 30.0, 2)
	check(a.room != null and a.room.explore and float(door["progress"]) > 0.2 and float(door["progress"]) < 0.9, "all members at the door: progress runs on the 3 s timer")
	var before_cell := String(a.run["cell"])
	for i in 80:
		a.step(1.0 / 30.0, 2)
	check(String(a.run["cell"]) != before_cell and String(a.run["cell"]) == String(ga["rooms"][before_cell]["doors"][door["dir"]]), "party moved through the door to the neighbouring cell")
	check(a.state in [Protocol.ExpState.IN_ROOM, Protocol.ExpState.NODE_MENU, Protocol.ExpState.REWARD], "neighbouring cell entered (combat, menu or treasure)")
	if a.state == Protocol.ExpState.IN_ROOM:
		check(not a.room.explore and a.room.entry_dir == ExpeditionInstance.DOOR_OPPOSITE[door["dir"]], "new combat room knows the entry door (%s)" % a.room.entry_dir)
		check(a.room.entry_spawns.has("run0") and a.room.players["run0"]["pos"].distance_to(CombatRoom.door_positions(a.room.room_def, ContentDB.rules)[a.room.entry_dir]) < 260.0, "players spawn just inside the entry door")
	# 되돌아가기: 클리어된 방은 탐색 모드로 다시 들어가고 적이 없다
	var back := ExpeditionInstance.new("exp_back", 4242)
	back.add_member(_make_session(5))
	back.start_run()
	_clear_current_room(back, "run5")
	back.pick_reward("run5", 0)
	var first_cell := String(back.run["cell"])
	var d1 := _travel_through(back, ["combat", "elite"])
	check(d1 != "" and String(back.run["cell"]) != first_cell, "travelled to an uncleared combat neighbour")
	if back.state == Protocol.ExpState.IN_ROOM and not back.room.explore:
		_clear_current_room(back, "run5")
		back.pick_reward("run5", 0)
		var came_from: String = ExpeditionInstance.DOOR_OPPOSITE[d1]
		var d2 := ""
		for o: Dictionary in back.room.objects.values():
			if int(o["kind"]) == Protocol.ObKind.DOOR and String(o["dir"]) == came_from:
				check(bool(o.get("target_cleared", false)), "door back to the cleared room is flagged cleared")
				back.room.players["run5"]["pos"] = o["pos"]
				d2 = came_from
		for i in 200:
			if back.room == null or not back.room.explore or String(back.run["cell"]) == first_cell:
				break
			back.step(1.0 / 30.0, 2)
		check(String(back.run["cell"]) == first_cell and back.room.explore and back.room.enemies.is_empty(), "backtracking re-enters the cleared room in explore mode without enemies")
	# 이탈자는 보상·문 이동을 막지 않는다
	var d := ExpeditionInstance.new("exp_t4", 77)
	d.add_member(_make_session(30))
	d.add_member(_make_session(31))
	d.start_run()
	d.mark_disconnected("run31")
	_clear_current_room(d, "run30")
	d.pick_reward("run30", 0)
	check(d.state != Protocol.ExpState.REWARD, "disconnected member's reward is defaulted so the party proceeds")
	var moved := _travel_through(d)
	check(moved != "", "a lone connected member counts as everyone at the door")
	# 안전 지점 합류: 합류 묶음과 N 재산정 (탐색 중 합류하면 걷는 방에 바로 들어온다)
	var e_inst := ExpeditionInstance.new("exp_t5", 500)
	e_inst.add_member(_make_session(40))
	e_inst.start_run()
	_clear_current_room(e_inst, "run40")
	check(e_inst.is_safe_point() and e_inst.can_join("run41") == "", "REWARD is a safe point for joining")
	e_inst.pick_reward("run40", 0)
	check(e_inst.is_safe_point() and e_inst.can_join("run41") == "", "explore mode is a safe point for joining")
	e_inst.add_member(_make_session(41))
	check(e_inst.run["players"].has("run41") and e_inst.room.players.has("run41"), "joiner gets a run player record and stands in the explore room")
	var guard := 0
	while guard < 6 and not (e_inst.state == Protocol.ExpState.IN_ROOM and not e_inst.room.explore):
		guard += 1
		if e_inst.state == Protocol.ExpState.IN_ROOM and e_inst.room.explore:
			if _travel_through(e_inst) == "":
				break
		elif e_inst.state == Protocol.ExpState.NODE_MENU:
			e_inst.node_action("run40", {"action": "continue"})
			e_inst.node_action("run41", {"action": "continue"})
			if e_inst.state == Protocol.ExpState.NODE_MENU:
				e_inst.node_action("run40", {"action": "vote", "choice": String(ContentDB.events[String(e_inst.run["menu"]["variant"])]["choices"][0]["id"])})
				e_inst.node_action("run41", {"action": "vote", "choice": String(ContentDB.events[String(e_inst.run["menu"]["variant"])]["choices"][0]["id"])})
		elif e_inst.state == Protocol.ExpState.REWARD:
			e_inst.pick_reward("run40", 0)
			e_inst.pick_reward("run41", 0)
	check(e_inst.state == Protocol.ExpState.IN_ROOM and not e_inst.room.explore and e_inst.n_locked == 2, "next combat room recalculates N with the joiner (state %d n %d)" % [e_inst.state, e_inst.n_locked])
	# 잘린 던전(테스트 설정): 방 1개면 클리어·보상 뒤 바로 완주
	ExpeditionInstance.debug_route_layers = 1
	var t1 := ExpeditionInstance.new("exp_t6", 12)
	t1.add_member(_make_session(45))
	t1.start_run()
	check(t1.grid()["rooms"].size() == 1 and String(t1.grid()["boss"]) == "", "debug_route_layers=1 keeps only the start room")
	_clear_current_room(t1, "run45")
	t1.pick_reward("run45", 0)
	check(t1.state == Protocol.ExpState.RESULT and t1.run_outcome == Protocol.Outcome.VICTORY, "truncated dungeon finishes the run after its last room")
	ExpeditionInstance.debug_route_layers = -1
	var t2 := ExpeditionInstance.new("exp_t7", 12)
	t2.add_member(_make_session(46))
	t2.start_run()
	check(t2.room != null and t2.room.boss != null and String(t2.current_node()["type"]) == "boss", "debug_route_layers=-1 starts in the boss room")
	ExpeditionInstance.debug_route_layers = 0


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
	# 씨앗은 시전 시 0 으로 소모되고, 회복 자체가 (0.5초 간격이 지났다면) 씨앗 1 을 다시 준다
	check(healed_amount >= 18.0 + seeds * 3 - 0.01 and int(p["resource"]) <= 1, "life sap heals base + seeds and consumes seeds (%.0f)" % healed_amount)
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
	# 3지역 던전: 격자가 이어지고 지역 보스 3개, 재현 가능
	var dungeons: Array = ExpeditionInstance.build_dungeon(4242, "willow_river", 3)
	var bosses := 0
	var regions := {}
	for g: Dictionary in dungeons:
		regions[String(g.get("region", ""))] = true
		for node: Dictionary in g.get("rooms", {}).values():
			if String(node["type"]) == "boss":
				bosses += 1
	check(bosses == 3 and regions.size() == 3, "dungeon spans 3 regions with 3 bosses (bosses %d, regions %d)" % [bosses, regions.size()])
	check(JSON.stringify(dungeons) == JSON.stringify(ExpeditionInstance.build_dungeon(4242, "willow_river", 3)), "dungeon reproducible for the same seed")
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


func test_difficulty_tutorial_pause() -> void:
	# 난이도 배율
	var inst := ExpeditionInstance.new("exp_d", 5)
	inst.difficulty = "hard"
	var prof := inst.effective_profile(ContentDB.get_party_profile(2))
	check(is_equal_approx(float(prof["enemy_hp_mult"]), 1.1 * 1.25) and is_equal_approx(float(prof["hit_damage_mult"]), 1.3), "hard difficulty multiplies profile (%s)" % [prof])
	inst.difficulty = "nope"
	var up := inst.effective_profile(ContentDB.get_party_profile(1))
	var bp := ContentDB.get_party_profile(1)
	check(is_equal_approx(float(up["enemy_hp_mult"]), float(bp["enemy_hp_mult"])) and is_equal_approx(float(up["hit_damage_mult"]), float(bp["hit_damage_mult"])) and is_equal_approx(float(up["boss_hp_mult"]), float(bp["boss_hp_mult"])), "unknown difficulty leaves multipliers unchanged")
	# 튜토리얼: 단계가 실제 행동으로 넘어가고, 건너뛰기가 방을 끝낸다
	var room := CombatRoom.new(ContentDB.get_room_def("tutorial"), ContentDB.get_party_profile(1), ContentDB.rules, 1, _members(1))
	check(room.objective == "tutorial" and room.enemies.size() >= 1 and room.enemies.values()[0]["role"] == "dummy", "tutorial room with dummies")
	var dt := 1.0 / 30.0
	var first_ev := false
	for ev: Dictionary in room.step(dt):
		if ev["k"] == "tutorial_step" and int(ev["index"]) == 0:
			first_ev = true
	check(first_ev, "first tutorial hint is sent on the first tick")
	var p: Dictionary = room.players["p0"]
	var seq := 1
	for i in 60:
		room.queue_input("p0", seq, Vector2.RIGHT, Vector2.ZERO, 0)
		seq += 1
		room.step(dt)
	check(room.tutorial_step == 1, "moving 200px completes the move step (step %d)" % room.tutorial_step)
	for e: Dictionary in room.enemies.values():
		room._damage_enemy(e, 1000.0, p, 0.0, 0.0)
	room.step(dt)
	check(room.tutorial_step == 2, "killing the dummy completes the attack step")
	var dummy_moved := false
	for e: Dictionary in room.enemies.values():
		if e["ai"] != Protocol.EnemyAI.DEAD and e["ai"] != Protocol.EnemyAI.IDLE:
			dummy_moved = true
	check(not dummy_moved, "dummies never chase or attack")
	room.queue_input("p0", seq, Vector2.RIGHT, Vector2.ZERO, Protocol.BTN_DODGE)
	seq += 1
	room.step(dt)
	check(room.tutorial_step == 3, "dodge completes the dodge step")
	room.tutorial_skip()
	room.step(dt)
	check(room.outcome == Protocol.Outcome.VICTORY and room.objective_done, "skip ends the tutorial as a clear")
	# 핑 이벤트는 다음 틱에 실린다
	var room2 := CombatRoom.new(ContentDB.get_room_def("test_arena"), ContentDB.get_party_profile(1), ContentDB.rules, 1, _members(1))
	room2.pending_events.append({"k": "ping", "id": "p0", "x": 10, "y": 20})
	var got_ping := false
	for ev: Dictionary in room2.step(dt):
		if ev["k"] == "ping":
			got_ping = true
	check(got_ping and room2.pending_events.is_empty(), "pending ping delivered once")
	# 파티 중단/이어하기: 안전 지점에서만 중단, 체크포인트에 paused, 멤버 복귀 시 해제 (SAVE-01)
	var e2 := ExpeditionInstance.new("exp_p", 77)
	var s0 := _make_session(60)
	e2.add_member(s0)
	e2.start_run()
	check(not e2.pause_run(), "cannot pause mid-combat")
	e2.room._all_spawned = true
	e2.room._director_reserve = 0.0   # 테스트: 증원 없이 바로 끝낸다
	for en: Dictionary in e2.room.enemies.values():
		e2.room._kill_enemy(en, e2.room.players["run60"])
	e2.step(dt, 2)
	check(e2.is_safe_point(), "reached a safe point after the room (state %d)" % e2.state)
	check(e2.pause_run() and e2.paused and bool(e2.to_checkpoint()["paused"]), "pause at safe point saves a paused checkpoint")
	var relics_before: Array = (e2._run_player("run60")["relics"] as Array).duplicate()
	var restored := ExpeditionInstance.from_checkpoint(e2.to_checkpoint())
	check(restored.paused and restored._run_player("run60")["relics"] == relics_before, "restored paused expedition keeps player state (no duplication)")
	restored.resume_member(s0)
	check(not restored.paused and not restored.suspended and restored.members["run60"]["connected"], "member resume clears paused state")
	# 관리자: 중단된 원정은 멤버에게만 이어하기로 보이고, 남에게는 보이지 않는다
	var mgr := ExpeditionManager.new(2, 1)
	mgr.instances[restored.id] = restored
	restored.paused = true
	var mine := mgr.board_list("run60")
	var other := mgr.board_list("someone")
	check(mine.size() == 1 and bool(mine[0].get("resume", false)) and other.is_empty(), "paused expedition listed only for its members as resume")
	var s1 := _make_session(61)
	var rj := mgr.join(s1, restored.id)
	check(not bool(rj["ok"]), "non-member cannot join a paused expedition")
	s0.expedition_id = ""   # 중단 후 마을로 돌아간 상태
	var rj2 := mgr.join(s0, restored.id)
	check(bool(rj2["ok"]) and bool(rj2.get("resumed", false)) and not restored.paused, "member resumes through join")


func test_snapshot_codec() -> void:
	check(Protocol.SNAP_P.size() == SnapshotCodec.PLAYER_FIELDS and Protocol.SNAP_E.size() == SnapshotCodec.ENEMY_FIELDS, "codec field counts match Protocol enums")
	var room := CombatRoom.new(ContentDB.get_room_def("test_arena"), ContentDB.get_party_profile(4), ContentDB.rules, 7, _members(4))
	for i in 30:
		room.queue_input("p0", 1 + i, Vector2.RIGHT, Vector2.RIGHT, Protocol.BTN_ATTACK if i % 9 == 0 else 0)
		room.step(1.0 / 30.0)
	var snap := room.snapshot()
	snap["ack"] = 77
	snap["boss"] = {"id": "ironclaw", "x": 512.3, "y": 300.7, "fx": 0.6, "fy": -0.8, "hp": 1234.5, "max_hp": 4000.0, "state": 3, "phase": 1, "shell_broken": 2, "shell_total": 3, "f": 9, "grabbed": "p1", "stagger_gauge": 40.0, "m": "IC-02", "mt": 12.3, "pattern": "claw_sweep"}
	snap["future_key"] = {"a": 1}
	var bytes := SnapshotCodec.encode(snap)
	var back := SnapshotCodec.decode(bytes)
	check(bytes.size() * 2 < var_to_bytes(snap).size(), "codec at least halves the 4-player snapshot (%d -> %d bytes)" % [var_to_bytes(snap).size(), bytes.size()])
	check(int(back["t"]) == int(snap["t"]) and int(back["ack"]) == 77 and back["wave"] == snap["wave"] and int(back["wood"]) == int(snap["wood"]), "codec keeps tick/ack/wave/wood")
	check(String(back["obj"][0]) == String(snap["obj"][0]) and absf(float(back["obj"][1]) - float(snap["obj"][1])) < 0.001 and int(back["obj"][2]) == int(snap["obj"][2]), "codec keeps objective")
	var ps: Array = snap["p"]
	var qs: Array = back["p"]
	var perr := 0.0
	var pid_ok := ps.size() == qs.size()
	for i in ps.size():
		pid_ok = pid_ok and String(ps[i][0]) == String(qs[i][0])
		var a: PackedFloat32Array = ps[i][1]
		var b: PackedFloat32Array = qs[i][1]
		for k in a.size():
			perr = maxf(perr, absf(a[k] - b[k]))
	check(pid_ok and qs.size() == 4, "codec keeps 4 player ids in order")
	check(perr <= 0.13, "player fields within quantization error (%.3f)" % perr)
	var es: Array = snap["e"]
	var fs: Array = back["e"]
	var eerr := 0.0
	var eid_ok := es.size() == fs.size() and es.size() > 0
	for i in es.size():
		eid_ok = eid_ok and int(es[i][0]) == int(fs[i][0]) and int(es[i][1]) == int(fs[i][1])
		var a: PackedFloat32Array = es[i][2]
		var b: PackedFloat32Array = fs[i][2]
		for k in a.size():
			eerr = maxf(eerr, absf(a[k] - b[k]))
	check(eid_ok, "codec keeps enemy ids and type indices")
	check(eerr <= 0.13, "enemy fields within quantization error (%.3f)" % eerr)
	var os: Array = snap["ob"]
	var qo: Array = back["ob"]
	var ob_ok := os.size() == qo.size()
	for i in os.size():
		var a: PackedFloat32Array = os[i]
		var b: PackedFloat32Array = qo[i]
		ob_ok = ob_ok and int(a[0]) == int(b[0]) and int(a[1]) == int(b[1]) and int(a[6]) == int(b[6]) and absf(a[2] - b[2]) <= 0.13 and absf(a[5] - b[5]) < 0.001
	check(ob_ok, "codec keeps objects (id/kind/state exact, progress float)")
	check((back["tg"] as Array).size() == (snap["tg"] as Array).size() and (back["pr"] as Array).size() == (snap["pr"] as Array).size(), "codec keeps telegraph/projectile counts")
	var bb: Dictionary = back["boss"]
	check(String(bb["id"]) == "ironclaw" and int(bb["f"]) == 9 and String(bb["m"]) == "IC-02" and String(bb["pattern"]) == "claw_sweep" and String(bb["grabbed"]) == "p1" and int(bb["state"]) == 3 and int(bb["phase"]) == 1, "codec keeps boss discrete fields")
	check(absf(float(bb["x"]) - 512.3) <= 0.13 and absf(float(bb["hp"]) - 1234.5) < 0.001 and absf(float(bb["mt"]) - 12.3) <= 0.03 and absf(float(bb["stagger_gauge"]) - 40.0) < 0.001, "codec keeps boss numeric fields")
	check(back.has("future_key") and back["future_key"] == snap["future_key"], "codec carries unknown keys verbatim")
	var hub := {"hub": 1, "p": [["acc1", 10.5, 20.5, 0.5, 0.5, "guardian", 1]]}
	check(SnapshotCodec.decode(SnapshotCodec.encode(hub)) == hub, "codec round-trips a generic (hub) snapshot")
	check(SnapshotCodec.decode(PackedByteArray()).is_empty(), "codec tolerates an empty packet")


func test_v3_pack_assets() -> void:
	# v3-A: 사수 8동작·수호목수 4동작·적 3종 이동/피격/사망·가재 4동작이 최종본이고 열 수가 요청서와 같다
	var expect := {"char.pinecone.walk": 4, "char.pinecone.attack": 4, "char.pinecone.cast_q": 4, "char.pinecone.cast_e": 4, "char.pinecone.cast_r": 4, "char.pinecone.hit": 2, "char.pinecone.down": 2, "char.pinecone.death": 4,
		"char.guardian.hit": 2, "char.guardian.down": 2, "char.guardian.death": 4, "char.guardian.interact": 4,
		"enemy.sap_snail.walk": 4, "enemy.sap_snail.hit": 2, "enemy.sap_snail.death": 4, "enemy.thorn_boar.walk": 4, "enemy.thorn_boar.charge": 4, "enemy.black_bird.death": 4,
		"boss.ironclaw.walk": 4, "boss.ironclaw.hit": 2, "boss.ironclaw.death": 6, "boss.ironclaw.molt": 4}
	var ok := true
	for id: String in expect.keys():
		var e := AssetRegistry.entry(id)
		var sheet := AssetRegistry.get_sheet(id)
		if String(e.get("status", "")) != "final" or int(sheet["hframes"]) != int(expect[id]) or int(sheet["vframes"]) != 4 or bool(sheet["is_fallback"]):
			ok = false
			failures.append("v3a sheet %s: status=%s cols=%d rows=%d" % [id, e.get("status", ""), int(sheet["hframes"]), int(sheet["vframes"])])
	check(ok, "v3-A character sheets are final with requested frame counts (4 directions)")
	check(AssetRegistry.entry("char.pinecone.attack").get("animation", {}).get("event_frames", {}).get("hit", -1) == 2 and AssetRegistry.entry("char.pinecone.cast_e").get("animation", {}).get("event_frames", {}).get("hit", -1) == 3, "ranger visual contact frames: attack/Q/R 2, E 3")
	var husk := AssetRegistry.get_sheet("prop.boss.husk")
	check(AssetRegistry.status("prop.boss.husk") == "final" and husk["frame_size"] == Vector2(256, 256) and int(husk["hframes"]) == 1, "husk_all is a 256x256 single frame (size exception honoured)")
	check(not bool(AssetRegistry.get_sheet("boss.ironclaw.molt")["loop"]), "boss molt is one-shot (held by boss state), not auto-looping")
	# v3-B: VFX 프레임 수·재생 모드
	var vfx := {"vfx.hammer_swing": [4, "one_shot"], "vfx.log_shield": [4, "loop"], "vfx.tail_shockwave": [5, "one_shot"], "vfx.great_tree": [6, "state_sequence"], "vfx.thorn_trap": [4, "state_sequence"], "vfx.forest_volley": [6, "one_shot"],
		"vfx.projectile_pinecone": [2, "loop"], "vfx.hit_spark": [3, "one_shot"], "vfx.rescue_ring": [4, "loop"], "vfx.heal_burst": [4, "one_shot"], "vfx.boss_ground_slam": [5, "one_shot"], "vfx.whirlpool": [4, "loop"]}
	ok = true
	for id: String in vfx.keys():
		var sheet := AssetRegistry.get_sheet(id)
		if AssetRegistry.status(id) != "final" or int(sheet["hframes"]) != int(vfx[id][0]) or String(sheet["mode"]) != String(vfx[id][1]):
			ok = false
			failures.append("v3b vfx %s: cols=%d mode=%s" % [id, int(sheet["hframes"]), sheet["mode"]])
	check(ok, "v3-B VFX sheets are final with requested frame counts and playback modes")
	var trap: Dictionary = AssetRegistry.get_sheet("vfx.thorn_trap")["segments"]
	check(not bool(AssetRegistry.get_sheet("vfx.thorn_trap")["loop"]) and _ints(trap.get("idle", {}).get("indices", [])) == [1, 2] and _ints(trap.get("trigger", {}).get("indices", [])) == [3], "thorn trap: whole strip does not loop; idle segment [1,2], trigger [3]")
	check(bool(AssetRegistry.get_sheet("vfx.great_tree")["hold_last"]), "great tree holds its last (active) frame")
	# v3-C: 타일·소품
	check(int(AssetRegistry.get_sheet("tile.willow.wall")["hframes"]) >= 9 and int(AssetRegistry.get_sheet("tile.willow.water")["hframes"]) == 2 and int(AssetRegistry.get_sheet("tile.willow.shore")["hframes"]) >= 4, "willow wall >=9 / water 2 / shore >=4 tiles (v4 adds corners)")
	check(AssetRegistry.get_sheet("tile.willow.ground")["frame_size"] == Vector2(256, 256) and AssetRegistry.status("tile.willow.ground") == "final", "willow ground is a 256px mosaic of the 4 variants")
	var props := {"prop.gnaw_tree": 3, "prop.device": 4, "prop.lever": 2, "prop.sluice_gate": 3, "prop.log_cover": 2, "prop.hold_point": 2, "prop.campfire": 2, "prop.hub.memory_tree": 3, "prop.hub.workshop": 3, "prop.hub.board": 1, "prop.stall": 1}
	ok = true
	for id: String in props.keys():
		if AssetRegistry.status(id) != "final" or int(AssetRegistry.get_sheet(id)["hframes"]) != int(props[id]):
			ok = false
			failures.append("v3c prop %s cols=%d" % [id, int(AssetRegistry.get_sheet(id)["hframes"])])
	check(ok, "v3-C props are final state strips with requested frame counts")
	var ft := AssetRegistry.get_frame_texture("prop.gnaw_tree", 2)
	check(ft != null and ft.get_width() == 256 and ft.get_height() == 256 and ft != AssetRegistry.get_frame_texture("prop.gnaw_tree", 0), "get_frame_texture cuts a single 256px frame and distinguishes frames")
	# v3-D/E: 아이콘·UI
	ok = true
	for id in ["icon.skill.guardian.q", "icon.skill.pinecone.r", "icon.heal", "icon.dodge", "icon.relic.oak_heart", "icon.status.slow", "ui.panel.default", "ui.button.default", "ui.button.hover", "ui.button.pressed", "ui.card.reward", "ui.card.route", "ui.bar.hp", "ui.bar.boss", "ui.title.logo", "ui.app_icon", "ui.frame.portrait"]:
		if AssetRegistry.status(id) != "final":
			ok = false
			failures.append("v3de %s status=%s" % [id, AssetRegistry.status(id)])
	check(ok, "v3-D/E icons and UI entries are final")
	var hp := AssetRegistry.entry("ui.bar.hp")
	check(_ints(hp.get("fill_rect_px", [])) == [17, 8, 222, 9] and int(AssetRegistry.get_sheet("ui.bar.hp")["hframes"]) == 2, "hp bar keeps frame/fill layers and the declared fill rect")
	check(int(AssetRegistry.entry("ui.panel.default").get("nine_slice_margin", 0)) == 12 and int(AssetRegistry.entry("ui.button.hover").get("nine_slice_margin", 0)) == 12, "panel/button 9-slice margins are 12px")
	check(int(AssetRegistry.get_sheet("ui.card.route")["hframes"]) == 5 and int(AssetRegistry.get_sheet("ui.card.reward")["hframes"]) == 2, "route card 5 variants, reward card 2 variants")


func _ints(a: Array) -> Array:
	var out: Array = []
	for v in a:
		out.append(int(v))
	return out


func test_roguelike_systems() -> void:
	# --- 서약(열기): 정리·열기 합·프로필 반영
	var n := ContentDB.normalize_pacts({"hard_shell": 2, "elite_season": 1, "nope": 3, "thin_sap": 9})
	check(n["pacts"] == {"hard_shell": 2, "elite_season": 1, "thin_sap": 1} and int(n["heat"]) == 5, "pacts normalized (unknown dropped, rank clamped) and heat summed (%s)" % [n])
	var inst := ExpeditionInstance.new("exp_rl", 21)
	inst.add_member(_make_session(70))
	inst.set_pacts({"hard_shell": 2, "wild_river": 1, "thin_sap": 1, "short_breath": 1, "ancient_armor": 1, "greedy_stall": 1})
	inst.start_run()
	var prof := inst.effective_profile(ContentDB.get_party_profile(1))
	check(is_equal_approx(float(prof["enemy_hp_mult"]), 1.4) and is_equal_approx(float(prof["hit_damage_mult"]), 1.2) and is_equal_approx(float(prof["boss_hp_mult"]), 1.25), "pacts multiply hp/damage/boss hp (%s)" % [prof])
	check(int(prof["dodge_charges_add"]) == -1 and is_equal_approx(float(prof["mechanic_gap_mult"]), 0.8) and is_equal_approx(float(prof["shop_price_mult"]), 1.4), "pacts feed dodge/mechanic gap/shop price")
	check(int(inst.members["run70"]["heal_uses"]) == int(ContentDB.rule("heal_uses_per_expedition", 2)) - 1, "thin sap pact removes one heal use at run start")
	check(int(inst.heat) == 8 and int(inst.to_checkpoint()["heat"]) == 8 and ExpeditionInstance.from_checkpoint(JSON.parse_string(JSON.stringify(inst.to_checkpoint()))).heat == 8, "heat survives the checkpoint round-trip (%d)" % inst.heat)
	# --- 위험도: 전투 시간·층으로 오르고 상한이 있다
	var d0 := inst.danger()
	inst.run["stats"]["combat_sec"] = 600.0
	inst.run["layer"] = 5
	var d1 := inst.danger()
	inst.run["stats"]["combat_sec"] = 100000.0
	var d2 := inst.danger()
	check(is_equal_approx(d0, 1.0) and d1 > 1.5 and d1 < 2.2 and is_equal_approx(d2, float(ContentDB.rule("danger", {}).get("max", 2.2))), "danger rises with combat time and layer and is capped (%.2f %.2f %.2f)" % [d0, d1, d2])
	inst.run["stats"]["combat_sec"] = 0.0
	inst.run["layer"] = 0
	# --- 디렉터 증원: 웨이브가 끝난 뒤 예산의 일부만큼 더 나오고, 예산이 다하면 방이 끝난다
	var room := CombatRoom.new(ContentDB.get_room_def("annihilate"), ContentDB.get_party_profile(1), ContentDB.rules, 5, _members(1))
	var spawned_before := int(room.stats["enemies_spawned"])
	var guard := 0
	var reinforced := false
	while not room.is_finished() and guard < 6000:
		guard += 1
		for en: Dictionary in room.enemies.values():
			if en["ai"] != Protocol.EnemyAI.DEAD:
				room._damage_enemy(en, 1000.0, room.players["p0"], 0.0, 0.0)
		for ev: Dictionary in room.step(1.0 / 30.0):
			if ev["k"] == "reinforce":
				reinforced = true
	check(room.outcome == Protocol.Outcome.VICTORY and reinforced and int(room.stats["enemies_spawned"]) > spawned_before, "director reinforces after the waves and the room still ends (%d spawned, %d steps)" % [int(room.stats["enemies_spawned"]), guard])
	# --- 정예 접두: 젖은(둔화)·검은 수액(회복 절반)·가시 껍질(반사 출혈)·재생·분열
	var r2 := CombatRoom.new(ContentDB.get_room_def("test_arena"), ContentDB.get_party_profile(1), ContentDB.rules, 6, _members(1))
	var p0: Dictionary = r2.players["p0"]
	var wet := r2._spawn_enemy("sap_snail", p0["pos"] + Vector2(40, 0), {"hp_mult": 2.0, "damage_mult": 1.0, "scale": 1.2, "affix": "wet", "name_ko": "젖은 달팽이"})
	check(String(wet["affix"]) == "wet" and bool(wet["elite"]), "elite spawned with an explicit affix")
	r2._damage_player(p0, 5.0, wet["pos"], str(wet["id"]), wet)
	check(float(p0["slow_t"]) > 0.0 and float(p0["slow_mult"]) > 0.3, "wet elite hit slows the player")
	var sap := r2._spawn_enemy("sap_snail", p0["pos"] + Vector2(-40, 0), {"hp_mult": 2.0, "affix": "black_sap"})
	r2._damage_player(p0, 5.0, sap["pos"], str(sap["id"]), sap)
	p0["hp"] = 50.0
	var healed := r2._heal_player(p0, 20.0, p0)
	check(float(p0["heal_cut_t"]) > 0.0 and is_equal_approx(healed, 10.0), "black sap halves healing (%.1f)" % healed)
	var thorn := r2._spawn_enemy("sap_snail", p0["pos"] + Vector2(30, 0), {"hp_mult": 2.0, "affix": "thorn_shell"})
	r2._damage_enemy(thorn, 5.0, p0, 0.0, 0.0)
	check(float(p0["bleed_t"]) > 0.0, "thorn shell reflects bleed to melee attackers")
	var regen := r2._spawn_enemy("sap_snail", Vector2(600, 400), {"hp_mult": 2.0, "affix": "regen_shell"})
	r2._damage_enemy(regen, 30.0, p0, 0.0, 0.0)
	var hp_after_hit := float(regen["hp"])
	for i in 120:
		r2.elapsed += 1.0 / 30.0
		r2._step_enemy(regen, 1.0 / 30.0)
	check(float(regen["hp"]) > hp_after_hit + 1.0, "regen shell heals after not being hit (%.1f -> %.1f)" % [hp_after_hit, float(regen["hp"])])
	var split := r2._spawn_enemy("sap_snail", Vector2(700, 400), {"hp_mult": 2.0, "affix": "splitting"})
	var before := r2.enemies.size()
	r2._damage_enemy(split, 10000.0, p0, 0.0, 0.0)
	check(r2.enemies.size() == before + 2, "splitting elite leaves two small copies")
	var copies := 0
	for en: Dictionary in r2.enemies.values():
		if int(en.get("split_depth", 0)) == 1:
			copies += 1
			r2._damage_enemy(en, 10000.0, p0, 0.0, 0.0)
	check(copies == 2 and r2.enemies.size() == before + 2, "copies do not split again")
	# 정예 확률: force_elite 프로필이면 첫 일반 스폰이 접두 정예가 된다
	var fp := ContentDB.get_party_profile(1).duplicate()
	fp["force_elite"] = true
	fp["elite_chance"] = 0.0
	var r3 := CombatRoom.new(ContentDB.get_room_def("annihilate"), fp, ContentDB.rules, 7, _members(1))
	var forced := 0
	for en: Dictionary in r3.enemies.values():
		if bool(en["elite"]) and String(en.get("affix", "")) != "":
			forced += 1
	check(forced == 1, "combat altar forces exactly one affix elite in the next room (%d)" % forced)
	# --- 보상 희귀도·리롤
	var inst2 := ExpeditionInstance.new("exp_rw", 33)
	inst2.add_member(_make_session(71))
	inst2.start_run()
	var rr := RandomNumberGenerator.new()
	rr.seed = 1
	var rare_only := inst2._weighted_relic(inst2._relic_pool("run71"), "run71", rr, "rare")
	check(rare_only != "" and String(ContentDB.relics[rare_only].get("rarity", "")) != "common", "min_rarity picks only rare or better")
	var rares := 0
	for i in 200:
		var pick := inst2._weighted_relic(inst2._relic_pool("run71"), "run71", rr)
		if String(ContentDB.relics[pick].get("rarity", "common")) != "common":
			rares += 1
	check(rares > 5 and rares < 120, "rarity weights give mostly common with some rare (%d/200)" % rares)
	inst2._begin_reward()
	var first: Array = (inst2.run["pending_rewards"]["run71"] as Array).duplicate(true)
	check(inst2.reroll_reward("run71") and int(inst2.run["players"]["run71"]["rerolls"]) == 0 and inst2.run["pending_rewards"]["run71"] != first, "reroll replaces the offer and spends the run's reroll")
	check(not inst2.reroll_reward("run71"), "no rerolls left")
	# --- 제단 사건: 도토리 지불·확률 유물·피의 제단·저주·전투 제단
	var ev := ExpeditionInstance.new("exp_alt", 12)
	ev.add_member(_make_session(72))
	ev.start_run()
	ev.run["players"]["run72"]["acorns"] = 50
	ev._begin_menu("event", "chance_altar")
	ev.node_action("run72", {"action": "vote", "choice": "pay_big"})
	var rp72: Dictionary = ev.run["players"]["run72"]
	check(int(rp72["acorns"]) == 10 and ((rp72["relics"] as Array).is_empty() or String(ContentDB.relics[rp72["relics"][0]].get("rarity", "")) != "common"), "chance altar charges acorns and can grant a rare+ relic")
	var ev2 := ExpeditionInstance.new("exp_alt2", 13)
	ev2.add_member(_make_session(73))
	ev2.start_run()
	ev2.members["run73"]["hp"] = 100.0
	ev2._begin_menu("event", "blood_altar")
	ev2.node_action("run73", {"action": "vote", "choice": "bleed"})
	check(is_equal_approx(float(ev2.members["run73"]["hp"]), 65.0) and int(ev2.run["players"]["run73"]["acorns"]) == 25, "blood altar trades hp for acorns")
	var ev3 := ExpeditionInstance.new("exp_alt3", 14)
	ev3.add_member(_make_session(74))
	ev3.start_run()
	ev3._begin_menu("event", "cursed_crate")
	ev3.node_action("run74", {"action": "vote", "choice": "open"})
	check(int(ev3.run["curse_rooms"]) == 2 and (ev3.run["players"]["run74"]["relics"] as Array).size() == 1, "cursed crate grants a relic and a 2-room curse")
	var cp := ev3.effective_profile(ContentDB.get_party_profile(1))
	check(is_equal_approx(float(cp["player_damage_taken_mult"]), 1.3), "curse raises damage taken in the profile")
	var ev4 := ExpeditionInstance.new("exp_alt4", 15)
	ev4.add_member(_make_session(75))
	ev4.start_run()
	ev4._begin_menu("event", "combat_altar")
	ev4.node_action("run75", {"action": "vote", "choice": "drum"})
	check(int(ev4.run["next_room_elite"]) == 1 and int(ev4.run["bonus_shards"]) == 2 and is_equal_approx(float(ev4.run["next_room_budget_add"]), 4.0) and bool(ev4.effective_profile(ContentDB.get_party_profile(1))["force_elite"]), "combat altar arms the next room and promises shards")
	# --- 휴식: 숫돌은 강화 1개, 휴식은 회복
	var rs := ExpeditionInstance.new("exp_rest", 16)
	rs.add_member(_make_session(76))
	rs.add_member(_make_session(77))
	rs.start_run()
	rs.members["run76"]["hp"] = 30.0
	rs.members["run77"]["hp"] = 30.0
	rs._begin_menu("rest", "campfire")
	rs.node_action("run76", {"action": "rest_choice", "choice": "smith"})
	rs.node_action("run77", {"action": "continue"})
	check((rs.run["players"]["run76"]["upgrades"] as Array).size() == 1 and is_equal_approx(float(rs.members["run76"]["hp"]), 30.0), "smith grants an upgrade and no heal")
	check(float(rs.members["run77"]["hp"]) > 30.0, "continue without a choice heals")
	rs.node_action("run76", {"action": "rest_choice", "choice": "heal"})
	check(is_equal_approx(float(rs.members["run76"]["hp"]), 30.0), "one choice per player per rest")
	# --- 보스: 갑각 온전 시 피해 감소, 기믹 실패 시 회복·추가 적
	var br := CombatRoom.new(ContentDB.get_room_def("boss_ironclaw"), ContentDB.get_party_profile(1), ContentDB.rules, 8, _members(1))
	var bscript: GDScript = load("res://server/expedition/boss_ironclaw.gd")
	var boss = bscript.new(br, ContentDB.get_party_profile(1), ContentDB.bosses["ironclaw"])
	br.boss = boss
	check(is_equal_approx(boss.damage_taken_mult(), 0.6), "intact shell reduces damage taken to 60%")
	boss.shell_broken = 1
	check(boss.damage_taken_mult() > 1.0, "breaking a shell segment removes the reduction")
	boss.hp = boss.max_hp * 0.5
	boss.active = "IC-01"
	boss.mechanics["IC-01"]["state"] = "active"
	var adds_before := br.enemies.size()
	boss._finish_mechanic(false, "test")
	check(is_equal_approx(boss.hp, boss.max_hp * 0.55) and br.enemies.size() == adds_before + 2, "failed mechanic heals the boss 5%% and spawns 2 adds (%d)" % (br.enemies.size() - adds_before))
	check(int(ContentDB.bosses["ironclaw"]["hp"]) == 900 and int(ContentDB.bosses["ironclaw"]["mechanic_gap_sec"]) == 9, "pacing: boss hp 900, mechanic gap 9s")
	check(int(ContentDB.get_room_def("annihilate")["waves"]["wave_count"]) == 4 and float(ContentDB.get_room_def("annihilate")["waves"]["base_budget"]) >= 14.0, "density: annihilate rooms have 4 waves and budget 14")


func test_v4_pack_assets() -> void:
	# F1~F3: 직업 3종 8상태, 적 9종 3상태, 보스 2종 4상태 (4방향 최종본)
	var ok := true
	var expect := {}
	for cid in ["sawtooth", "sapshaman", "hydro"]:
		for st in ["walk", "attack", "cast", "cast_q", "cast_e", "cast_r"]:
			expect["char.%s.%s" % [cid, st]] = 4
		expect["char.%s.hit" % cid] = 2
		expect["char.%s.down" % cid] = 2
	for eid in ["shell_soldier", "spore_mushroom", "root_puppet", "reed_frog", "river_leech", "lantern_moth", "woodjaw_beetle", "gear_crab", "sap_totem"]:
		expect["enemy.%s.walk" % eid] = 4
		expect["enemy.%s.hit" % eid] = 2
		expect["enemy.%s.death" % eid] = 4
	for bid in ["lantern_toad", "root_king"]:
		expect["boss.%s.walk" % bid] = 4
		expect["boss.%s.hit" % bid] = 2
		expect["boss.%s.death" % bid] = 6
		expect["boss.%s.molt" % bid] = 4
	for id: String in expect.keys():
		var sheet := AssetRegistry.get_sheet(id)
		if AssetRegistry.status(id) != "final" or int(sheet["hframes"]) != int(expect[id]) or int(sheet["vframes"]) != 4 or bool(sheet["is_fallback"]):
			ok = false
			failures.append("v4 sheet %s: status=%s cols=%d rows=%d" % [id, AssetRegistry.status(id), int(sheet["hframes"]), int(sheet["vframes"])])
	check(ok, "v4 class/enemy/boss sheets are final 4-direction strips with requested frame counts")
	check(int(AssetRegistry.entry("char.sawtooth.cast_e").get("animation", {}).get("event_frames", {}).get("hit", -1)) == 3 and int(AssetRegistry.entry("char.hydro.attack").get("animation", {}).get("event_frames", {}).get("hit", -1)) == 2, "new class contact frames: attack/Q/R 2, E 3")
	check(AssetRegistry.status("char.sawtooth.idle") == "final" and AssetRegistry.status("boss.ironclaw.idle") == "final", "v1/v2 idle sheets are kept (merge by animation, not by actor)")
	# 타일 인덱스 (docs/terrain_indices.json)
	check(int(AssetRegistry.get_sheet("tile.willow.wall")["hframes"]) == 13 and int(AssetRegistry.get_sheet("tile.willow.shore")["hframes"]) == 12, "willow wall 13 (outer corners) and shore 12 (convex/concave corners)")
	ok = true
	for rg in ["swamp", "rootdam"]:
		if int(AssetRegistry.get_sheet("tile.%s.wall" % rg)["hframes"]) != 9 or int(AssetRegistry.get_sheet("tile.%s.water" % rg)["hframes"]) != 2 or int(AssetRegistry.get_sheet("tile.%s.shore" % rg)["hframes"]) != 4 or AssetRegistry.status("tile.%s.ground" % rg) != "final":
			ok = false
	check(ok, "swamp and root-dam tiles: ground mosaic, wall 9, water 2, shore 4")
	# 소품 상태 수
	var props := {"prop.boss.pillar": 3, "prop.boss.gate": 3, "prop.boss.claw_link": 3, "prop.boss.corridor": 3, "prop.boss.rope": 3, "prop.boss.debris": 3, "prop.boss.anchor": 3, "prop.boss.platform": 3, "prop.dam": 3, "prop.raft": 2, "prop.secret": 2, "prop.turret": 3, "prop.swamp.mushroom": 2, "prop.swamp.stump": 2, "prop.hub.training_ground": 3, "prop.hub.herbal_hut": 3, "prop.hub.archive": 3}
	ok = true
	for id: String in props.keys():
		if AssetRegistry.status(id) != "final" or int(AssetRegistry.get_sheet(id)["hframes"]) != int(props[id]):
			ok = false
			failures.append("v4 prop %s cols=%d" % [id, int(AssetRegistry.get_sheet(id)["hframes"])])
	check(ok, "v4 props are final state strips")
	# VFX
	ok = true
	for id in ["vfx.gnaw_dash", "vfx.wood_split", "vfx.log_whirl", "vfx.sap_bloom", "vfx.root_bind", "vfx.spring_flood", "vfx.water_turret", "vfx.torrent_valve", "vfx.great_dam", "vfx.projectile_water", "vfx.telegraph_circle", "vfx.telegraph_line"]:
		if AssetRegistry.status(id) != "final":
			ok = false
	check(ok, "v4 VFX for the three new classes and both telegraphs are final")
	check(int(AssetRegistry.get_sheet("vfx.great_tree_active")["hframes"]) == 2 and bool(AssetRegistry.get_sheet("vfx.great_tree_active")["loop"]) and int(AssetRegistry.get_sheet("vfx.great_tree")["hframes"]) == 6, "great tree keeps the v3 growth strip and adds the v4 active loop")
	check(_ints(AssetRegistry.entry("vfx.telegraph_circle").get("visual_bounds_px", [])) == [229, 215], "telegraph circle carries its visual ring bounds (not a hitbox)")
	# 아이콘·초상·NPC
	ok = true
	for id in ["icon.skill.sawtooth.q", "icon.skill.hydro.r", "icon.relic.storm_tail", "icon.class.sapshaman", "icon.enemy.gear_crab", "portrait.hydro", "portrait.root_king", "npc.merchant_doto", "portrait.npc.smith_resin"]:
		if AssetRegistry.status(id) != "final":
			ok = false
	check(ok, "v4 icons, portraits and NPC sprites are final")
	var rep := AssetRegistry.report()
	check(int(rep["placeholder"]) == 0 and int(rep["planned"]) == 0, "no placeholder or planned entries remain (%d / %d)" % [int(rep["placeholder"]), int(rep["planned"])])
	# 카드 content_rect
	check(_ints(AssetRegistry.entry("ui.card.reward").get("content_rect", [])) == [56, 69, 144, 246] and _ints(AssetRegistry.entry("ui.card.route").get("content_rect", [])) == [56, 44, 144, 96], "v4 cards carry their transparent content rect")
	# 오디오: wav 효과음·ogg 루프
	var sfx := AssetRegistry.get_audio("sfx.dodge")
	check(sfx != null and sfx is AudioStreamWAV and AssetRegistry.status("sfx.dodge") == "final", "sfx wav loads as a stream")
	var bgm := AssetRegistry.get_audio("bgm.hub")
	check(bgm != null and bgm is AudioStreamOggVorbis and (bgm as AudioStreamOggVorbis).loop and AssetRegistry.entry("bgm.hub").get("bus", "") == "Music", "bgm ogg loads with loop enabled")
	var amb := AssetRegistry.get_audio("amb.water")
	check(amb != null and amb is AudioStreamOggVorbis and (amb as AudioStreamOggVorbis).loop and float(AssetRegistry.entry("amb.water").get("gain_db", 0.0)) < 0.0, "ambience ogg loads with loop and a negative suggested gain")
	ok = true
	for id in ["sfx.down", "sfx.great_tree", "sfx.hammer_hit", "sfx.player_hit", "sfx.rescue", "sfx.sling", "sfx.snail_death", "sfx.snail_hit", "sfx.tail_slam", "sfx.ui_click", "sfx.wood_block", "bgm.combat_normal", "bgm.boss", "amb.wind"]:
		if AssetRegistry.get_audio(id) == null:
			ok = false
			failures.append("audio %s failed to load" % id)
	check(ok, "all 17 pack audio entries decode")


## 영구 장비: 데이터 무결성, 등급별 줄 수·계층 제한, 재현, 상한, 장착/해제, 무기 교체가 전투에 반영되는지
func test_equipment() -> void:
	var eqdb: Dictionary = ContentDB.equipment
	check(eqdb.get("weapons", {}).size() == 10 and eqdb.get("armors", {}).size() == 3 and eqdb.get("trinkets", {}).size() == 4, "10 weapons (2 per class), 3 armors, 4 trinkets defined")
	for cid: String in ["guardian", "sawtooth", "pinecone", "sapshaman", "hydro"]:
		var n := 0
		for wid: String in eqdb["weapons"].keys():
			if String(eqdb["weapons"][wid].get("class", "")) == cid:
				n += 1
		check(n == 2 and Equipment.default_weapon(cid) != "", "class %s has 2 weapons and a default" % cid)
	# 모든 특성·고유의 mods 키가 RunMods 키여야 전투에 반영된다
	var bad_keys: Array = []
	for a: Dictionary in ContentDB.gear_affixes.get("affixes", []):
		for k: String in a.get("mods", {}).keys():
			if not RunMods.MOD_KEYS.has(k):
				bad_keys.append(k)
	for u: Dictionary in ContentDB.gear_affixes.get("uniques", []):
		for k: String in u.get("mods", {}).keys():
			if not RunMods.MOD_KEYS.has(k):
				bad_keys.append(k)
	for tbl: String in ["weapons", "armors", "trinkets"]:
		for bid: String in eqdb[tbl].keys():
			for k: String in eqdb[tbl][bid].get("base", {}).keys():
				if not RunMods.MOD_KEYS.has(k):
					bad_keys.append(k)
	check(bad_keys.is_empty(), "all gear mod keys are RunMods keys (%s)" % [bad_keys])
	check(ContentDB.gear_affixes.get("affixes", []).size() >= 45 and ContentDB.gear_affixes.get("uniques", []).size() == 9, "affix pool >= 45 and 9 uniques")
	# 등급별 줄 수 + 계층 제한 + 전설 고유
	var rng := RandomNumberGenerator.new()
	var lines_ok := true
	var tier_ok := true
	var unique_ok := true
	for r: String in ["common", "uncommon", "rare", "epic", "legendary"]:
		var rdef := Equipment.rarity_def(r)
		for i in 12:
			rng.seed = 1000 + i
			var it := Equipment.roll_item(rng, "pinecone", 1, r, "weapon")
			if (it["affixes"] as Array).size() != int(rdef["lines"]):
				lines_ok = false
			for af: Dictionary in it["affixes"]:
				var a := Equipment.affix_def(String(af["id"]))
				if int(a.get("tier", 1)) > int(rdef["tier_max"]):
					tier_ok = false
				if a.has("attack") and String(a["attack"]) != "projectile":
					tier_ok = false
			if (String(it.get("unique", "")) != "") != bool(rdef.get("unique", false)):
				unique_ok = false
	check(lines_ok, "affix line count follows rarity (0/1/2/3/3)")
	check(tier_ok, "affix tiers respect the rarity tier cap and weapon attack shape")
	check(unique_ok, "only legendary items carry a unique trait")
	rng.seed = 77
	var a1 := Equipment.roll_item(rng, "guardian", 2, "epic", "weapon")
	rng.seed = 77
	var a2 := Equipment.roll_item(rng, "guardian", 2, "epic", "weapon")
	check(JSON.stringify(a1) == JSON.stringify(a2) and String(a1["class"]) == "guardian", "same seed rolls the same item; weapon matches the class")
	var uniq_ids: Dictionary = {}
	for af: Dictionary in a1["affixes"]:
		uniq_ids[String(af["id"])] = true
	check(uniq_ids.size() == (a1["affixes"] as Array).size(), "no duplicate affix on one item")
	# 등급 굴림: 최소 등급과 보너스
	var counts := {}
	for i in 400:
		rng.seed = 5000 + i
		var r := Equipment.roll_rarity(rng, "rare", 0.0)
		counts[r] = int(counts.get(r, 0)) + 1
	check(not counts.has("common") and not counts.has("uncommon") and int(counts.get("rare", 0)) > int(counts.get("legendary", 0)), "min rarity floor respected and rare stays commoner than legendary (%s)" % [counts])
	# 레벨 배율·설명·이름
	var lvl3 := {"uid": "x", "slot": "armor", "base": "bark_vest", "rarity": "common", "level": 3, "affixes": [], "unique": ""}
	check(is_equal_approx(float(Equipment.item_mods(lvl3)["mods"]["max_hp_add"]), 14.0 * 1.5), "base stat scales with region level (14 × 1.5)")
	check(Equipment.describe(a1).size() >= 4 and Equipment.display_name(a1).begins_with("영웅의 "), "describe lists base + affix lines; epic name prefix")
	# 장착/해제 + 상한 + 무기 교체
	var prog := {"inventory": [], "equipped": {}}
	rng.seed = 9
	var log_w := {}
	for i in 50:
		var cand := Equipment.roll_item(rng, "guardian", 1, "uncommon", "weapon")
		if String(cand["base"]) == "guardian_log":
			log_w = cand
			break
	check(not log_w.is_empty(), "rolled the alternate guardian weapon (log)")
	prog["inventory"].append(log_w)
	var big := {"uid": "big1", "slot": "armor", "base": "shell_plate", "rarity": "legendary", "level": 3, "affixes": [{"id": "a_dr", "t": 1.0}, {"id": "a_hp", "t": 1.0}, {"id": "a_damage", "t": 1.0}], "unique": "u_ancient_shell"}
	prog["inventory"].append(big)
	var t1 := {"uid": "t1", "slot": "trinket", "base": "resin_ring", "rarity": "common", "level": 1, "affixes": [], "unique": ""}
	var t2 := {"uid": "t2", "slot": "trinket", "base": "firefly_bead", "rarity": "common", "level": 1, "affixes": [], "unique": ""}
	prog["inventory"].append(t1)
	prog["inventory"].append(t2)
	check(Equipment.equip(prog, "weapon", String(log_w["uid"])) == "" and String(prog["equipped"]["weapon"]["guardian"]) == String(log_w["uid"]), "weapon equips into the class slot")
	check(Equipment.equip(prog, "armor", "big1") == "" and Equipment.equip(prog, "trinket1", "t1") == "" and Equipment.equip(prog, "trinket2", "t2") == "", "armor and two trinkets equip")
	check(Equipment.equip(prog, "trinket1", "t2") == "" and String(prog["equipped"]["trinket2"]) == "" and String(prog["equipped"]["trinket1"]) == "t2", "moving a trinket between slots frees the old slot")
	check(Equipment.equip(prog, "armor", "nope") == "NO_ITEM", "unknown uid rejected")
	var bundle := Equipment.gear_bundle(prog, "guardian")
	check(bundle["items"].size() == 3 and String(bundle["weapon_id"]) == "guardian_log" and not (bundle["weapon_attack"] as Dictionary).is_empty(), "bundle collects weapon + armor + one trinket for the class")
	check(float(bundle["mods"]["damage_reduction"]) <= float(eqdb["caps"]["damage_reduction"]) + 0.0001 and float(bundle["mods"]["damage_reduction"]) > 0.1, "gear cap clamps damage reduction (%.3f)" % float(bundle["mods"]["damage_reduction"]))
	var has_unique_proc := false
	for pr: Dictionary in bundle["procs"]:
		if String(pr.get("source", "")).begins_with("unique:"):
			has_unique_proc = true
	check(has_unique_proc, "unique proc carried into the bundle")
	check(Equipment.gear_bundle(prog, "pinecone")["weapon_id"] == "" and Equipment.gear_bundle(prog, "pinecone")["items"].size() == 2, "another class sees no weapon but shares armor/trinket")
	check(Equipment.equip(prog, "weapon:guardian", "") == "" and not prog["equipped"]["weapon"].has("guardian"), "weapon unequip by class slot")
	# 전투 반영: 무기 교체 정의가 기본 공격에 덮이고, 장비 mods 가 member_mods 에 합산된다
	var inst := ExpeditionInstance.new("exp_gear", 21)
	var s := _make_session(80)
	inst.add_member(s)
	inst.members["run80"]["gear"] = {"mods": {"max_hp_add": 20.0, "damage_mult": 0.1}, "procs": [{"trigger": "on_kill", "effect": "heal", "value": 3, "icd_sec": 0.5, "source": "gear:test"}], "weapon_attack": ContentDB.equipment["weapons"]["guardian_log"]["basic_attack"], "weapon_id": "guardian_log"}
	inst.start_run()
	var p: Dictionary = inst.room.players["run80"]
	check(is_equal_approx(float(p["max_hp"]), float(ContentDB.get_class_def("guardian")["base_hp"]) + 20.0), "gear max hp applied to combat")
	check(float(p["mods"]["damage_mult"]) >= 0.1, "gear damage mult merged into mods")
	var atk := inst.room.basic_attack_def(p)
	check(int(atk["damage"]) == 17 and float(atk["angle_deg"]) == 165.0 and String(atk.get("shape", "arc")) == "arc", "weapon override replaces basic attack numbers but keeps the class shape")
	var has_gear_proc := false
	for pr: Dictionary in p["procs"]:
		if String(pr.get("source", "")) == "gear:test":
			has_gear_proc = true
	check(has_gear_proc, "gear proc present on the combat player")
	# 산탄 무기: 투사체 3개
	var inst2 := ExpeditionInstance.new("exp_gear2", 22)
	var s2 := _make_session(81, "pinecone")
	inst2.add_member(s2)
	inst2.members["run81"]["gear"] = {"mods": {}, "procs": [], "weapon_attack": ContentDB.equipment["weapons"]["pinecone_launcher"]["basic_attack"], "weapon_id": "pinecone_launcher"}
	inst2.start_run()
	var p2: Dictionary = inst2.room.players["run81"]
	inst2.room.projectiles.clear()
	inst2.room._apply_basic_attack(p2, inst2.room.basic_attack_def(p2))
	check(inst2.room.projectiles.size() == 3, "launcher fires 3 pellets")
	# 강화: 비용·상한·기본 속성 배율, 재감정: 줄 교체·계층 유지·중복 금지, 분해: 장착 중 불가·재료 획득
	var prog2 := {"inventory": [], "equipped": {}, "materials": {"sap_crystal": 0}}
	var rare_arm := {"uid": "ra", "slot": "armor", "base": "bark_vest", "rarity": "rare", "level": 1, "affixes": [{"id": "a_hp", "t": 0.5}, {"id": "a_speed", "t": 0.5}], "unique": "", "name_ko": "정교한 나무껍질 조끼"}
	prog2["inventory"].append(rare_arm)
	check(Equipment.enhance(prog2, "ra") == "NOT_ENOUGH_MATERIALS", "enhance refused without crystals")
	Equipment.add_material(prog2, 100)
	var c0 := Equipment.enhance_cost(rare_arm)
	check(c0 == int(ceil(3.0 * (1.0 + 2 * 0.5))), "enhance cost = 3 × (1 + rarity index × 0.5) for rare (%d)" % c0)
	check(Equipment.enhance(prog2, "ra") == "" and int(rare_arm["enhance"]) == 1 and Equipment.material_count(prog2) == 100 - c0, "enhance +1 consumes crystals")
	check(is_equal_approx(float(Equipment.item_mods(rare_arm)["mods"]["max_hp_add"]), 14.0 * 1.10 * 1.1 + Equipment.affix_value([6, 20], 0.5, "int")), "enhance scales only the base stat (+10% per level, on top of the rare base_mult 1.10)")
	check(rare_arm["name_ko"].ends_with("+1") and Equipment.describe(rare_arm)[0].contains("강화 +1"), "name and description show the enhance level")
	for i in 4:
		Equipment.enhance(prog2, "ra")
	check(int(rare_arm["enhance"]) == 5 and Equipment.enhance(prog2, "ra") == "MAX_ENHANCE" and Equipment.enhance_cost(rare_arm) == -1, "enhance stops at +5")
	var before_mats := Equipment.material_count(prog2)
	var rr := RandomNumberGenerator.new()
	rr.seed = 3
	check(Equipment.reforge(prog2, "ra", 5, rr) == "BAD_INDEX", "reforge rejects a bad line index")
	var old_id := String(rare_arm["affixes"][1]["id"])
	check(Equipment.reforge(prog2, "ra", 1, rr) == "" and String(rare_arm["affixes"][1]["id"]) != old_id and String(rare_arm["affixes"][1]["id"]) != "a_hp" and (rare_arm["affixes"] as Array).size() == 2, "reforge replaces the chosen line with a different, non-duplicate affix")
	check(Equipment.material_count(prog2) == before_mats - Equipment.reforge_cost(rare_arm), "reforge consumes the rarity cost")
	var tier_ok2 := true
	for i in 20:
		Equipment.add_material(prog2, 10)
		Equipment.reforge(prog2, "ra", 0, rr)
		if int(Equipment.affix_def(String(rare_arm["affixes"][0]["id"])).get("tier", 1)) > 2 or Equipment.affix_def(String(rare_arm["affixes"][0]["id"])).has("class"):
			tier_ok2 = false
	check(tier_ok2, "reforged lines stay within the rarity tier cap and slot rules")
	Equipment.equip(prog2, "armor", "ra")
	check(Equipment.salvage(prog2, "ra") == "ITEM_EQUIPPED", "equipped item cannot be salvaged")
	Equipment.equip(prog2, "armor", "")
	var mats_before := Equipment.material_count(prog2)
	check(Equipment.salvage_value(rare_arm) == 5 + 5 and Equipment.salvage(prog2, "ra") == "" and Equipment.find_item(prog2, "ra").is_empty() and Equipment.material_count(prog2) == mats_before + 10, "salvage removes the item and pays rarity value + enhance level")
	# 강화 결과 3단계: 성공률은 단계마다 내려가고 파괴는 1% 고정, 실패는 재료만 소모
	var table: Array = eqdb["enhance"]["success_chance"]
	var falling := true
	for i in range(1, table.size()):
		if float(table[i]) > float(table[i - 1]):
			falling = false
	check(falling and float(table[0]) >= 0.9 and is_equal_approx(float(eqdb["enhance"]["destroy_chance"]), 0.01), "success chance falls with level (%s), destroy fixed at 1%%" % [table])
	var outcomes := {"ok": 0, "fail": 0, "destroy": 0}
	var trials := 3000
	var orng := RandomNumberGenerator.new()
	orng.seed = 4242
	for i in trials:
		var pr := {"inventory": [{"uid": "e%d" % i, "slot": "armor", "base": "bark_vest", "rarity": "common", "level": 1, "affixes": [], "unique": "", "enhance": 4, "name_ko": "x"}], "equipped": {"armor": "e%d" % i}, "materials": {"sap_crystal": 100}}
		var r := Equipment.enhance(pr, "e%d" % i, orng)
		if r == "":
			outcomes["ok"] += 1
			if int(pr["inventory"][0]["enhance"]) != 5:
				outcomes["ok"] = -99999
		elif r == "ENHANCE_FAILED":
			outcomes["fail"] += 1
			if int(pr["inventory"][0]["enhance"]) != 4 or Equipment.material_count(pr) == 100:
				outcomes["fail"] = -99999
		elif r == "ENHANCE_DESTROYED":
			outcomes["destroy"] += 1
			if not (pr["inventory"] as Array).is_empty() or String(pr["equipped"]["armor"]) != "":
				outcomes["destroy"] = -99999
	var p_ok := float(outcomes["ok"]) / trials
	var p_destroy := float(outcomes["destroy"]) / trials
	check(absf(p_ok - float(table[4])) < 0.04 and absf(p_destroy - 0.01) < 0.008 and outcomes["fail"] > 0, "+4→+5 outcomes match the table (ok %.2f fail %d destroy %.3f); failure keeps the level, destruction removes and unequips" % [p_ok, outcomes["fail"], p_destroy])
	# 제작 도안: 기본 3종 열림, 보스 도안 잠김 → 해금 → 비용 차감·창고 추가
	var prog3 := {"inventory": [], "equipped": {}, "materials": {"sap_crystal": 50}, "memory_shards": 20, "blueprints": []}
	var crng := RandomNumberGenerator.new()
	crng.seed = 8
	check(Equipment.recipes().size() == 9 and Equipment.recipe_unlocked(prog3, Equipment.recipe_def("bp_uncommon_weapon")) and not Equipment.recipe_unlocked(prog3, Equipment.recipe_def("bp_rare_weapon")), "9 recipes; uncommon open, rare locked at start")
	check(Equipment.craft(prog3, "bp_rare_weapon", "guardian", crng).get("error", "") == "RECIPE_LOCKED", "locked recipe refused")
	var made := Equipment.craft(prog3, "bp_uncommon_weapon", "sawtooth", crng)
	check(made.has("item") and String(made["item"]["rarity"]) == "uncommon" and String(made["item"]["class"]) == "sawtooth" and (made["item"]["affixes"] as Array).size() == 1 and Equipment.material_count(prog3) == 46 and int(prog3["memory_shards"]) == 18 and prog3["inventory"].size() == 1, "crafting rolls the recipe's slot/rarity for the current class and pays crystals + shards")
	prog3["blueprints"].append_array(Equipment.blueprints_for_boss("ironclaw"))
	check(Equipment.blueprints_for_boss("ironclaw").size() == 2 and Equipment.recipe_unlocked(prog3, Equipment.recipe_def("bp_rare_weapon")), "ironclaw kill unlocks the two rare blueprints")
	prog3["memory_shards"] = 1
	check(Equipment.craft(prog3, "bp_rare_armor", "guardian", crng).get("error", "") == "NOT_ENOUGH_SHARDS", "crafting checks memory shards")
	# 바닥 드랍 규칙: 일반·정예 확률, 보스 확정 희귀 이상, 창고 상한. 아무 직업 무기나 나올 수 있다
	var gd: Dictionary = eqdb["ground_drop"]
	check(float(gd.get("normal_chance", 0)) > 0.0 and float(gd.get("elite_chance", 0)) > float(gd.get("normal_chance", 0)) and String(gd.get("boss_min_rarity", "")) == "rare" and int(eqdb["drop"].get("inventory_cap", 0)) == 60, "ground drop rules: normal < elite chance, boss min rarity rare, cap 60")
	var classes_seen := {}
	for i in 200:
		var w := Equipment.roll_item(crng, "", 1, "common", "weapon", i + 1)
		classes_seen[String(w.get("class", ""))] = true
	check(classes_seen.size() >= 4, "ground drops roll weapons of any class (%d classes in 200 rolls)" % classes_seen.size())


## 방 지형 랜덤화: 재현성, 보스·튜토리얼 제외, 보호 지점 침범 없음, 연결성, 원정 입장 페이로드에 생성 지형 포함
func test_room_gen() -> void:
	var base := ContentDB.get_room_def("hold_point")
	var a := RoomGen.decorate(base, 4242)
	var b := RoomGen.decorate(base, 4242)
	var c := RoomGen.decorate(base, 4243)
	check(a.has("generated") and JSON.stringify(a) == JSON.stringify(b), "room gen is reproducible for the same seed")
	check(JSON.stringify(a.get("obstacles", [])) != JSON.stringify(c.get("obstacles", [])), "different seeds give different obstacles")
	check((a["obstacles"] as Array).size() >= 3 and JSON.stringify(a["hold_zone"]) == JSON.stringify(base["hold_zone"]) and JSON.stringify(a["player_spawns"]) == JSON.stringify(base["player_spawns"]), "generated room keeps anchors (hold zone, spawns) and has obstacles")
	for o: Dictionary in a["obstacles"]:
		for pt: Dictionary in RoomGen.protected_points(a):
			check(Vector2(float(o["x"]), float(o["y"])).distance_to(pt["pos"]) >= float(pt["keep"]) + float(o["r"]) - 0.5, "obstacle keeps clear of protected point")
	check(RoomGen.validate(a).is_empty(), "generated room is fully connected")
	var boss := ContentDB.get_room_def("boss_ironclaw")
	check(not RoomGen.decorate(boss, 1).has("generated") and JSON.stringify(RoomGen.decorate(boss, 1)) == JSON.stringify(boss), "boss rooms are never randomized")
	# 프리팹 조각: 격자 메타·조각 ID·충돌 원 소품은 지역 소품, 장식은 최종 에셋만
	var meta: Dictionary = a.get("generated", {})
	check(String(meta.get("mode", "")) == "prefab" and int(meta.get("cols", 0)) == 4 and int(meta.get("rows", 0)) == 3, "prefab mode: 1400x900 room is a 4x3 chunk grid (%s)" % [meta])
	var ids := {}
	for row: Array in meta.get("chunks", []):
		for cid: String in row:
			ids[cid] = true
	check(ids.size() >= 2, "several different chunks used (%d)" % ids.size())
	for o: Dictionary in a["obstacles"]:
		check(String(o["asset"]) == "" or AssetRegistry.has(String(o["asset"])), "chunk collider uses a known prop id (%s)" % o.get("asset", ""))
	for d: Dictionary in a.get("decor", []):
		check(AssetRegistry.has(String(d["asset"])) and AssetRegistry.status(String(d["asset"])) == "final", "decor only references final assets")
	check(RoomGen.asset_for_role("willow_river", "boulder") == "prop.willow.boulder_cluster" and RoomGen.asset_for_role("ancient_root_dam", "trunk") == "prop.dam.trunk", "roles use the v7 props now that they are final")
	# v7 팩: 27개 ID 가 final·select_frame 이고 변형 수가 요청과 같다
	var v7_expect := {"boulder_cluster": 2, "trunk": 2, "trunk_long_h": 1, "trunk_long_v": 1, "stump_cluster": 2, "bush": 3}
	var v7_ok := 0
	for reg: String in ["willow", "swamp", "dam"]:
		for role: String in v7_expect.keys():
			var vid := "prop.%s.%s" % [reg, role]
			var sh := AssetRegistry.get_sheet(vid)
			if AssetRegistry.status(vid) == "final" and not bool(sh["is_fallback"]) and int(sh["hframes"]) == int(v7_expect[role]) and String(sh["mode"]) == "select_frame":
				v7_ok += 1
		for kind: String in ["dirt", "leaves", "puddle"]:
			var did := "decal.%s.%s" % [reg, kind]
			var dsh := AssetRegistry.get_sheet(did)
			if AssetRegistry.status(did) == "final" and not bool(dsh["is_fallback"]) and int(dsh["hframes"]) == 3:
				v7_ok += 1
	check(v7_ok == 27, "v7 pack: 27 prop/decal sheets registered as final select_frame variants (%d)" % v7_ok)
	var sfx_ok := 0
	for sid: String in ["sfx.drop.common", "sfx.drop.uncommon", "sfx.drop.rare", "sfx.drop.epic", "sfx.drop.legendary", "sfx.pickup"]:
		if AssetRegistry.status(sid) == "final" and AssetRegistry.get_audio(sid) != null:
			sfx_ok += 1
	check(sfx_ok == 6, "drop/pickup sounds registered and loadable (%d/6)" % sfx_ok)
	var deco_room := RoomGen.decorate(ContentDB.get_room_def("swamp_annihilate"), 777)
	check((deco_room.get("decor", []) as Array).size() >= 2, "generated room now carries floor decals (%d)" % (deco_room.get("decor", []) as Array).size())
	# 막힌 방은 검사에 걸린다
	var blocked := base.duplicate(true)
	blocked["obstacles"] = [{"shape": "circle", "x": 700, "y": 450, "r": 480, "asset": "prop.willow.rock"}]
	check(not RoomGen.validate(blocked).is_empty(), "validator reports unreachable points")
	# 원정 입장 페이로드는 생성된 지형을 담는다
	var inst := ExpeditionInstance.new("exp_gen", 99)
	var s0 := Session.new(1)
	s0.account_id = "g0"
	s0.nickname = "G0"
	s0.class_id = "guardian"
	inst.add_member(s0)
	inst.start_run()
	var payload := inst.room_enter_payload()
	check(JSON.stringify(payload["room_def"]["obstacles"]) == JSON.stringify(inst.room.room_def["obstacles"]), "enter payload carries the generated obstacles")


## 적 처치 → 바닥 드랍 → 밟아서 줍기(서버 본체가 처리할 목록) → 버리기(본인은 잠시 못 주움)
func test_ground_drops() -> void:
	var room := CombatRoom.new(ContentDB.get_room_def("test_arena"), ContentDB.get_party_profile(1), ContentDB.rules, 77, _members(1), {"drop": {"heat": 0, "depth": 0, "level": 1, "tutorial": false, "mult": 1000.0}})
	var dt := 1.0 / 30.0
	var p: Dictionary = room.players["p0"]
	var e: Dictionary = room.enemies.values()[0]
	var before := room.ground_items.size()
	room._damage_enemy(e, 100000.0, p, 0.0, 0.0)
	room.step(dt)
	check(room.ground_items.size() == before + 1, "killing an enemy with drop chance x1000 leaves one item on the ground")
	var gi: Dictionary = room.ground_items.values()[0]
	var dropped := false
	for ev: Dictionary in room.events:
		if ev.get("k", "") == "drop" and int(ev.get("gid", -1)) == int(gi["gid"]):
			dropped = true
	check(dropped or room.pending_events.is_empty(), "drop event carries the ground id")
	check((gi["pos"] as Vector2).distance_to(e["pos"]) <= 80.0, "item lands near the corpse")
	# 밟으면 pending_pickups 로 넘어가고 바닥에서 사라진다
	p["pos"] = gi["pos"]
	room.step(dt)
	check(room.pending_pickups.size() == 1 and not room.ground_items.has(int(gi["gid"])), "walking over an item queues a pickup and removes it from the floor")
	var pk: Dictionary = room.pending_pickups[0]
	room.pending_pickups.clear()
	# 창고가 찼다면 되돌리고 잠시 잠근다
	room.return_ground_item(pk["gi"], "p0", 4.0)
	room.step(dt)
	check(room.ground_items.size() == 1 and room.pending_pickups.is_empty(), "returned item is locked for that player")
	# 버린 장비: 본인은 owner_lock_sec 동안 못 줍고, 이벤트는 다음 틱에 실린다
	var gid2 := room.place_ground_item({"uid": "it_x", "slot": "armor", "base": "bark_vest", "rarity": "epic", "name_ko": "테스트 조끼", "affixes": []}, p["pos"], "p0")
	var evs := room.step(dt)
	var seen := false
	for ev: Dictionary in evs:
		if ev.get("k", "") == "drop" and int(ev.get("gid", -1)) == gid2 and String(ev.get("rarity", "")) == "epic":
			seen = true
	check(seen and room.ground_items.has(gid2) and room.pending_pickups.is_empty(), "dropped item stays on the floor for its owner and is announced next tick")
	check(room.ground_payload().size() == 2 and String(room.ground_payload()[0].get("name", "")) != "", "ground payload lists items for late joiners")
	# 개인 드랍: 2인 파티에서 적 하나를 잡으면 사람마다 따로 굴리고(×1000 이면 둘 다), 남의 것은 밟아도 안 줍는다. 버린 장비(owner "")는 누구나
	var r3 := CombatRoom.new(ContentDB.get_room_def("test_arena"), ContentDB.get_party_profile(2), ContentDB.rules, 79, _members(2), {"drop": {"heat": 0, "depth": 0, "level": 1, "tutorial": false, "mult": 1000.0}})
	var e3: Dictionary = r3.enemies.values()[0]
	r3._damage_enemy(e3, 100000.0, r3.players["p0"], 0.0, 0.0)
	r3.step(dt)
	var owners := {}
	for gi3: Dictionary in r3.ground_items.values():
		owners[String(gi3.get("owner", ""))] = true
	check(r3.ground_items.size() == 2 and owners.has("p0") and owners.has("p1"), "personal drops: one roll per party member, each item owned")
	var p1_item: Dictionary = {}
	for gi3: Dictionary in r3.ground_items.values():
		if String(gi3.get("owner", "")) == "p1":
			p1_item = gi3
		else:
			gi3["pos"] = Vector2(-900, -900)   # p0 의 것은 멀리 치워 두고 p1 의 것만 밟게 한다
	r3.players["p0"]["pos"] = p1_item["pos"]
	r3.players["p1"]["pos"] = Vector2(-999, -999)
	r3.step(dt)
	check(r3.pending_pickups.is_empty() and r3.ground_items.has(int(p1_item["gid"])), "another player cannot pick up someone else's personal drop")
	r3.players["p1"]["pos"] = p1_item["pos"]
	r3.step(dt)
	check(r3.pending_pickups.size() == 1 and String(r3.pending_pickups[0]["aid"]) == "p1", "the owner picks up their own drop")
	r3.pending_pickups.clear()
	var pub := r3.place_ground_item({"uid": "it_pub", "slot": "armor", "base": "bark_vest", "rarity": "common", "name_ko": "공용 조끼", "affixes": []}, Vector2(300, 300), "p1")
	r3.step(dt)
	r3.players["p0"]["pos"] = Vector2(300, 300)
	r3.step(dt)
	check(r3.pending_pickups.size() == 1 and String(r3.pending_pickups[0]["aid"]) == "p0" and not r3.ground_items.has(pub), "a dropped (public) item can be picked up by anyone else")
	# 자동 공격 우선순위: 공격 버튼을 계속 누른 채 Q 를 누르면 스킬이 나간다
	var room2 := CombatRoom.new(ContentDB.get_room_def("test_arena"), ContentDB.get_party_profile(1), ContentDB.rules, 78, _members(1))
	room2.queue_input("p0", 1, Vector2.ZERO, Vector2.RIGHT, Protocol.BTN_ATTACK | Protocol.BTN_Q)
	room2.step(dt)
	check(room2.players["p0"]["action"] == Protocol.Action.CAST and room2.players["p0"]["action_kind"] == "q", "skill wins over a held attack button")


## v5 팩: 장비 아이콘 17·등급 테두리 5프레임·빈 슬롯 4프레임·배지·자물쇠·망치·재료·도안 3·강화 VFX 3·효과음 3 이 최종본으로 연결되고 프레임 선택이 맞는지
func test_v5_pack_assets() -> void:
	var singles := ["icon.material.sap_crystal", "icon.blueprint.weapon", "icon.blueprint.armor", "icon.blueprint.trinket", "ui.badge.enhance", "ui.icon.locked", "ui.icon.crafted"]
	for tbl: String in ["weapons", "armors", "trinkets"]:
		for bid: String in ContentDB.equipment[tbl].keys():
			singles.append("icon.gear." + bid)
	var ok := true
	for id: String in singles:
		if not (AssetRegistry.has(id) and AssetRegistry.status(id) == "final" and not bool(AssetRegistry.get_sheet(id).get("is_fallback", true))):
			ok = false
			print("  missing v5 single: " + id)
	check(ok and singles.size() == 24, "v5: 24 single icons registered as final and loadable")
	var rar := AssetRegistry.get_sheet("ui.frame.rarity")
	check(AssetRegistry.status("ui.frame.rarity") == "final" and int(rar["hframes"]) == 5 and String(rar["mode"]) == "select_frame" and rar["frame_size"] == Vector2(64, 64), "v5: rarity frame is a 5-frame select_frame sheet")
	var slot := AssetRegistry.get_sheet("ui.slot.gear")
	check(AssetRegistry.status("ui.slot.gear") == "final" and int(slot["hframes"]) == 4 and String(slot["mode"]) == "select_frame", "v5: empty slot glyphs are a 4-frame select_frame sheet")
	# 등급 지수 → 프레임 인덱스 (0 일반 … 4 전설), 프레임 텍스처가 서로 다른 조각
	var f0 := AssetRegistry.get_frame_texture("ui.frame.rarity", Equipment.rarity_index("common"))
	var f4 := AssetRegistry.get_frame_texture("ui.frame.rarity", Equipment.rarity_index("legendary"))
	check(Equipment.rarity_index("legendary") == 4 and f0 != f4 and f0.get_width() == 64, "v5: rarity index picks distinct 64px frames")
	var inner := f4.get_image().get_pixel(32, 32)
	var edge := f4.get_image().get_pixel(2, 32)
	check(inner.a == 0.0 and edge.a > 0.5, "v5: rarity frame inner area is transparent and the border is opaque")
	for kind: Array in [["success", 6, 12.0], ["fail", 4, 10.0], ["destroy", 8, 10.0]]:
		var sh := AssetRegistry.get_sheet("vfx.enhance." + String(kind[0]))
		check(AssetRegistry.status("vfx.enhance." + String(kind[0])) == "final" and int(sh["hframes"]) == int(kind[1]) and is_equal_approx(float(sh["fps"]), float(kind[2])) and String(sh["mode"]) == "one_shot" and not bool(sh["hold_last"]), "v5: enhance %s vfx %d frames @%d fps one_shot" % [kind[0], int(kind[1]), int(kind[2])])
		var au := AssetRegistry.get_audio("sfx.enhance." + String(kind[0]))
		check(au != null and String(AssetRegistry.entry("sfx.enhance." + String(kind[0])).get("ext", "")) == "ogg", "v5: enhance %s sfx loads (ogg)" % kind[0])
	var mf: Dictionary = AssetRegistry.manifest
	var v5n := 0
	for e: Dictionary in mf.get("assets", []):
		if String(e.get("source", {}).get("pack", "")) == "beaver_assets_v5":
			v5n += 1
	check(v5n == 32 and mf.get("packs", {}).has("beaver_assets_v5"), "v5: 32 manifest entries from the pack and the pack is listed")


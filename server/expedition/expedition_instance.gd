class_name ExpeditionInstance
extends RefCounted
## 1~4인 원정 인스턴스. 다른 원정과 적·보상·상태를 공유하지 않는다.
## 흐름: PREPARING → (start_run) → IN_ROOM → REWARD → ROUTE_VOTE|LOADING → IN_ROOM|NODE_MENU … → RESULT → (restart|hub)
## 파티 대표는 편의 기능만 가지며 월드·저장·전투 소유권은 서버에 있다 (14절).
## 서버가 보낼 메시지는 outbox 에 쌓고 ServerMain 이 전송한다. 안전 지점(REWARD/ROUTE_VOTE/NODE_MENU)마다 체크포인트를 남긴다.

var id: String
var seed_value: int
var state: int = Protocol.ExpState.PREPARING
var public: bool = true
var difficulty: String = "normal"
var created_at: float
var members: Dictionary = {}      # account_id -> {nickname, class_id, ready, connected, peer_id, disconnect_at, joined_at, heal_uses, hp, permanent}
var room: CombatRoom = null
var room_index: int = 0
var room_id: String = "test_arena"
var choices: Dictionary = {}      # RESULT 상태의 선택
var last_result: Dictionary = {}
var n_locked: int = 0
var suspended: bool = false
var suspended_at: float = 0.0
var paused: bool = false            # 파티가 안전 지점에서 명시적으로 중단한 원정 (이어하기 가능, SAVE-01)
var paused_at: float = 0.0
var tutorial: bool = false
var pacts: Dictionary = {}          # 서약 {id: rank} (Hades 열기 식 난이도 모듈)
var heat: int = 0
var content_version: String = Protocol.CONTENT_VERSION
var _snap_accum: int = 0
var rooms_cleared: int = 0
var host_nick: String = ""
var rng := RandomNumberGenerator.new()
var run: Dictionary = {}          # 런 상태 (아래 _new_run 참고)
var outbox: Array = []            # [{"to": "members"|account_id, "type": S, "payload": {}}]
var checkpoint_dirty: bool = false
var restored_from_checkpoint: bool = false
var phase_deadline: float = 0.0
var run_outcome: int = Protocol.Outcome.NONE
var run_finished_unreported: bool = false
static var debug_route_layers: int = 0   # 테스트용: 0 이면 전체 경로, N 이면 앞 N개 층만 사용
static var debug_boss: String = ""        # 테스트·연습용: 지정 보스방 하나만 있는 경로 (ironclaw / lantern_toad / root_king)


func _init(expedition_id: String, seed_: int) -> void:
	id = expedition_id
	seed_value = seed_
	rng.seed = seed_
	created_at = Time.get_unix_time_from_system()


# ------------------------------------------------------------------ 멤버

func member_count() -> int:
	return members.size()


func connected_count() -> int:
	var c := 0
	for m: Dictionary in members.values():
		if m["connected"]:
			c += 1
	return c


func is_safe_point() -> bool:
	return state in [Protocol.ExpState.REWARD, Protocol.ExpState.ROUTE_VOTE, Protocol.ExpState.NODE_MENU]


func is_joinable() -> bool:
	return state == Protocol.ExpState.PREPARING or state == Protocol.ExpState.RESULT or (is_safe_point() and public)


func can_join(account_id: String) -> String:
	if members.has(account_id):
		return ""
	if members.size() >= Protocol.MAX_PARTY_SIZE:
		return Protocol.ERR_PARTY_FULL
	if not is_joinable():
		return Protocol.ERR_BAD_STATE
	return ""


func add_member(s: Session, permanent: Dictionary = {}, trait_id: String = "") -> void:
	members[s.account_id] = {
		"nickname": s.nickname, "class_id": s.class_id, "ready": false, "connected": true, "peer_id": s.peer_id,
		"disconnect_at": 0.0, "joined_at": Time.get_unix_time_from_system(), "heal_uses": int(ContentDB.rule("heal_uses_per_expedition", 2)), "hp": -1.0,
		"permanent": permanent, "trait": trait_id, "secrets_found": [],
	}
	s.expedition_id = id
	choices.erase(s.account_id)
	if is_safe_point():
		# 안전 지점 합류 (14절): 합류용 묶음, 기존 멤버 장비 복제 없음, 다음 방부터 N 재산정
		_run_player(s.account_id)
		_apply_join_bundle(s.account_id)
		s.location = Protocol.Location.JOIN_PENDING
		_send_phase_to(s.account_id)
		s.location = _location_for_state()
	else:
		s.location = Protocol.Location.PREPARING_EXPEDITION if state == Protocol.ExpState.PREPARING else Protocol.Location.RESULT


func remove_member(account_id: String) -> void:
	members.erase(account_id)
	choices.erase(account_id)
	if room != null:
		room.remove_player(account_id)
	if not run.is_empty():
		run.get("votes", {}).erase(account_id)
		run.get("pending_rewards", {}).erase(account_id)


func set_ready(account_id: String, ready: bool, class_id: String) -> void:
	if members.has(account_id):
		members[account_id]["ready"] = ready
		if ContentDB.is_class_playable(class_id):
			members[account_id]["class_id"] = class_id


func all_ready() -> bool:
	if members.is_empty():
		return false
	for m: Dictionary in members.values():
		if m["connected"] and not m["ready"]:
			return false
	return true


func mark_disconnected(account_id: String) -> void:
	if not members.has(account_id):
		return
	members[account_id]["connected"] = false
	members[account_id]["disconnect_at"] = Time.get_unix_time_from_system()
	members[account_id]["ready"] = false
	if room != null:
		room.set_connected(account_id, false)
	if connected_count() == 0 and state == Protocol.ExpState.IN_ROOM:
		suspended = true
		suspended_at = Time.get_unix_time_from_system()


func mark_reconnected(s: Session) -> void:
	if not members.has(s.account_id):
		return
	members[s.account_id]["connected"] = true
	members[s.account_id]["peer_id"] = s.peer_id
	members[s.account_id]["disconnect_at"] = 0.0
	s.expedition_id = id
	if room != null:
		room.set_connected(s.account_id, true)
	if suspended:
		suspended = false
	s.location = _location_for_state()
	if restored_from_checkpoint:
		outbox.append({"to": s.account_id, "type": Protocol.S.NOTICE, "payload": {"text": "서버 재시작으로 마지막 안전 지점(%s)부터 이어갑니다. 진행 중이던 전투는 복원되지 않습니다." % String(run.get("checkpoint_note", ""))}})
	_send_phase_to(s.account_id)
	if state == Protocol.ExpState.REWARD and (run.get("pending_rewards", {}) as Dictionary).is_empty():
		_check_reward_done()


func _location_for_state() -> int:
	match state:
		Protocol.ExpState.IN_ROOM: return Protocol.Location.IN_ROOM
		Protocol.ExpState.RESULT: return Protocol.Location.RESULT
		Protocol.ExpState.REWARD: return Protocol.Location.REWARD
		Protocol.ExpState.ROUTE_VOTE: return Protocol.Location.ROUTE_VOTE
		Protocol.ExpState.NODE_MENU: return Protocol.Location.REWARD
		_: return Protocol.Location.PREPARING_EXPEDITION


## 유예 시간이 지난 이탈자를 정리한다. 돌려주는 값은 제거된 계정 ID 목록.
func prune_disconnected(grace_sec: float) -> Array:
	var removed: Array = []
	var now := Time.get_unix_time_from_system()
	var grace := grace_sec
	if restored_from_checkpoint or is_safe_point():
		grace = maxf(grace_sec, float(ContentDB.rule("checkpoint_grace_sec", 600.0)))
	for aid: String in members.keys():
		var m: Dictionary = members[aid]
		if not m["connected"] and now - float(m["disconnect_at"]) > grace:
			removed.append(aid)
	for aid: String in removed:
		remove_member(aid)
	return removed


# ------------------------------------------------------------------ 런

## 원정 경로: 시작 지역부터 next 를 따라 이어지는 지역들의 층을 모두 붙인다 (정식 1차: 3지역, 지역마다 보스).
static func build_route(seed_: int, start_region: String = "willow_river", max_regions: int = 3) -> Array:
	var map_rng := RandomNumberGenerator.new()
	map_rng.seed = seed_
	var layers: Array = []
	var li := 0
	var rid := start_region
	var guard := 0
	while rid != "" and guard < max_regions:
		guard += 1
		var region: Dictionary = ContentDB.regions.get(rid, {})
		if region.is_empty():
			break
		for layer_tpl: Array in region.get("layers", []):
			var nodes: Array = []
			var ni := 0
			for tpl: Dictionary in layer_tpl:
				var pool: Array = tpl.get("pool", [])
				var variant := String(pool[map_rng.randi() % pool.size()]) if not pool.is_empty() else ""
				nodes.append({"id": "L%dN%d" % [li, ni], "layer": li, "index": ni, "type": tpl["type"], "variant": variant, "hint": region.get("danger_hints", {}).get(tpl["type"], ""), "region": rid, "region_name": region.get("name_ko", rid)})
				ni += 1
			layers.append(nodes)
			li += 1
		rid = String(region.get("next", ""))
	return layers


func _new_run() -> void:
	var region: Dictionary = ContentDB.regions.get("willow_river", {})
	var map_rng := RandomNumberGenerator.new()
	map_rng.seed = seed_value
	var reward_rng := RandomNumberGenerator.new()
	reward_rng.seed = seed_value + 7919
	var layers: Array = build_route(seed_value, "willow_river", int(ContentDB.rule("run_regions", 3)))
	if tutorial:
		layers = [[{"id": "L0N0", "layer": 0, "index": 0, "type": "combat", "variant": "tutorial", "hint": "튜토리얼", "region": "willow_river", "region_name": "버들둑 훈련장"}]]
	if debug_boss != "" and ContentDB.bosses.has(debug_boss):
		var bnode := {}
		for layer: Array in layers:
			for node: Dictionary in layer:
				if String(node["type"]) == "boss" and String(node["variant"]) == debug_boss:
					bnode = node
		if not bnode.is_empty():
			layers = [[bnode]]
	elif debug_route_layers > 0 and layers.size() > debug_route_layers:
		layers = layers.slice(0, debug_route_layers)
	elif debug_route_layers < 0:
		layers = [layers[layers.size() - 1]]   # 테스트용: 마지막 보스 노드만
	run = {
		"region": region.get("id", "willow_river"), "region_name": region.get("name_ko", ""), "layers": layers, "layer": 0, "current": "", "path": [],
		"xp": 0, "level": 1, "team_wood": 0, "players": {}, "next_room_budget_add": 0.0,
		"pending_rewards": {}, "votes": {}, "menu": {}, "enemy_pool": region.get("enemy_pool", []), "curse_rooms": 0, "curse_mult": 1.0, "next_room_elite": 0, "bonus_shards": 0, "par_hits": 0,
		"stats": {"rooms_cleared": 0, "enemies_killed": 0, "combat_sec": 0.0, "nodes": [], "started_at": Time.get_unix_time_from_system(), "memories": 0, "secrets": [], "mechanics_succeeded": [], "bosses_killed": []},
		"reward_rng_state": reward_rng.state, "map_rng_state": map_rng.state, "checkpoint_note": "",
	}
	for aid: String in members.keys():
		_run_player(aid)
		members[aid]["hp"] = -1.0
		var perm: Dictionary = members[aid].get("permanent", {})
		members[aid]["heal_uses"] = maxi(int(ContentDB.rule("heal_uses_per_expedition", 2)) + int(perm.get("heal_uses_add", 0)) + int(pact_sum("heal_uses_add")), 0)
		run["team_wood"] = maxi(int(run["team_wood"]), int(perm.get("team_wood_add", 0)))
	room_index = 0
	rooms_cleared = 0
	run_outcome = Protocol.Outcome.NONE


func _run_player(aid: String) -> Dictionary:
	var rp: Dictionary = run["players"].get(aid, {})
	if rp.is_empty():
		rp = {"relics": [], "upgrades": [], "acorns": int(members.get(aid, {}).get("permanent", {}).get("start_acorns", 0)), "max_hp_add": 0, "shop_buys": {}, "level_seen": 1, "rerolls": int(ContentDB.rule("reward_rerolls_per_run", 1))}
		run["players"][aid] = rp
	return rp


func _apply_join_bundle(aid: String) -> void:
	var nodes_done: int = run["path"].size()
	var per := int(ContentDB.rule("join_bundle_relics_per_nodes", 2))
	var count := nodes_done / maxi(per, 1)
	var rp := _run_player(aid)
	var rr := _reward_rng()
	for i in count:
		var pool := _relic_pool(aid)
		if pool.is_empty():
			break
		rp["relics"].append(String(pool[rr.randi() % pool.size()]))
	var total := 0
	var n := 0
	for other: String in run["players"].keys():
		if other != aid:
			total += int(run["players"][other]["acorns"])
			n += 1
	rp["acorns"] = total / maxi(n, 1)
	run["reward_rng_state"] = rr.state
	outbox.append({"to": "members", "type": Protocol.S.NOTICE, "payload": {"text": "%s 이(가) 안전 지점에서 합류했습니다. 다음 방부터 인원을 다시 계산합니다." % members[aid]["nickname"]}})


func _reward_rng() -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.state = int(run["reward_rng_state"])
	return r


func _relic_pool(aid: String) -> Array:
	var owned: Array = _run_player(aid)["relics"]
	var out: Array = []
	for rid: String in ContentDB.relics.keys():
		if rid.begins_with("_") or owned.has(rid):
			continue
		out.append(rid)
	out.sort()
	return out


func _upgrade_pool(aid: String) -> Array:
	var cls: String = members[aid]["class_id"]
	var taken: Array = _run_player(aid)["upgrades"]
	var groups: Array = []
	for uid: String in taken:
		groups.append(String(ContentDB.upgrades.get(cls, {}).get(uid, {}).get("exclusive_group", uid)))
	var taken_slots: Array = []
	for uid: String in taken:
		taken_slots.append(String(ContentDB.upgrades.get(cls, {}).get(uid, {}).get("skill", "")))
	var out: Array = []
	for uid: String in ContentDB.upgrades.get(cls, {}).keys():
		var u: Dictionary = ContentDB.upgrades[cls][uid]
		if taken.has(uid) or groups.has(String(u.get("exclusive_group", uid))):
			continue
		if bool(u.get("evolution", false)):
			# 진화: 런 레벨 조건 + 같은 스킬의 강화를 하나 이상 가진 뒤에만 (눈에 보이는 행동 변화)
			if int(run.get("level", 1)) < int(u.get("requires_level", 4)) or not taken_slots.has(String(u.get("skill", ""))):
				continue
			var evolved := false
			for tid: String in taken:
				if bool(ContentDB.upgrades.get(cls, {}).get(tid, {}).get("evolution", false)) and String(ContentDB.upgrades[cls][tid].get("skill", "")) == String(u.get("skill", "")):
					evolved = true
			if evolved:
				continue
		out.append(uid)
	out.sort()
	return out


func member_mods(aid: String) -> Dictionary:
	var rp := _run_player(aid)
	var extra := {"max_hp_add": float(rp.get("max_hp_add", 0))}
	var perm: Dictionary = members[aid].get("permanent", {})
	for k: String in perm.keys():
		if k in RunMods.MOD_KEYS:
			extra[k] = float(extra.get(k, 0.0)) + float(perm[k])
	return RunMods.build(rp["relics"], rp["upgrades"], String(members[aid]["class_id"]), int(run.get("level", 1)), extra, ContentDB.rules, String(members[aid].get("trait", "")))


func current_node() -> Dictionary:
	if run.is_empty() or String(run["current"]) == "":
		return {}
	for layer: Array in run["layers"]:
		for n: Dictionary in layer:
			if n["id"] == run["current"]:
				return n
	return {}


func _node_by_id(nid: String) -> Dictionary:
	for layer: Array in run["layers"]:
		for n: Dictionary in layer:
			if n["id"] == nid:
				return n
	return {}


## 출정: 런을 만들고 첫 노드로 들어간다.
func start_run() -> void:
	_new_run()
	state = Protocol.ExpState.LOADING
	_enter_layer(0)


func _enter_layer(layer_index: int) -> void:
	run["layer"] = layer_index
	var layers: Array = run["layers"]
	if layer_index >= layers.size():
		_finish_run(Protocol.Outcome.VICTORY)
		return
	var nodes: Array = layers[layer_index]
	if nodes.size() == 1:
		_enter_node(nodes[0])
	else:
		_begin_route_vote(nodes)


func _enter_node(node: Dictionary) -> void:
	run["current"] = node["id"]
	var nr := String(node.get("region", run.get("region", "")))
	if nr != "" and nr != String(run.get("region", "")):
		run["region"] = nr
		run["region_name"] = String(node.get("region_name", nr))
		run["enemy_pool"] = ContentDB.regions.get(nr, {}).get("enemy_pool", run.get("enemy_pool", []))
		outbox.append({"to": "members", "type": Protocol.S.NOTICE, "payload": {"text": "%s 에 들어섰다. %s" % [run["region_name"], ContentDB.regions.get(nr, {}).get("description_ko", "")]}})
	match String(node["type"]):
		"combat", "boss", "elite":
			_start_room_for_node(node)
		"event":
			_begin_menu("event", String(node["variant"]))
		"shop":
			_begin_menu("shop", String(node["variant"]))
		"rest":
			_begin_menu("rest", String(node["variant"]))


func _start_room_for_node(node: Dictionary) -> void:
	room_id = String(node["variant"]) if String(node["type"]) != "boss" else "boss_" + String(node["variant"])
	if ContentDB.get_room_def(room_id).is_empty():
		room_id = "annihilate"
	start_room()


func set_pacts(sel: Dictionary) -> void:
	var n := ContentDB.normalize_pacts(sel)
	pacts = n["pacts"]
	heat = int(n["heat"])


## 서약 합산: 키별로 rank × per_rank 값을 더한 사전
func pact_sum(key: String) -> float:
	var total := 0.0
	for id: String in pacts.keys():
		total += float(ContentDB.pacts.get(id, {}).get(key + "_per_rank", 0.0)) * float(pacts[id])
	return total


## RoR2 식 시간 위험도. 전투 누적 시간(메뉴·투표 시간 제외)과 층 수로 오르고 난이도·서약이 속도를 정한다.
func danger() -> float:
	var dr: Dictionary = ContentDB.rules.get("danger", {})
	if dr.is_empty() or run.is_empty():
		return 1.0
	var d: Dictionary = ContentDB.rules.get("difficulties", {}).get(difficulty, {})
	var pace := float(d.get("danger_pace", 1.0)) + pact_sum("danger_pace_add")
	var combat_min := float(run.get("stats", {}).get("combat_sec", 0.0)) / 60.0
	if room != null and state == Protocol.ExpState.IN_ROOM:
		combat_min += room.elapsed / 60.0
	var v := 1.0 + combat_min * float(dr.get("per_combat_min", 0.06)) * pace + float(run.get("layer", 0)) * float(dr.get("per_layer", 0.03))
	return clampf(v, 1.0, float(dr.get("max", 2.2)))


## 인원 프로필 × 난이도 × 서약 × 위험도 (rules.difficulties, data/pacts.json, rules.danger)
func effective_profile(base: Dictionary) -> Dictionary:
	var d: Dictionary = ContentDB.rules.get("difficulties", {}).get(difficulty, {})
	var out := base.duplicate()
	var dr: Dictionary = ContentDB.rules.get("danger", {})
	var dg := danger()
	var hp_m := float(d.get("enemy_hp_mult", 1.0)) * (1.0 + pact_sum("enemy_hp_mult")) * (1.0 + (dg - 1.0) * float(dr.get("hp_weight", 0.8)))
	var dmg_m := float(d.get("damage_mult", 1.0)) * (1.0 + pact_sum("damage_mult")) * (1.0 + (dg - 1.0) * float(dr.get("damage_weight", 0.5)))
	var budget_m := float(d.get("wave_budget_mult", 1.0)) * (1.0 + (dg - 1.0) * float(dr.get("budget_weight", 0.3)))
	out["enemy_hp_mult"] = float(base.get("enemy_hp_mult", 1.0)) * hp_m
	out["hit_damage_mult"] = float(base.get("hit_damage_mult", 1.0)) * dmg_m
	out["boss_hp_mult"] = float(base.get("boss_hp_mult", 1.0)) * float(d.get("boss_hp_mult", 1.0)) * (1.0 + pact_sum("boss_hp_mult"))
	out["wave_budget_mult"] = float(base.get("wave_budget_mult", 1.0)) * budget_m
	out["elite_chance"] = float(ContentDB.elites.get("spawn", {}).get("base_chance", 0.06)) * float(d.get("elite_chance_mult", 1.0)) * (1.0 + pact_sum("elite_chance_mult")) * dg
	out["dodge_charges_add"] = int(pact_sum("dodge_charges_add"))
	out["mechanic_gap_mult"] = maxf(1.0 + pact_sum("mechanic_gap_mult"), 0.4)
	out["shop_price_mult"] = 1.0 + pact_sum("shop_price_mult")
	out["player_damage_taken_mult"] = float(run.get("curse_mult", 1.0)) if int(run.get("curse_rooms", 0)) > 0 else 1.0
	out["force_elite"] = int(run.get("next_room_elite", 0)) > 0
	out["danger"] = dg
	out["heat"] = heat
	out["difficulty"] = difficulty
	return out


## 파티 중단 (안전 지점에서만): 체크포인트로 저장되고 멤버는 마을로 돌아간다. 멤버가 모집판에서 이어하기로 복귀한다.
func pause_run() -> bool:
	if not is_safe_point() and state != Protocol.ExpState.PREPARING:
		return false
	if state == Protocol.ExpState.PREPARING:
		return false
	paused = true
	paused_at = Time.get_unix_time_from_system()
	suspended = true
	checkpoint_dirty = true
	for aid: String in members.keys():
		members[aid]["ready"] = false
	return true


func resume_member(s: Session) -> void:
	paused = false
	suspended = false
	mark_reconnected(s)
	outbox.append({"to": "members", "type": Protocol.S.NOTICE, "payload": {"text": "%s 이(가) 중단했던 원정을 이어갑니다 (%s)." % [s.nickname, String(run.get("checkpoint_note", ""))]}})


## 방 시작: 이 시점의 연결된 멤버 수로 N 을 확정하고 프로필을 고정한다.
func start_room() -> Dictionary:
	if run.is_empty():
		_new_run()
		run["current"] = "L0N0"
	var member_list: Array = []
	for aid: String in members.keys():
		var m: Dictionary = members[aid]
		if not m["connected"]:
			continue
		var mm := member_mods(aid)
		var entry := {"account_id": aid, "nickname": m["nickname"], "class_id": m["class_id"], "connected": true, "heal_uses": m["heal_uses"], "mods": mm["mods"], "procs": mm["procs"], "build_kind": m.get("build_kind", "log_cover"), "secrets_found": m.get("secrets_found", [])}
		if float(m.get("hp", -1.0)) >= 0.0:
			entry["hp"] = float(m["hp"])
		member_list.append(entry)
		m["ready"] = false
	n_locked = clampi(member_list.size(), 1, Protocol.MAX_PARTY_SIZE)
	var profile := ContentDB.get_party_profile(n_locked)
	var room_seed := int(rng.randi())
	var opts := {"budget_add": float(run.get("next_room_budget_add", 0.0)), "team_wood": int(run.get("team_wood", 0)), "enemy_pool": ContentDB.get_room_def(room_id).get("enemy_pool", run.get("enemy_pool", []))}
	run["next_room_budget_add"] = 0.0
	room = CombatRoom.new(ContentDB.get_room_def(room_id), effective_profile(profile), ContentDB.rules, room_seed, member_list, opts)
	run["next_room_elite"] = 0
	if int(run.get("curse_rooms", 0)) > 0:
		run["curse_rooms"] = int(run["curse_rooms"]) - 1
	if room_id.begins_with("boss_"):
		var boss_id := String(room_id.trim_prefix("boss_"))
		var path := "res://server/expedition/boss_%s.gd" % boss_id
		if not ResourceLoader.exists(path):
			path = "res://server/expedition/boss_ironclaw.gd"
		var boss_script: GDScript = load(path)
		if boss_script != null:
			room.boss = boss_script.new(room, effective_profile(profile), ContentDB.bosses.get(boss_id, {}))
	room_index += 1
	state = Protocol.ExpState.IN_ROOM
	choices.clear()
	last_result = {}
	var payload := room_enter_payload()
	outbox.append({"to": "members", "type": Protocol.S.ENTER_EXPEDITION, "payload": payload})
	_push_run_state()
	return payload


func room_enter_payload() -> Dictionary:
	var def := ContentDB.get_room_def(room_id)
	var party: Array = []
	for aid: String in members.keys():
		var m: Dictionary = members[aid]
		party.append({"id": aid, "nick": m["nickname"], "class_id": m["class_id"], "connected": m["connected"]})
	return {
		"expedition_id": id, "room_index": room_index, "room_id": room_id, "room_def": def, "seed": room.seed_value if room else 0,
		"n": n_locked, "profile": ContentDB.get_party_profile(n_locked), "party": party, "difficulty": difficulty, "node": current_node(),
		"rules": {"down_duration_sec": ContentDB.rule("down_duration_sec"), "rescue_hold_sec": ContentDB.rule("rescue_hold_sec"), "rescue_range": ContentDB.rule("rescue_range"), "dodge_charges": ContentDB.rule("dodge_charges"), "build_cost_wood": ContentDB.rule("build_cost_wood")},
		"content_version": content_version,
	}


func party_payload() -> Dictionary:
	var party: Array = []
	for aid: String in members.keys():
		var m: Dictionary = members[aid]
		party.append({"id": aid, "nick": m["nickname"], "class_id": m["class_id"], "ready": m["ready"], "connected": m["connected"], "choice": choices.get(aid, "")})
	return {"expedition_id": id, "state": state, "public": public, "difficulty": difficulty, "members": party, "room_index": room_index, "rooms_cleared": rooms_cleared, "suspended": suspended, "seed": seed_value}


func board_entry() -> Dictionary:
	return {"id": id, "state": state, "public": public, "difficulty": difficulty, "heat": heat, "pacts": pacts, "members": members.size(), "max": Protocol.MAX_PARTY_SIZE, "room_index": room_index, "joinable": is_joinable() and members.size() < Protocol.MAX_PARTY_SIZE and not paused, "host_nick": host_nick, "paused": paused, "tutorial": tutorial, "region": run.get("region_name", "") if not run.is_empty() else ""}


func run_payload() -> Dictionary:
	if run.is_empty():
		return {}
	var players: Dictionary = {}
	for aid: String in run["players"].keys():
		var rp: Dictionary = run["players"][aid]
		players[aid] = {"relics": rp["relics"], "upgrades": rp["upgrades"], "acorns": rp["acorns"], "max_hp_add": rp["max_hp_add"], "heal_uses": members.get(aid, {}).get("heal_uses", 0), "hp": members.get(aid, {}).get("hp", -1), "build_kind": members.get(aid, {}).get("build_kind", "log_cover"), "synergies": member_mods(aid).get("synergies", []), "rerolls": rp.get("rerolls", 0)}
	return {"expedition_id": id, "state": state, "region": run["region"], "region_name": run["region_name"], "layers": run["layers"], "layer": run["layer"], "current": run["current"], "path": run["path"],
		"danger": snappedf(danger(), 0.01), "heat": heat, "pacts": pacts, "curse_rooms": run.get("curse_rooms", 0), "bonus_shards": run.get("bonus_shards", 0),
		"xp": run["xp"], "level": run["level"], "xp_table": ContentDB.rule("xp_per_level", []), "team_wood": run["team_wood"], "players": players, "stats": run["stats"], "deadline_in": maxf(phase_deadline - Time.get_unix_time_from_system(), 0.0) if phase_deadline > 0.0 else 0.0}


func _push_run_state() -> void:
	outbox.append({"to": "members", "type": Protocol.S.RUN_STATE, "payload": run_payload()})


## 서버 tick. 돌려주는 값: {"events": [...], "snapshot": {...} | null, "finished": bool}
func step(dt: float, snapshot_every: int) -> Dictionary:
	var out := {"events": [], "snapshot": null, "finished": false}
	_step_phase_timers()
	if state != Protocol.ExpState.IN_ROOM or room == null or suspended:
		return out
	out["events"] = room.step(dt).duplicate()
	_snap_accum += 1
	if _snap_accum >= snapshot_every:
		_snap_accum = 0
		out["snapshot"] = room.snapshot()
	if room.is_finished():
		_on_room_finished()
		out["finished"] = true
	return out


func _on_room_finished() -> void:
	last_result = room.result_summary()
	var victory: bool = room.outcome == Protocol.Outcome.VICTORY
	run["team_wood"] = room.team_wood
	run["stats"]["combat_sec"] = float(run["stats"]["combat_sec"]) + room.elapsed
	for sid: String in last_result.get("stats", {}).get("secrets", []):
		if not (run["stats"]["secrets"] as Array).has(sid):
			run["stats"]["secrets"].append(sid)
	for mid: String in last_result.get("mechanics_succeeded", []):
		run["stats"]["mechanics_succeeded"].append(mid)
		if mid == "RK-04":
			run["stats"]["memories"] = int(run["stats"].get("memories", 0)) + 1
	if int(last_result.get("outcome", 0)) == Protocol.Outcome.VICTORY and String(last_result.get("boss_id", "")) != "":
		run["stats"]["bosses_killed"].append(String(last_result["boss_id"]))
	run["stats"]["enemies_killed"] = int(run["stats"]["enemies_killed"]) + int(room.stats["enemies_killed"])
	run["stats"]["nodes"].append({"node": run["current"], "room": room_id, "elapsed": room.elapsed, "outcome": room.outcome, "n": n_locked})
	# 경험치(파티 공유)·도토리(개인)·체력 이월
	var xp := 0
	var acorn_rng := _reward_rng()
	for type_id: String in room.stats["kills_by_type"].keys():
		var cnt := int(room.stats["kills_by_type"][type_id])
		xp += cnt * int(ContentDB.get_enemy_def(type_id).get("xp", 5))
	run["xp"] = int(run["xp"]) + xp
	var table: Array = ContentDB.rule("xp_per_level", [0])
	var lvl := 1
	for i in table.size():
		if int(run["xp"]) >= int(table[i]):
			lvl = i + 1
	run["level"] = lvl
	var kills := int(room.stats["enemies_killed"])
	for aid: String in members.keys():
		var rp := _run_player(aid)
		var ps: Dictionary = last_result["players"].get(aid, {})
		if not ps.is_empty():
			members[aid]["hp"] = float(ps.get("hp", -1)) if int(ps.get("state", 0)) == Protocol.EntState.ALIVE else float(ps.get("max_hp", 100)) * float(ContentDB.rule("return_from_death_hp_fraction", 0.5))
			members[aid]["heal_uses"] = int(ps.get("heal_uses", members[aid]["heal_uses"]))
		if members[aid]["connected"] and victory:
			var mult := 1.0 + float(member_mods(aid)["mods"].get("acorn_mult", 0.0))
			var gained := 0
			for i in kills:
				gained += acorn_rng.randi_range(int(ContentDB.rule("acorns_per_kill_min", 2)), int(ContentDB.rule("acorns_per_kill_max", 4)))
			rp["acorns"] = mini(int(rp["acorns"]) + int(gained * mult), int(ContentDB.rule("acorn_cap", 999)))
			last_result["players"][aid]["acorns_gained"] = int(gained * mult)
	# Dead Cells 시간 문 식 기록 보너스: 기준 시간 안에 방을 깨면 도토리·경험치 보너스
	var par: Dictionary = ContentDB.rule("room_par", {})
	var par_sec := float(par.get("base_sec", 70)) + float(par.get("per_player_sec", 10)) * n_locked
	last_result["par_sec"] = par_sec
	last_result["par_bonus"] = false
	if victory and room.objective != "boss" and room.objective != "tutorial" and room.elapsed <= par_sec:
		last_result["par_bonus"] = true
		run["stats"]["par_hits"] = int(run["stats"].get("par_hits", 0)) + 1
		var bonus_xp := int(xp * float(par.get("xp_mult", 0.25)))
		run["xp"] = int(run["xp"]) + bonus_xp
		xp += bonus_xp
		for aid: String in members.keys():
			if members[aid]["connected"]:
				var rp2 := _run_player(aid)
				rp2["acorns"] = mini(int(rp2["acorns"]) + int(par.get("acorns", 10)), int(ContentDB.rule("acorn_cap", 999)))
				last_result["players"][aid]["acorns_gained"] = int(last_result["players"][aid].get("acorns_gained", 0)) + int(par.get("acorns", 10))
		for i in table.size():
			if int(run["xp"]) >= int(table[i]):
				lvl = i + 1
		run["level"] = lvl
	run["reward_rng_state"] = acorn_rng.state
	last_result["xp_gained"] = xp
	last_result["level"] = lvl
	choices.clear()
	if victory:
		rooms_cleared += 1
		run["stats"]["rooms_cleared"] = int(run["stats"]["rooms_cleared"]) + 1
		run["path"].append(run["current"])
		var node := current_node()
		if String(node.get("type", "")) == "boss" and int(run.get("layer", 0)) >= (run["layers"] as Array).size() - 1:
			_finish_run(Protocol.Outcome.VICTORY)   # 마지막 지역 보스만 원정을 끝낸다. 중간 지역 보스는 다음 지역으로 이어진다.
		else:
			_begin_reward()
	else:
		_finish_run(Protocol.Outcome.WIPE)


func _finish_run(outcome: int) -> void:
	run_outcome = outcome
	state = Protocol.ExpState.RESULT
	phase_deadline = 0.0
	choices.clear()
	if last_result.is_empty():
		last_result = {"outcome": outcome, "elapsed": 0.0, "players": {}, "stats": {}}
	last_result["run_outcome"] = outcome
	last_result["run_stats"] = run.get("stats", {})
	last_result["run_complete"] = outcome == Protocol.Outcome.VICTORY
	run_finished_unreported = true
	checkpoint_dirty = true


# ------------------------------------------------------------------ 보상

func _begin_reward() -> void:
	state = Protocol.ExpState.REWARD
	phase_deadline = Time.get_unix_time_from_system() + float(ContentDB.rule("reward_choice_sec", 25.0))
	run["pending_rewards"] = {}
	var rr := _reward_rng()
	for aid: String in members.keys():
		run["pending_rewards"][aid] = _make_reward_options(aid, rr)
	run["reward_rng_state"] = rr.state
	run["checkpoint_note"] = "reward"
	checkpoint_dirty = true
	for aid: String in members.keys():
		if members[aid]["connected"]:
			_send_phase_to(aid)
	_push_run_state()


## 희귀도 가중치: rules.rarity_weights × (층·유물 보너스). Hades 보온 희귀도처럼 깊이 들어갈수록 희귀가 흔해진다.
func _rarity_weight(rarity: String, aid: String) -> float:
	var w: Dictionary = ContentDB.rule("rarity_weights", {"common": 1.0, "rare": 0.25, "legendary": 0.06})
	var base := float(w.get(rarity, 0.0))
	if rarity == "common":
		return base
	var bonus := 1.0 + float(run.get("layer", 0)) * float(ContentDB.rule("rarity_layer_bonus", 0.03)) * 4.0 + float(member_mods(aid)["mods"].get("rare_chance_add", 0.0)) * 3.0
	return base * bonus


func _weighted_relic(pool: Array, aid: String, rr: RandomNumberGenerator, min_rarity: String = "") -> String:
	var order := {"common": 0, "rare": 1, "legendary": 2}
	var cands: Array = []
	var total := 0.0
	for rid: String in pool:
		var rarity := String(ContentDB.relics.get(rid, {}).get("rarity", "common"))
		if min_rarity != "" and int(order.get(rarity, 0)) < int(order.get(min_rarity, 0)):
			continue
		var w := _rarity_weight(rarity, aid)
		if w <= 0.0:
			continue
		cands.append([rid, w])
		total += w
	if cands.is_empty():
		return "" if pool.is_empty() or min_rarity != "" else String(pool[rr.randi() % pool.size()])
	var x := rr.randf() * total
	for c: Array in cands:
		x -= float(c[1])
		if x <= 0.0:
			return String(c[0])
	return String(cands[cands.size() - 1][0])


func _make_reward_options(aid: String, rr: RandomNumberGenerator) -> Array:
	var relics := _relic_pool(aid)
	var upgrades := _upgrade_pool(aid)
	var options: Array = []
	var guard := 0
	while options.size() < 3 and guard < 20 and (not relics.is_empty() or not upgrades.is_empty()):
		guard += 1
		var take_upgrade := not upgrades.is_empty() and (relics.is_empty() or rr.randf() < 0.35)
		if take_upgrade:
			var uid: String = upgrades.pop_at(rr.randi() % upgrades.size())
			var u: Dictionary = ContentDB.upgrades.get(String(members[aid]["class_id"]), {}).get(uid, {})
			var urar := "legendary" if bool(u.get("evolution", false)) else ("rare" if bool(u.get("stackable", false)) else "common")
			options.append({"kind": "upgrade", "id": uid, "name_ko": u.get("name_ko", uid), "desc_ko": u.get("desc_ko", ""), "skill": u.get("skill", ""), "rarity": urar})
		else:
			var rid := _weighted_relic(relics, aid, rr)
			if rid == "":
				break
			relics.erase(rid)
			var r: Dictionary = ContentDB.relics.get(rid, {})
			options.append({"kind": "relic", "id": rid, "name_ko": r.get("name_ko", rid), "desc_ko": r.get("desc_ko", ""), "rarity": r.get("rarity", "common")})
	if options.is_empty():
		options.append({"kind": "acorns", "id": "acorns", "name_ko": "도토리 20", "desc_ko": "더 얻을 유물이 없다", "value": 20})
	return options


## 보상 다시 뽑기 (런당 rules.reward_rerolls_per_run 회). 같은 시드 흐름을 이어 쓴다.
func reroll_reward(aid: String) -> bool:
	if state != Protocol.ExpState.REWARD or not run["pending_rewards"].has(aid):
		return false
	var rp := _run_player(aid)
	if int(rp.get("rerolls", 0)) <= 0:
		return false
	rp["rerolls"] = int(rp["rerolls"]) - 1
	var rr := _reward_rng()
	run["pending_rewards"][aid] = _make_reward_options(aid, rr)
	run["reward_rng_state"] = rr.state
	checkpoint_dirty = true
	_send_phase_to(aid)
	return true


func pick_reward(aid: String, index: int) -> bool:
	if state != Protocol.ExpState.REWARD or not run["pending_rewards"].has(aid):
		return false
	var options: Array = run["pending_rewards"][aid]
	if options.is_empty():
		return false
	var opt: Dictionary = options[clampi(index, 0, options.size() - 1)]
	_apply_reward(aid, opt)
	run["pending_rewards"].erase(aid)
	outbox.append({"to": "members", "type": Protocol.S.NOTICE, "payload": {"text": "%s: %s 선택" % [members.get(aid, {}).get("nickname", aid), opt.get("name_ko", "")]}})
	_check_reward_done()
	return true


func _apply_reward(aid: String, opt: Dictionary) -> void:
	var rp := _run_player(aid)
	match String(opt.get("kind", "")):
		"relic": rp["relics"].append(String(opt["id"]))
		"upgrade": rp["upgrades"].append(String(opt["id"]))
		"acorns": rp["acorns"] = int(rp["acorns"]) + int(opt.get("value", 0))


func _check_reward_done() -> void:
	for aid: String in run["pending_rewards"].keys():
		if members.has(aid) and members[aid]["connected"]:
			return
	# 연결 끊긴 멤버의 보상은 기본 선택(첫 번째)으로 처리해 진행을 막지 않는다
	for aid: String in run["pending_rewards"].keys().duplicate():
		var options: Array = run["pending_rewards"][aid]
		if not options.is_empty():
			_apply_reward(aid, options[0])
		run["pending_rewards"].erase(aid)
	_push_run_state()
	_enter_layer(int(run["layer"]) + 1)


# ------------------------------------------------------------------ 경로 투표

func _begin_route_vote(nodes: Array) -> void:
	state = Protocol.ExpState.ROUTE_VOTE
	phase_deadline = Time.get_unix_time_from_system() + float(ContentDB.rule("route_vote_sec", 25.0))
	run["votes"] = {}
	run["vote_nodes"] = nodes.duplicate(true)
	run["checkpoint_note"] = "route"
	checkpoint_dirty = true
	_push_run_state()
	for aid: String in members.keys():
		if members[aid]["connected"]:
			_send_phase_to(aid)


func vote_route(aid: String, node_id: String) -> bool:
	if state != Protocol.ExpState.ROUTE_VOTE:
		return false
	var valid := false
	for n: Dictionary in run.get("vote_nodes", []):
		if n["id"] == node_id:
			valid = true
	if not valid:
		return false
	run["votes"][aid] = node_id
	outbox.append({"to": "members", "type": Protocol.S.ROUTE_OFFER, "payload": route_offer_payload()})
	var all := true
	for m_aid: String in members.keys():
		if members[m_aid]["connected"] and not run["votes"].has(m_aid):
			all = false
	if all:
		_resolve_route()
	return true


func route_offer_payload() -> Dictionary:
	return {"nodes": run.get("vote_nodes", []), "votes": run.get("votes", {}), "deadline_in": maxf(phase_deadline - Time.get_unix_time_from_system(), 0.0), "layer": run["layer"], "rule": "다수결. 기권은 투표한 사람에게 맡깁니다. 동률이면 시드 추첨."}


func _resolve_route() -> void:
	var tally: Dictionary = {}
	for nid: String in run["votes"].values():
		tally[nid] = int(tally.get(nid, 0)) + 1
	var nodes: Array = run.get("vote_nodes", [])
	var best: Array = []
	var best_n := -1
	for n: Dictionary in nodes:
		var c := int(tally.get(n["id"], 0))
		if c > best_n:
			best_n = c
			best = [n]
		elif c == best_n:
			best.append(n)
	var pick: Dictionary = best[0]
	if best.size() > 1:
		var rr := _reward_rng()
		pick = best[rr.randi() % best.size()]   # 동률: 시드 기반 추첨 (14절)
		run["reward_rng_state"] = rr.state
	outbox.append({"to": "members", "type": Protocol.S.NOTICE, "payload": {"text": "경로 결정: %s (%s)" % [_node_label(pick), "동률 추첨" if best.size() > 1 else "다수결"]}})
	_enter_node(pick)


func _node_label(n: Dictionary) -> String:
	var type_ko: String = {"combat": "전투", "event": "탐험·사건", "shop": "상점", "rest": "휴식", "boss": "지역 보스", "elite": "정예"}.get(String(n.get("type", "")), "?")
	var vname := ""
	match String(n.get("type", "")):
		"combat": vname = String(ContentDB.get_room_def(String(n.get("variant", ""))).get("name_ko", n.get("variant", "")))
		"event": vname = String(ContentDB.events.get(String(n.get("variant", "")), {}).get("name_ko", ""))
		"shop": vname = String(ContentDB.shop.get(String(n.get("variant", "")), {}).get("name_ko", ""))
		"boss": vname = String(ContentDB.bosses.get(String(n.get("variant", "")), {}).get("name_ko", "철턱 가재"))
	return "%s · %s" % [type_ko, vname] if vname != "" else type_ko


# ------------------------------------------------------------------ 메뉴 노드 (이벤트·상점·휴식)

func _begin_menu(kind: String, variant: String) -> void:
	state = Protocol.ExpState.NODE_MENU
	phase_deadline = Time.get_unix_time_from_system() + float(ContentDB.rule("node_menu_sec", 45.0))
	run["menu"] = {"kind": kind, "variant": variant, "votes": {}, "done": [], "applied": false}
	run["checkpoint_note"] = "menu"
	if kind == "rest":
		# StS 휴식처: 각자 회복(기본) 또는 숫돌(무작위 스킬 강화 1개)을 고른다. 계속을 누를 때까지 안 고르면 회복.
		run["menu"]["rest_choice"] = {}
	checkpoint_dirty = true
	for aid: String in members.keys():
		if members[aid]["connected"]:
			_send_phase_to(aid)
	_push_run_state()


func menu_payload() -> Dictionary:
	var menu: Dictionary = run.get("menu", {})
	var data: Dictionary = {}
	match String(menu.get("kind", "")):
		"event": data = ContentDB.events.get(String(menu.get("variant", "")), {})
		"shop": data = ContentDB.shop.get(String(menu.get("variant", "")), {})
		"rest": data = {"name_ko": "모닥불 휴식", "text_ko": "각자 고릅니다: 휴식(체력 %d%% 회복 + 회복 도구 보충) 또는 숫돌(무작위 스킬 강화 1개, 회복 없음). 고르지 않고 계속하면 휴식." % int(float(ContentDB.rule("rest_heal_fraction", 0.4)) * 100), "rest_choice": menu.get("rest_choice", {})}
	return {"kind": menu.get("kind", ""), "variant": menu.get("variant", ""), "data": data, "votes": menu.get("votes", {}), "done": menu.get("done", []), "deadline_in": maxf(phase_deadline - Time.get_unix_time_from_system(), 0.0), "run": run_payload()}


## 메뉴 행동: {"action": "vote", "choice": id} | {"action": "buy", "item": id} | {"action": "continue"}
func node_action(aid: String, payload: Dictionary) -> Dictionary:
	if String(payload.get("action", "")) == "skip_tutorial":
		if state == Protocol.ExpState.IN_ROOM and room != null and room.objective == "tutorial":
			room.tutorial_skip()
			return {"ok": true}
		return {"ok": false, "error": Protocol.ERR_BAD_STATE}
	if String(payload.get("action", "")) == "ping":
		if state == Protocol.ExpState.IN_ROOM and room != null:
			room.pending_events.append({"k": "ping", "id": aid, "x": float(payload.get("x", 0)), "y": float(payload.get("y", 0))})
			return {"ok": true}
		return {"ok": false, "error": Protocol.ERR_BAD_STATE}
	if state != Protocol.ExpState.NODE_MENU:
		return {"ok": false, "error": Protocol.ERR_BAD_STATE}
	var menu: Dictionary = run["menu"]
	match String(payload.get("action", "")):
		"vote":
			if menu["kind"] != "event":
				return {"ok": false, "error": Protocol.ERR_BAD_STATE}
			menu["votes"][aid] = String(payload.get("choice", ""))
			_broadcast_menu()
			var all := true
			for m_aid: String in members.keys():
				if members[m_aid]["connected"] and not menu["votes"].has(m_aid):
					all = false
			if all:
				_resolve_event()
			return {"ok": true}
		"buy":
			if menu["kind"] != "shop":
				return {"ok": false, "error": Protocol.ERR_BAD_STATE}
			return _buy(aid, String(payload.get("item", "")))
		"rest_choice":
			if menu["kind"] != "rest":
				return {"ok": false, "error": Protocol.ERR_BAD_STATE}
			_apply_rest_choice(aid, String(payload.get("choice", "heal")))
			_broadcast_menu()
			return {"ok": true}
		"continue":
			if menu["kind"] == "rest":
				_apply_rest_choice(aid, "heal")
			if not (menu["done"] as Array).has(aid):
				menu["done"].append(aid)
			_broadcast_menu()
			var all := true
			for m_aid: String in members.keys():
				if members[m_aid]["connected"] and not (menu["done"] as Array).has(m_aid):
					all = false
			if all and menu["kind"] != "event":
				_leave_menu()
			return {"ok": true}
	return {"ok": false, "error": Protocol.ERR_BAD_STATE}


func _apply_rest_choice(aid: String, choice: String) -> void:
	var menu: Dictionary = run["menu"]
	var done: Dictionary = menu.get("rest_choice", {})
	if done.has(aid) or not members.has(aid):
		return
	if choice == "smith":
		var pool := _upgrade_pool(aid)
		if not pool.is_empty():
			var rr := _reward_rng()
			var uid := String(pool[rr.randi() % pool.size()])
			_run_player(aid)["upgrades"].append(uid)
			run["reward_rng_state"] = rr.state
			var u: Dictionary = ContentDB.upgrades.get(String(members[aid]["class_id"]), {}).get(uid, {})
			outbox.append({"to": "members", "type": Protocol.S.NOTICE, "payload": {"text": "%s: 숫돌 — %s" % [members[aid]["nickname"], u.get("name_ko", uid)]}})
		else:
			choice = "heal"
	if choice != "smith":
		var max_hp := float(ContentDB.get_class_def(String(members[aid]["class_id"])).get("base_hp", 100)) + float(member_mods(aid)["mods"].get("max_hp_add", 0.0))
		var hp := float(members[aid].get("hp", -1.0))
		if hp < 0.0:
			hp = max_hp
		members[aid]["hp"] = minf(hp + max_hp * (float(ContentDB.rule("rest_heal_fraction", 0.4)) + float(member_mods(aid)["mods"].get("rest_heal_add", 0.0))), max_hp)
		members[aid]["heal_uses"] = maxi(int(ContentDB.rule("heal_uses_per_expedition", 2)) + int(pact_sum("heal_uses_add")), 0)
		choice = "heal"
	done[aid] = choice
	menu["rest_choice"] = done
	checkpoint_dirty = true
	_push_run_state()


func _buy(aid: String, item_id: String) -> Dictionary:
	var shop: Dictionary = ContentDB.shop.get(String(run["menu"]["variant"]), {})
	var item: Dictionary = {}
	for it: Dictionary in shop.get("items", []):
		if it["id"] == item_id:
			item = it
	if item.is_empty():
		return {"ok": false, "error": Protocol.ERR_BAD_CONTENT_ID}
	var rp := _run_player(aid)
	var bought := int(rp["shop_buys"].get(item_id, 0))
	if bought >= int(item.get("limit_per_player", 1)):
		return {"ok": false, "error": "SOLD_OUT"}
	var cost := int(round(float(item.get("cost", 0)) * (1.0 + pact_sum("shop_price_mult")) * (1.0 - clampf(float(member_mods(aid)["mods"].get("shop_discount", 0.0)), 0.0, 0.5))))
	if int(rp["acorns"]) < cost:
		return {"ok": false, "error": "NOT_ENOUGH_ACORNS"}
	# 서버가 한 번만 처리: 잔액 검증 후 즉시 차감. 음수 불가.
	rp["acorns"] = int(rp["acorns"]) - cost
	rp["shop_buys"][item_id] = bought + 1
	var eff: Dictionary = item.get("effect", {})
	match String(eff.get("type", "")):
		"heal_uses": members[aid]["heal_uses"] = int(members[aid]["heal_uses"]) + int(eff.get("value", 1))
		"max_hp_add":
			rp["max_hp_add"] = int(rp["max_hp_add"]) + int(eff.get("value", 10))
			if float(members[aid].get("hp", -1.0)) >= 0.0:
				members[aid]["hp"] = float(members[aid]["hp"]) + float(eff.get("value", 10))
		"wood": run["team_wood"] = mini(int(run["team_wood"]) + int(eff.get("value", 4)), int(ContentDB.rule("wood_cap", 30)))
		"random_relic":
			var pool := _relic_pool(aid)
			if not pool.is_empty():
				var rr := _reward_rng()
				rp["relics"].append(String(pool[rr.randi() % pool.size()]))
				run["reward_rng_state"] = rr.state
	checkpoint_dirty = true
	_push_run_state()
	_broadcast_menu()
	return {"ok": true, "item": item_id, "acorns": rp["acorns"]}


func _resolve_event() -> void:
	var menu: Dictionary = run["menu"]
	if bool(menu.get("applied", false)):
		return
	var ev: Dictionary = ContentDB.events.get(String(menu["variant"]), {})
	var tally: Dictionary = {}
	for c: String in menu["votes"].values():
		tally[c] = int(tally.get(c, 0)) + 1
	var best: Array = []
	var best_n := -1
	for ch: Dictionary in ev.get("choices", []):
		var c := int(tally.get(ch["id"], 0))
		if c > best_n:
			best_n = c
			best = [ch]
		elif c == best_n:
			best.append(ch)
	if best.is_empty():
		_leave_menu()
		return
	var pick: Dictionary = best[0]
	if best.size() > 1:
		var rr := _reward_rng()
		pick = best[rr.randi() % best.size()]
		run["reward_rng_state"] = rr.state
	for eff: Dictionary in pick.get("effects", []):
		match String(eff.get("type", "")):
			"wood": run["team_wood"] = mini(int(run["team_wood"]) + int(eff.get("value", 0)), int(ContentDB.rule("wood_cap", 30)))
			"heal_all":
				for aid: String in members.keys():
					var max_hp := float(ContentDB.get_class_def(String(members[aid]["class_id"])).get("base_hp", 100)) + float(member_mods(aid)["mods"].get("max_hp_add", 0.0))
					var hp := float(members[aid].get("hp", -1.0))
					if hp < 0.0:
						hp = max_hp
					members[aid]["hp"] = minf(hp + max_hp * float(eff.get("value", 0.3)), max_hp)
			"next_room_budget_add": run["next_room_budget_add"] = float(run.get("next_room_budget_add", 0.0)) + float(eff.get("value", 1.0))
			"acorns_all":
				for aid: String in members.keys():
					var rp := _run_player(aid)
					rp["acorns"] = mini(int(rp["acorns"]) + int(eff.get("value", 0)), int(ContentDB.rule("acorn_cap", 999)))
			"acorns_cost_all":
				for aid: String in members.keys():
					var rp := _run_player(aid)
					rp["acorns"] = maxi(int(rp["acorns"]) - int(eff.get("value", 0)), 0)
			"hp_cost_all":
				for aid: String in members.keys():
					var max_hp := float(ContentDB.get_class_def(String(members[aid]["class_id"])).get("base_hp", 100)) + float(member_mods(aid)["mods"].get("max_hp_add", 0.0))
					var hp := float(members[aid].get("hp", -1.0))
					if hp < 0.0:
						hp = max_hp
					members[aid]["hp"] = maxf(hp * (1.0 - float(eff.get("value", 0.35))), 1.0)
			"random_relic_chance":
				var rr2 := _reward_rng()
				for aid: String in members.keys():
					if rr2.randf() < float(eff.get("value", 0.5)):
						var rid := _weighted_relic(_relic_pool(aid), aid, rr2, String(eff.get("min_rarity", "")))
						if rid != "":
							_run_player(aid)["relics"].append(rid)
							outbox.append({"to": "members", "type": Protocol.S.NOTICE, "payload": {"text": "%s: %s 획득" % [members[aid]["nickname"], ContentDB.relics.get(rid, {}).get("name_ko", rid)]}})
				run["reward_rng_state"] = rr2.state
			"curse":
				run["curse_rooms"] = int(run.get("curse_rooms", 0)) + int(eff.get("value", 2))
				run["curse_mult"] = maxf(float(run.get("curse_mult", 1.0)), float(eff.get("damage_taken_mult", 1.3)))
			"next_room_elite": run["next_room_elite"] = int(run.get("next_room_elite", 0)) + int(eff.get("value", 1))
			"shards_all": run["bonus_shards"] = int(run.get("bonus_shards", 0)) + int(eff.get("value", 1))
	menu["applied"] = true
	outbox.append({"to": "members", "type": Protocol.S.NOTICE, "payload": {"text": "사건 결과: %s" % pick.get("text_ko", "")}})
	_push_run_state()
	_leave_menu()


func _leave_menu() -> void:
	run["path"].append(run["current"])
	run["menu"] = {}
	_enter_layer(int(run["layer"]) + 1)


func _broadcast_menu() -> void:
	outbox.append({"to": "members", "type": Protocol.S.NODE_MENU, "payload": menu_payload()})


# ------------------------------------------------------------------ 단계 타이머·재전송

func _step_phase_timers() -> void:
	if phase_deadline <= 0.0 or Time.get_unix_time_from_system() < phase_deadline:
		return
	if connected_count() == 0:
		return  # 전원 오프라인이면 진행하지 않는다 (상태 보존)
	match state:
		Protocol.ExpState.REWARD:
			for aid: String in run["pending_rewards"].keys().duplicate():
				var options: Array = run["pending_rewards"][aid]
				if not options.is_empty():
					_apply_reward(aid, options[0])
				run["pending_rewards"].erase(aid)
			outbox.append({"to": "members", "type": Protocol.S.NOTICE, "payload": {"text": "제한시간 종료: 남은 보상은 첫 번째로 자동 선택"}})
			_push_run_state()
			_enter_layer(int(run["layer"]) + 1)
		Protocol.ExpState.ROUTE_VOTE:
			if run["votes"].is_empty():
				run["votes"]["_timeout"] = String(run["vote_nodes"][0]["id"])
			_resolve_route()
		Protocol.ExpState.NODE_MENU:
			if run["menu"].get("kind", "") == "event":
				_resolve_event()
			else:
				_leave_menu()
	phase_deadline = 0.0 if state in [Protocol.ExpState.IN_ROOM, Protocol.ExpState.RESULT] else phase_deadline


func _send_phase_to(aid: String) -> void:
	match state:
		Protocol.ExpState.IN_ROOM:
			outbox.append({"to": aid, "type": Protocol.S.ENTER_EXPEDITION, "payload": room_enter_payload()})
		Protocol.ExpState.REWARD:
			var opts: Array = run["pending_rewards"].get(aid, [])
			outbox.append({"to": aid, "type": Protocol.S.RUN_STATE, "payload": run_payload()})
			outbox.append({"to": aid, "type": Protocol.S.REWARD_OFFER, "payload": {"options": opts, "deadline_in": maxf(phase_deadline - Time.get_unix_time_from_system(), 0.0), "result": last_result, "picked": opts.is_empty()}})
		Protocol.ExpState.ROUTE_VOTE:
			outbox.append({"to": aid, "type": Protocol.S.RUN_STATE, "payload": run_payload()})
			outbox.append({"to": aid, "type": Protocol.S.ROUTE_OFFER, "payload": route_offer_payload()})
		Protocol.ExpState.NODE_MENU:
			outbox.append({"to": aid, "type": Protocol.S.NODE_MENU, "payload": menu_payload()})
		Protocol.ExpState.RESULT:
			outbox.append({"to": aid, "type": Protocol.S.RUN_STATE, "payload": run_payload()})
			outbox.append({"to": aid, "type": Protocol.S.ROOM_RESULT, "payload": result_payload()})
	outbox.append({"to": aid, "type": Protocol.S.PARTY_STATE, "payload": party_payload()})


func result_payload() -> Dictionary:
	var r := last_result.duplicate(true)
	r["expedition_id"] = id
	r["room_index"] = room_index
	r["rooms_cleared"] = rooms_cleared
	r["run_outcome"] = run_outcome
	r["run"] = run_payload()
	return r


# ------------------------------------------------------------------ RESULT 선택

func set_choice(account_id: String, choice: String) -> void:
	if members.has(account_id) and choice in ["restart", "hub"]:
		choices[account_id] = choice


func resolved_choice() -> String:
	if state != Protocol.ExpState.RESULT:
		return ""
	var first := ""
	for aid: String in members.keys():
		if not members[aid]["connected"]:
			continue
		var c: String = choices.get(aid, "")
		if c == "":
			return ""
		if first == "":
			first = c
		elif c != first:
			return ""
	return first


# ------------------------------------------------------------------ 체크포인트

func to_checkpoint() -> Dictionary:
	var mem: Dictionary = {}
	for aid: String in members.keys():
		var m: Dictionary = members[aid].duplicate(true)
		m["connected"] = false
		m["peer_id"] = 0
		mem[aid] = m
	return {"id": id, "seed": seed_value, "public": public, "difficulty": difficulty, "pacts": pacts, "heat": heat, "paused": paused, "tutorial": tutorial, "created_at": created_at, "saved_at": Time.get_unix_time_from_system(),
		"state": state, "room_index": room_index, "room_id": room_id, "rooms_cleared": rooms_cleared, "n_locked": n_locked, "host_nick": host_nick,
		"members": mem, "run": run.duplicate(true), "rng_state": rng.state, "content_version": content_version, "phase_deadline": phase_deadline, "run_outcome": run_outcome,
		"room_in_progress": state == Protocol.ExpState.IN_ROOM, "last_result": last_result.duplicate(true)}


static func from_checkpoint(cp: Dictionary) -> ExpeditionInstance:
	var inst := ExpeditionInstance.new(String(cp["id"]), int(cp["seed"]))
	inst.public = bool(cp.get("public", true))
	inst.difficulty = String(cp.get("difficulty", "normal"))
	inst.paused = bool(cp.get("paused", false))
	inst.tutorial = bool(cp.get("tutorial", false))
	inst.set_pacts(cp.get("pacts", {}))
	inst.created_at = float(cp.get("created_at", 0))
	inst.room_index = int(cp.get("room_index", 0))
	inst.room_id = String(cp.get("room_id", "annihilate"))
	inst.rooms_cleared = int(cp.get("rooms_cleared", 0))
	inst.n_locked = int(cp.get("n_locked", 1))
	inst.host_nick = String(cp.get("host_nick", ""))
	inst.members = cp.get("members", {}).duplicate(true)
	inst.run = cp.get("run", {}).duplicate(true)
	inst.rng.state = int(cp.get("rng_state", 0))
	inst.last_result = cp.get("last_result", {}).duplicate(true)
	inst.run_outcome = int(cp.get("run_outcome", 0))
	inst.restored_from_checkpoint = true
	inst.suspended = true
	inst.suspended_at = Time.get_unix_time_from_system()
	var now := Time.get_unix_time_from_system()
	for aid: String in inst.members.keys():
		inst.members[aid]["connected"] = false
		inst.members[aid]["disconnect_at"] = now
	# 체크포인트는 안전 지점(REWARD/ROUTE_VOTE/NODE_MENU/RESULT)에서만 저장된다.
	# 전투 중 서버가 죽었다면 마지막 안전 지점으로만 복구된다 (14절). 투표는 다시 받는다.
	inst.state = int(cp.get("state", Protocol.ExpState.RESULT))
	if inst.state == Protocol.ExpState.ROUTE_VOTE:
		inst.run["votes"] = {}
	if inst.state in [Protocol.ExpState.IN_ROOM, Protocol.ExpState.LOADING, Protocol.ExpState.PREPARING]:
		inst.state = Protocol.ExpState.RESULT
		inst.run_outcome = Protocol.Outcome.SERVER_ERROR
	inst.phase_deadline = 0.0
	inst.suspended = false
	return inst

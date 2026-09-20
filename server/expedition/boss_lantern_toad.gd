class_name BossLanternToad
extends BossIronclaw
## 늪등불 두꺼비 (검은 수액 습지 보스). 기본 패턴 4개(점프 강타·혀 창·수액 투척·몸통 박치기)는 공통 컨트롤러가 처리하고,
## 독립 기믹 5개(TF-01~05)를 여기서 정의한다. 각 기믹은 목표·판단·해결 방법이 다르고 인원 프로필로 목표 수·유예·동시 조작이 바뀐다.

var sap_hazard_mult: float = 1.0
var sap_hazard_mult_t: float = 0.0


func _hazard_scale() -> float:
	return sap_hazard_mult if sap_hazard_mult_t > 0.0 else 1.0


func _step_extra(dt: float) -> void:
	sap_hazard_mult_t = maxf(sap_hazard_mult_t - dt, 0.0)


func _mechanic_start(mid: String, m: Dictionary) -> void:
	match mid:
		"TF-01": _tf01_start(m)
		"TF-02": _tf02_start(m)
		"TF-03": _tf03_start(m)
		"TF-04": _tf04_start(m)
		"TF-05": _tf05_start(m)


func _mechanic_step(mid: String, dt: float, m: Dictionary) -> void:
	match mid:
		"TF-01": _tf01_step(dt, m)
		"TF-02": _tf02_step(dt, m)
		"TF-03": _tf03_step(dt, m)
		"TF-04": _tf04_step(dt, m)
		"TF-05": _tf05_step(dt, m)


func _mechanic_end(mid: String, success: bool) -> void:
	match mid:
		"TF-01": _tf01_end(success)
		"TF-02": _tf02_end(success)
		"TF-03": _tf03_end(success)
		"TF-04": _tf04_end(success)
		"TF-05": _tf05_end(success)


func _mechanic_object(o: Dictionary, p: Dictionary) -> void:
	match int(o["kind"]):
		Protocol.ObKind.LANTERN: _tf01_light(o, p)
		Protocol.ObKind.SEED: _pickup(o, p)
		Protocol.ObKind.SPORE_NODE: _tf03_sever(o, p)
		Protocol.ObKind.RESONANCE_LOG: _tf04_hit(o, p)
		Protocol.ObKind.FIREFLY: _pickup(o, p)


func _points(key: String, fallback: Array) -> Array:
	return room.room_def.get(key, fallback)


# ------------------------------------------------------------------ TF-01 등불 점화
## 목표: 등불 N개를 동시에 켠다. 3인 이상은 켜진 등불이 일정 시간 뒤 꺼지므로 분담·순서가 필요하다.

func _tf01_start(m: Dictionary) -> void:
	var prof := mprofile("TF-01")
	var pts := _points("lantern_points", [[300, 500], [750, 150], [1200, 500], [750, 850]])
	var ids: Array = []
	for i in mini(int(prof.get("lanterns", 1)), pts.size()):
		var o := _add_object(Protocol.ObKind.LANTERN, Vector2(pts[i][0], pts[i][1]), 26.0, {"hold_sec": float(prof.get("light_sec", 2.0)), "interactable": true, "lit_t": 0.0})
		ids.append(o["id"])
	_spawn_adds(int(prof.get("adds", 0)), "lantern_moth")
	m["data"] = {"lanterns": ids, "relight": float(prof.get("relight_sec", 0.0))}


func _tf01_light(o: Dictionary, p: Dictionary) -> void:
	o["state"] = 1
	o["interactable"] = false
	o["progress"] = 0.0
	o["lit_t"] = float(mechanics["TF-01"]["data"].get("relight", 0.0))
	p["stats"]["objective"] = float(p["stats"]["objective"]) + 1.0
	room.events.append({"k": "lantern_lit", "oid": o["id"], "by": p["id"]})
	var all_lit := true
	for lid in mechanics["TF-01"]["data"]["lanterns"]:
		var l: Dictionary = room.objects.get(lid, {})
		if l.is_empty() or int(l["state"]) != 1:
			all_lit = false
	if all_lit:
		_finish_mechanic(true, "all_lit")


func _tf01_step(dt: float, m: Dictionary) -> void:
	if float(m["data"].get("relight", 0.0)) <= 0.0:
		return
	for lid in m["data"]["lanterns"]:
		var l: Dictionary = room.objects.get(lid, {})
		if l.is_empty() or int(l["state"]) != 1:
			continue
		l["lit_t"] = float(l["lit_t"]) - dt
		l["progress"] = clampf(float(l["lit_t"]) / maxf(float(m["data"]["relight"]), 1.0), 0.0, 1.0)
		if float(l["lit_t"]) <= 0.0:
			l["state"] = 0
			l["interactable"] = true
			room.events.append({"k": "lantern_out", "oid": l["id"]})


func _tf01_end(success: bool) -> void:
	_remove_mechanic_objects([Protocol.ObKind.LANTERN])
	if success:
		state = BS.EXPOSED
		exposed_t = 8.0
		t = 8.0
		_enter_stagger(2.0)
		room.events.append({"k": "boss_exposed", "sec": 8.0})
	else:
		for pl: Dictionary in room.players.values():
			if pl["state"] == Protocol.EntState.ALIVE:
				room._damage_player(pl, 12.0, pos, "boss")
		room.events.append({"k": "darkness_burst"})


# ------------------------------------------------------------------ TF-02 정화 씨앗 운반
## 목표: 씨앗을 집어(F) 연못 중앙까지 운반한다. 운반 중에는 느리고, 보스에게 맞으면 떨어뜨린다.

func _tf02_start(m: Dictionary) -> void:
	var prof := mprofile("TF-02")
	var pts := _points("seed_points", [[500, 200], [1000, 200], [500, 800], [1000, 800]])
	var ids: Array = []
	for i in mini(int(prof.get("seeds", 1)), pts.size()):
		var o := _add_object(Protocol.ObKind.SEED, Vector2(pts[i][0], pts[i][1]), 22.0, {"hold_sec": float(prof.get("pickup_sec", 0.8)), "interactable": true, "carrier": ""})
		ids.append(o["id"])
	var pond: Array = _points("pond", [750, 500])
	m["data"] = {"seeds": ids, "delivered": 0, "need": ids.size(), "pond": Vector2(pond[0], pond[1])}


func _tf02_step(_dt: float, m: Dictionary) -> void:
	var d: Dictionary = m["data"]
	for pid: String in carry.keys().duplicate():
		var o := _carried_object(pid)
		if o.is_empty() or int(o["kind"]) != Protocol.ObKind.SEED:
			continue
		var pl: Dictionary = room.players[pid]
		if (pl["pos"] as Vector2).distance_to(d["pond"]) <= 60.0:
			carry.erase(pid)
			room.objects.erase(o["id"])
			d["delivered"] = int(d["delivered"]) + 1
			pl["stats"]["objective"] = float(pl["stats"]["objective"]) + 1.0
			room.events.append({"k": "seed_delivered", "by": pid, "count": d["delivered"], "need": d["need"]})
			if int(d["delivered"]) >= int(d["need"]):
				_finish_mechanic(true, "pond_purified")
				return


func _tf02_end(success: bool) -> void:
	for pid: String in carry.keys().duplicate():
		var o := _carried_object(pid)
		if not o.is_empty() and int(o["kind"]) == Protocol.ObKind.SEED:
			carry.erase(pid)
	_remove_mechanic_objects([Protocol.ObKind.SEED])
	var pond: Vector2 = mechanics["TF-02"]["data"].get("pond", pos)
	if success:
		joint_weak_t = 15.0
		_clear_hazards()
		room.events.append({"k": "pond_purified", "x": pond.x, "y": pond.y})
	else:
		_add_hazard(pond, 200.0, 8.0, 4.0)
		room.events.append({"k": "pond_spread", "x": pond.x, "y": pond.y})


# ------------------------------------------------------------------ TF-03 포자 연결선 끊기
## 목표: 보스를 회복시키는 포자 결절을 모두 갉아 끊는다. 결절은 주기적으로 맥동하며 그동안은 만질 수 없다.

func _tf03_start(m: Dictionary) -> void:
	var prof := mprofile("TF-03")
	var ids: Array = []
	var count := int(prof.get("nodes", 1))
	for i in count:
		var a := TAU * i / float(count) + 0.4
		var np := room._clamp_in_bounds(pos + Vector2(cos(a), sin(a)) * 260.0, 30.0)
		var o := _add_object(Protocol.ObKind.SPORE_NODE, np, 28.0, {"hold_sec": float(prof.get("sever_sec", 2.0)), "interactable": true, "pulse_t": float(prof.get("pulse_every_sec", 4.0)) + i * 0.7})
		ids.append(o["id"])
	regen_per_sec = float(prof.get("heal_per_sec", 3.0)) * count
	m["data"] = {"nodes": ids, "pulse_every": float(prof.get("pulse_every_sec", 4.0)), "pulse_sec": float(prof.get("pulse_sec", 1.0))}


func _tf03_step(dt: float, m: Dictionary) -> void:
	var alive := 0
	for nid in m["data"]["nodes"]:
		var o: Dictionary = room.objects.get(nid, {})
		if o.is_empty():
			continue
		alive += 1
		o["pulse_t"] = float(o["pulse_t"]) - dt
		var pulsing := float(o["pulse_t"]) <= float(m["data"]["pulse_sec"])
		o["state"] = 1 if pulsing else 0
		o["interactable"] = not pulsing
		if pulsing:
			o["progress"] = 0.0
			for pl: Dictionary in room.players.values():
				if pl["state"] == Protocol.EntState.ALIVE and (pl["pos"] as Vector2).distance_to(o["pos"]) <= 70.0:
					room._damage_player(pl, 6.0 * dt, o["pos"], "hazard")
		if float(o["pulse_t"]) <= 0.0:
			o["pulse_t"] = float(m["data"]["pulse_every"])
	regen_per_sec = float(mprofile("TF-03").get("heal_per_sec", 3.0)) * alive


func _tf03_sever(o: Dictionary, p: Dictionary) -> void:
	room.objects.erase(o["id"])
	p["stats"]["objective"] = float(p["stats"]["objective"]) + 1.0
	room.events.append({"k": "spore_severed", "by": p["id"], "x": o["pos"].x, "y": o["pos"].y})
	var left := 0
	for nid in mechanics["TF-03"]["data"]["nodes"]:
		if room.objects.has(nid):
			left += 1
	if left == 0:
		_finish_mechanic(true, "all_severed")


func _tf03_end(success: bool) -> void:
	_remove_mechanic_objects([Protocol.ObKind.SPORE_NODE])
	regen_per_sec = 0.0
	if success:
		hp = maxf(hp - max_hp * 0.10, 1.0)
		_enter_stagger(3.0)
	else:
		hp = minf(hp + max_hp * 0.10, max_hp)
		room.events.append({"k": "boss_molt_heal", "hp": hp})


# ------------------------------------------------------------------ TF-04 공명목 두드리기
## 목표: 번호가 붙은 공명목을 순서대로 두드린다. 3인 이상은 연속 타격 사이 간격이 짧아 여러 명이 나눠야 한다.

func _tf04_start(m: Dictionary) -> void:
	var prof := mprofile("TF-04")
	var pts := _points("lily_pads", [[400, 300], [1100, 300], [400, 700], [1100, 700]])
	var count := mini(int(prof.get("logs", 2)), pts.size())
	var order := range(count)
	order.shuffle()
	var ids: Array = []
	for i in count:
		var o := _add_object(Protocol.ObKind.RESONANCE_LOG, Vector2(pts[i][0], pts[i][1]), 30.0, {"hold_sec": float(prof.get("hit_sec", 0.4)), "interactable": true, "order": int(order[i])})
		o["state"] = int(order[i]) + 1   # 표시용 번호 (1..N)
		ids.append(o["id"])
	m["data"] = {"logs": ids, "next": 0, "last_hit_t": -1.0, "sync": float(prof.get("sync_sec", 99.0))}


func _tf04_hit(o: Dictionary, p: Dictionary) -> void:
	var d: Dictionary = mechanics["TF-04"]["data"]
	o["progress"] = 0.0
	if int(o["order"]) != int(d["next"]):
		# 틀린 순서: 그 자리 감전 + 순서 초기화 (전체 진행은 유지)
		_add_hazard(o["pos"], 70.0, 3.0, 6.0)
		d["next"] = 0
		room.events.append({"k": "log_wrong", "by": p["id"], "x": o["pos"].x, "y": o["pos"].y})
		return
	if int(d["next"]) > 0 and float(d["last_hit_t"]) >= 0.0 and room.elapsed - float(d["last_hit_t"]) > float(d["sync"]):
		d["next"] = 0
		room.events.append({"k": "log_too_slow", "by": p["id"]})
		return
	d["next"] = int(d["next"]) + 1
	d["last_hit_t"] = room.elapsed
	p["stats"]["objective"] = float(p["stats"]["objective"]) + 1.0
	room.events.append({"k": "log_hit", "by": p["id"], "order": o["order"]})
	if int(d["next"]) >= (d["logs"] as Array).size():
		_finish_mechanic(true, "resonance")


func _tf04_step(_dt: float, _m: Dictionary) -> void:
	pass


func _tf04_end(success: bool) -> void:
	_remove_mechanic_objects([Protocol.ObKind.RESONANCE_LOG])
	if success:
		_enter_stagger(4.0)
		exposed_t = 5.0
		room.events.append({"k": "boss_exposed", "sec": 5.0})


# ------------------------------------------------------------------ TF-05 혼합통과 정화 반딧불
## 목표: 도망치는 반딧불을 잡아(F) 혼합통에 넣는다. 반딧불은 플레이어에게서 달아나므로 몰이가 필요하다.

func _tf05_start(m: Dictionary) -> void:
	var prof := mprofile("TF-05")
	var vp: Array = _points("vat", [750, 300])
	var vat := _add_object(Protocol.ObKind.VAT, Vector2(vp[0], vp[1]), 34.0, {"interactable": false, "filled": 0})
	var ids: Array = []
	for i in int(prof.get("fireflies", 1)):
		var a := TAU * i / maxf(float(prof.get("fireflies", 1)), 1.0)
		var fp := room._clamp_in_bounds(pos + Vector2(cos(a), sin(a)) * 300.0, 30.0)
		var o := _add_object(Protocol.ObKind.FIREFLY, fp, 18.0, {"hold_sec": float(prof.get("catch_sec", 0.6)), "interactable": true, "carrier": ""})
		ids.append(o["id"])
	m["data"] = {"vat": vat["id"], "fireflies": ids, "need": ids.size(), "flee": float(prof.get("flee_speed", 90.0))}


func _tf05_step(dt: float, m: Dictionary) -> void:
	var d: Dictionary = m["data"]
	var vat: Dictionary = room.objects.get(d["vat"], {})
	for fid in d["fireflies"]:
		var o: Dictionary = room.objects.get(fid, {})
		if o.is_empty() or String(o.get("carrier", "")) != "":
			continue
		var nearest := room._nearest_alive_player(o["pos"], 160.0)
		if nearest != "":
			var away: Vector2 = (o["pos"] - room.players[nearest]["pos"]).normalized()
			o["pos"] = room._clamp_in_bounds(o["pos"] + away * float(d["flee"]) * dt, 24.0)
	for pid: String in carry.keys().duplicate():
		var o := _carried_object(pid)
		if o.is_empty() or int(o["kind"]) != Protocol.ObKind.FIREFLY or vat.is_empty():
			continue
		if (room.players[pid]["pos"] as Vector2).distance_to(vat["pos"]) <= 60.0:
			carry.erase(pid)
			room.objects.erase(o["id"])
			vat["filled"] = int(vat["filled"]) + 1
			vat["progress"] = float(vat["filled"]) / maxf(float(d["need"]), 1.0)
			room.players[pid]["stats"]["objective"] = float(room.players[pid]["stats"]["objective"]) + 1.0
			room.events.append({"k": "firefly_added", "by": pid, "count": vat["filled"], "need": d["need"]})
			if int(vat["filled"]) >= int(d["need"]):
				_finish_mechanic(true, "vat_full")
				return


func _tf05_end(success: bool) -> void:
	for pid: String in carry.keys().duplicate():
		var o := _carried_object(pid)
		if not o.is_empty() and int(o["kind"]) == Protocol.ObKind.FIREFLY:
			carry.erase(pid)
	_remove_mechanic_objects([Protocol.ObKind.FIREFLY, Protocol.ObKind.VAT])
	if success:
		exposed_t = 6.0
		state = BS.EXPOSED
		t = 6.0
		for e: Dictionary in room.enemies.values():
			if e["ai"] != Protocol.EnemyAI.DEAD:
				room._kill_enemy(e, {"id": "light", "stats": {"kills": 0, "damage_dealt": 0.0}, "pos": e["pos"], "facing": Vector2.RIGHT})
		room.events.append({"k": "light_burst", "x": pos.x, "y": pos.y})
	else:
		sap_hazard_mult = 1.6
		sap_hazard_mult_t = 20.0
		room.events.append({"k": "sap_thickens"})

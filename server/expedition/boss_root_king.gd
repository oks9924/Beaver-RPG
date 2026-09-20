class_name BossRootKing
extends BossIronclaw
## 뿌리왕 (고대 뿌리댐 보스). 기본 패턴 4개(뿌리 휩쓸기·수압 분사·뿌리 분출·파편 부채꼴)는 공통 컨트롤러가 처리하고,
## 독립 기믹 5개(RK-01~05)를 정의한다: 댐 균열 막기, 수로 조각 연결, 기생 뿌리 뽑기, 기억 잔향 따라가기, 압력계 밸브.

var pressure: float = 0.0


func _mechanic_start(mid: String, m: Dictionary) -> void:
	match mid:
		"RK-01": _rk01_start(m)
		"RK-02": _rk02_start(m)
		"RK-03": _rk03_start(m)
		"RK-04": _rk04_start(m)
		"RK-05": _rk05_start(m)


func _mechanic_step(mid: String, dt: float, m: Dictionary) -> void:
	match mid:
		"RK-01": _rk01_step(dt, m)
		"RK-02": _rk02_step(dt, m)
		"RK-03": _rk03_step(dt, m)
		"RK-04": _rk04_step(dt, m)
		"RK-05": _rk05_step(dt, m)


func _mechanic_end(mid: String, success: bool) -> void:
	match mid:
		"RK-01": _rk01_end(success)
		"RK-02": _rk02_end(success)
		"RK-03": _rk03_end(success)
		"RK-04": _rk04_end(success)
		"RK-05": _rk05_end(success)


func _mechanic_object(o: Dictionary, p: Dictionary) -> void:
	match int(o["kind"]):
		Protocol.ObKind.CRACK: _rk01_plug(o, p)
		Protocol.ObKind.CHANNEL_PIECE: _rk02_toggle(o, p)
		Protocol.ObKind.PARASITE: _rk03_pull(o, p)
		Protocol.ObKind.ECHO: _rk04_reach(o, p)
		Protocol.ObKind.VALVE: _rk05_turn(o, p)


func _points(key: String, fallback: Array) -> Array:
	return room.room_def.get(key, fallback)


# ------------------------------------------------------------------ RK-01 댐 균열 막기
## 목표: 수압이 차오르기 전에 균열 N개를 모두 막는다 (분산 목표). 3인 이상은 추가 적이 방해한다.

func _rk01_start(m: Dictionary) -> void:
	var prof := mprofile("RK-01")
	var pts := _points("crack_points", [[400, 250], [1100, 250], [400, 750], [1100, 750]])
	var ids: Array = []
	for i in mini(int(prof.get("cracks", 1)), pts.size()):
		var o := _add_object(Protocol.ObKind.CRACK, Vector2(pts[i][0], pts[i][1]), 26.0, {"hold_sec": float(prof.get("plug_sec", 2.0)), "interactable": true})
		ids.append(o["id"])
	_spawn_adds(int(prof.get("adds", 0)), "gear_crab")
	m["data"] = {"cracks": ids}


func _rk01_plug(o: Dictionary, p: Dictionary) -> void:
	o["state"] = 1
	o["interactable"] = false
	o["progress"] = 1.0
	p["stats"]["objective"] = float(p["stats"]["objective"]) + 1.0
	room.events.append({"k": "crack_plugged", "by": p["id"], "x": o["pos"].x, "y": o["pos"].y})
	for cid in mechanics["RK-01"]["data"]["cracks"]:
		var c: Dictionary = room.objects.get(cid, {})
		if c.is_empty() or int(c["state"]) != 1:
			return
	_finish_mechanic(true, "all_plugged")


func _rk01_step(_dt: float, _m: Dictionary) -> void:
	pass


func _rk01_end(success: bool) -> void:
	_remove_mechanic_objects([Protocol.ObKind.CRACK])
	if success:
		_enter_stagger(4.0)
		joint_weak_t = 12.0
		room.events.append({"k": "pressure_vented"})
	else:
		if not room.water_zone.is_empty():
			room.water_zone["state"] = 2
			room.water_zone["flood_t"] = 6.0
		_add_hazard(room.bounds.get_center(), 220.0, 6.0, 5.0)
		room.events.append({"k": "dam_flood"})


# ------------------------------------------------------------------ RK-02 수로 조각 연결
## 목표: 수로 조각의 방향(0/1)을 표식과 맞춰 수압 분사를 보스에게 되돌린다. 조각 수는 인원에 따라 늘어난다.

func _rk02_start(m: Dictionary) -> void:
	var prof := mprofile("RK-02")
	var count := int(prof.get("pieces", 2))
	var ids: Array = []
	var c := room.bounds.get_center()
	for i in count:
		var pp := room._clamp_in_bounds(Vector2(c.x - 300 + 600.0 * i / maxf(count - 1, 1), c.y + 260), 30.0)
		var cur := room.rng.randi() % 2
		var tgt := room.rng.randi() % 2
		if i == 0 and cur == tgt:
			cur = 1 - tgt
		var o := _add_object(Protocol.ObKind.CHANNEL_PIECE, pp, 26.0, {"hold_sec": float(prof.get("hold_sec", 1.0)), "interactable": true, "cur": cur, "target": tgt})
		o["state"] = cur + 2 * tgt
		ids.append(o["id"])
	m["data"] = {"pieces": ids}


func _rk02_toggle(o: Dictionary, p: Dictionary) -> void:
	o["cur"] = 1 - int(o["cur"])
	o["state"] = int(o["cur"]) + 2 * int(o["target"])
	o["progress"] = 0.0
	p["stats"]["objective"] = float(p["stats"]["objective"]) + 1.0
	var mismatch := 0
	for pid in mechanics["RK-02"]["data"]["pieces"]:
		var pc: Dictionary = room.objects.get(pid, {})
		if not pc.is_empty() and int(pc["cur"]) != int(pc["target"]):
			mismatch += 1
	room.events.append({"k": "piece_turned", "by": p["id"], "mismatch": mismatch})
	if mismatch == 0:
		for pid in mechanics["RK-02"]["data"]["pieces"]:
			var pc: Dictionary = room.objects.get(pid, {})
			if not pc.is_empty():
				pc["interactable"] = false
				pc["state"] = 4
		_finish_mechanic(true, "channel_redirected")
	elif int(o["cur"]) != int(o["target"]):
		_add_hazard(o["pos"] + Vector2(0, -80), 80.0, 3.0, 5.0)


func _rk02_step(_dt: float, _m: Dictionary) -> void:
	pass


func _rk02_end(success: bool) -> void:
	_remove_mechanic_objects([Protocol.ObKind.CHANNEL_PIECE])
	if success:
		hp = maxf(hp - max_hp * 0.12, 1.0)
		_enter_stagger(2.0)
		room.events.append({"k": "jet_redirected", "x": pos.x, "y": pos.y})
	else:
		_add_hazard(pos + facing * 200.0, 140.0, 5.0, 6.0)
		room.events.append({"k": "jet_misfire"})


# ------------------------------------------------------------------ RK-03 기생 뿌리 뽑기
## 목표: 주기적으로 플레이어를 붙잡는 기생 뿌리를 모두 뽑는다. 붙잡힌 사람은 뽑을 수 없으므로 서로 풀어 줘야 한다.

func _rk03_start(m: Dictionary) -> void:
	var prof := mprofile("RK-03")
	var pts := _points("root_points", [[600, 300], [900, 300], [600, 700], [900, 700]])
	var ids: Array = []
	for i in mini(int(prof.get("parasites", 1)), pts.size()):
		var o := _add_object(Protocol.ObKind.PARASITE, Vector2(pts[i][0], pts[i][1]), 28.0, {"hold_sec": float(prof.get("pull_sec", 2.0)), "interactable": true})
		ids.append(o["id"])
	regen_per_sec = 2.0 * ids.size()
	m["data"] = {"parasites": ids, "latch_t": float(prof.get("latch_every_sec", 6.0)), "latch_every": float(prof.get("latch_every_sec", 6.0)), "root_sec": float(prof.get("root_sec", 1.2))}


func _rk03_step(dt: float, m: Dictionary) -> void:
	var d: Dictionary = m["data"]
	d["latch_t"] = float(d["latch_t"]) - dt
	if float(d["latch_t"]) <= 0.0:
		d["latch_t"] = float(d["latch_every"])
		var alive: Array = []
		for pl: Dictionary in room.players.values():
			if pl["state"] == Protocol.EntState.ALIVE:
				alive.append(pl)
		if not alive.is_empty():
			var victim: Dictionary = alive[room.rng.randi() % alive.size()]
			room._apply_hit_status(victim, {"root_sec": d["root_sec"], "bleed_dps": 1.5, "bleed_sec": 2.0})
			room.events.append({"k": "parasite_latch", "id": victim["id"]})
	# 붙잡힌(속박) 플레이어는 뿌리를 뽑을 수 없다
	for pid in d["parasites"]:
		var o: Dictionary = room.objects.get(pid, {})
		if o.is_empty():
			continue
		var holder: Dictionary = room.players.get(o.get("last_holder", ""), {})
		if not holder.is_empty() and float(holder["root_t"]) > 0.0 and holder["action"] == Protocol.Action.INTERACTING and holder["interact_target"] == o["id"]:
			o["progress"] = 0.0
			holder["action"] = Protocol.Action.IDLE
			holder["action_kind"] = ""
			holder["interact_target"] = 0


func _rk03_pull(o: Dictionary, p: Dictionary) -> void:
	if float(p["root_t"]) > 0.0:
		o["progress"] = 0.0
		return
	room.objects.erase(o["id"])
	p["stats"]["objective"] = float(p["stats"]["objective"]) + 1.0
	room.events.append({"k": "parasite_pulled", "by": p["id"], "x": o["pos"].x, "y": o["pos"].y})
	var left := 0
	for pid in mechanics["RK-03"]["data"]["parasites"]:
		if room.objects.has(pid):
			left += 1
	regen_per_sec = 2.0 * left
	if left == 0:
		_finish_mechanic(true, "roots_pulled")


func _rk03_end(success: bool) -> void:
	_remove_mechanic_objects([Protocol.ObKind.PARASITE])
	regen_per_sec = 0.0
	if success:
		exposed_t = 5.0
		state = BS.EXPOSED
		t = 5.0
		room.events.append({"k": "boss_exposed", "sec": 5.0})
	else:
		hp = minf(hp + max_hp * 0.12, max_hp)
		room.events.append({"k": "boss_molt_heal", "hp": hp})


# ------------------------------------------------------------------ RK-04 기억 잔향 따라가기
## 목표: 차례로 나타나는 기억 잔향에 제한 시간 안에 도달해 붙잡는다. 잔향 수와 창 길이는 인원에 따라 다르다.

func _rk04_start(m: Dictionary) -> void:
	var prof := mprofile("RK-04")
	m["data"] = {"index": 0, "count": int(prof.get("echoes", 2)), "window": float(prof.get("window_sec", 10.0)), "hold": float(prof.get("hold_sec", 1.0)), "echo": 0, "window_t": 0.0}
	_rk04_spawn_next(m)


func _rk04_spawn_next(m: Dictionary) -> void:
	var d: Dictionary = m["data"]
	var pts := _points("echo_points", [[350, 350], [1150, 350], [750, 850]])
	var pt: Array = pts[int(d["index"]) % pts.size()]
	var o := _add_object(Protocol.ObKind.ECHO, Vector2(pt[0], pt[1]), 30.0, {"hold_sec": float(d["hold"]), "interactable": true})
	d["echo"] = o["id"]
	d["window_t"] = float(d["window"])
	room.events.append({"k": "echo_appears", "x": o["pos"].x, "y": o["pos"].y, "index": d["index"], "count": d["count"]})


func _rk04_reach(o: Dictionary, p: Dictionary) -> void:
	var m: Dictionary = mechanics["RK-04"]
	var d: Dictionary = m["data"]
	room.objects.erase(o["id"])
	p["stats"]["objective"] = float(p["stats"]["objective"]) + 1.0
	d["index"] = int(d["index"]) + 1
	room.events.append({"k": "echo_caught", "by": p["id"], "index": d["index"], "count": d["count"]})
	if int(d["index"]) >= int(d["count"]):
		_finish_mechanic(true, "memory_found")
	else:
		_rk04_spawn_next(m)


func _rk04_step(dt: float, m: Dictionary) -> void:
	var d: Dictionary = m["data"]
	d["window_t"] = float(d["window_t"]) - dt
	var o: Dictionary = room.objects.get(d["echo"], {})
	if not o.is_empty():
		o["progress"] = clampf(float(d["window_t"]) / maxf(float(d["window"]), 1.0), 0.0, 1.0) if o["progress"] == 0.0 else o["progress"]
	if float(d["window_t"]) <= 0.0:
		_finish_mechanic(false, "echo_faded")


func _rk04_end(success: bool) -> void:
	_remove_mechanic_objects([Protocol.ObKind.ECHO])
	if success:
		exposed_t = 8.0
		state = BS.EXPOSED
		t = 8.0
		room.events.append({"k": "memory_found", "boss": def.get("id", "")})
	else:
		enrage_t = 15.0
		room.events.append({"k": "boss_enraged", "sec": 15.0})


# ------------------------------------------------------------------ RK-05 압력계 밸브
## 목표: 압력이 차기 전에 밸브 2개를 돌린다. 2인 이상은 두 밸브를 거의 동시에(sync) 돌려야 하고, 1인은 순차 유예 안에 돌린다.

func _rk05_start(m: Dictionary) -> void:
	var prof := mprofile("RK-05")
	var gp: Array = _points("gauge_point", [750, 120])
	var gauge := _add_object(Protocol.ObKind.GAUGE, Vector2(gp[0], gp[1]), 24.0, {"interactable": false})
	var pts := _points("valve_points", [[300, 500], [1200, 500]])
	var ids: Array = []
	for i in mini(int(prof.get("valves", 2)), pts.size()):
		var o := _add_object(Protocol.ObKind.VALVE, Vector2(pts[i][0], pts[i][1]), 26.0, {"hold_sec": float(prof.get("hold_sec", 1.5)), "interactable": true, "turned_t": -1.0})
		ids.append(o["id"])
	pressure = 0.0
	m["data"] = {"gauge": gauge["id"], "valves": ids, "sync": float(prof.get("sync_sec", 5.0)), "concurrent": bool(prof.get("concurrent", false)), "rate": float(prof.get("rate", 5.0))}


func _rk05_turn(o: Dictionary, p: Dictionary) -> void:
	var d: Dictionary = mechanics["RK-05"]["data"]
	o["turned_t"] = room.elapsed
	o["state"] = 1
	o["interactable"] = false
	o["progress"] = 1.0
	p["stats"]["objective"] = float(p["stats"]["objective"]) + 1.0
	room.events.append({"k": "valve_turned", "by": p["id"]})
	var times: Array = []
	for vid in d["valves"]:
		var v: Dictionary = room.objects.get(vid, {})
		if v.is_empty() or float(v["turned_t"]) < 0.0:
			return
		times.append(float(v["turned_t"]))
	var spread := float(times.max()) - float(times.min())
	if spread <= float(d["sync"]):
		_finish_mechanic(true, "vented")
	else:
		# 너무 늦게 맞춘 밸브: 먼저 돌린 밸브가 다시 잠긴다
		for vid in d["valves"]:
			var v: Dictionary = room.objects[vid]
			if float(v["turned_t"]) == float(times.min()):
				v["turned_t"] = -1.0
				v["state"] = 0
				v["interactable"] = true
				v["progress"] = 0.0
		room.events.append({"k": "valve_reset"})


func _rk05_step(dt: float, m: Dictionary) -> void:
	var d: Dictionary = m["data"]
	pressure = minf(pressure + float(d["rate"]) * dt, 100.0)
	var g: Dictionary = room.objects.get(d["gauge"], {})
	if not g.is_empty():
		g["progress"] = pressure / 100.0
		g["state"] = 1 if pressure > 70.0 else 0
	# 동시 조작 프로필: 먼저 돌린 밸브는 sync 안에 짝을 못 찾으면 되돌아간다
	if bool(d["concurrent"]):
		for vid in d["valves"]:
			var v: Dictionary = room.objects.get(vid, {})
			if not v.is_empty() and float(v["turned_t"]) >= 0.0 and room.elapsed - float(v["turned_t"]) > float(d["sync"]):
				v["turned_t"] = -1.0
				v["state"] = 0
				v["interactable"] = true
				v["progress"] = 0.0
				room.events.append({"k": "valve_reset"})
	if pressure >= 100.0:
		_finish_mechanic(false, "pressure_max")


func _rk05_end(success: bool) -> void:
	_remove_mechanic_objects([Protocol.ObKind.VALVE, Protocol.ObKind.GAUGE])
	pressure = 0.0
	if success:
		_enter_stagger(4.0)
		hp = maxf(hp - max_hp * 0.08, 1.0)
		room.events.append({"k": "pressure_vented"})
	else:
		for pl: Dictionary in room.players.values():
			if pl["state"] == Protocol.EntState.ALIVE:
				room._damage_player(pl, 15.0, pos, "boss")
		_add_hazard(pos, 160.0, 4.0, 6.0)
		room.events.append({"k": "steam_burst"})

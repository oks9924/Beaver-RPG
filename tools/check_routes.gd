extends Node
## GEN-01: 시드 100개로 던전 격자를 생성해 방 수·시작/보스 칸·문 대칭·보스 도달 가능·방 정의·문 위치를 점검한다.
## 실행: godot --headless --path . -- --tool=check_routes [--seeds=N]

func _ready() -> void:
	var seeds := 100
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seeds="):
			seeds = int(a.trim_prefix("--seeds="))
	var problems: PackedStringArray = []
	var stats := {"grids": 0, "rooms": 0, "regions": {}, "types": {}, "rooms_min": 99, "rooms_max": 0, "path_min": 99, "path_max": 0}
	for seed_ in seeds:
		var dungeons: Array = ExpeditionInstance.build_dungeon(seed_ * 7919 + 13, "willow_river", 3)
		var again: Array = ExpeditionInstance.build_dungeon(seed_ * 7919 + 13, "willow_river", 3)
		if JSON.stringify(dungeons) != JSON.stringify(again):
			problems.append("seed %d: dungeon not reproducible" % seed_)
		if dungeons.size() != 3:
			problems.append("seed %d: expected 3 region grids, got %d" % [seed_, dungeons.size()])
			continue
		for g: Dictionary in dungeons:
			stats["grids"] += 1
			var rooms: Dictionary = g.get("rooms", {})
			var rid := String(g.get("region", "?"))
			stats["regions"][rid] = int(stats["regions"].get(rid, 0)) + rooms.size()
			stats["rooms"] += rooms.size()
			stats["rooms_min"] = mini(int(stats["rooms_min"]), rooms.size())
			stats["rooms_max"] = maxi(int(stats["rooms_max"]), rooms.size())
			var dd: Dictionary = ContentDB.regions.get(rid, {}).get("dungeon", {})
			if rooms.size() < int(dd.get("rooms_min", 9)) - 2 or rooms.size() > int(dd.get("rooms_max", 11)):
				problems.append("seed %d %s: room count %d outside %d..%d" % [seed_, rid, rooms.size(), int(dd.get("rooms_min", 9)) - 2, int(dd.get("rooms_max", 11))])
			var sk := String(g.get("start", ""))
			var bk := String(g.get("boss", ""))
			if not rooms.has(sk) or not rooms.has(bk):
				problems.append("seed %d %s: start or boss cell missing" % [seed_, rid])
				continue
			if int(rooms[sk]["x"]) != 0 or int(rooms[bk]["x"]) != int(g.get("cols", 5)) - 1:
				problems.append("seed %d %s: start not in the left column or boss not in the right column" % [seed_, rid])
			if String(rooms[bk]["type"]) != "boss" or (rooms[bk]["doors"] as Dictionary).size() != 1:
				problems.append("seed %d %s: boss cell must be type boss with exactly one door" % [seed_, rid])
			var bosses := 0
			for k: String in rooms.keys():
				var node: Dictionary = rooms[k]
				var t := String(node["type"])
				stats["types"][t] = int(stats["types"].get(t, 0)) + 1
				if t == "boss":
					bosses += 1
				for dir: String in node["doors"].keys():
					var tk := String(node["doors"][dir])
					var back := String(ExpeditionInstance.DOOR_OPPOSITE.get(dir, ""))
					if not rooms.has(tk):
						problems.append("seed %d %s: door to missing cell %s" % [seed_, rid, tk])
					elif String(rooms[tk]["doors"].get(back, "")) != k:
						problems.append("seed %d %s: door %s->%s not symmetric" % [seed_, rid, k, tk])
					var expect: Vector2i = ExpeditionInstance.key_cell(k) + ExpeditionInstance.DOOR_DELTA[dir]
					if ExpeditionInstance.cell_key(expect) != tk:
						problems.append("seed %d %s: door %s from %s points to non-adjacent %s" % [seed_, rid, dir, k, tk])
				match t:
					"combat", "elite":
						_check_room(String(node["variant"]), seed_, problems)
					"boss":
						_check_room("boss_" + String(node["variant"]), seed_, problems)
						if ContentDB.bosses.get(String(node["variant"]), {}).is_empty():
							problems.append("seed %d: boss def missing %s" % [seed_, node["variant"]])
					"event":
						if ContentDB.events.get(String(node["variant"]), {}).is_empty():
							problems.append("seed %d: event missing %s" % [seed_, node["variant"]])
					"shop":
						if ContentDB.shop.get(String(node["variant"]), {}).is_empty():
							problems.append("seed %d: shop missing %s" % [seed_, node["variant"]])
					"rest", "treasure":
						pass
					_:
						problems.append("seed %d: unknown node type %s" % [seed_, t])
			if bosses != 1:
				problems.append("seed %d %s: expected 1 boss room, got %d" % [seed_, rid, bosses])
			# 보스 도달 가능 (BFS) + 최단 경로 길이 통계
			var dist := {sk: 0}
			var queue: Array = [sk]
			while not queue.is_empty():
				var k: String = queue.pop_front()
				for tk: String in rooms[k]["doors"].values():
					if not dist.has(tk):
						dist[tk] = int(dist[k]) + 1
						queue.append(tk)
			if not dist.has(bk):
				problems.append("seed %d %s: boss unreachable from start" % [seed_, rid])
			else:
				stats["path_min"] = mini(int(stats["path_min"]), int(dist[bk]) + 1)
				stats["path_max"] = maxi(int(stats["path_max"]), int(dist[bk]) + 1)
			if dist.size() != rooms.size():
				problems.append("seed %d %s: %d rooms unreachable" % [seed_, rid, rooms.size() - dist.size()])
			if not ContentDB.get_room_def(String(g.get("hall", ""))).is_empty() and String(ContentDB.get_room_def(String(g.get("hall", ""))).get("objective", "")) != "explore":
				problems.append("%s: hall room must have objective explore" % rid)
	# 모든 방 정의 자체 점검 (경로에 뽑히지 않은 변형 포함) + 네 방향 문 위치
	for rid: String in ContentDB.rooms.keys():
		if rid.begins_with("_"):
			continue
		_check_room(rid, -1, problems)
		_check_doors(rid, problems)
	var uniq := {}
	for pr in problems:
		uniq[pr] = true
	print("dungeons checked: seeds=%d grids=%d rooms=%d (per grid %d..%d, shortest path %d..%d) regions=%s types=%s" % [seeds, stats["grids"], stats["rooms"], stats["rooms_min"], stats["rooms_max"], stats["path_min"], stats["path_max"], stats["regions"], stats["types"]])
	for pr in uniq.keys():
		print("  PROBLEM " + pr)
	print("route check: %d problems" % uniq.size())
	get_tree().quit(0 if uniq.is_empty() else 1)


## 문 위치가 경계 안, 물·장애물 밖인지. 입장 위치도 같은 조건.
func _check_doors(rid: String, problems: PackedStringArray) -> void:
	var def := ContentDB.get_room_def(rid)
	var b: Dictionary = def.get("bounds", {})
	var rect := Rect2(float(b.get("x", 0)), float(b.get("y", 0)), float(b.get("w", 0)), float(b.get("h", 0)))
	var positions := CombatRoom.door_positions(def, ContentDB.rules)
	for dir: String in positions.keys():
		var v: Vector2 = positions[dir]
		if not rect.grow(-40).has_point(v):
			problems.append("%s: door %s outside bounds %s" % [rid, dir, v])
		if CombatRoom._door_blocked(v, def):
			problems.append("%s: door %s blocked by water/obstacle" % [rid, dir])
		for sp: Array in CombatRoom.entry_spawn_points(def, dir, ContentDB.rules):
			var e := Vector2(sp[0], sp[1])
			if not rect.grow(-20).has_point(e):
				problems.append("%s: entry spawn %s outside bounds" % [rid, dir])
			for ob: Dictionary in def.get("obstacles", []):
				if Vector2(float(ob["x"]), float(ob["y"])).distance_to(e) < float(ob["r"]) + 18:
					problems.append("%s: entry spawn %s inside obstacle" % [rid, dir])
			for w: Dictionary in def.get("water", []):
				if Rect2(float(w["x"]), float(w["y"]), float(w["w"]), float(w["h"])).has_point(e):
					problems.append("%s: entry spawn %s in water" % [rid, dir])


func _check_room(rid: String, seed_: int, problems: PackedStringArray) -> void:
	var def := ContentDB.get_room_def(rid)
	if def.is_empty():
		problems.append("seed %d: room def missing %s" % [seed_, rid])
		return
	var b: Dictionary = def.get("bounds", {})
	var rect := Rect2(float(b.get("x", 0)), float(b.get("y", 0)), float(b.get("w", 0)), float(b.get("h", 0)))
	if rect.size.x < 400 or rect.size.y < 300:
		problems.append("%s: bounds too small" % rid)
	var obstacles: Array = def.get("obstacles", [])
	for sp: Array in def.get("player_spawns", []):
		var v := Vector2(sp[0], sp[1])
		if not rect.grow(-20).has_point(v):
			problems.append("%s: player spawn outside bounds %s" % [rid, v])
		for ob: Dictionary in obstacles:
			if Vector2(float(ob["x"]), float(ob["y"])).distance_to(v) < float(ob["r"]) + 18:
				problems.append("%s: player spawn inside obstacle" % rid)
	for sp: Array in def.get("enemy_spawns", []):
		if not rect.grow(-10).has_point(Vector2(sp[0], sp[1])):
			problems.append("%s: enemy spawn outside bounds" % rid)
	for h: Dictionary in def.get("hazards", []):
		if not rect.encloses(Rect2(float(h["x"]), float(h["y"]), float(h["w"]), float(h["h"]))):
			problems.append("%s: hazard outside bounds" % rid)
	for pick: Dictionary in def.get("enemy_pool", []):
		var ed := ContentDB.get_enemy_def(String(pick.get("id", "")))
		if ed.is_empty() or not bool(ed.get("implemented", false)):
			problems.append("%s: enemy pool id not implemented %s" % [rid, pick.get("id", "")])
	var esc: Dictionary = def.get("escort", {})
	if String(def.get("objective", "")) == "escort":
		var path: Array = esc.get("path", [])
		if path.size() < 2:
			problems.append("%s: escort path too short" % rid)
		for pt: Array in path:
			var v := Vector2(pt[0], pt[1])
			if not rect.grow(-10).has_point(v):
				problems.append("%s: escort path point outside bounds" % rid)
			for ob: Dictionary in obstacles:
				if Vector2(float(ob["x"]), float(ob["y"])).distance_to(v) < float(ob["r"]) + 34:
					problems.append("%s: escort path point inside obstacle" % rid)
	if String(def.get("objective", "")) == "device" and (def.get("devices", []) as Array).is_empty():
		problems.append("%s: device room without devices" % rid)
	if String(def.get("objective", "")) == "hold_point" and (def.get("hold_zone", {}) as Dictionary).is_empty():
		problems.append("%s: hold room without hold_zone" % rid)
	if def.has("elite") and ContentDB.get_enemy_def(String(def["elite"].get("id", ""))).is_empty():
		problems.append("%s: elite id missing" % rid)
	for asset_id: String in def.get("assets", {}).values():
		if not AssetRegistry.has(asset_id):
			problems.append("%s: asset id missing %s" % [rid, asset_id])
	for ob: Dictionary in obstacles:
		if ob.has("asset") and not AssetRegistry.has(String(ob["asset"])):
			problems.append("%s: obstacle asset missing %s" % [rid, ob["asset"]])

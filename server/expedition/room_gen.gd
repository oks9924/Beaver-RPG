class_name RoomGen
extends RefCounted
## 방 내부 지형 랜덤화 (GEN-02): 방 틀(크기·시작 위치·적 등장·목표물·기믹)은 두고, 장애물과 물만 시드로 뿌린다.
## 보스·튜토리얼·테스트 방은 건드리지 않는다. 뿌린 뒤 격자 채우기로 모든 지점(시작·적·문·목표물)이 이어지는지 확인하고, 안 되면 다른 시드로 다시 한다.

const SKIP_OBJECTIVES := ["boss", "tutorial"]


static func rules() -> Dictionary:
	return ContentDB.rules.get("room_gen", {})


static func eligible(def: Dictionary) -> bool:
	if not bool(rules().get("enabled", true)):
		return false
	if String(def.get("id", "")) == "test_arena":
		return false
	return not SKIP_OBJECTIVES.has(String(def.get("objective", "annihilate")))


## 시드로 장애물·물을 다시 뿌린 방 정의 사본. 실패하면 원본을 돌려준다.
static func decorate(def: Dictionary, seed_: int) -> Dictionary:
	if not eligible(def):
		return def
	var rg := rules()
	var tries := int(rg.get("tries", 6))
	var mode := String(rg.get("mode", "prefab"))
	if mode == "prefab" and (ContentDB.chunks.get("chunks", []) as Array).is_empty():
		mode = "scatter"
	for attempt in tries:
		var out := _generate_prefab(def, seed_ + attempt * 7919, rg) if mode == "prefab" else _generate(def, seed_ + attempt * 7919, rg)
		if out.is_empty():
			continue
		if validate(out).is_empty():
			var meta: Dictionary = out.get("generated", {})
			meta["seed"] = seed_
			meta["attempt"] = attempt
			meta["mode"] = mode
			out["generated"] = meta
			return out
	return def


# ------------------------------------------------------------------ 프리팹 조각 (GEN-03)

## 역할(boulder/trunk/stump/bush) → 지역 소품 ID. 앞 후보(v7)가 최종 에셋이면 그것, 아니면 기존 소품으로 대체한다.
static func asset_for_role(region: String, role: String) -> String:
	var roles: Dictionary = ContentDB.chunks.get("roles", {}).get(region, {})
	var cands: Array = roles.get(role, [])
	for c: String in cands:
		if AssetRegistry.has(c) and AssetRegistry.status(c) == "final":
			return c
	return String(cands[cands.size() - 1]) if not cands.is_empty() else "prop.willow.rock"


static func _region_prefix(region: String) -> String:
	match region:
		"black_sap_swamp": return "swamp"
		"ancient_root_dam": return "dam"
		_: return "willow"


static func _pick_chunk(rng: RandomNumberGenerator, pool: Array) -> Dictionary:
	var total := 0.0
	for c: Dictionary in pool:
		total += float(c.get("weight", 1))
	var r := rng.randf() * total
	for c: Dictionary in pool:
		r -= float(c.get("weight", 1))
		if r <= 0.0:
			return c
	return pool[pool.size() - 1]


## 방을 cell 격자로 나누고 칸마다 조각을 고른다. 문이 닿는 칸은 open 계열만, 보호 지점을 침범하는 조각은 다른 조각으로 바꾼다.
static func _generate_prefab(def: Dictionary, seed_: int, rg: Dictionary) -> Dictionary:
	var lib: Dictionary = ContentDB.chunks
	var all_chunks: Array = lib.get("chunks", [])
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var out := def.duplicate(true)
	var b: Dictionary = def.get("bounds", {"x": 0, "y": 0, "w": 1400, "h": 900})
	var rect := Rect2(float(b["x"]), float(b["y"]), float(b["w"]), float(b["h"]))
	var region := String(def.get("region", "willow_river"))
	var cell_def: Dictionary = lib.get("cell", {"w": 350, "h": 300})
	var cols := maxi(int(round(rect.size.x / float(cell_def.get("w", 350)))), 2)
	var rows := maxi(int(round(rect.size.y / float(cell_def.get("h", 300)))), 2)
	var cw := rect.size.x / cols
	var ch := rect.size.y / rows
	var short := minf(cw, ch)
	var anchors := protected_points(def)
	var doors := CombatRoom.door_positions(def, ContentDB.rules)
	var keep_door := float(rg.get("keep_door", 160))
	var margin := float(rg.get("edge_margin", 110))
	var water: Array = []
	for w: Dictionary in def.get("water", []):
		if rng.randf() < float(rg.get("water_keep_chance", 0.7)):
			var nw := w.duplicate()
			var h := rng.randf_range(float(rg.get("water_h_min", 60)), float(rg.get("water_h_max", 100)))
			nw["y"] = rect.end.y - h
			nw["h"] = h
			water.append(nw)
	var obstacles: Array = []
	var decor: Array = []
	var grid: Array = []
	var max_obs := int(rg.get("prefab_max_obstacles", 14))
	for gy in rows:
		var row: Array = []
		for gx in cols:
			var cell_rect := Rect2(rect.position + Vector2(gx * cw, gy * ch), Vector2(cw, ch))
			var door_cell := false
			for dp: Vector2 in doors.values():
				if cell_rect.grow(keep_door * 0.5).has_point(dp):
					door_cell = true
			var pool: Array = []
			for c: Dictionary in all_chunks:
				if door_cell and not (c.get("tags", []) as Array).has("open"):
					continue
				pool.append(c)
			var chosen_id := "open"
			for attempt in 8:
				var c := _pick_chunk(rng, pool)
				var placed := _instantiate_chunk(c, cell_rect, short, region, anchors, doors, keep_door, rect, margin, water)
				if placed.is_empty() or obstacles.size() + (placed["obstacles"] as Array).size() > max_obs:
					continue
				obstacles.append_array(placed["obstacles"])
				decor.append_array(placed["decor"])
				water.append_array(placed["water"])
				chosen_id = String(c["id"])
				break
			row.append(chosen_id)
		grid.append(row)
	# 남는 공간에 1차 방식 장애물 몇 개
	var extra := rng.randi_range(0, int(rg.get("prefab_extra_max", 2)))
	var guard := 0
	while extra > 0 and guard < 60 and obstacles.size() < max_obs:
		guard += 1
		var r := roundf(rng.randf_range(float(rg.get("radius_min", 36)), float(rg.get("radius_max", 60))))
		var pos := Vector2(rng.randf_range(rect.position.x + margin, rect.end.x - margin), rng.randf_range(rect.position.y + margin, rect.end.y - margin)).round()
		if _collider_ok(pos, r, anchors, doors, keep_door, rect, margin, water, obstacles, float(rg.get("spacing", 150))):
			obstacles.append({"shape": "circle", "x": pos.x, "y": pos.y, "r": r, "asset": asset_for_role(region, ["boulder", "stump", "bush"][rng.randi() % 3])})
			extra -= 1
	if obstacles.size() < 2:
		return {}
	# 바닥 장식(자국·낙엽·웅덩이): v7 에셋이 최종일 때만
	var decals: Array = lib.get("decals", {}).get(region, [])
	for i in rng.randi_range(2, 5):
		if decals.is_empty():
			break
		var did := String(decals[rng.randi() % decals.size()])
		if AssetRegistry.has(did) and AssetRegistry.status(did) == "final":
			decor.append({"asset": did, "x": roundf(rng.randf_range(rect.position.x + 80, rect.end.x - 80)), "y": roundf(rng.randf_range(rect.position.y + 80, rect.end.y - 80)), "size": roundf(rng.randf_range(160, 240)), "frame": rng.randi() % 3})
	out["obstacles"] = obstacles
	out["water"] = water
	out["decor"] = decor
	out["generated"] = {"chunks": grid, "cols": cols, "rows": rows}
	return out


static func _collider_ok(pos: Vector2, r: float, anchors: Array, doors: Dictionary, keep_door: float, rect: Rect2, margin: float, water: Array, obstacles: Array, spacing: float) -> bool:
	if not rect.grow(-margin).has_point(pos):
		return false
	for w: Dictionary in water:
		if Rect2(float(w["x"]), float(w["y"]), float(w["w"]), float(w["h"])).grow(r + 20.0).has_point(pos):
			return false
	for a: Dictionary in anchors:
		if pos.distance_to(a["pos"]) < float(a["keep"]) + r:
			return false
	for dp: Vector2 in doors.values():
		if pos.distance_to(dp) < keep_door + r:
			return false
	for o: Dictionary in obstacles:
		if pos.distance_to(Vector2(float(o["x"]), float(o["y"]))) < spacing + r * 0.5:
			return false
	return true


## 조각 하나를 칸에 놓는다. 충돌 원이나 물이 보호 지점·문·가장자리를 침범하면 빈 딕셔너리.
static func _instantiate_chunk(c: Dictionary, cell_rect: Rect2, short: float, region: String, anchors: Array, doors: Dictionary, keep_door: float, rect: Rect2, margin: float, water: Array) -> Dictionary:
	var obs: Array = []
	var dec: Array = []
	var wat: Array = []
	var cols_def: Array = c.get("colliders", [])
	for col: Dictionary in cols_def:
		var pos := (cell_rect.position + Vector2(float(col["u"]) * cell_rect.size.x, float(col["v"]) * cell_rect.size.y)).round()
		var r := roundf(float(col["r"]) * short)
		if not _collider_ok(pos, r, anchors, doors, keep_door, rect, margin, water, [], 0.0):
			continue   # 보호 지점을 침범하는 원만 뺀다
		obs.append({"shape": "circle", "x": pos.x, "y": pos.y, "r": r, "asset": asset_for_role(region, String(col.get("role", "boulder"))), "part": String(col.get("part", ""))})
	if not cols_def.is_empty() and obs.size() * 2 < cols_def.size():
		return {}   # 절반 넘게 빠지면 이 조각은 포기 (모양이 안 남는다)
	if not cols_def.is_empty() and obs.size() < cols_def.size():
		for o: Dictionary in obs:
			o["part"] = ""   # 일부만 남았으면 합성 장식은 쓰지 않는다
	for w: Dictionary in c.get("water", []):
		var wr := Rect2(cell_rect.position + Vector2(float(w["u"]) * cell_rect.size.x, float(w["v"]) * cell_rect.size.y), Vector2(float(w["w"]) * cell_rect.size.x, float(w["h"]) * cell_rect.size.y))
		for a: Dictionary in anchors:
			if wr.grow(30.0).has_point(a["pos"]):
				return {}
		for dp: Vector2 in doors.values():
			if wr.grow(keep_door).has_point(dp):
				return {}
		wat.append({"x": roundf(wr.position.x), "y": roundf(wr.position.y), "w": roundf(wr.size.x), "h": roundf(wr.size.y), "damage_fraction": 0.1})
	for d: Dictionary in c.get("decor", []):
		# 긴 통나무 같은 합성 장식: v7 에셋이 최종일 때만 그리고, 그 조각의 충돌 원 스프라이트는 숨긴다
		var did := "prop.%s.%s" % [_region_prefix(region), String(d.get("asset_role", ""))]
		if AssetRegistry.has(did) and AssetRegistry.status(did) == "final":
			dec.append({"asset": did, "x": roundf(cell_rect.position.x + float(d["u"]) * cell_rect.size.x), "y": roundf(cell_rect.position.y + float(d["v"]) * cell_rect.size.y), "size": roundf(float(d.get("size", 1.0)) * cell_rect.size.x), "frame": 0})
			for o: Dictionary in obs:
				if String(o.get("part", "")) != "":
					o["asset"] = ""
	return {"obstacles": obs, "decor": dec, "water": wat}


static func _generate(def: Dictionary, seed_: int, rg: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var out := def.duplicate(true)
	var b: Dictionary = def.get("bounds", {"x": 0, "y": 0, "w": 1400, "h": 900})
	var rect := Rect2(float(b["x"]), float(b["y"]), float(b["w"]), float(b["h"]))
	var explore := String(def.get("objective", "")) == "explore"
	# 물: 원래 물이 있으면 확률로 유지하고 높이만 바꾼다 (아래쪽 띠). 없으면 없다.
	var water: Array = []
	for w: Dictionary in def.get("water", []):
		if rng.randf() < float(rg.get("water_keep_chance", 0.7)):
			var nw := w.duplicate()
			var h := rng.randf_range(float(rg.get("water_h_min", 60)), float(rg.get("water_h_max", 100)))
			nw["y"] = rect.end.y - h
			nw["h"] = h
			water.append(nw)
	out["water"] = water
	# 장애물 후보 자산: 그 방의 원래 장애물 자산 (지역 소품)
	var pool: Array = []
	for o: Dictionary in def.get("obstacles", []):
		var a := String(o.get("asset", ""))
		if a != "" and not pool.has(a):
			pool.append(a)
	if pool.is_empty():
		pool = ["prop.willow.rock"]
	var count := rng.randi_range(int(rg.get("explore_obstacles_min", 3)), int(rg.get("explore_obstacles_max", 6))) if explore \
		else rng.randi_range(int(rg.get("obstacles_min", 4)), int(rg.get("obstacles_max", 9)))
	var anchors := protected_points(def)
	var doors := CombatRoom.door_positions(def, ContentDB.rules)
	var margin := float(rg.get("edge_margin", 110))
	var spacing := float(rg.get("spacing", 150))
	var obstacles: Array = []
	var guard := 0
	while obstacles.size() < count and guard < 400:
		guard += 1
		var r := roundf(rng.randf_range(float(rg.get("radius_min", 36)), float(rg.get("radius_max", 60))))
		var pos := Vector2(rng.randf_range(rect.position.x + margin, rect.end.x - margin), rng.randf_range(rect.position.y + margin, rect.end.y - margin)).round()
		var ok := true
		for w: Dictionary in water:
			if Rect2(float(w["x"]), float(w["y"]), float(w["w"]), float(w["h"])).grow(r + 20.0).has_point(pos):
				ok = false
				break
		if not ok:
			continue
		for a: Dictionary in anchors:
			if pos.distance_to(a["pos"]) < float(a["keep"]) + r:
				ok = false
				break
		if not ok:
			continue
		for dp: Vector2 in doors.values():
			if pos.distance_to(dp) < float(rg.get("keep_door", 160)) + r:
				ok = false
				break
		if not ok:
			continue
		for o: Dictionary in obstacles:
			if pos.distance_to(Vector2(float(o["x"]), float(o["y"]))) < spacing + r * 0.5:
				ok = false
				break
		if not ok:
			continue
		obstacles.append({"shape": "circle", "x": pos.x, "y": pos.y, "r": r, "asset": String(pool[rng.randi() % pool.size()])})
	if obstacles.size() < int(rg.get("explore_obstacles_min", 3) if explore else rg.get("obstacles_min", 4)) - 1:
		return {}
	out["obstacles"] = obstacles
	return out


## 장애물이 침범하면 안 되는 지점과 여유 거리
static func protected_points(def: Dictionary) -> Array:
	var rg := rules()
	var out: Array = []
	for s: Array in def.get("player_spawns", []):
		out.append({"pos": Vector2(float(s[0]), float(s[1])), "keep": float(rg.get("keep_spawn", 140))})
	for s: Array in def.get("enemy_spawns", []):
		out.append({"pos": Vector2(float(s[0]), float(s[1])), "keep": float(rg.get("keep_enemy", 100))})
	var ka := float(rg.get("keep_anchor", 90))
	for t: Array in def.get("gnaw_trees", []):
		out.append({"pos": Vector2(float(t[0]), float(t[1])), "keep": ka})
	for dv: Dictionary in def.get("devices", []):
		out.append({"pos": Vector2(float(dv["x"]), float(dv["y"])), "keep": ka})
	var hz: Dictionary = def.get("hold_zone", {})
	if not hz.is_empty():
		out.append({"pos": Vector2(float(hz["x"]), float(hz["y"])), "keep": float(hz.get("r", 120)) + 60.0})
	var esc: Dictionary = def.get("escort", {})
	for pnt: Array in esc.get("path", []):
		out.append({"pos": Vector2(float(pnt[0]), float(pnt[1])), "keep": float(esc.get("radius", 140)) + 30.0})
	if esc.has("path"):
		# 경로 선분 중간 지점도 보호 (긴 구간)
		var path: Array = esc["path"]
		for i in range(path.size() - 1):
			var a := Vector2(float(path[i][0]), float(path[i][1]))
			var c := Vector2(float(path[i + 1][0]), float(path[i + 1][1]))
			for k in [0.25, 0.5, 0.75]:
				out.append({"pos": a.lerp(c, k), "keep": float(esc.get("radius", 140)) + 30.0})
	var sl: Variant = def.get("sluice", null)
	if sl is Dictionary and (sl as Dictionary).has("lever"):
		out.append({"pos": Vector2(float(sl["lever"][0]), float(sl["lever"][1])), "keep": ka})
	var sec: Dictionary = def.get("secret", {})
	if sec.has("x"):
		out.append({"pos": Vector2(float(sec["x"]), float(sec["y"])), "keep": ka})
	for hzd: Dictionary in def.get("hazards", []):
		out.append({"pos": Vector2(float(hzd["x"]) + float(hzd["w"]) * 0.5, float(hzd["y"]) + float(hzd["h"]) * 0.5), "keep": maxf(float(hzd["w"]), float(hzd["h"])) * 0.5 + 40.0})
	return out


## 격자 채우기: 보호 지점·문 앞·문 입장 위치가 전부 한 덩어리로 이어지면 빈 배열, 아니면 문제 목록
static func validate(def: Dictionary) -> PackedStringArray:
	var problems: PackedStringArray = []
	var rg := rules()
	var b: Dictionary = def.get("bounds", {"x": 0, "y": 0, "w": 1400, "h": 900})
	var rect := Rect2(float(b["x"]), float(b["y"]), float(b["w"]), float(b["h"]))
	var cell := float(rg.get("grid", 40))
	var pr := float(rg.get("player_radius", 18))
	var cols := int(ceil(rect.size.x / cell))
	var rows := int(ceil(rect.size.y / cell))
	var obstacles: Array = def.get("obstacles", [])
	var blocked := PackedByteArray()
	blocked.resize(cols * rows)
	for gy in rows:
		for gx in cols:
			var c := rect.position + Vector2((gx + 0.5) * cell, (gy + 0.5) * cell)
			for o: Dictionary in obstacles:
				if c.distance_to(Vector2(float(o["x"]), float(o["y"]))) < float(o["r"]) + pr:
					blocked[gy * cols + gx] = 1
					break
	var targets: Array = []
	for a: Dictionary in protected_points(def):
		targets.append(a["pos"])
	var doors := CombatRoom.door_positions(def, ContentDB.rules)
	for dir: String in doors.keys():
		targets.append(doors[dir])
		for sp: Array in CombatRoom.entry_spawn_points(def, dir, ContentDB.rules):
			targets.append(Vector2(float(sp[0]), float(sp[1])))
	if targets.is_empty():
		return problems
	var start: Vector2 = targets[0]
	var sx := clampi(int((start.x - rect.position.x) / cell), 0, cols - 1)
	var sy := clampi(int((start.y - rect.position.y) / cell), 0, rows - 1)
	var seen := PackedByteArray()
	seen.resize(cols * rows)
	var queue: Array = [Vector2i(sx, sy)]
	seen[sy * cols + sx] = 1
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n := cur + d
			if n.x < 0 or n.y < 0 or n.x >= cols or n.y >= rows:
				continue
			var idx := n.y * cols + n.x
			if seen[idx] == 1 or blocked[idx] == 1:
				continue
			seen[idx] = 1
			queue.append(n)
	for t: Vector2 in targets:
		var tx := clampi(int((t.x - rect.position.x) / cell), 0, cols - 1)
		var ty := clampi(int((t.y - rect.position.y) / cell), 0, rows - 1)
		# 목표 지점 칸이 장애물 안이면 이웃 칸 중 하나라도 닿으면 통과
		var ok := seen[ty * cols + tx] == 1
		if not ok:
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n := Vector2i(tx, ty) + d
				if n.x >= 0 and n.y >= 0 and n.x < cols and n.y < rows and seen[n.y * cols + n.x] == 1:
					ok = true
					break
		if not ok:
			problems.append("point (%d,%d) unreachable" % [int(t.x), int(t.y)])
	return problems

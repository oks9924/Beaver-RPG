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
	for attempt in tries:
		var out := _generate(def, seed_ + attempt * 7919, rg)
		if out.is_empty():
			continue
		if validate(out).is_empty():
			out["generated"] = {"seed": seed_, "attempt": attempt}
			return out
	return def


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

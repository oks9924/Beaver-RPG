extends Node
## GEN-01: 시드 100개로 경로를 생성해 층·노드·방 정의·보스 위치·등장 위치·호위 경로가 유효한지 점검한다.
## 실행: godot --headless --path . -- --tool=check_routes [--seeds=N]

func _ready() -> void:
	var seeds := 100
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seeds="):
			seeds = int(a.trim_prefix("--seeds="))
	var problems: PackedStringArray = []
	var stats := {"layers": 0, "nodes": 0, "regions": {}, "types": {}}
	for seed_ in seeds:
		var layers: Array = ExpeditionInstance.build_route(seed_ * 7919 + 13, "willow_river", 3)
		var again: Array = ExpeditionInstance.build_route(seed_ * 7919 + 13, "willow_river", 3)
		if JSON.stringify(layers) != JSON.stringify(again):
			problems.append("seed %d: route not reproducible" % seed_)
		if layers.is_empty():
			problems.append("seed %d: empty route" % seed_)
			continue
		var last: Array = layers[layers.size() - 1]
		if last.size() != 1 or String(last[0]["type"]) != "boss":
			problems.append("seed %d: last layer is not a single boss node" % seed_)
		var boss_count := 0
		for layer: Array in layers:
			stats["layers"] += 1
			if layer.is_empty():
				problems.append("seed %d: empty layer" % seed_)
			for node: Dictionary in layer:
				stats["nodes"] += 1
				var t := String(node["type"])
				stats["types"][t] = int(stats["types"].get(t, 0)) + 1
				stats["regions"][String(node.get("region", "?"))] = int(stats["regions"].get(String(node.get("region", "?")), 0)) + 1
				match t:
					"combat", "elite":
						_check_room(String(node["variant"]), seed_, problems)
					"boss":
						boss_count += 1
						_check_room("boss_" + String(node["variant"]), seed_, problems)
						if ContentDB.bosses.get(String(node["variant"]), {}).is_empty():
							problems.append("seed %d: boss def missing %s" % [seed_, node["variant"]])
					"event":
						if ContentDB.events.get(String(node["variant"]), {}).is_empty():
							problems.append("seed %d: event missing %s" % [seed_, node["variant"]])
					"shop":
						if ContentDB.shop.get(String(node["variant"]), {}).is_empty():
							problems.append("seed %d: shop missing %s" % [seed_, node["variant"]])
					"rest":
						pass
					_:
						problems.append("seed %d: unknown node type %s" % [seed_, t])
		if boss_count != 3:
			problems.append("seed %d: expected 3 region bosses, got %d" % [seed_, boss_count])
	# 모든 방 정의 자체 점검 (경로에 뽑히지 않은 변형 포함)
	for rid: String in ContentDB.rooms.keys():
		if rid.begins_with("_"):
			continue
		_check_room(rid, -1, problems)
	var uniq := {}
	for pr in problems:
		uniq[pr] = true
	print("routes checked: seeds=%d layers=%d nodes=%d regions=%s types=%s" % [seeds, stats["layers"], stats["nodes"], stats["regions"], stats["types"]])
	for pr in uniq.keys():
		print("  PROBLEM " + pr)
	print("route check: %d problems" % uniq.size())
	get_tree().quit(0 if uniq.is_empty() else 1)


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

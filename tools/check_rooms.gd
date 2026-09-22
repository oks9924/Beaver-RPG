extends Node
## GEN-02: 모든 방 정의 × 시드 N개로 지형을 랜덤 생성해 재현성·장애물 수·보호 지점 침범·연결성을 점검한다.
## 실행: godot --headless --path . -- --tool=check_rooms [--seeds=100]

func _ready() -> void:
	var seeds := 100
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seeds="):
			seeds = int(a.trim_prefix("--seeds="))
	var problems: PackedStringArray = []
	var stats := {"rooms": 0, "generated": 0, "fallback": 0, "obst_min": 99, "obst_max": 0, "obst_sum": 0, "water_kept": 0, "skipped": 0}
	var rg: Dictionary = ContentDB.rules.get("room_gen", {})
	for rid: String in ContentDB.rooms.keys():
		var base := ContentDB.get_room_def(rid)
		if not RoomGen.eligible(base):
			stats["skipped"] += 1
			continue
		stats["rooms"] += 1
		for s in seeds:
			var seed_ := s * 104729 + rid.hash()
			var def := RoomGen.decorate(base, seed_)
			var again := RoomGen.decorate(base, seed_)
			if JSON.stringify(def) != JSON.stringify(again):
				problems.append("%s seed %d: not reproducible" % [rid, s])
			if not def.has("generated"):
				stats["fallback"] += 1
				stats["fallback_rooms"] = stats.get("fallback_rooms", {})
				stats["fallback_rooms"][rid] = int(stats["fallback_rooms"].get(rid, 0)) + 1
				continue
			stats["generated"] += 1
			var obs: Array = def.get("obstacles", [])
			stats["obst_min"] = mini(int(stats["obst_min"]), obs.size())
			stats["obst_max"] = maxi(int(stats["obst_max"]), obs.size())
			stats["obst_sum"] += obs.size()
			if not (def.get("water", []) as Array).is_empty():
				stats["water_kept"] += 1
			var v := RoomGen.validate(def)
			for pr in v:
				problems.append("%s seed %d: %s" % [rid, s, pr])
			for a: Dictionary in RoomGen.protected_points(def):
				for o: Dictionary in obs:
					if Vector2(float(o["x"]), float(o["y"])).distance_to(a["pos"]) < float(a["keep"]) + float(o["r"]) - 0.5:
						problems.append("%s seed %d: obstacle inside protected point" % [rid, s])
			var b: Dictionary = def["bounds"]
			for o: Dictionary in obs:
				if float(o["x"]) < float(b["x"]) + 60 or float(o["y"]) < float(b["y"]) + 60 or float(o["x"]) > float(b["x"]) + float(b["w"]) - 60 or float(o["y"]) > float(b["y"]) + float(b["h"]) - 60:
					problems.append("%s seed %d: obstacle too close to the edge" % [rid, s])
	var gen := maxi(int(stats["generated"]), 1)
	print("check_rooms: rooms=%d (skipped %d) seeds=%d generated=%d fallback=%d obstacles %d..%d avg %.1f water kept %.0f%% problems=%d" % [
		stats["rooms"], stats["skipped"], seeds, stats["generated"], stats["fallback"], stats["obst_min"], stats["obst_max"], float(stats["obst_sum"]) / gen, 100.0 * float(stats["water_kept"]) / gen, problems.size()])
	for pr in problems.slice(0, 20):
		print("  " + pr)
	if stats.has("fallback_rooms"):
		print("  fallback by room: %s" % [stats["fallback_rooms"]])
	get_tree().quit(1 if not problems.is_empty() or int(stats["fallback"]) > int(stats["generated"]) / 20 else 0)

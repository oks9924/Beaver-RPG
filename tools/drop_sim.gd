extends Node
## DROP-02: 드랍 표 검증. 30분 한 판(사람 기준 처치 600 · 정예 12 · 보스 3)을 N번 시뮬레이션해 등급별 판당 개수와 전설까지 걸리는 판 수를 출력한다.
## 실행: godot --headless --path . -- --tool=drop_sim [--runs=1000] [--kills=600] [--elites=12] [--bosses=3] [--heat=0]

func _ready() -> void:
	var runs := 1000
	var kills := 600
	var elites := 12
	var bosses := 3
	var heat := 0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--runs="): runs = int(a.trim_prefix("--runs="))
		if a.begins_with("--kills="): kills = int(a.trim_prefix("--kills="))
		if a.begins_with("--elites="): elites = int(a.trim_prefix("--elites="))
		if a.begins_with("--bosses="): bosses = int(a.trim_prefix("--bosses="))
		if a.begins_with("--heat="): heat = int(a.trim_prefix("--heat="))
	var gd: Dictionary = ContentDB.equipment.get("ground_drop", {})
	var order := Equipment.rarity_order()
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var totals := {}
	for r: String in order:
		totals[r] = 0
	var first_legendary: Array = []
	var run_of_first := -1
	var bonus := float(heat) * float(gd.get("heat_rarity_bonus", 0.03))
	for run in runs:
		var got_leg := false
		var drops := 0
		for i in kills:
			if rng.randf() < float(gd.get("normal_chance", 0.015)):
				var r := Equipment.roll_rarity(rng, "", bonus)
				totals[r] += 1
				drops += 1
				got_leg = got_leg or r == "legendary"
		for i in elites:
			if rng.randf() < float(gd.get("elite_chance", 0.35)):
				var r := Equipment.roll_rarity(rng, String(gd.get("elite_min_rarity", "uncommon")), bonus)
				totals[r] += 1
				drops += 1
				got_leg = got_leg or r == "legendary"
		for i in bosses * int(gd.get("boss_count", 2)):
			var r := Equipment.roll_rarity(rng, String(gd.get("boss_min_rarity", "rare")), bonus)
			totals[r] += 1
			drops += 1
			got_leg = got_leg or r == "legendary"
		if got_leg:
			first_legendary.append(run)
	var total := 0
	for r: String in order:
		total += int(totals[r])
	print("drop_sim: runs=%d kills=%d elites=%d bosses=%d heat=%d → 판당 드랍 %.1f개" % [runs, kills, elites, bosses, heat, float(total) / runs])
	for r: String in order:
		var rd := Equipment.rarity_def(r)
		var lines := int(rd.get("lines", 0))
		var avg_roll := (float(rd.get("roll_min", 0.0)) + float(rd.get("roll_max", 1.0))) * 0.5
		var power := float(rd.get("base_mult", 1.0)) * (1.0 + 0.10 * lines * (0.5 + avg_roll)) * (1.12 if bool(rd.get("unique", false)) else 1.0)
		print("  %-9s 판당 %6.2f개  (%.1f%%)  기대 성능 ≈ %.2f" % [r, float(totals[r]) / runs, 100.0 * float(totals[r]) / maxf(total, 1), power])
	var leg_runs_per := float(runs) / maxf(first_legendary.size(), 1)
	print("  전설이 나온 판 비율 %.1f%% → 평균 %.1f판에 1개" % [100.0 * first_legendary.size() / runs, leg_runs_per])
	get_tree().quit(0)

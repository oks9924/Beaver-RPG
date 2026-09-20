class_name RunMods
extends RefCounted
## 유물·스킬 강화·런 레벨·영구 보너스를 플레이어 수치 보정(mods)과 발동 효과(procs)로 합친다.
## 같은 이름의 배율은 더하고(가산 강화), 상한은 rules.caps 로 자른다. 발동형은 원인 ID 와 내부 재사용 대기시간을 갖는다 (7절).

const MOD_KEYS := ["damage_mult", "max_hp_add", "dodge_charges_add", "speed_mult", "cdr", "knockback_mult", "stagger_add", "acorn_mult", "pierce_add",
	"e_radius_mult", "e_stagger_add", "q_duration_add", "q_value_set", "r_root_sec", "q_pellets_add", "q_spread_add", "e_max_traps_add", "e_root_add",
	"mark_damage_add", "mark_splash", "r_duration_add",
	"q_damage_add", "e_damage_add", "r_damage_add", "q_cdr", "e_cdr", "r_cdr", "r_shield_add", "guard_bonus_add", "e_double", "r_heal_tick",
	"e_vuln_sec_add", "e_vuln_add", "mark_hits_add", "r_radius_mult", "basic_recovery_mult", "r_slow", "r_final_burst", "e_trap_scatter",
	"q_distance_add", "q_invuln_add", "e_angle_add", "r_move_set", "heat_max_add", "heat_bleed", "heat_decay_add", "low_hp_damage", "low_hp_taken", "r_end_knockback", "q_ram",
	"q_radius_mult", "q_damage", "q_heal_add", "r_heal_add", "seed_interval_mult", "q_full_seed_bonus", "q_root_sec", "r_slow_set", "r_follow",
	"q_max_turrets_add", "q_fire_rate", "q_hp_add", "e_length_add", "e_knockback_add", "e_ally_sec_add", "e_self_slide", "r_hp_add", "r_burst_radius_add", "pressure_per_hit_add", "q_double_shot", "q_shot_slow", "r_burst_on_place", "r_burst_shield",
	"damage_reduction", "dodge_recharge_add", "basic_damage_add", "proj_speed_mult", "rest_heal_add", "structure_hp_mult", "build_cost_add", "rescue_hold_add", "rescue_protect_add",
	"heal_mult", "shop_discount", "boss_damage_mult", "shield_cap_add", "shield_duration_add", "interact_speed", "knockback_slow", "hp_per_ally", "start_acorns", "status_resist",
	"dodge_invuln_add", "proj_damage_add", "proj_bleed", "low_hp_regen", "shard_bonus", "start_shield", "mastery_xp_mult", "heal_fraction_add", "rare_chance_add", "secret_reward_add"]


static func empty() -> Dictionary:
	var m := {}
	for k in MOD_KEYS:
		m[k] = 0.0
	return m


## trait_id: 직업 숙련 대체 특성 (mastery.json). 유물 시너지는 relics.json 의 _synergies 를 태그 개수로 판정한다.
static func build(relic_ids: Array, upgrade_ids: Array, class_id: String, level: int, extra: Dictionary, rules: Dictionary, trait_id: String = "") -> Dictionary:
	var mods := empty()
	var procs: Array = []
	var synergies: Array = []
	var tag_count := {}
	for rid: String in relic_ids:
		for tg: String in ContentDB.relics.get(rid, {}).get("tags", []):
			tag_count[tg] = int(tag_count.get(tg, 0)) + 1
	var syn_defs: Dictionary = ContentDB.relics.get("_synergies", {})
	for tg: String in syn_defs.keys():
		if tg.begins_with("_"):
			continue
		var sd: Dictionary = syn_defs[tg]
		if int(tag_count.get(tg, 0)) >= int(sd.get("count", 2)):
			synergies.append(tg)
			_merge(mods, sd.get("mods", {}))
			for p: Dictionary in sd.get("procs", []):
				var pp := p.duplicate()
				pp["source"] = "synergy:" + tg
				pp["_last"] = -1000.0
				procs.append(pp)
	if trait_id != "":
		var tdef := ContentDB.mastery_trait(class_id, trait_id)
		_merge(mods, tdef.get("mods", {}))
		for p: Dictionary in tdef.get("procs", []):
			var pp := p.duplicate()
			pp["source"] = "trait:" + trait_id
			pp["_last"] = -1000.0
			procs.append(pp)
	for rid: String in relic_ids:
		var r: Dictionary = ContentDB.relics.get(rid, {})
		_merge(mods, r.get("mods", {}))
		for p: Dictionary in r.get("procs", []):
			var pp := p.duplicate()
			pp["source"] = rid
			pp["_last"] = -1000.0
			procs.append(pp)
	for uid: String in upgrade_ids:
		var u: Dictionary = ContentDB.upgrades.get(class_id, {}).get(uid, {})
		_merge(mods, u.get("mods", {}))
		for p: Dictionary in u.get("procs", []):
			var pp := p.duplicate()
			pp["source"] = uid
			pp["_last"] = -1000.0
			procs.append(pp)
	mods["damage_mult"] += float(rules.get("level_damage_mult_per_level", 0.04)) * maxi(level - 1, 0)
	mods["max_hp_add"] += float(rules.get("level_hp_add_per_level", 6)) * maxi(level - 1, 0)
	_merge(mods, extra)
	var caps: Dictionary = rules.get("caps", {})
	mods["cdr"] = minf(mods["cdr"], float(caps.get("cooldown_reduction_max", 0.4)))
	return {"mods": mods, "procs": procs, "synergies": synergies}


static func _merge(into: Dictionary, add: Dictionary) -> void:
	for k: String in add.keys():
		if k.ends_with("_set"):
			into[k] = float(add[k])
		else:
			into[k] = float(into.get(k, 0.0)) + float(add[k])

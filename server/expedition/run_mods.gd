class_name RunMods
extends RefCounted
## 유물·스킬 강화·런 레벨·영구 보너스를 플레이어 수치 보정(mods)과 발동 효과(procs)로 합친다.
## 같은 이름의 배율은 더하고(가산 강화), 상한은 rules.caps 로 자른다. 발동형은 원인 ID 와 내부 재사용 대기시간을 갖는다 (7절).

const MOD_KEYS := ["damage_mult", "max_hp_add", "dodge_charges_add", "speed_mult", "cdr", "knockback_mult", "stagger_add", "acorn_mult", "pierce_add",
	"e_radius_mult", "e_stagger_add", "q_duration_add", "q_value_set", "r_root_sec", "q_pellets_add", "q_spread_add", "e_max_traps_add", "e_root_add",
	"mark_damage_add", "mark_splash", "r_duration_add"]


static func empty() -> Dictionary:
	var m := {}
	for k in MOD_KEYS:
		m[k] = 0.0
	return m


static func build(relic_ids: Array, upgrade_ids: Array, class_id: String, level: int, extra: Dictionary, rules: Dictionary) -> Dictionary:
	var mods := empty()
	var procs: Array = []
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
	return {"mods": mods, "procs": procs}


static func _merge(into: Dictionary, add: Dictionary) -> void:
	for k: String in add.keys():
		if k.ends_with("_set"):
			into[k] = float(add[k])
		else:
			into[k] = float(into.get(k, 0.0)) + float(add[k])

class_name Equipment
extends RefCounted
## 영구 장비 (data/equipment.json, data/affixes.json). 서버가 굴리고 계정 progression 에 저장하며, 클라이언트는 설명·색만 읽는다.
## 아이템: {uid, slot(weapon|armor|trinket), base, class, rarity, level(1~3), affixes:[{id, v}], unique, name_ko}
## 기본 속성 = base × level_scale, 부가 속성은 등급별 줄 수, 전설은 고유 특성 1개. 합산은 caps 로 자른다.

const SLOTS := ["weapon", "armor", "trinket1", "trinket2"]


static func db() -> Dictionary:
	return ContentDB.equipment


static func rarity_order() -> Array:
	return db().get("rarity_order", ["common", "uncommon", "rare", "epic", "legendary"])


static func rarity_index(r: String) -> int:
	return maxi(rarity_order().find(r), 0)


static func rarity_def(r: String) -> Dictionary:
	return db().get("rarities", {}).get(r, {})


static func base_def(item: Dictionary) -> Dictionary:
	var slot := String(item.get("slot", ""))
	var table := "weapons" if slot == "weapon" else ("armors" if slot == "armor" else "trinkets")
	return db().get(table, {}).get(String(item.get("base", "")), {})


## 직업의 기본 무기(장비가 없을 때 쓰는 정의 id)
static func default_weapon(class_id: String) -> String:
	for wid: String in db().get("weapons", {}).keys():
		var w: Dictionary = db()["weapons"][wid]
		if String(w.get("class", "")) == class_id and bool(w.get("default", false)):
			return wid
	return ""


## 등급 굴림: 가중치 × (열기·깊이 보너스는 상위 등급 쪽으로), min_rarity 아래는 제외
static func roll_rarity(rng: RandomNumberGenerator, min_rarity: String = "", bonus: float = 0.0) -> String:
	var order := rarity_order()
	var min_i := rarity_index(min_rarity) if min_rarity != "" else 0
	var weights: Array = []
	var total := 0.0
	for i in order.size():
		var w := 0.0
		if i >= min_i:
			w = float(rarity_def(String(order[i])).get("weight", 1.0))
			if i > 0:
				w *= 1.0 + bonus * float(i)
		weights.append(w)
		total += w
	var r := rng.randf() * total
	for i in order.size():
		r -= float(weights[i])
		if r <= 0.0 and float(weights[i]) > 0.0:
			return String(order[i])
	return String(order[min_i])


static func roll_slot(rng: RandomNumberGenerator) -> String:
	var sw: Dictionary = db().get("drop", {}).get("slot_weights", {"weapon": 0.4, "armor": 0.3, "trinket": 0.3})
	var total := 0.0
	for k: String in sw.keys():
		total += float(sw[k])
	var r := rng.randf() * total
	for k: String in sw.keys():
		r -= float(sw[k])
		if r <= 0.0:
			return k
	return "armor"


## 아이템 하나를 굴린다. slot 이 "" 이면 슬롯도 굴린다. class_id 는 무기용(그 직업 무기 2종 중 하나).
static func roll_item(rng: RandomNumberGenerator, class_id: String, level: int, rarity: String, slot: String = "", uid_seed: int = 0) -> Dictionary:
	if slot == "":
		slot = roll_slot(rng)
	var table := "weapons" if slot == "weapon" else ("armors" if slot == "armor" else "trinkets")
	var pool: Array = []
	for bid: String in db().get(table, {}).keys():
		if slot != "weapon" or String(db()[table][bid].get("class", "")) == class_id:
			pool.append(bid)
	pool.sort()
	if pool.is_empty():
		return {}
	var base := String(pool[rng.randi() % pool.size()])
	var bdef: Dictionary = db()[table][base]
	var rdef := rarity_def(rarity)
	var item := {"uid": "it_%08x%04x" % [uid_seed if uid_seed != 0 else rng.randi(), rng.randi() & 0xFFFF], "slot": slot, "base": base, "class": String(bdef.get("class", "")), "rarity": rarity, "level": clampi(level, 1, 3), "affixes": [], "unique": ""}
	var lines := int(rdef.get("lines", 0))
	var tier_max := int(rdef.get("tier_max", 1))
	var attack_shape := ""
	if slot == "weapon":
		var cdef := ContentDB.get_class_def(class_id)
		attack_shape = String(bdef.get("basic_attack", {}).get("shape", cdef.get("basic_attack", {}).get("shape", "arc")))
	var candidates: Array = []
	for a: Dictionary in ContentDB.gear_affixes.get("affixes", []):
		if int(a.get("tier", 1)) > tier_max:
			continue
		if a.has("slots") and not (a["slots"] as Array).has(slot):
			continue
		if a.has("class") and String(a["class"]) != class_id:
			continue
		if a.has("attack") and String(a["attack"]) != attack_shape:
			continue
		candidates.append(a)
	var used: Dictionary = {}
	for i in lines:
		# 상위 계층 우선: 영웅·전설은 첫 줄에 3계층, 희귀는 2계층이 한 줄 이상 들어가게 시도한다
		var want_tier := tier_max if i == 0 else 0
		var pick := _pick_affix(rng, candidates, used, want_tier)
		if pick.is_empty():
			pick = _pick_affix(rng, candidates, used, 0)
		if pick.is_empty():
			break
		used[String(pick["id"])] = true
		var t := rng.randf_range(float(rdef.get("roll_min", 0.0)), float(rdef.get("roll_max", 1.0)))
		item["affixes"].append({"id": String(pick["id"]), "t": snappedf(t, 0.01)})
	if bool(rdef.get("unique", false)):
		var upool: Array = []
		for u: Dictionary in ContentDB.gear_affixes.get("uniques", []):
			var us := String(u.get("slot", ""))
			if (us == slot or (us == "trinket" and slot == "trinket")) and (not u.has("class") or String(u["class"]) == class_id):
				upool.append(String(u["id"]))
		upool.sort()
		if not upool.is_empty():
			item["unique"] = String(upool[rng.randi() % upool.size()])
	item["name_ko"] = display_name(item)
	return item


static func _pick_affix(rng: RandomNumberGenerator, candidates: Array, used: Dictionary, tier: int) -> Dictionary:
	var pool: Array = []
	for a: Dictionary in candidates:
		if used.has(String(a["id"])):
			continue
		if tier > 0 and int(a.get("tier", 1)) != tier:
			continue
		pool.append(a)
	if pool.is_empty():
		return {}
	return pool[rng.randi() % pool.size()]


static func affix_def(aid: String) -> Dictionary:
	for a: Dictionary in ContentDB.gear_affixes.get("affixes", []):
		if String(a.get("id", "")) == aid:
			return a
	return {}


static func unique_def(uid: String) -> Dictionary:
	for u: Dictionary in ContentDB.gear_affixes.get("uniques", []):
		if String(u.get("id", "")) == uid:
			return u
	return {}


## [min,max] 범위와 굴림 t(0~1) 로 실제 값. 정수형(fmt int*)은 반올림.
static func affix_value(range_: Variant, t: float, fmt: String = "pct") -> float:
	if range_ is Array and (range_ as Array).size() >= 2:
		var v := lerpf(float(range_[0]), float(range_[1]), clampf(t, 0.0, 1.0))
		if fmt.begins_with("int"):
			return float(roundi(v))
		return snappedf(v, 0.001)
	return float(range_)


## 아이템 하나의 mods·procs (기본 속성 × 레벨 배율 + 부가 속성 + 고유)
static func item_mods(item: Dictionary) -> Dictionary:
	var mods := {}
	var procs: Array = []
	var bdef := base_def(item)
	var scale := base_scale(item)
	for k: String in bdef.get("base", {}).keys():
		mods[k] = float(mods.get(k, 0.0)) + float(bdef["base"][k]) * scale
	for af: Dictionary in item.get("affixes", []):
		var a := affix_def(String(af.get("id", "")))
		var t := float(af.get("t", 0.5))
		for k: String in a.get("mods", {}).keys():
			mods[k] = float(mods.get(k, 0.0)) + affix_value(a["mods"][k], t, String(a.get("fmt", "pct")))
		for pr: Dictionary in a.get("procs", []):
			var pp := pr.duplicate()
			for pk: String in ["value", "chance"]:
				if pp.has(pk) and pp[pk] is Array:
					pp[pk] = affix_value(pp[pk], t, "num" if pk == "chance" else String(a.get("fmt", "int")))
			pp["source"] = "gear:" + String(af.get("id", ""))
			pp["_last"] = -1000.0
			procs.append(pp)
	var u := unique_def(String(item.get("unique", "")))
	for k: String in u.get("mods", {}).keys():
		mods[k] = float(mods.get(k, 0.0)) + float(u["mods"][k])
	for pr: Dictionary in u.get("procs", []):
		var pp := pr.duplicate()
		pp["source"] = "unique:" + String(u.get("id", ""))
		pp["_last"] = -1000.0
		procs.append(pp)
	return {"mods": mods, "procs": procs}


## 장착 장비 합산 (직업별 무기 슬롯). caps 로 자른다. 무기의 기본 공격 교체 정의도 돌려준다.
static func gear_bundle(prog: Dictionary, class_id: String) -> Dictionary:
	var mods := {}
	var procs: Array = []
	var items: Array = []
	var weapon_attack := {}
	var weapon_id := ""
	for it: Dictionary in equipped_items(prog, class_id):
		items.append(it)
		var im := item_mods(it)
		for k: String in im["mods"].keys():
			mods[k] = float(mods.get(k, 0.0)) + float(im["mods"][k])
		procs.append_array(im["procs"])
		if String(it.get("slot", "")) == "weapon":
			weapon_id = String(it.get("base", ""))
			weapon_attack = base_def(it).get("basic_attack", {}).duplicate(true)
	var caps: Dictionary = db().get("caps", {})
	for k: String in caps.keys():
		if k.begins_with("_") or not mods.has(k):
			continue
		var c := float(caps[k])
		mods[k] = clampf(float(mods[k]), -absf(c), absf(c))
	return {"mods": mods, "procs": procs, "items": items, "weapon_attack": weapon_attack, "weapon_id": weapon_id}


## 장착된 아이템 목록 (무기는 class_id 의 슬롯). 창고에서 사라진 uid 는 무시.
static func equipped_items(prog: Dictionary, class_id: String) -> Array:
	var out: Array = []
	var inv: Array = prog.get("inventory", [])
	var eqp: Dictionary = prog.get("equipped", {})
	var uids: Array = []
	var wslot: Dictionary = eqp.get("weapon", {})
	if wslot is Dictionary and String(wslot.get(class_id, "")) != "":
		uids.append(String(wslot[class_id]))
	for sk: String in ["armor", "trinket1", "trinket2"]:
		if String(eqp.get(sk, "")) != "":
			uids.append(String(eqp[sk]))
	for it: Dictionary in inv:
		if uids.has(String(it.get("uid", ""))):
			out.append(it)
	return out


static func find_item(prog: Dictionary, uid: String) -> Dictionary:
	for it: Dictionary in prog.get("inventory", []):
		if String(it.get("uid", "")) == uid:
			return it
	return {}


## 장착. 무기는 아이템의 직업 슬롯에, 장신구는 지정 슬롯(trinket1/trinket2)에. uid "" 이면 해제. 돌려주는 값: "" 또는 오류 코드.
static func equip(prog: Dictionary, slot: String, uid: String) -> String:
	if not prog.has("equipped") or not (prog["equipped"] is Dictionary):
		prog["equipped"] = {"weapon": {}, "armor": "", "trinket1": "", "trinket2": ""}
	var eqp: Dictionary = prog["equipped"]
	if not eqp.has("weapon") or not (eqp["weapon"] is Dictionary):
		eqp["weapon"] = {}
	for sk: String in ["armor", "trinket1", "trinket2"]:
		if not eqp.has(sk):
			eqp[sk] = ""
	if uid == "":
		if slot == "weapon":
			return "BAD_SLOT"
		if slot.begins_with("weapon:"):
			eqp["weapon"].erase(slot.trim_prefix("weapon:"))
			return ""
		if not SLOTS.has(slot):
			return "BAD_SLOT"
		eqp[slot] = ""
		return ""
	var it := find_item(prog, uid)
	if it.is_empty():
		return "NO_ITEM"
	match String(it.get("slot", "")):
		"weapon":
			var cls := String(it.get("class", ""))
			eqp["weapon"][cls] = uid
		"armor":
			eqp["armor"] = uid
		"trinket":
			var target := slot if slot in ["trinket1", "trinket2"] else ("trinket1" if String(eqp.get("trinket1", "")) == "" else "trinket2")
			# 같은 장신구를 두 슬롯에 끼지 못한다
			for sk: String in ["trinket1", "trinket2"]:
				if String(eqp.get(sk, "")) == uid:
					eqp[sk] = ""
			eqp[target] = uid
		_:
			return "BAD_SLOT"
	return ""


## 기본 속성 배율 = 지역 레벨 배율 × (1 + 강화 단계 × base_mult_per_level)
static func base_scale(item: Dictionary) -> float:
	var scale := float(db().get("level_scale", {}).get(str(int(item.get("level", 1))), 1.0))
	return scale * (1.0 + int(item.get("enhance", 0)) * float(db().get("enhance", {}).get("base_mult_per_level", 0.1)))


static func display_name(item: Dictionary) -> String:
	var bdef := base_def(item)
	var name := String(bdef.get("name_ko", item.get("base", "?")))
	var u := unique_def(String(item.get("unique", "")))
	var out := name
	if not u.is_empty():
		out = String(u.get("name_ko", name))
	else:
		var pre: String = {"uncommon": "단단한 ", "rare": "정교한 ", "epic": "영웅의 "}.get(String(item.get("rarity", "common")), "")
		out = pre + name
	if int(item.get("enhance", 0)) > 0:
		out += " +%d" % int(item["enhance"])
	return out


# ------------------------------------------------------------------ 강화 · 재감정 · 분해 (재료: 수액 결정)

static func material_count(prog: Dictionary, mat: String = "sap_crystal") -> int:
	return int(prog.get("materials", {}).get(mat, 0))


static func add_material(prog: Dictionary, amount: int, mat: String = "sap_crystal") -> void:
	if not prog.has("materials") or not (prog["materials"] is Dictionary):
		prog["materials"] = {}
	prog["materials"][mat] = maxi(int(prog["materials"].get(mat, 0)) + amount, 0)


static func enhance_cost(item: Dictionary) -> int:
	var en: Dictionary = db().get("enhance", {})
	var lv := int(item.get("enhance", 0))
	var costs: Array = en.get("cost", [3, 5, 8, 12, 18])
	if lv >= int(en.get("max", 5)) or costs.is_empty():
		return -1
	var base := float(costs[mini(lv, costs.size() - 1)])
	return int(ceil(base * (1.0 + rarity_index(String(item.get("rarity", "common"))) * float(en.get("rarity_cost_mult", 0.5)))))


static func reforge_cost(item: Dictionary) -> int:
	var c: Dictionary = db().get("reforge", {}).get("cost", {})
	if (item.get("affixes", []) as Array).is_empty():
		return -1
	return int(c.get(String(item.get("rarity", "common")), -1))


static func salvage_value(item: Dictionary) -> int:
	var v: Dictionary = db().get("salvage", {}).get("value", {})
	return int(v.get(String(item.get("rarity", "common")), 1)) + int(item.get("enhance", 0))


static func is_equipped(prog: Dictionary, uid: String) -> bool:
	var eqp: Dictionary = prog.get("equipped", {})
	for sk: String in ["armor", "trinket1", "trinket2"]:
		if String(eqp.get(sk, "")) == uid:
			return true
	var w: Variant = eqp.get("weapon", {})
	if w is Dictionary:
		for cid: String in (w as Dictionary).keys():
			if String(w[cid]) == uid:
				return true
	return false


## 다음 단계 성공률 (success_chance[현재 단계]). 파괴는 destroy_chance 고정, 나머지가 실패(재료만 소모).
static func enhance_success_chance(item: Dictionary) -> float:
	var en: Dictionary = db().get("enhance", {})
	var table: Array = en.get("success_chance", [0.95, 0.85, 0.7, 0.55, 0.4])
	var lv := int(item.get("enhance", 0))
	if table.is_empty():
		return 1.0
	return clampf(float(table[mini(lv, table.size() - 1)]), 0.0, 1.0)


static func enhance_destroy_chance() -> float:
	return clampf(float(db().get("enhance", {}).get("destroy_chance", 0.01)), 0.0, 1.0)


## 강화: 수액 결정을 쓰고 굴린다. 돌려주는 값: "" 성공(enhance +1), "ENHANCE_FAILED" 실패(재료만 소모), "ENHANCE_DESTROYED" 파괴(창고에서 제거), 그 외 오류 코드.
## 굴림 순서: [0, destroy) 파괴 → [destroy, destroy + success) 성공 → 나머지 실패. rng 가 없으면 항상 성공(테스트·도구용).
static func enhance(prog: Dictionary, uid: String, rng: RandomNumberGenerator = null) -> String:
	var it := find_item(prog, uid)
	if it.is_empty():
		return "NO_ITEM"
	var cost := enhance_cost(it)
	if cost < 0:
		return "MAX_ENHANCE"
	if material_count(prog) < cost:
		return "NOT_ENOUGH_MATERIALS"
	add_material(prog, -cost)
	if rng != null:
		var roll := rng.randf()
		var destroy := enhance_destroy_chance()
		if roll < destroy:
			var inv: Array = prog.get("inventory", [])
			for i in inv.size():
				if String(inv[i].get("uid", "")) == uid:
					inv.remove_at(i)
					break
			_unequip_uid(prog, uid)
			return "ENHANCE_DESTROYED"
		if roll >= destroy + enhance_success_chance(it):
			return "ENHANCE_FAILED"
	it["enhance"] = int(it.get("enhance", 0)) + 1
	it["name_ko"] = display_name(it)
	return ""


static func _unequip_uid(prog: Dictionary, uid: String) -> void:
	var eqp: Dictionary = prog.get("equipped", {})
	for sk: String in ["armor", "trinket1", "trinket2"]:
		if String(eqp.get(sk, "")) == uid:
			eqp[sk] = ""
	var w: Variant = eqp.get("weapon", {})
	if w is Dictionary:
		for cid: String in (w as Dictionary).keys().duplicate():
			if String(w[cid]) == uid:
				(w as Dictionary).erase(cid)


# ------------------------------------------------------------------ 제작 도안

static func recipes() -> Array:
	return db().get("recipes", {}).get("list", [])


static func recipe_def(rid: String) -> Dictionary:
	for r: Dictionary in recipes():
		if String(r.get("id", "")) == rid:
			return r
	return {}


## 도안 해금 여부: unlock 이 비면 항상, boss 면 progression.blueprints 에 도안 id 가 있어야 한다
static func recipe_unlocked(prog: Dictionary, r: Dictionary) -> bool:
	var unlock: Dictionary = r.get("unlock", {})
	if unlock.is_empty():
		return true
	return (prog.get("blueprints", []) as Array).has(String(r.get("id", "")))


## 보스 처치로 해금되는 도안 id 목록
static func blueprints_for_boss(boss_id: String) -> Array:
	var out: Array = []
	for r: Dictionary in recipes():
		if String(r.get("unlock", {}).get("boss", "")) == boss_id:
			out.append(String(r.get("id", "")))
	return out


## 제작: 비용(수액 결정·기억 조각)을 내고 도안의 슬롯·등급·레벨로 굴린다. 돌려주는 값 {"error": code} 또는 {"item": ...}
static func craft(prog: Dictionary, rid: String, class_id: String, rng: RandomNumberGenerator) -> Dictionary:
	var r := recipe_def(rid)
	if r.is_empty():
		return {"error": "NO_RECIPE"}
	if not recipe_unlocked(prog, r):
		return {"error": "RECIPE_LOCKED"}
	var cost: Dictionary = r.get("cost", {})
	if material_count(prog) < int(cost.get("sap_crystal", 0)):
		return {"error": "NOT_ENOUGH_MATERIALS"}
	if int(prog.get("memory_shards", 0)) < int(cost.get("memory_shards", 0)):
		return {"error": "NOT_ENOUGH_SHARDS"}
	var inv: Array = prog.get("inventory", [])
	if inv.size() >= int(db().get("drop", {}).get("inventory_cap", 60)):
		return {"error": "INVENTORY_FULL"}
	var item := roll_item(rng, class_id, int(r.get("level", 1)), String(r.get("rarity", "uncommon")), String(r.get("slot", "armor")), int(rng.randi()))
	if item.is_empty():
		return {"error": "NO_RECIPE"}
	add_material(prog, -int(cost.get("sap_crystal", 0)))
	prog["memory_shards"] = int(prog.get("memory_shards", 0)) - int(cost.get("memory_shards", 0))
	item["crafted"] = true
	inv.append(item)
	prog["inventory"] = inv
	return {"item": item}


## 재감정: index 번째 부가 속성을 같은 등급 계층 안에서 새 특성으로 다시 굴린다 (다른 줄과 중복 금지)
static func reforge(prog: Dictionary, uid: String, index: int, rng: RandomNumberGenerator) -> String:
	var it := find_item(prog, uid)
	if it.is_empty():
		return "NO_ITEM"
	var affixes: Array = it.get("affixes", [])
	if index < 0 or index >= affixes.size():
		return "BAD_INDEX"
	var cost := reforge_cost(it)
	if cost < 0:
		return "BAD_STATE"
	if material_count(prog) < cost:
		return "NOT_ENOUGH_MATERIALS"
	var rdef := rarity_def(String(it.get("rarity", "common")))
	var slot := String(it.get("slot", ""))
	var class_id := String(it.get("class", ""))
	var attack_shape := ""
	if slot == "weapon":
		attack_shape = String(base_def(it).get("basic_attack", {}).get("shape", ContentDB.get_class_def(class_id).get("basic_attack", {}).get("shape", "arc")))
	var used: Dictionary = {}
	for i in affixes.size():
		if i != index:
			used[String(affixes[i]["id"])] = true
	used[String(affixes[index]["id"])] = true   # 같은 특성으로 되돌아오지 않게
	var candidates: Array = []
	for a: Dictionary in ContentDB.gear_affixes.get("affixes", []):
		if int(a.get("tier", 1)) > int(rdef.get("tier_max", 1)):
			continue
		if a.has("slots") and not (a["slots"] as Array).has(slot):
			continue
		if a.has("class") and String(a["class"]) != class_id:
			continue
		if a.has("attack") and String(a["attack"]) != attack_shape:
			continue
		candidates.append(a)
	var pick := _pick_affix(rng, candidates, used, 0)
	if pick.is_empty():
		return "NO_CANDIDATE"
	add_material(prog, -cost)
	var t := rng.randf_range(float(rdef.get("roll_min", 0.0)), float(rdef.get("roll_max", 1.0)))
	affixes[index] = {"id": String(pick["id"]), "t": snappedf(t, 0.01)}
	return ""


## 분해: 장착 중이 아닌 장비를 없애고 수액 결정을 얻는다
static func salvage(prog: Dictionary, uid: String) -> String:
	var it := find_item(prog, uid)
	if it.is_empty():
		return "NO_ITEM"
	if is_equipped(prog, uid):
		return "ITEM_EQUIPPED"
	add_material(prog, salvage_value(it))
	var inv: Array = prog.get("inventory", [])
	for i in inv.size():
		if String(inv[i].get("uid", "")) == uid:
			inv.remove_at(i)
			break
	return ""


## 설명 줄들: [기본 속성, 부가 속성..., 고유]
static func describe(item: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = []
	var bdef := base_def(item)
	var scale := base_scale(item)
	var base_parts: PackedStringArray = []
	for k: String in bdef.get("base", {}).keys():
		base_parts.append(_mod_text(k, float(bdef["base"][k]) * scale))
	out.append("기본: " + (", ".join(base_parts) if not base_parts.is_empty() else "-") + " (지역 %d%s)" % [int(item.get("level", 1)), (" · 강화 +%d" % int(item["enhance"])) if int(item.get("enhance", 0)) > 0 else ""])
	if not bdef.get("basic_attack", {}).is_empty():
		out.append("기본 공격 교체: " + String(bdef.get("desc_ko", "")))
	for af: Dictionary in item.get("affixes", []):
		var a := affix_def(String(af.get("id", "")))
		if a.is_empty():
			continue
		var t := float(af.get("t", 0.5))
		var v := 0.0
		var fmt := String(a.get("fmt", "pct"))
		if a.has("mods"):
			var mk: String = (a["mods"] as Dictionary).keys()[0]
			v = affix_value(a["mods"][mk], t, fmt)
		elif a.has("procs"):
			var pr: Dictionary = a["procs"][0]
			v = affix_value(pr.get("chance", pr.get("value", 0)), t, fmt) if fmt == "chance" else affix_value(pr.get("value", 0), t, fmt)
		out.append("· " + String(a.get("name_ko", a.get("id", ""))).replace("{v}", _fmt_value(v, fmt)))
	var u := unique_def(String(item.get("unique", "")))
	if not u.is_empty():
		out.append("★ %s — %s" % [u.get("name_ko", ""), u.get("desc_ko", "")])
	return out


static func _fmt_value(v: float, fmt: String) -> String:
	match fmt:
		"pct", "pct_abs", "chance": return str(roundi(absf(v) * 100.0))
		"int", "int_abs": return str(roundi(absf(v)))
		"sec", "sec_abs": return "%.1f" % absf(v)
	return "%.1f" % v


const MOD_KO := {"damage_mult": "피해 +{p}%", "max_hp_add": "최대 체력 +{i}", "knockback_mult": "넉백 +{p}%", "stagger_add": "경직 +{s}초", "proj_damage_add": "투사체 피해 +{i}", "proj_bleed": "출혈 {i}/초", "heal_mult": "회복 +{p}%",
	"structure_hp_mult": "설치물 체력 +{p}%", "e_length_add": "급류 길이 +{i}", "damage_reduction": "받는 피해 -{p}%", "speed_mult": "이동 속도 +{p}%", "dodge_invuln_add": "회피 무적 +{s}초", "acorn_mult": "도토리 +{p}%", "cdr": "재사용 대기시간 -{p}%"}


static func _mod_text(k: String, v: float) -> String:
	var tpl := String(MOD_KO.get(k, k + " {n}"))
	return tpl.replace("{p}", str(roundi(v * 100.0))).replace("{i}", str(roundi(v))).replace("{s}", "%.2f" % v).replace("{n}", "%.2f" % v)


static func rarity_color(r: String) -> Color:
	return Color.html(String(rarity_def(r).get("color", "#ffffff")))


static func rarity_name(r: String) -> String:
	return String(rarity_def(r).get("name_ko", r))

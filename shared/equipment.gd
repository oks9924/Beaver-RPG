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
	var scale := float(db().get("level_scale", {}).get(str(int(item.get("level", 1))), 1.0))
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


static func display_name(item: Dictionary) -> String:
	var bdef := base_def(item)
	var name := String(bdef.get("name_ko", item.get("base", "?")))
	var u := unique_def(String(item.get("unique", "")))
	if not u.is_empty():
		return String(u.get("name_ko", name))
	var pre: String = {"uncommon": "단단한 ", "rare": "정교한 ", "epic": "영웅의 "}.get(String(item.get("rarity", "common")), "")
	return pre + name


## 설명 줄들: [기본 속성, 부가 속성..., 고유]
static func describe(item: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = []
	var bdef := base_def(item)
	var scale := float(db().get("level_scale", {}).get(str(int(item.get("level", 1))), 1.0))
	var base_parts: PackedStringArray = []
	for k: String in bdef.get("base", {}).keys():
		base_parts.append(_mod_text(k, float(bdef["base"][k]) * scale))
	out.append("기본: " + (", ".join(base_parts) if not base_parts.is_empty() else "-") + " (지역 %d)" % int(item.get("level", 1)))
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

extends Node
## data/*.json 을 읽어 서버·클라이언트가 같은 콘텐츠 수치를 사용하게 한다.
## 숫자는 코드에 흩어놓지 않고 이 데이터 파일에서 조절한다 (7절).

const DATA_DIR := "res://data/"

var classes: Dictionary = {}
var mastery: Dictionary = {}
var npcs: Dictionary = {}
var quests: Dictionary = {}
var equipment: Dictionary = {}      # data/equipment.json (영구 장비: 무기·갑옷·장신구·등급)
var gear_affixes: Dictionary = {}   # data/affixes.json (장비 부가 속성·전설 고유)
var enemies: Dictionary = {}
var party_scaling: Dictionary = {}
var rules: Dictionary = {}
var rooms: Dictionary = {}
var status_effects: Dictionary = {}
var hitboxes: Dictionary = {}
var relics: Dictionary = {}
var upgrades: Dictionary = {}
var events: Dictionary = {}
var shop: Dictionary = {}
var regions: Dictionary = {}
var bosses: Dictionary = {}
var village: Dictionary = {}
var pacts: Dictionary = {}       # 서약(열기) 모듈
var elites: Dictionary = {}      # 정예 접두
var load_errors: PackedStringArray = []


func _ready() -> void:
	reload()


func reload() -> void:
	load_errors.clear()
	classes = _load_json("classes.json")
	enemies = _load_json("enemies.json")
	party_scaling = _load_json("party_scaling.json")
	rules = _load_json("rules.json")
	rooms = _load_json("rooms.json")
	status_effects = _load_json("status_effects.json")
	hitboxes = _load_json("hitboxes.json")
	relics = _load_json("relics.json")
	upgrades = _load_json("upgrades.json")
	events = _load_json("events.json")
	shop = _load_json("shop.json")
	regions = _load_json("regions.json")
	bosses = _load_json("bosses.json") if FileAccess.file_exists(DATA_DIR + "bosses.json") else {}
	village = _load_json("village.json")
	pacts = _load_json("pacts.json") if FileAccess.file_exists(DATA_DIR + "pacts.json") else {}
	elites = _load_json("elites.json") if FileAccess.file_exists(DATA_DIR + "elites.json") else {}
	mastery = _load_json("mastery.json") if FileAccess.file_exists(DATA_DIR + "mastery.json") else {}
	npcs = _load_json("npcs.json") if FileAccess.file_exists(DATA_DIR + "npcs.json") else {}
	quests = _load_json("quests.json") if FileAccess.file_exists(DATA_DIR + "quests.json") else {}
	equipment = _load_json("equipment.json") if FileAccess.file_exists(DATA_DIR + "equipment.json") else {}
	gear_affixes = _load_json("affixes.json") if FileAccess.file_exists(DATA_DIR + "affixes.json") else {}
	for d: Dictionary in [relics, upgrades, events, shop, regions, bosses, village, mastery, npcs, quests, equipment, gear_affixes]:
		d.erase("_comment")
	_validate()


func _load_json(file: String) -> Dictionary:
	var path := DATA_DIR + file
	if not FileAccess.file_exists(path):
		load_errors.append("missing " + path)
		return {}
	var text := FileAccess.get_file_as_string(path)
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		load_errors.append("%s: parse error line %d: %s" % [file, json.get_error_line(), json.get_error_message()])
		return {}
	if typeof(json.data) != TYPE_DICTIONARY:
		load_errors.append(file + ": root must be an object")
		return {}
	return json.data


func _validate() -> void:
	for cid: String in classes.keys():
		var c: Dictionary = classes[cid]
		if c.get("id", "") != cid:
			load_errors.append("classes.json: id mismatch for " + cid)
	for eid: String in enemies.keys():
		var e: Dictionary = enemies[eid]
		if e.get("id", "") != eid:
			load_errors.append("enemies.json: id mismatch for " + eid)
	for n in range(1, Protocol.MAX_PARTY_SIZE + 1):
		if not party_scaling.get("profiles", {}).has(str(n)):
			load_errors.append("party_scaling.json: missing profile for %d players" % n)
	if not load_errors.is_empty():
		for e in load_errors:
			push_error("[ContentDB] " + e)


func get_class_def(class_id: String) -> Dictionary:
	return classes.get(class_id, {})


func is_class_playable(class_id: String) -> bool:
	var c := get_class_def(class_id)
	return not c.is_empty() and bool(c.get("implemented", false))


func get_enemy_def(enemy_id: String) -> Dictionary:
	return enemies.get(enemy_id, {})


## 인원별 프로필 (8절 PartyScalingProfile). N은 1~4로 고정된다.
func get_party_profile(n: int) -> Dictionary:
	var k := str(clampi(n, 1, Protocol.MAX_PARTY_SIZE))
	return party_scaling.get("profiles", {}).get(k, {})


func rule(key: String, default: Variant = null) -> Variant:
	return rules.get(key, default)


func get_room_def(room_id: String) -> Dictionary:
	return rooms.get(room_id, {})


## 마을 시설 단계에 따른 영구 보너스 합계 (상한 적용). world["hub"]["structures"] 를 받는다.
func village_bonus(structures: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var caps: Dictionary = village.get("permanent_caps", {})
	for sid: String in village.get("structures", {}).keys():
		var sdef: Dictionary = village["structures"][sid]
		var level := int(structures.get(sid, {}).get("level", 0))
		var best: Dictionary = {}
		for lk: String in sdef.get("levels", {}).keys():
			if int(lk) <= level:
				for bk: String in sdef["levels"][lk].get("bonus", {}).keys():
					best[bk] = maxf(float(best.get(bk, 0.0)), float(sdef["levels"][lk]["bonus"][bk]))
		for bk: String in best.keys():
			out[bk] = float(out.get(bk, 0.0)) + float(best[bk])
	for bk: String in caps.keys():
		if out.has(bk):
			out[bk] = minf(float(out[bk]), float(caps[bk]))
	return out


## 스냅샷용 적 종류 인덱스 (문자열 대신 정수로 보내 패킷을 줄인다). 양쪽이 같은 정렬 순서를 쓴다.
var _enemy_ids: Array = []
func enemy_ids() -> Array:
	if _enemy_ids.is_empty():
		_enemy_ids = enemies.keys().filter(func(k: String) -> bool: return not k.begins_with("_"))
		_enemy_ids.sort()
	return _enemy_ids


func enemy_index(type_id: String) -> int:
	return enemy_ids().find(type_id)


func enemy_id_at(index: int) -> String:
	var ids := enemy_ids()
	return String(ids[index]) if index >= 0 and index < ids.size() else ""


## 숙련 경험치 → 단계 (1~10). mastery.json level_xp 는 누적 임계값.
func mastery_level(xp: int) -> int:
	var table: Array = mastery.get("level_xp", [0, 100])
	var lv := 1
	for i in table.size():
		if xp >= int(table[i]):
			lv = i + 1
	return lv


func mastery_trait(class_id: String, trait_id: String) -> Dictionary:
	for t: Dictionary in mastery.get("traits", {}).get(class_id, []):
		if String(t.get("id", "")) == trait_id:
			return t
	return {}


## 서약 목록(id 순). _ 로 시작하는 키는 제외.
func pact_ids() -> Array:
	var out: Array = []
	for k: String in pacts.keys():
		if not k.begins_with("_"):
			out.append(k)
	out.sort()
	return out


## 서약 선택 {id: rank} 을 검증해 정리하고 열기 합계를 돌려준다. 모르는 id·범위 밖 rank 는 버린다.
func normalize_pacts(sel: Dictionary) -> Dictionary:
	var out := {}
	var heat := 0
	for k in sel.keys():
		var id := String(k)
		var d: Dictionary = pacts.get(id, {})
		if d.is_empty() or id.begins_with("_"):
			continue
		var rank := clampi(int(sel[k]), 0, int(d.get("max_rank", 1)))
		if rank <= 0:
			continue
		out[id] = rank
		heat += rank * int(d.get("heat_per_rank", 1))
	return {"pacts": out, "heat": mini(heat, int(pacts.get("_rewards", {}).get("max_heat", 12)))}


## 정예 접두 id 목록
func affix_ids() -> Array:
	var out: Array = elites.get("affixes", {}).keys()
	out.sort()
	return out

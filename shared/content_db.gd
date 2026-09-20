extends Node
## data/*.json 을 읽어 서버·클라이언트가 같은 콘텐츠 수치를 사용하게 한다.
## 숫자는 코드에 흩어놓지 않고 이 데이터 파일에서 조절한다 (7절).

const DATA_DIR := "res://data/"

var classes: Dictionary = {}
var mastery: Dictionary = {}
var npcs: Dictionary = {}
var quests: Dictionary = {}
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
	mastery = _load_json("mastery.json") if FileAccess.file_exists(DATA_DIR + "mastery.json") else {}
	npcs = _load_json("npcs.json") if FileAccess.file_exists(DATA_DIR + "npcs.json") else {}
	quests = _load_json("quests.json") if FileAccess.file_exists(DATA_DIR + "quests.json") else {}
	for d: Dictionary in [relics, upgrades, events, shop, regions, bosses, village, mastery, npcs, quests]:
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

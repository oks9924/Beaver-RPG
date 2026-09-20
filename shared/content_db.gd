extends Node
## data/*.json 을 읽어 서버·클라이언트가 같은 콘텐츠 수치를 사용하게 한다.
## 숫자는 코드에 흩어놓지 않고 이 데이터 파일에서 조절한다 (7절).

const DATA_DIR := "res://data/"

var classes: Dictionary = {}
var enemies: Dictionary = {}
var party_scaling: Dictionary = {}
var rules: Dictionary = {}
var rooms: Dictionary = {}
var status_effects: Dictionary = {}
var hitboxes: Dictionary = {}
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

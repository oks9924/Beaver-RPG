class_name ClientSettings
extends RefCounted
## 클라이언트 로컬 설정. 그래픽·조작·서버 목록·비권위 캐시만 저장한다. 게임 진행도는 서버가 소유한다.

const PATH := "user://client_settings.json"

var data: Dictionary = {
	"servers": [{"name": "로컬 테스트", "address": "127.0.0.1", "port": 7777}],
	"recent": [],
	"last_nick": "",
	"remember_token": true,
	"tokens": {},          # "host:port" -> {account_id, token, nick}
	"ally_vfx_alpha": 0.7,
	"ui_scale": 1.0,
	"screen_shake": 1.0,
	"volume_bgm": 0.8,
	"volume_sfx": 0.8,
	"volume_ambient": 0.6,
	"fullscreen": false,
	"show_dev_overlay": false,
	"flash_reduce": false,
	"auto_attack": true,   # 가만히 서 있고 적이 가까우면 마우스 방향으로 계속 기본 공격
	"keybinds": {},        # action -> physical keycode (재설정한 키만)
	"last_class": "guardian",
	"last_difficulty": "normal",
}


func load() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(PATH)) == OK and typeof(json.data) == TYPE_DICTIONARY:
		for k: String in json.data.keys():
			data[k] = json.data[k]


func save() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "  "))
		f.close()


func add_recent(address: String, port: int) -> void:
	var key := "%s:%d" % [address, port]
	var recent: Array = data["recent"]
	recent.erase(key)
	recent.push_front(key)
	while recent.size() > 5:
		recent.pop_back()
	var found := false
	for s: Dictionary in data["servers"]:
		if s["address"] == address and int(s["port"]) == port:
			found = true
	if not found:
		data["servers"].append({"name": key, "address": address, "port": port})
	save()


func token_for(address: String, port: int) -> Dictionary:
	return data["tokens"].get("%s:%d" % [address, port], {})


func store_token(address: String, port: int, account_id: String, token: String, nick: String) -> void:
	if not bool(data.get("remember_token", true)):
		return
	data["tokens"]["%s:%d" % [address, port]] = {"account_id": account_id, "token": token, "nick": nick}
	save()


func clear_token(address: String, port: int) -> void:
	data["tokens"].erase("%s:%d" % [address, port])
	save()

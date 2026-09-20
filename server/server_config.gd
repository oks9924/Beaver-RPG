class_name ServerConfig
extends RefCounted
## 전용 서버 설정. 비밀 값은 넣지 않는다. 파일이 없으면 예제 값으로 생성한다 (15절 운영 항목).

const DEFAULTS := {
	"bind_address": "*",
	"port": 7777,
	"world_id": "",
	"world_name": "버들둑 마을",
	"max_online_players": 8,
	"max_active_expeditions": 2,
	"max_party_size": 4,
	"allow_registration": true,
	"reconnect_reserved_slots": 1,
	"data_dir": "",
	"log_level": "info",
	"metrics_interval_sec": 30,
	"hello_timeout_sec": 10,
	"maintenance": false,
	"login_fail_lockout_sec": 30,
	"login_fail_max": 5,
	"password_iterations": 60000,
	"token_ttl_days": 7,
}

var values: Dictionary = DEFAULTS.duplicate(true)
var path: String = ""
var loaded_from_file: bool = false


static func default_config_path() -> String:
	if OS.has_feature("editor"):
		return "user://server_config.json"
	return OS.get_executable_path().get_base_dir().path_join("server_config.json")


static func default_data_dir() -> String:
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("user://server_data")
	return OS.get_executable_path().get_base_dir().path_join("server_data")


func load(config_path: String, overrides: Dictionary) -> void:
	path = config_path
	if FileAccess.file_exists(path):
		var json := JSON.new()
		if json.parse(FileAccess.get_file_as_string(path)) == OK and typeof(json.data) == TYPE_DICTIONARY:
			for k: String in json.data.keys():
				values[k] = json.data[k]
			loaded_from_file = true
		else:
			push_error("[ServerConfig] invalid json in %s, using defaults" % path)
	else:
		save()
	for k: String in overrides.keys():
		match k:
			"port": values["port"] = int(overrides[k])
			"data-dir": values["data_dir"] = String(overrides[k])
			"max-online": values["max_online_players"] = int(overrides[k])
			"max-expeditions": values["max_active_expeditions"] = int(overrides[k])
			"log-level": values["log_level"] = String(overrides[k])
			"world-id": values["world_id"] = String(overrides[k])
	values["max_party_size"] = Protocol.MAX_PARTY_SIZE  # 고정
	if String(values["data_dir"]) == "":
		values["data_dir"] = default_data_dir()


func save() -> void:
	var dir := path.get_base_dir()
	if dir.begins_with("user://"):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	else:
		DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(values, "  "))
		f.close()


func get_value(key: String) -> Variant:
	return values.get(key, DEFAULTS.get(key))

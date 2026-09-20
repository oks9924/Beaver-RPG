class_name JsonFileStore
extends StoreBase
## JSON 파일 기반 저장소. 단일 서버 프로세스가 메모리 상태를 소유하고, 변경 시 임시 파일에 쓴 뒤 rename 으로 교체한다.
## 여러 클라이언트가 파일 하나를 덮어쓰는 구조가 아니다. 계정은 accounts.json, 월드는 world.json, 이전본은 *.bak.

var data_dir: String
var accounts: Dictionary = {}       # id -> account
var _nick_index: Dictionary = {}    # nickname_lower -> id
var _world: Dictionary = {}
var _dirty_accounts: bool = false
var _dirty_world: bool = false
var _expeditions: Dictionary = {}
var _dirty_expeditions: bool = false
var write_failures: int = 0


func _init(dir: String) -> void:
	data_dir = dir


func describe() -> String:
	return "JsonFileStore(%s)" % data_dir


func open() -> Error:
	var err := DirAccess.make_dir_recursive_absolute(data_dir)
	if err != OK and err != ERR_ALREADY_EXISTS:
		return err
	var acc := _read_json(data_dir.path_join("accounts.json"))
	if acc.is_empty():
		var bak := _read_json(data_dir.path_join("accounts.json.bak"))
		if not bak.is_empty():
			push_warning("[Store] accounts.json unreadable, recovered from .bak")
			acc = bak
	accounts = acc.get("accounts", {})
	_nick_index.clear()
	for id: String in accounts.keys():
		_nick_index[String(accounts[id].get("nickname_lower", ""))] = id
	var w := _read_json(data_dir.path_join("world.json"))
	if w.is_empty():
		var wb := _read_json(data_dir.path_join("world.json.bak"))
		if not wb.is_empty():
			push_warning("[Store] world.json unreadable, recovered from .bak")
			w = wb
	_world = w
	_expeditions = _read_json(data_dir.path_join("expeditions.json")).get("expeditions", {})
	return OK


func load_expeditions() -> Dictionary:
	return _expeditions.duplicate(true)


func save_expedition(checkpoint: Dictionary) -> Error:
	_expeditions[String(checkpoint["id"])] = checkpoint.duplicate(true)
	_dirty_expeditions = true
	return flush()


func delete_expedition(id: String) -> Error:
	if _expeditions.erase(id):
		_dirty_expeditions = true
		return flush()
	return OK


func close() -> void:
	flush()


func load_world() -> Dictionary:
	return _world.duplicate(true)


func save_world(world: Dictionary) -> Error:
	_world = world.duplicate(true)
	_dirty_world = true
	return flush()


func get_account(account_id: String) -> Dictionary:
	return accounts.get(account_id, {}).duplicate(true)


func find_account_by_nickname(nickname_lower: String) -> Dictionary:
	var id: String = _nick_index.get(nickname_lower, "")
	if id == "":
		return {}
	return get_account(id)


func put_account(account: Dictionary) -> Error:
	var id: String = account["id"]
	var nick_lower: String = account.get("nickname_lower", "")
	var existing_id: String = _nick_index.get(nick_lower, "")
	if existing_id != "" and existing_id != id:
		return ERR_ALREADY_EXISTS
	accounts[id] = account.duplicate(true)
	_nick_index[nick_lower] = id
	_dirty_accounts = true
	return flush()


func account_count() -> int:
	return accounts.size()


func all_account_ids() -> Array:
	return accounts.keys()


func flush() -> Error:
	var err := OK
	if _dirty_accounts:
		err = _write_atomic(data_dir.path_join("accounts.json"), {"schema_version": SCHEMA_VERSION, "accounts": accounts})
		if err == OK:
			_dirty_accounts = false
	if _dirty_world:
		var e2 := _write_atomic(data_dir.path_join("world.json"), _world)
		if e2 == OK:
			_dirty_world = false
		elif err == OK:
			err = e2
	if _dirty_expeditions:
		var e3 := _write_atomic(data_dir.path_join("expeditions.json"), {"schema_version": SCHEMA_VERSION, "expeditions": _expeditions})
		if e3 == OK:
			_dirty_expeditions = false
		elif err == OK:
			err = e3
	return err


func backup(dest_dir: String) -> Error:
	var err := DirAccess.make_dir_recursive_absolute(dest_dir)
	if err != OK and err != ERR_ALREADY_EXISTS:
		return err
	for f in ["accounts.json", "world.json", "expeditions.json"]:
		var src := data_dir.path_join(f)
		if FileAccess.file_exists(src):
			var e := DirAccess.copy_absolute(src, dest_dir.path_join(f))
			if e != OK:
				return e
	return OK


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		push_error("[Store] parse error in %s: %s" % [path, json.get_error_message()])
		return {}
	if typeof(json.data) != TYPE_DICTIONARY:
		return {}
	return json.data


## tmp 파일에 쓰고 fsync 후 rename. 기존 파일은 .bak 으로 보존한다.
func _write_atomic(path: String, data: Dictionary) -> Error:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		write_failures += 1
		push_error("[Store] cannot open %s: %s" % [tmp, error_string(FileAccess.get_open_error())])
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(data, "", false))
	f.flush()
	f.close()
	if FileAccess.file_exists(path):
		var bak := path + ".bak"
		if FileAccess.file_exists(bak):
			DirAccess.remove_absolute(bak)
		DirAccess.rename_absolute(path, bak)
	var err := DirAccess.rename_absolute(tmp, path)
	if err != OK:
		write_failures += 1
		push_error("[Store] rename failed for %s: %s" % [path, error_string(err)])
	return err

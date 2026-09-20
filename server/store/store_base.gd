class_name StoreBase
extends RefCounted
## 영구 저장 인터페이스. 서버가 계정·월드의 기준 데이터를 소유한다 (15절).
## 단계 1 구현은 JsonFileStore. 운영 규모에 맞춰 SQLite 등으로 교체할 수 있게 인터페이스를 분리한다.

const SCHEMA_VERSION := 1


func open() -> Error:
	return ERR_UNAVAILABLE


func close() -> void:
	pass


func load_world() -> Dictionary:
	return {}


func save_world(_world: Dictionary) -> Error:
	return ERR_UNAVAILABLE


func get_account(_account_id: String) -> Dictionary:
	return {}


func find_account_by_nickname(_nickname_lower: String) -> Dictionary:
	return {}


func put_account(_account: Dictionary) -> Error:
	return ERR_UNAVAILABLE


func account_count() -> int:
	return 0


func all_account_ids() -> Array:
	return []


func flush() -> Error:
	return OK


func backup(_dest_dir: String) -> Error:
	return ERR_UNAVAILABLE


func describe() -> String:
	return "abstract"

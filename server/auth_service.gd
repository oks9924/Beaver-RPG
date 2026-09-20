class_name AuthService
extends RefCounted
## 서버 내부 계정. 닉네임(표시)과 불변 계정 ID 를 분리한다. 비밀번호는 PBKDF2-HMAC-SHA256(솔트, 반복) 으로만 저장한다.
## 재접속 토큰은 무작위 32바이트이며 서버에는 SHA-256 해시만 둔다. 만료·폐기·재발급 규칙은 아래 상수를 따른다.
## 주의: 단계 1 의 ENet 전송은 DTLS 가 켜져 있지 않다. 자격 증명 암호화 채널은 docs/architecture.md 의 남은 작업으로 명시한다.

const ALGO := "pbkdf2-hmac-sha256"
const NICK_MIN := 2
const NICK_MAX := 16
const PASSWORD_MIN := 6
const PASSWORD_MAX := 128
const MAX_TOKENS := 5

var store: StoreBase
var iterations: int = 60000
var token_ttl_sec: int = 7 * 86400
var lockout_sec: float = 30.0
var fail_max: int = 5
var _fail_by_nick: Dictionary = {}   # nick_lower -> {count, until}
var _crypto := Crypto.new()


func _init(s: StoreBase, iters: int, ttl_days: int) -> void:
	store = s
	iterations = iters
	token_ttl_sec = ttl_days * 86400


static func is_valid_nickname(nick: String) -> bool:
	if nick.length() < NICK_MIN or nick.length() > NICK_MAX:
		return false
	var re := RegEx.new()
	re.compile("^[\\p{L}\\p{N}_]+$")
	return re.search(nick) != null


func register(nick: String, password: String) -> Dictionary:
	nick = nick.strip_edges()
	if not is_valid_nickname(nick):
		return {"ok": false, "error": Protocol.ERR_INVALID_NICK}
	if password.length() < PASSWORD_MIN or password.length() > PASSWORD_MAX:
		return {"ok": false, "error": Protocol.ERR_INVALID_PASSWORD}
	var lower := nick.to_lower()
	if not store.find_account_by_nickname(lower).is_empty():
		return {"ok": false, "error": Protocol.ERR_NICK_TAKEN}
	var salt := _crypto.generate_random_bytes(16)
	var hash := pbkdf2_sha256(password.to_utf8_buffer(), salt, iterations, 32)
	var now := int(Time.get_unix_time_from_system())
	var account := {
		"schema_version": StoreBase.SCHEMA_VERSION,
		"id": _crypto.generate_random_bytes(16).hex_encode(),
		"nickname": nick,
		"nickname_lower": lower,
		"created_at": now,
		"last_login_at": now,
		"auth": {"algo": ALGO, "salt": salt.hex_encode(), "hash": hash.hex_encode(), "iterations": iterations},
		"tokens": [],
		"stats": {"logins": 0, "expeditions_started": 0, "rooms_cleared": 0, "wipes": 0, "kills": 0, "downs": 0, "deaths": 0, "rescues": 0, "damage_dealt": 0},
		"progression": {"memory_shards": 0, "class_mastery": {}, "village_repair": 0, "unlocked_classes": ["guardian"], "story_flags": []},
	}
	var err := store.put_account(account)
	if err != OK:
		return {"ok": false, "error": Protocol.ERR_SAVE_FAILED if err != ERR_ALREADY_EXISTS else Protocol.ERR_NICK_TAKEN}
	return {"ok": true, "account": account}


func login(nick: String, password: String) -> Dictionary:
	var lower := nick.strip_edges().to_lower()
	var now := Time.get_unix_time_from_system()
	var fail: Dictionary = _fail_by_nick.get(lower, {})
	if not fail.is_empty() and float(fail.get("until", 0)) > now:
		return {"ok": false, "error": Protocol.ERR_RATE_LIMITED}
	var account := store.find_account_by_nickname(lower)
	var ok := false
	if not account.is_empty():
		var auth: Dictionary = account.get("auth", {})
		var salt := PackedByteArray()
		salt = _hex_decode(String(auth.get("salt", "")))
		var expected := _hex_decode(String(auth.get("hash", "")))
		var got := pbkdf2_sha256(password.to_utf8_buffer(), salt, int(auth.get("iterations", iterations)), expected.size())
		ok = constant_time_equal(got, expected)
	else:
		# 존재하지 않는 닉네임도 같은 비용을 치르게 해 타이밍으로 계정 유무를 알 수 없게 한다.
		pbkdf2_sha256(password.to_utf8_buffer(), PackedByteArray([1, 2, 3, 4]), iterations, 32)
	if not ok:
		var count := int(fail.get("count", 0)) + 1
		var until := 0.0
		if count >= fail_max:
			until = now + lockout_sec
			count = 0
		_fail_by_nick[lower] = {"count": count, "until": until}
		return {"ok": false, "error": Protocol.ERR_BAD_CREDENTIALS}
	_fail_by_nick.erase(lower)
	account["last_login_at"] = int(now)
	account["stats"]["logins"] = int(account["stats"].get("logins", 0)) + 1
	var token := issue_token(account)
	if store.put_account(account) != OK:
		return {"ok": false, "error": Protocol.ERR_SAVE_FAILED}
	return {"ok": true, "account": account, "token": token}


func login_with_token(account_id: String, token: String) -> Dictionary:
	var account := store.get_account(account_id)
	if account.is_empty():
		return {"ok": false, "error": Protocol.ERR_BAD_CREDENTIALS}
	var now := int(Time.get_unix_time_from_system())
	var th := sha256_hex(token.to_utf8_buffer())
	var found := false
	var kept: Array = []
	for t: Dictionary in account.get("tokens", []):
		if int(t.get("expires_at", 0)) <= now:
			continue
		if constant_time_equal(String(t.get("hash", "")).to_utf8_buffer(), th.to_utf8_buffer()):
			found = true
			continue  # 사용한 토큰은 폐기하고 새 토큰을 발급한다.
		kept.append(t)
	if not found:
		return {"ok": false, "error": Protocol.ERR_TOKEN_EXPIRED}
	account["tokens"] = kept
	account["last_login_at"] = now
	var new_token := issue_token(account)
	if store.put_account(account) != OK:
		return {"ok": false, "error": Protocol.ERR_SAVE_FAILED}
	return {"ok": true, "account": account, "token": new_token}


func revoke_all_tokens(account_id: String) -> void:
	var account := store.get_account(account_id)
	if account.is_empty():
		return
	account["tokens"] = []
	store.put_account(account)


func issue_token(account: Dictionary) -> String:
	var raw := _crypto.generate_random_bytes(32).hex_encode()
	var now := int(Time.get_unix_time_from_system())
	var tokens: Array = account.get("tokens", [])
	var kept: Array = []
	for t: Dictionary in tokens:
		if int(t.get("expires_at", 0)) > now:
			kept.append(t)
	kept.append({"hash": sha256_hex(raw.to_utf8_buffer()), "expires_at": now + token_ttl_sec, "issued_at": now})
	while kept.size() > MAX_TOKENS:
		kept.pop_front()
	account["tokens"] = kept
	return raw


static func sha256_hex(data: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(data)
	return ctx.finish().hex_encode()


## PBKDF2 (RFC 8018) with HMAC-SHA256. Godot 의 검증된 HMAC 구현 위에서 표준 반복만 수행한다.
static func pbkdf2_sha256(password: PackedByteArray, salt: PackedByteArray, iters: int, dk_len: int) -> PackedByteArray:
	var out := PackedByteArray()
	var block_index := 1
	while out.size() < dk_len:
		var u := salt.duplicate()
		u.append_array(PackedByteArray([(block_index >> 24) & 0xFF, (block_index >> 16) & 0xFF, (block_index >> 8) & 0xFF, block_index & 0xFF]))
		var h := HMACContext.new()
		h.start(HashingContext.HASH_SHA256, password)
		h.update(u)
		var t := h.finish()
		var prev := t.duplicate()
		for i in range(1, iters):
			var hh := HMACContext.new()
			hh.start(HashingContext.HASH_SHA256, password)
			hh.update(prev)
			prev = hh.finish()
			for j in t.size():
				t[j] = t[j] ^ prev[j]
		out.append_array(t)
		block_index += 1
	return out.slice(0, dk_len)


static func constant_time_equal(a: PackedByteArray, b: PackedByteArray) -> bool:
	if a.size() != b.size():
		return false
	var diff := 0
	for i in a.size():
		diff |= a[i] ^ b[i]
	return diff == 0


static func _hex_decode(hex: String) -> PackedByteArray:
	return hex.hex_decode()

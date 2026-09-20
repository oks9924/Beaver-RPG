class_name NetClient
extends Node
## 클라이언트 네트워크. 연결 상태 DISCONNECTED→CONNECTING→AUTHENTICATING→SYNCING→ONLINE 을 관리한다.

signal state_changed(state: int)
signal hello_result(payload: Dictionary)
signal auth_result(payload: Dictionary)
signal message(type: int, payload: Dictionary)
signal snapshot(payload: Dictionary)
signal disconnected(reason: String)

var state: int = Protocol.ConnState.DISCONNECTED
var peer: ENetMultiplayerPeer
var host: String = ""
var port: int = 0
var server_info: Dictionary = {}
var account: Dictionary = {}
var token: String = ""
var ping_ms: int = 0
var server_tick_ms: float = 0.0
var last_error: String = ""
var last_error_payload: Dictionary = {}
var _ping_sent_at: int = 0
var _ping_accum: float = 0.0
var bytes_in_rate: float = 0.0
var _connect_timeout: float = 0.0
var pending_disconnect_reason: String = ""
var hello_override: Dictionary = {}   # 테스트 전용: 버전 불일치 시나리오


func _ready() -> void:
	Net.server_message.connect(_on_server_message)
	Net.server_snapshot.connect(_on_snapshot)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _set_state(s: int) -> void:
	if state == s:
		return
	state = s
	state_changed.emit(s)


func connect_to(h: String, p: int) -> void:
	disconnect_from_server("")
	host = h
	port = p
	last_error = ""
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_client(host, port)
	if err != OK:
		last_error = "CONNECT_FAILED"
		disconnected.emit(last_error)
		return
	multiplayer.multiplayer_peer = peer
	_connect_timeout = 6.0
	_set_state(Protocol.ConnState.CONNECTING)


func disconnect_from_server(reason: String = "user") -> void:
	if peer != null:
		peer.close()
		peer = null
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	account = {}
	server_info = {}
	if state != Protocol.ConnState.DISCONNECTED:
		_set_state(Protocol.ConnState.DISCONNECTED)
		if reason != "":
			disconnected.emit(reason)


func is_online() -> bool:
	return state == Protocol.ConnState.ONLINE


func send(type: int, payload: Dictionary = {}) -> void:
	if state == Protocol.ConnState.DISCONNECTED:
		return
	Net.send_to_server(type, payload)


func send_input(seq: int, mv: Vector2, aim: Vector2, buttons: int) -> void:
	if state != Protocol.ConnState.ONLINE:
		return
	Net.send_input(seq, mv, aim, buttons)


func _on_connected() -> void:
	_set_state(Protocol.ConnState.AUTHENTICATING)
	var hello := Protocol.version_info()
	hello.merge(hello_override, true)
	Net.send_to_server(Protocol.C.HELLO, hello)


func _on_connection_failed() -> void:
	last_error = "CONNECT_FAILED"
	disconnect_from_server("")
	disconnected.emit(last_error)


func _on_server_disconnected() -> void:
	var reason := pending_disconnect_reason if pending_disconnect_reason != "" else "SERVER_CLOSED"
	pending_disconnect_reason = ""
	disconnect_from_server("")
	disconnected.emit(reason)


func _on_server_message(type: int, payload: Dictionary) -> void:
	match type:
		Protocol.S.HELLO_RESULT:
			if bool(payload.get("ok", false)):
				server_info = payload.get("server", {})
			else:
				last_error = String(payload.get("error", "HELLO_FAILED"))
				last_error_payload = payload
				pending_disconnect_reason = last_error
			hello_result.emit(payload)
		Protocol.S.AUTH_RESULT:
			if bool(payload.get("ok", false)):
				account = payload.get("account", {})
				token = String(payload.get("token", ""))
				server_info = payload.get("server", server_info)
				_set_state(Protocol.ConnState.SYNCING)
			else:
				last_error = String(payload.get("error", "AUTH_FAILED"))
				last_error_payload = payload
			auth_result.emit(payload)
		Protocol.S.ENTER_HUB, Protocol.S.ENTER_EXPEDITION:
			_set_state(Protocol.ConnState.ONLINE)
			message.emit(type, payload)
		Protocol.S.KICKED:
			last_error = String(payload.get("error", "KICKED"))
			pending_disconnect_reason = last_error
			message.emit(type, payload)
		Protocol.S.PONG:
			ping_ms = int(Time.get_ticks_msec() - int(payload.get("t", 0)))
			server_tick_ms = float(payload.get("tick_ms", 0.0))
			message.emit(type, payload)
		Protocol.S.ACCOUNT_UPDATE:
			account = payload.get("account", account)
			message.emit(type, payload)
		_:
			message.emit(type, payload)


func _on_snapshot(payload: Dictionary) -> void:
	snapshot.emit(payload)


func _process(dt: float) -> void:
	if state == Protocol.ConnState.CONNECTING:
		_connect_timeout -= dt
		if _connect_timeout <= 0.0:
			last_error = "CONNECT_TIMEOUT"
			disconnect_from_server("")
			disconnected.emit(last_error)
			return
	if state >= Protocol.ConnState.AUTHENTICATING:
		_ping_accum += dt
		if _ping_accum >= 1.0:
			_ping_accum = 0.0
			Net.send_to_server(Protocol.C.PING, {"t": Time.get_ticks_msec()})

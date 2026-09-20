class_name Session
extends RefCounted
## 접속 세션. peer ID 는 임시이며 계정 ID 와 분리한다. 세션이 끊겨도 계정·원정 슬롯은 유예 시간 동안 남는다.

enum State { CONNECTED, HELLO_OK, AUTHED }

var peer_id: int
var state: int = State.CONNECTED
var connected_at: float
var account_id: String = ""
var nickname: String = ""
var location: int = Protocol.Location.NONE
var expedition_id: String = ""
var class_id: String = "guardian"
var login_attempts: int = 0
var last_input_seq: int = 0
var client_build: String = ""
var last_ping_ms: int = 0
var msg_count_window: int = 0
var msg_window_start: float = 0.0
var hub_pos: Vector2 = Vector2.ZERO
var hub_facing: Vector2 = Vector2(0, 1)
var hub_move: Vector2 = Vector2.ZERO


func _init(pid: int) -> void:
	peer_id = pid
	connected_at = Time.get_unix_time_from_system()


func is_authed() -> bool:
	return state == State.AUTHED and account_id != ""

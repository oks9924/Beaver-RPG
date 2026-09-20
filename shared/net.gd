extends Node
## 서버와 클라이언트가 같은 NodePath(/root/Net)에 갖는 RPC 창구.
## 실제 처리 로직은 신호를 통해 ServerMain / ClientMain 이 담당한다.
## - c_*: 클라이언트 → 서버 (any_peer). 서버는 반드시 세션·권한을 검증한다.
## - s_*: 서버 → 클라이언트 (authority). 클라이언트가 호출하면 권한 오류로 거부된다.

signal client_message(peer_id: int, type: int, payload: Dictionary)
signal client_input(peer_id: int, seq: int, mx: float, my: float, ax: float, ay: float, buttons: int)
signal server_message(type: int, payload: Dictionary)
signal server_snapshot(payload: Dictionary)


@rpc("any_peer", "call_remote", "reliable")
func c_msg(type: int, payload: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	client_message.emit(multiplayer.get_remote_sender_id(), type, payload)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func c_input(seq: int, mx: float, my: float, ax: float, ay: float, buttons: int) -> void:
	if not multiplayer.is_server():
		return
	client_input.emit(multiplayer.get_remote_sender_id(), seq, mx, my, ax, ay, buttons)


@rpc("authority", "call_remote", "reliable")
func s_msg(type: int, payload: Dictionary) -> void:
	server_message.emit(type, payload)


@rpc("authority", "call_remote", "unreliable_ordered")
func s_snapshot(bytes: PackedByteArray) -> void:
	server_snapshot.emit(SnapshotCodec.decode(bytes))


# --- 편의 함수 ---

func send_to_server(type: int, payload: Dictionary = {}) -> void:
	c_msg.rpc_id(1, type, payload)


func send_input(seq: int, mv: Vector2, aim: Vector2, buttons: int) -> void:
	c_input.rpc_id(1, seq, mv.x, mv.y, aim.x, aim.y, buttons)


func peer_ready(peer_id: int) -> bool:
	if not multiplayer.get_peers().has(peer_id):
		return false
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet != null:
		var pp := enet.get_peer(peer_id)
		if pp == null or pp.get_state() != ENetPacketPeer.STATE_CONNECTED:
			return false
	return true


func send_to_peer(peer_id: int, type: int, payload: Dictionary = {}) -> void:
	if not peer_ready(peer_id):
		return  # 끊겼거나 끊는 중인 peer
	s_msg.rpc_id(peer_id, type, payload)


func send_snapshot(peer_id: int, payload: Dictionary) -> void:
	send_snapshot_bytes(peer_id, SnapshotCodec.encode(payload))


func send_snapshot_bytes(peer_id: int, bytes: PackedByteArray) -> void:
	if not peer_ready(peer_id):
		return
	s_snapshot.rpc_id(peer_id, bytes)

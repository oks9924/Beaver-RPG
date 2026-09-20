class_name SnapshotCodec
extends RefCounted
## 스냅샷 바이너리 인코딩. 방 스냅샷은 고정 폭 정수(위치 0.25px, 시간 0.05s)로 줄여 4인 방도 ENet MTU(1392B) 안에 들어가게 한다.
## decode() 는 encode() 전과 같은 모양의 Dictionary 를 돌려주므로 클라이언트·봇·테스트는 그대로 쓴다.
## 방 스냅샷이 아닌 것(허브 등)과 코덱이 모르는 키는 var_to_bytes 로 그대로 싣는다.

const KIND_GENERIC := 0
const KIND_ROOM := 1
const POS_SCALE := 4.0      # 0.25 px
const TIME_SCALE := 20.0    # 0.05 s
const VAL_SCALE := 4.0      # hp / shield / resource 0.25 단위
const KNOWN_KEYS := ["t", "wave", "p", "e", "tg", "pr", "ob", "wood", "obj", "wz", "hz", "boss", "ack"]
const PLAYER_FIELDS := 21
const ENEMY_FIELDS := 8


static func encode(snap: Dictionary) -> PackedByteArray:
	var sp := StreamPeerBuffer.new()
	sp.big_endian = false
	if not (snap.has("p") and snap.has("e") and snap.has("t")):
		sp.put_u8(KIND_GENERIC)
		sp.put_var(snap)
		return sp.data_array
	sp.put_u8(KIND_ROOM)
	sp.put_u32(int(snap.get("t", 0)))
	sp.put_u32(int(snap.get("ack", 0)))
	var wave: Array = snap.get("wave", [0, 0])
	sp.put_u8(clampi(int(wave[0]), 0, 255))
	sp.put_u8(clampi(int(wave[1]), 0, 255))
	sp.put_u16(clampi(int(snap.get("wood", 0)), 0, 65535))
	var obj: Array = snap.get("obj", ["", 0.0, 0])
	_put_str(sp, String(obj[0]))
	sp.put_float(float(obj[1]))
	sp.put_u8(clampi(int(obj[2]), 0, 255))
	# players
	var ps: Array = snap["p"]
	sp.put_u8(ps.size())
	for entry: Array in ps:
		_put_str(sp, String(entry[0]))
		var v: PackedFloat32Array = entry[1]
		_put_pos(sp, v[Protocol.SNAP_P.X]); _put_pos(sp, v[Protocol.SNAP_P.Y])
		_put_dir(sp, v[Protocol.SNAP_P.FX]); _put_dir(sp, v[Protocol.SNAP_P.FY])
		_put_val(sp, v[Protocol.SNAP_P.HP])
		sp.put_u8(int(v[Protocol.SNAP_P.STATE])); sp.put_u8(int(v[Protocol.SNAP_P.ACTION])); sp.put_u8(int(v[Protocol.SNAP_P.DODGE]))
		_put_val(sp, v[Protocol.SNAP_P.SHIELD])
		_put_time(sp, v[Protocol.SNAP_P.DOWN_T])
		_put_time(sp, v[Protocol.SNAP_P.CD_Q]); _put_time(sp, v[Protocol.SNAP_P.CD_E]); _put_time(sp, v[Protocol.SNAP_P.CD_R])
		var bits := (1 if v[Protocol.SNAP_P.INVULN] > 0.5 else 0) | (2 if v[Protocol.SNAP_P.CONNECTED] > 0.5 else 0) | (4 if v[Protocol.SNAP_P.FRONT_GUARD] > 0.5 else 0)
		sp.put_u8(bits)
		_put_time(sp, v[Protocol.SNAP_P.RESCUE_T])
		sp.put_u8(clampi(int(v[Protocol.SNAP_P.HEAL]), 0, 255))
		sp.put_u8(int(v[Protocol.SNAP_P.ACTION_KIND]))
		_put_val(sp, v[Protocol.SNAP_P.RESOURCE])
		sp.put_u8(int(v[Protocol.SNAP_P.STATUS]) & 0xFF)
	# enemies
	var es: Array = snap["e"]
	sp.put_u8(mini(es.size(), 255))
	for i in mini(es.size(), 255):
		var entry: Array = es[i]
		sp.put_u16(int(entry[0]) & 0xFFFF)
		sp.put_u8(int(entry[1]) & 0xFF)
		var v: PackedFloat32Array = entry[2]
		_put_pos(sp, v[Protocol.SNAP_E.X]); _put_pos(sp, v[Protocol.SNAP_E.Y])
		_put_dir(sp, v[Protocol.SNAP_E.FX]); _put_dir(sp, v[Protocol.SNAP_E.FY])
		_put_val(sp, v[Protocol.SNAP_E.HP]); _put_val(sp, v[Protocol.SNAP_E.MAX_HP])
		sp.put_u8(int(v[Protocol.SNAP_E.AI]) & 0xFF)
		sp.put_u8(int(v[Protocol.SNAP_E.STATUS]) & 0xFF)
	# telegraphs [type, x, y, len|r, t, total, dx, dy, w]
	var tgs: Array = snap.get("tg", [])
	sp.put_u8(mini(tgs.size(), 255))
	for i in mini(tgs.size(), 255):
		var t: PackedFloat32Array = tgs[i]
		sp.put_u8(int(t[0]))
		_put_pos(sp, t[1]); _put_pos(sp, t[2]); _put_pos(sp, t[3])
		_put_time(sp, t[4]); _put_time(sp, t[5])
		_put_dir(sp, t[6]); _put_dir(sp, t[7])
		_put_pos(sp, t[8])
	# projectiles [x, y, vx, vy, r, kind]
	var prs: Array = snap.get("pr", [])
	sp.put_u8(mini(prs.size(), 255))
	for i in mini(prs.size(), 255):
		var r: PackedFloat32Array = prs[i]
		_put_pos(sp, r[0]); _put_pos(sp, r[1])
		sp.put_16(clampi(roundi(r[2]), -32768, 32767)); sp.put_16(clampi(roundi(r[3]), -32768, 32767))
		sp.put_u8(clampi(roundi(r[4]), 0, 255)); sp.put_u8(int(r[5]) & 0xFF)
	# objects [id, kind, x, y, r, progress, state]
	var obs: Array = snap.get("ob", [])
	sp.put_u8(mini(obs.size(), 255))
	for i in mini(obs.size(), 255):
		var o: PackedFloat32Array = obs[i]
		sp.put_u16(int(o[0]) & 0xFFFF); sp.put_u8(int(o[1]) & 0xFF)
		_put_pos(sp, o[2]); _put_pos(sp, o[3]); _put_pos(sp, o[4])
		sp.put_float(o[5]); sp.put_16(int(o[6]))
	# water zone / hazards (float 유지: 개수가 적다)
	var wz: PackedFloat32Array = snap.get("wz", PackedFloat32Array())
	sp.put_u8(wz.size())
	for f in wz: sp.put_float(f)
	var hz: Array = snap.get("hz", [])
	sp.put_u8(mini(hz.size(), 255))
	for i in mini(hz.size(), 255):
		var h: PackedFloat32Array = hz[i]
		sp.put_u8(h.size())
		for f in h: sp.put_float(f)
	# boss
	var boss: Dictionary = snap.get("boss", {})
	sp.put_u8(0 if boss.is_empty() else 1)
	if not boss.is_empty():
		_put_str(sp, String(boss.get("id", "")))
		_put_pos(sp, float(boss.get("x", 0.0))); _put_pos(sp, float(boss.get("y", 0.0)))
		_put_dir(sp, float(boss.get("fx", 0.0))); _put_dir(sp, float(boss.get("fy", 1.0)))
		sp.put_float(float(boss.get("hp", 0.0))); sp.put_float(float(boss.get("max_hp", 1.0)))
		sp.put_u8(int(boss.get("state", 0)) & 0xFF); sp.put_u8(int(boss.get("phase", 0)) & 0xFF)
		sp.put_u8(int(boss.get("shell_broken", 0)) & 0xFF); sp.put_u8(int(boss.get("shell_total", 0)) & 0xFF)
		sp.put_u8(int(boss.get("f", 0)) & 0xFF)
		_put_str(sp, String(boss.get("grabbed", "")))
		sp.put_float(float(boss.get("stagger_gauge", 0.0)))
		_put_str(sp, String(boss.get("m", "")))
		_put_time(sp, float(boss.get("mt", 0.0)))
		_put_str(sp, String(boss.get("pattern", "")))
	# 모르는 키는 그대로
	var extra := {}
	for k in snap.keys():
		if not k in KNOWN_KEYS:
			extra[k] = snap[k]
	if extra.is_empty():
		sp.put_u8(0)
	else:
		sp.put_u8(1)
		sp.put_var(extra)
	return sp.data_array


static func decode(bytes: PackedByteArray) -> Dictionary:
	if bytes.is_empty():
		return {}
	var sp := StreamPeerBuffer.new()
	sp.big_endian = false
	sp.data_array = bytes
	var kind := sp.get_u8()
	if kind == KIND_GENERIC:
		var v: Variant = sp.get_var()
		return v if v is Dictionary else {}
	var snap := {}
	snap["t"] = sp.get_u32()
	snap["ack"] = sp.get_u32()
	snap["wave"] = [sp.get_u8(), sp.get_u8()]
	snap["wood"] = sp.get_u16()
	var oname := _get_str(sp)
	var oprog := sp.get_float()
	snap["obj"] = [oname, oprog, sp.get_u8()]
	var ps: Array = []
	for i in sp.get_u8():
		var id := _get_str(sp)
		var v := PackedFloat32Array(); v.resize(PLAYER_FIELDS)
		v[Protocol.SNAP_P.X] = _get_pos(sp); v[Protocol.SNAP_P.Y] = _get_pos(sp)
		v[Protocol.SNAP_P.FX] = _get_dir(sp); v[Protocol.SNAP_P.FY] = _get_dir(sp)
		v[Protocol.SNAP_P.HP] = _get_val(sp)
		v[Protocol.SNAP_P.STATE] = sp.get_u8(); v[Protocol.SNAP_P.ACTION] = sp.get_u8(); v[Protocol.SNAP_P.DODGE] = sp.get_u8()
		v[Protocol.SNAP_P.SHIELD] = _get_val(sp)
		v[Protocol.SNAP_P.DOWN_T] = _get_time(sp)
		v[Protocol.SNAP_P.CD_Q] = _get_time(sp); v[Protocol.SNAP_P.CD_E] = _get_time(sp); v[Protocol.SNAP_P.CD_R] = _get_time(sp)
		var bits := sp.get_u8()
		v[Protocol.SNAP_P.INVULN] = 1.0 if bits & 1 else 0.0
		v[Protocol.SNAP_P.CONNECTED] = 1.0 if bits & 2 else 0.0
		v[Protocol.SNAP_P.FRONT_GUARD] = 1.0 if bits & 4 else 0.0
		v[Protocol.SNAP_P.RESCUE_T] = _get_time(sp)
		v[Protocol.SNAP_P.HEAL] = sp.get_u8()
		v[Protocol.SNAP_P.ACTION_KIND] = sp.get_u8()
		v[Protocol.SNAP_P.RESOURCE] = _get_val(sp)
		v[Protocol.SNAP_P.STATUS] = sp.get_u8()
		ps.append([id, v])
	snap["p"] = ps
	var es: Array = []
	for i in sp.get_u8():
		var id := sp.get_u16()
		var idx := sp.get_u8()
		var v := PackedFloat32Array(); v.resize(ENEMY_FIELDS)
		v[Protocol.SNAP_E.X] = _get_pos(sp); v[Protocol.SNAP_E.Y] = _get_pos(sp)
		v[Protocol.SNAP_E.FX] = _get_dir(sp); v[Protocol.SNAP_E.FY] = _get_dir(sp)
		v[Protocol.SNAP_E.HP] = _get_val(sp); v[Protocol.SNAP_E.MAX_HP] = _get_val(sp)
		v[Protocol.SNAP_E.AI] = sp.get_u8(); v[Protocol.SNAP_E.STATUS] = sp.get_u8()
		es.append([id, idx, v])
	snap["e"] = es
	var tgs: Array = []
	for i in sp.get_u8():
		var t := PackedFloat32Array(); t.resize(9)
		t[0] = sp.get_u8()
		t[1] = _get_pos(sp); t[2] = _get_pos(sp); t[3] = _get_pos(sp)
		t[4] = _get_time(sp); t[5] = _get_time(sp)
		t[6] = _get_dir(sp); t[7] = _get_dir(sp)
		t[8] = _get_pos(sp)
		tgs.append(t)
	snap["tg"] = tgs
	var prs: Array = []
	for i in sp.get_u8():
		var r := PackedFloat32Array(); r.resize(6)
		r[0] = _get_pos(sp); r[1] = _get_pos(sp)
		r[2] = sp.get_16(); r[3] = sp.get_16()
		r[4] = sp.get_u8(); r[5] = sp.get_u8()
		prs.append(r)
	snap["pr"] = prs
	var obs: Array = []
	for i in sp.get_u8():
		var o := PackedFloat32Array(); o.resize(7)
		o[0] = sp.get_u16(); o[1] = sp.get_u8()
		o[2] = _get_pos(sp); o[3] = _get_pos(sp); o[4] = _get_pos(sp)
		o[5] = sp.get_float(); o[6] = sp.get_16()
		obs.append(o)
	snap["ob"] = obs
	var wzn := sp.get_u8()
	if wzn > 0:
		var wz := PackedFloat32Array()
		for i in wzn: wz.append(sp.get_float())
		snap["wz"] = wz
	var hzn := sp.get_u8()
	if hzn > 0:
		var hz: Array = []
		for i in hzn:
			var h := PackedFloat32Array()
			for j in sp.get_u8(): h.append(sp.get_float())
			hz.append(h)
		snap["hz"] = hz
	if sp.get_u8() == 1:
		var boss := {}
		boss["id"] = _get_str(sp)
		boss["x"] = _get_pos(sp); boss["y"] = _get_pos(sp)
		boss["fx"] = _get_dir(sp); boss["fy"] = _get_dir(sp)
		boss["hp"] = sp.get_float(); boss["max_hp"] = sp.get_float()
		boss["state"] = sp.get_u8(); boss["phase"] = sp.get_u8()
		boss["shell_broken"] = sp.get_u8(); boss["shell_total"] = sp.get_u8()
		boss["f"] = sp.get_u8()
		boss["grabbed"] = _get_str(sp)
		boss["stagger_gauge"] = sp.get_float()
		boss["m"] = _get_str(sp)
		boss["mt"] = _get_time(sp)
		boss["pattern"] = _get_str(sp)
		snap["boss"] = boss
	if sp.get_available_bytes() > 0 and sp.get_u8() == 1:
		var extra: Variant = sp.get_var()
		if extra is Dictionary:
			for k in extra.keys():
				snap[k] = extra[k]
	return snap


# --- 필드 헬퍼 ---

static func _put_str(sp: StreamPeerBuffer, s: String) -> void:
	var b := s.to_utf8_buffer()
	sp.put_u8(mini(b.size(), 255))
	sp.put_data(b.slice(0, mini(b.size(), 255)))


static func _get_str(sp: StreamPeerBuffer) -> String:
	var n := sp.get_u8()
	if n == 0:
		return ""
	var r: Array = sp.get_data(n)
	return (r[1] as PackedByteArray).get_string_from_utf8()


static func _put_pos(sp: StreamPeerBuffer, v: float) -> void:
	sp.put_16(clampi(roundi(v * POS_SCALE), -32768, 32767))


static func _get_pos(sp: StreamPeerBuffer) -> float:
	return float(sp.get_16()) / POS_SCALE


static func _put_dir(sp: StreamPeerBuffer, v: float) -> void:
	sp.put_8(clampi(roundi(v * 127.0), -127, 127))


static func _get_dir(sp: StreamPeerBuffer) -> float:
	return float(sp.get_8()) / 127.0


static func _put_time(sp: StreamPeerBuffer, v: float) -> void:
	sp.put_u16(clampi(roundi(v * TIME_SCALE), 0, 65535))


static func _get_time(sp: StreamPeerBuffer) -> float:
	return float(sp.get_u16()) / TIME_SCALE


static func _put_val(sp: StreamPeerBuffer, v: float) -> void:
	sp.put_u16(clampi(roundi(v * VAL_SCALE), 0, 65535))


static func _get_val(sp: StreamPeerBuffer) -> float:
	return float(sp.get_u16()) / VAL_SCALE

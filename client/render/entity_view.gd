class_name EntityView
extends Node2D
## 플레이어·적 하나의 표시. 스프라이트 시트는 에셋 ID(prefix + "." + anim) 로 가져오며 파일 경로를 알지 못한다.

var sprite_prefix: String = "char.guardian"
var entity_id: Variant
var is_player: bool = true
var display_name: String = ""
var is_local: bool = false
var facing: Vector2 = Vector2(0, 1)
var target_pos: Vector2 = Vector2.ZERO
var hp: float = 1.0
var max_hp: float = 1.0
var shield: float = 0.0
var state: int = Protocol.EntState.ALIVE
var action: int = Protocol.Action.IDLE
var ai_state: int = Protocol.EnemyAI.IDLE
var moving: bool = false
var invuln: bool = false
var connected: bool = true
var down_t: float = 0.0
var rescue_t: float = 0.0
var front_guard: bool = false
var party_color: Color = Color.WHITE
var boss_state: int = -1
var molting: bool = false
var _sprite := Sprite2D.new()
var _guard := Sprite2D.new()
var _anim: String = ""
var _frame_t: float = 0.0
var _frame_i: int = 0
var _sheet: Dictionary = {}
var _flash_t: float = 0.0
var _last_pos: Vector2 = Vector2.ZERO
var _fallback_only: bool = false
var font: Font


func _ready() -> void:
	add_child(_sprite)
	_guard.texture = AssetRegistry.get_sheet("vfx.log_shield")["texture"]
	_guard.visible = false
	add_child(_guard)
	font = AssetRegistry.get_font("font.ui.main")
	_set_anim("idle")


func _set_anim(name: String) -> void:
	if _anim == name:
		return
	_anim = name
	_frame_t = 0.0
	_frame_i = 0
	_sheet = AssetRegistry.get_sheet(sprite_prefix + "." + name)
	_sprite.texture = _sheet["texture"]
	_sprite.hframes = int(_sheet["hframes"])
	_sprite.vframes = int(_sheet["vframes"])
	var fs: Vector2 = _sheet["frame_size"]
	var rs: Vector2 = _sheet["render_size"]
	_fallback_only = bool(_sheet.get("is_fallback", false))
	if _fallback_only:
		_sprite.hframes = 1
		_sprite.vframes = 1
		_sprite.scale = Vector2(0.75, 0.75)
		_sprite.offset = Vector2(0, -32)
		return
	_sprite.scale = rs / fs
	var anchor: Vector2 = _sheet["anchor"]
	_sprite.offset = Vector2(fs.x * (0.5 - anchor.x), fs.y * (0.5 - anchor.y))


func _pick_anim() -> String:
	if is_player:
		match state:
			Protocol.EntState.DOWNED, Protocol.EntState.DEAD:
				return "down"
		match action:
			Protocol.Action.WINDUP, Protocol.Action.ACTIVE, Protocol.Action.RECOVERY:
				return "attack"
			Protocol.Action.CAST, Protocol.Action.RESCUING:
				return "cast"
		return "walk" if moving else "idle"
	if boss_state >= 0:
		match boss_state:
			BossIronclaw.BS.DEAD: return "death"
			BossIronclaw.BS.WINDUP, BossIronclaw.BS.ATTACK, BossIronclaw.BS.GRAB_APPROACH, BossIronclaw.BS.GRABBING: return "attack"
			BossIronclaw.BS.STAGGER: return "stagger"
			BossIronclaw.BS.MOLT: return "molt"
			BossIronclaw.BS.CHASE: return "walk" if moving else "idle"
		return "idle"
	match ai_state:
		Protocol.EnemyAI.DEAD: return "death"
		Protocol.EnemyAI.WINDUP, Protocol.EnemyAI.ATTACK: return "attack"
		Protocol.EnemyAI.CHASE: return "walk"
		Protocol.EnemyAI.STAGGER: return "hit"
	return "idle"


func flash() -> void:
	_flash_t = 0.12


func _process(dt: float) -> void:
	if not is_local:
		position = position.lerp(target_pos, 1.0 - exp(-dt * 18.0))
	moving = (position - _last_pos).length() > 0.5
	_last_pos = position
	_set_anim(_pick_anim())
	if not _fallback_only:
		var frames: Array = _sheet["frames"]
		var fps := float(_sheet["fps"])
		if frames.size() > 1 and fps > 0.0:
			_frame_t += dt
			if _frame_t >= 1.0 / fps:
				_frame_t -= 1.0 / fps
				if _frame_i + 1 < frames.size():
					_frame_i += 1
				elif bool(_sheet["loop"]):
					_frame_i = 0
		var row := SimRules.dir_row(facing) if int(_sheet["vframes"]) == 4 else 0
		_sprite.frame = row * int(_sheet["hframes"]) + int(frames[_frame_i])
	_flash_t = maxf(_flash_t - dt, 0.0)
	var mod := Color.WHITE
	if _flash_t > 0.0:
		mod = Color(1.6, 0.6, 0.6)
	elif invuln:
		mod = Color(0.8, 0.9, 1.4, 0.7)
	elif not connected:
		mod = Color(0.6, 0.6, 0.6, 0.6)
	elif state == Protocol.EntState.DEAD:
		mod = Color(0.5, 0.5, 0.5, 0.5)
	_sprite.modulate = mod
	_guard.visible = front_guard and state == Protocol.EntState.ALIVE
	if _guard.visible:
		_guard.rotation = facing.angle()
		_guard.position = Vector2(0, -28)
		var gs: Dictionary = AssetRegistry.get_sheet("vfx.log_shield")
		_guard.scale = (gs["render_size"] as Vector2) / (gs["frame_size"] as Vector2)
	queue_redraw()


func _draw() -> void:
	# 그림자 겸 파티 색 링, 체력 바, 이름표. 실제 문구는 UI(폰트)로 렌더링한다.
	draw_arc(Vector2.ZERO, 20, 0, TAU, 24, Color(party_color, 0.55) if is_player else Color(0.2, 0.1, 0.3, 0.5), 2.0)
	if is_player and state == Protocol.EntState.DOWNED:
		draw_arc(Vector2.ZERO, 30, 0, TAU, 32, Color(1, 0.35, 0.2, 0.8), 3.0)
		var t := "%.0f" % down_t
		draw_string(font, Vector2(-10, -72), t, HORIZONTAL_ALIGNMENT_CENTER, 20, 14, Color(1, 0.6, 0.4))
	var w := 44.0 if is_player else (120.0 if boss_state >= 0 else 36.0)
	var y := -70.0 if is_player else (-150.0 if boss_state >= 0 else -60.0)
	draw_rect(Rect2(-w / 2, y, w, 6), Color(0, 0, 0, 0.6))
	var frac := clampf(hp / maxf(max_hp, 1.0), 0.0, 1.0)
	var col := Color(0.3, 0.85, 0.35) if is_player else Color(0.85, 0.3, 0.25)
	draw_rect(Rect2(-w / 2, y, w * frac, 6), col)
	if shield > 0.0:
		var sf := clampf(shield / maxf(max_hp, 1.0), 0.0, 1.0)
		draw_rect(Rect2(-w / 2, y - 3, w * sf, 3), Color(0.5, 0.8, 1.0))
	if rescue_t > 0.0:
		draw_rect(Rect2(-w / 2, y + 8, w * clampf(rescue_t / 3.0, 0.0, 1.0), 4), Color(0.6, 1.0, 0.6))
	if is_player and display_name != "":
		draw_string(font, Vector2(-60, y - 8), display_name, HORIZONTAL_ALIGNMENT_CENTER, 120, 13, Color(1, 1, 1) if not is_local else Color(1, 0.95, 0.6))

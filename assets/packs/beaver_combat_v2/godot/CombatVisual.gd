extends AnimatedSprite2D
## Visual adapter only. The server owns damage, targets and mechanic outcomes.

@export var visual_frames: SpriteFrames
@export var ground_anchor_px := Vector2(64.0, 106.0)

func _ready() -> void:
	centered = false
	offset = -ground_anchor_px
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	if visual_frames != null:
		sprite_frames = visual_frames

func configure(frames: SpriteFrames, anchor_px: Vector2) -> void:
	visual_frames = frames
	sprite_frames = frames
	ground_anchor_px = anchor_px
	centered = false
	offset = -anchor_px

func play_named(animation_name: StringName, restart := false) -> bool:
	if sprite_frames == null or not sprite_frames.has_animation(animation_name):
		return false
	if restart:
		stop()
		play(animation_name)
	elif animation != animation_name or not is_playing():
		play(animation_name)
	return true

func set_phase_progress(animation_name: StringName, normalized_progress: float) -> bool:
	## Caller supplies progress from the authoritative phase start and duration.
	## It is safe to hold at 1.0 until the next server state arrives.
	if sprite_frames == null or not sprite_frames.has_animation(animation_name):
		return false
	var count := sprite_frames.get_frame_count(animation_name)
	if count <= 0:
		return false
	if animation != animation_name:
		animation = animation_name
	pause()
	var progress := clampf(normalized_progress, 0.0, 1.0)
	var cursor := progress * float(count)
	var index := mini(int(cursor), count - 1)
	var fraction := 1.0 if progress >= 1.0 else cursor - float(index)
	set_frame_and_progress(index, fraction)
	return true

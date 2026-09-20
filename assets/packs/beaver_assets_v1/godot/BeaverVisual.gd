extends AnimatedSprite2D
## Presentation-only adapter. Do not drive authoritative combat from these frames.

@export var visual_frames: SpriteFrames
@export var ground_anchor_px := Vector2(64.0, 106.0)

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	centered = false
	offset = -ground_anchor_px
	if visual_frames != null:
		sprite_frames = visual_frames
		play_state(&"idle", &"down")

func configure(frames: SpriteFrames, anchor: Vector2) -> void:
	visual_frames = frames
	sprite_frames = frames
	ground_anchor_px = anchor
	centered = false
	offset = -anchor

func play_state(state: StringName, direction: StringName, restart := false) -> void:
	if sprite_frames == null:
		return
	var animation_name := StringName("%s_%s" % [state, direction])
	if not sprite_frames.has_animation(animation_name):
		animation_name = StringName("idle_%s" % direction)
	if not sprite_frames.has_animation(animation_name):
		return
	if restart:
		stop()
		play(animation_name)
	elif animation != animation_name:
		play(animation_name)
	elif not is_playing() and sprite_frames.get_animation_loop(animation_name):
		play(animation_name)

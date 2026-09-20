class_name WorldView
extends Node2D
## 허브·전투방의 월드 표시. 바닥 타일, 장애물, 엔티티, 위험 예고, 짧은 이펙트, 카메라.
## 모든 텍스처는 AssetRegistry 의 ID 로 가져온다.

var bounds: Rect2 = Rect2(0, 0, 1200, 800)
var entities: Dictionary = {}     # key ("p:<id>" | "e:<id>") -> EntityView
var telegraphs: Array = []        # [x, y, r, remaining, total, asset]
var camera := Camera2D.new()
var _ground := Sprite2D.new()
var _water_rects: Array = []
var _obstacles: Array = []
var _obstacle_sprites: Array = []
var _effects: Node2D = Node2D.new()
var _telegraph_layer: Node2D = Node2D.new()
var ally_vfx_alpha: float = 0.7
var _audio_last: Dictionary = {}
var _audio_players: Array = []
var _tg_tex: Texture2D
const PARTY_COLORS := [Color(0.95, 0.8, 0.3), Color(0.4, 0.75, 1.0), Color(0.5, 0.9, 0.5), Color(0.95, 0.5, 0.8)]


func _ready() -> void:
	_ground.centered = false
	_ground.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_ground.region_enabled = true
	add_child(_ground)
	add_child(_telegraph_layer)
	_telegraph_layer.draw.connect(_draw_telegraphs)
	add_child(_effects)
	add_child(camera)
	camera.enabled = true
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 8.0
	for i in 6:
		var ap := AudioStreamPlayer.new()
		add_child(ap)
		_audio_players.append(ap)
	_tg_tex = AssetRegistry.get_texture("vfx.telegraph_circle")


func setup(area_bounds: Rect2, ground_asset: String, obstacles: Array, water: Array) -> void:
	bounds = area_bounds
	_ground.texture = AssetRegistry.get_texture(ground_asset)
	_ground.region_rect = Rect2(Vector2.ZERO, bounds.size)
	_ground.position = bounds.position
	for s: Node in _obstacle_sprites:
		s.queue_free()
	_obstacle_sprites.clear()
	_obstacles = obstacles
	for ob: Dictionary in obstacles:
		var spr := Sprite2D.new()
		spr.texture = AssetRegistry.get_texture(String(ob.get("asset", "prop.willow.rock")))
		spr.position = Vector2(float(ob["x"]), float(ob["y"]))
		var r := float(ob.get("r", 40))
		spr.scale = Vector2.ONE * (r * 2.4 / maxf(spr.texture.get_width(), 1))
		spr.offset = Vector2(0, -12)
		add_child(spr)
		_obstacle_sprites.append(spr)
	_water_rects = water
	for w: Dictionary in water:
		var ws := Sprite2D.new()
		ws.centered = false
		ws.texture = AssetRegistry.get_texture("tile.willow.water")
		ws.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		ws.region_enabled = true
		ws.region_rect = Rect2(0, 0, float(w["w"]), float(w["h"]))
		ws.position = Vector2(float(w["x"]), float(w["y"]))
		add_child(ws)
		_obstacle_sprites.append(ws)
	camera.limit_left = int(bounds.position.x) - 200
	camera.limit_top = int(bounds.position.y) - 200
	camera.limit_right = int(bounds.end.x) + 200
	camera.limit_bottom = int(bounds.end.y) + 200
	queue_redraw()


func clear_entities() -> void:
	for e: EntityView in entities.values():
		e.queue_free()
	entities.clear()
	telegraphs.clear()
	for c: Node in _effects.get_children():
		c.queue_free()


func get_or_create(key: String, is_player: bool, sprite_prefix: String, pos: Vector2) -> EntityView:
	if entities.has(key):
		return entities[key]
	var ev := EntityView.new()
	ev.is_player = is_player
	ev.sprite_prefix = sprite_prefix
	ev.position = pos
	ev.target_pos = pos
	add_child(ev)
	entities[key] = ev
	return ev


func remove_missing(keys_present: Array, prefix: String) -> void:
	for k: String in entities.keys():
		if k.begins_with(prefix) and not keys_present.has(k):
			entities[k].queue_free()
			entities.erase(k)


func party_color(index: int) -> Color:
	return PARTY_COLORS[index % PARTY_COLORS.size()]


func _draw() -> void:
	# 경계 벽: 타일 ID 로 색을 가져오지 않고 단순 선으로 표시 (임시)
	draw_rect(bounds.grow(4), Color(0.25, 0.18, 0.1), false, 8.0)


func _process(dt: float) -> void:
	_telegraph_layer.queue_redraw()
	var i := _effects.get_child_count() - 1
	while i >= 0:
		var fx: Node2D = _effects.get_child(i)
		var t := float(fx.get_meta("t", 0.0)) + dt
		var life := float(fx.get_meta("life", 0.3))
		fx.set_meta("t", t)
		if t >= life:
			fx.queue_free()
		else:
			var spr := fx as Sprite2D
			if spr != null and spr.hframes > 1:
				spr.frame = mini(int(t / life * spr.hframes), spr.hframes - 1)
			fx.modulate.a = ally_vfx_alpha * (1.0 - t / life * 0.5)
		i -= 1


func _draw_telegraphs() -> void:
	# 적 강공격 예고: 색 + 모양(링과 채워지는 원) 으로 표시한다. 아군 이펙트에 가려지지 않게 별도 레이어.
	for tg: Array in telegraphs:
		var c := Vector2(float(tg[0]), float(tg[1]))
		var r := float(tg[2])
		var remaining := float(tg[3])
		var total := maxf(float(tg[4]), 0.01)
		var progress := clampf(1.0 - remaining / total, 0.0, 1.0)
		_telegraph_layer.draw_circle(c, r, Color(1.0, 0.45, 0.2, 0.18))
		_telegraph_layer.draw_circle(c, r * progress, Color(1.0, 0.35, 0.15, 0.35))
		_telegraph_layer.draw_arc(c, r, 0, TAU, 40, Color(1.0, 0.5, 0.2, 0.95), 3.0)
		if _tg_tex != null:
			var s := r * 2.0 / maxf(_tg_tex.get_width(), 1)
			_telegraph_layer.draw_set_transform(c, 0.0, Vector2(s, s))
			_telegraph_layer.draw_texture(_tg_tex, -_tg_tex.get_size() / 2.0, Color(1, 1, 1, 0.5))
			_telegraph_layer.draw_set_transform(Vector2.ZERO)


func spawn_effect(asset_id: String, pos: Vector2, rotation_: float = 0.0, life: float = -1.0) -> void:
	var sheet := AssetRegistry.get_sheet(asset_id)
	var spr := Sprite2D.new()
	spr.texture = sheet["texture"]
	spr.hframes = int(sheet["hframes"])
	spr.vframes = int(sheet["vframes"])
	var fs: Vector2 = sheet["frame_size"]
	var rs: Vector2 = sheet["render_size"]
	spr.scale = rs / fs if not bool(sheet.get("is_fallback", false)) else Vector2(0.5, 0.5)
	spr.position = pos
	spr.rotation = rotation_
	var fps := float(sheet["fps"])
	spr.set_meta("life", life if life > 0.0 else (spr.hframes / maxf(fps, 1.0)))
	spr.set_meta("t", 0.0)
	_effects.add_child(spr)


func play_sound(asset_id: String, min_gap: float = 0.06) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_audio_last.get(asset_id, -10.0)) < min_gap:
		return
	var stream := AssetRegistry.get_audio(asset_id)
	if stream == null:
		return
	for ap: AudioStreamPlayer in _audio_players:
		if not ap.playing:
			ap.stream = stream
			ap.play()
			_audio_last[asset_id] = now
			return

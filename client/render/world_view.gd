class_name WorldView
extends Node2D
## 허브·전투방의 월드 표시. 바닥 타일, 장애물, 엔티티, 위험 예고, 짧은 이펙트, 카메라.
## 모든 텍스처는 AssetRegistry 의 ID 로 가져온다.

var bounds: Rect2 = Rect2(0, 0, 1200, 800)
var entities: Dictionary = {}     # key ("p:<id>" | "e:<id>") -> EntityView
var telegraphs: Array = []        # PackedFloat32Array (Protocol.SNAP_TG)
var projectiles: Array = []       # PackedFloat32Array (Protocol.SNAP_PR)
var objects: Array = []           # PackedFloat32Array (Protocol.SNAP_OB)
var water_zone: PackedFloat32Array = PackedFloat32Array()
var boss_state: Dictionary = {}
var _object_tex: Dictionary = {}
var _mechanic_fx: Dictionary = {}   # mechanic id ("IC-01") -> {"success": bool, "t": sec since end, "active": bool}
const MECHANIC_OF_KIND := {Protocol.ObKind.PILLAR: "ic_01", Protocol.ObKind.GATE: "ic_02", Protocol.ObKind.CLAW_LINK: "ic_03", Protocol.ObKind.CORRIDOR: "ic_04", Protocol.ObKind.ANCHOR: "ic_05"}
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
	for kind_asset in [["gnaw_tree", "prop.gnaw_tree"], ["device", "prop.device"], ["lever", "prop.lever"], ["structure", "prop.log_cover"], ["trap", "vfx.thorn_trap"], ["proj_enemy", "vfx.projectile_sap"], ["proj_player", "vfx.projectile_pinecone"],
			["pillar", "prop.boss.pillar"], ["gate", "prop.boss.gate"], ["husk", "prop.boss.husk"], ["corridor", "prop.boss.corridor"], ["rope", "prop.boss.rope"], ["debris", "prop.boss.debris"], ["anchor", "prop.boss.anchor"], ["platform", "prop.boss.platform"], ["claw_link", "prop.boss.claw_link"], ["turret", "prop.turret"], ["dam", "prop.dam"], ["proj_water", "vfx.projectile_water"]]:
		_object_tex[kind_asset[0]] = AssetRegistry.get_texture(kind_asset[1])


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
	for mid: String in _mechanic_fx.keys():
		if not bool(_mechanic_fx[mid].get("active", false)):
			_mechanic_fx[mid]["t"] = float(_mechanic_fx[mid]["t"]) + dt
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
	var L := _telegraph_layer
	# 수문 물길: 낮음(연한 파랑) / 경고(깜빡임) / 높음(급류)
	if water_zone.size() >= 5:
		var rect := Rect2(water_zone[0], water_zone[1], water_zone[2], water_zone[3])
		var st := int(water_zone[4])
		var col := Color(0.3, 0.55, 0.9, 0.18)
		if st == 1:
			col = Color(0.9, 0.7, 0.2, 0.35 if int(Time.get_ticks_msec() / 120) % 2 == 0 else 0.15)
		elif st == 2:
			col = Color(0.2, 0.5, 1.0, 0.45)
		L.draw_rect(rect, col)
		L.draw_rect(rect, Color(0.4, 0.7, 1.0, 0.8), false, 2.0)
		if st == 2:
			for i in 6:
				var y := rect.position.y + rect.size.y * (i + 0.5) / 6.0
				L.draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), Color(0.7, 0.9, 1.0, 0.35), 2.0)
	# 상호작용물
	for o: PackedFloat32Array in objects:
		var kind := int(o[Protocol.SNAP_OB.KIND])
		var c := Vector2(o[Protocol.SNAP_OB.X], o[Protocol.SNAP_OB.Y])
		var r := o[Protocol.SNAP_OB.R]
		var prog := o[Protocol.SNAP_OB.PROGRESS]
		var st := int(o[Protocol.SNAP_OB.STATE])
		match kind:
			Protocol.ObKind.HOLD_ZONE:
				var zc := Color(0.4, 0.9, 0.5, 0.18) if st == 1 else (Color(0.95, 0.4, 0.3, 0.2) if st == 2 else Color(0.9, 0.85, 0.4, 0.14))
				L.draw_circle(c, r, zc)
				L.draw_arc(c, r, 0, TAU, 48, Color(0.95, 0.9, 0.5, 0.9), 3.0)
				if prog > 0.0:
					L.draw_arc(c, r + 8, -PI / 2, -PI / 2 + TAU * prog, 48, Color(0.5, 1.0, 0.6, 0.95), 6.0)
			Protocol.ObKind.VOLLEY:
				L.draw_circle(c, r, Color(0.5, 0.9, 0.4, 0.2))
				L.draw_arc(c, r, 0, TAU, 40, Color(0.6, 1.0, 0.5, 0.9), 2.0)
			Protocol.ObKind.TRAP:
				_draw_tex(L, _object_tex["trap"], c, r * 2.0, Color(1, 1, 1, 0.9 if st == 1 else 0.5))
			Protocol.ObKind.TURRET:
				_draw_tex(L, _object_tex["turret"], c + Vector2(0, -10), 64, Color.WHITE if st == 1 else Color(0.85, 0.9, 1.0))
				L.draw_arc(c, 18, -PI / 2, -PI / 2 + TAU * prog, 24, Color(0.4, 0.8, 1.0, 0.9), 3.0)
			Protocol.ObKind.DAM:
				_draw_tex(L, _object_tex["dam"], c + Vector2(0, -16), r * 2.6, Color.WHITE)
				L.draw_rect(Rect2(c.x - 26, c.y - 60, 52, 5), Color(0, 0, 0, 0.6))
				L.draw_rect(Rect2(c.x - 26, c.y - 60, 52 * prog, 5), Color(0.4, 0.75, 1.0))
			Protocol.ObKind.ROOT_ZONE:
				L.draw_circle(c, r, Color(0.45, 0.3, 0.15, 0.25))
				L.draw_arc(c, r, 0, TAU, 32, Color(0.6, 0.85, 0.35, 0.9), 2.0)
				for i in 6:
					var a := i * TAU / 6.0 + prog * 2.0
					L.draw_line(c, c + Vector2(cos(a), sin(a)) * r * 0.9, Color(0.5, 0.35, 0.2, 0.7), 2.0)
			Protocol.ObKind.FLOOD_ZONE:
				L.draw_circle(c, r, Color(0.35, 0.8, 0.45, 0.16))
				L.draw_arc(c, r * (0.6 + 0.4 * fmod(prog * 3.0, 1.0)), 0, TAU, 48, Color(0.5, 1.0, 0.6, 0.5), 2.0)
				L.draw_arc(c, r, 0, TAU, 48, Color(0.5, 1.0, 0.6, 0.9), 2.0)
			Protocol.ObKind.STRUCTURE:
				_draw_tex(L, _object_tex["structure"], c + Vector2(0, -8), 72, Color.WHITE)
				L.draw_rect(Rect2(c.x - 20, c.y - 44, 40, 5), Color(0, 0, 0, 0.6))
				L.draw_rect(Rect2(c.x - 20, c.y - 44, 40 * prog, 5), Color(0.8, 0.6, 0.3))
			Protocol.ObKind.GNAW_TREE:
				_draw_tex(L, _object_tex["gnaw_tree"], c + Vector2(0, -20), 84, Color.WHITE)
				_draw_progress(L, c, prog, "F 갉기")
			Protocol.ObKind.DEVICE:
				_draw_tex(L, _object_tex["device"], c + Vector2(0, -10), 76, Color.WHITE if st == 0 else Color(0.6, 1.0, 0.7))
				_draw_progress(L, c, prog if st == 0 else 1.0, "F 가동" if st == 0 else "가동 완료")
			Protocol.ObKind.SLUICE_LEVER:
				_draw_tex(L, _object_tex["lever"], c + Vector2(0, -10), 60, Color.WHITE)
				_draw_progress(L, c, prog, "F 수문")
			Protocol.ObKind.PILLAR:
				if not _draw_device(L, kind, c, prog, st, 150):
					_draw_tex(L, _object_tex["pillar"], c + Vector2(0, -30), 100, Color.WHITE if st == 0 else Color(1.0, 0.75, 0.4))
				_draw_progress(L, c, prog, "F 갉기 (약화)" if st == 0 else "약화됨 — 돌진 유도!")
				if st == 1:
					L.draw_arc(c, 40, 0, TAU, 32, Color(1.0, 0.8, 0.3, 0.9), 3.0)
			Protocol.ObKind.GATE:
				var cur := st & 1
				var tgt := (st >> 1) & 1
				var locked := st == 4
				if not _draw_device(L, kind, c, prog, st, 140):
					_draw_tex(L, _object_tex["gate"], c + Vector2(0, -20), 80, Color(0.6, 1.0, 0.7) if locked else Color.WHITE)
				L.draw_rect(Rect2(c.x - 26, c.y + 28, 24, 10), Color(0.3, 0.6, 1.0) if cur == 1 else Color(0.5, 0.4, 0.3))
				L.draw_rect(Rect2(c.x + 2, c.y + 28, 24, 10), Color(0.3, 0.6, 1.0) if tgt == 1 else Color(0.5, 0.4, 0.3), false, 2.0)
				_draw_progress(L, c + Vector2(0, 10), prog, "잠김" if locked else ("F 수문 (현재→목표)"))
			Protocol.ObKind.CLAW_LINK:
				if not _draw_device(L, kind, c, prog * 0.5 + (0.5 if st >= 1 else 0.0), 0 if st < 2 else 1, 120):
					_draw_tex(L, _object_tex["claw_link"], c, 64, Color.WHITE if st < 2 else Color(0.6, 1.0, 0.7))
				_draw_progress(L, c, prog, ["F 고리 노출", "F 쐐기 박기", "풀려남"][clampi(st, 0, 2)])
			Protocol.ObKind.HUSK:
				var wig := sin(Time.get_ticks_msec() / 90.0) * 6.0 if st == 1 else 0.0
				_draw_tex(L, _object_tex["husk"], c + Vector2(wig, -30), 180, Color(0.85, 0.85, 0.9))
				if st == 1:
					# 본체: 흐르는 물결 + 더듬이 흔들림 (색이 아닌 움직임으로 구분)
					for k in 3:
						var rr := 60.0 + k * 18.0 + fmod(Time.get_ticks_msec() / 40.0, 18.0)
						L.draw_arc(c, rr, 0, TAU, 40, Color(0.6, 0.85, 1.0, 0.35), 2.0)
			Protocol.ObKind.CORRIDOR:
				if not _draw_device(L, kind, c, prog, st, 140):
					_draw_tex(L, _object_tex["corridor"], c, 90, Color.WHITE if st == 0 else Color(0.5, 0.5, 0.5))
				_draw_progress(L, c, prog, "F 통로 차단" if st == 0 else "차단됨")
			Protocol.ObKind.ROPE:
				_draw_tex(L, _object_tex["rope"], c, 44, Color.WHITE if st == 0 else Color(0.6, 1.0, 0.7))
				_draw_progress(L, c, prog, "F 닻줄 연결" if st == 0 else "연결됨")
			Protocol.ObKind.DEBRIS:
				_draw_tex(L, _object_tex["debris"], c, 80, Color.WHITE)
				_draw_progress(L, c, prog, "F 잔해 제거")
			Protocol.ObKind.ANCHOR:
				if not _draw_device(L, kind, c, prog, st, 150):
					_draw_tex(L, _object_tex["anchor"], c + Vector2(0, -20), 80, Color.WHITE if st == 0 else Color(0.6, 1.0, 0.7))
				_draw_progress(L, c, prog, "F 고정 (줄·잔해 먼저)" if st == 0 else "고정됨")
			Protocol.ObKind.PLATFORM:
				var pc := Color(0.9, 0.8, 0.4, 0.25) if st == 2 else Color(0.6, 0.5, 0.3, 0.2)
				L.draw_circle(c, r, pc)
				L.draw_arc(c, r, 0, TAU, 48, Color(1.0, 0.85, 0.4, 0.9) if st == 2 else Color(0.8, 0.7, 0.5, 0.8), 3.0)
				if st != 2:
					L.draw_arc(c, r + 10, -PI / 2, -PI / 2 + TAU * prog, 48, Color(1.0, 0.4, 0.3, 0.9), 5.0)
				_draw_progress(L, c, 0.0, "안전 발판 (+25%)" if st == 2 else "끌려가는 발판")
			Protocol.ObKind.HAZARD:
				L.draw_circle(c, r, Color(0.5, 0.2, 0.8, 0.3))
				L.draw_arc(c, r, 0, TAU, 40, Color(0.7, 0.3, 1.0, 0.9), 3.0)
			_:
				L.draw_arc(c, r, 0, TAU, 24, Color(1, 1, 1, 0.6), 2.0)
				_draw_progress(L, c, prog, "F")
	# 적 강공격 예고: 색 + 모양(원/직선) 으로 표시. 아군 이펙트에 가려지지 않게 별도 레이어.
	for tg: PackedFloat32Array in telegraphs:
		var c := Vector2(tg[Protocol.SNAP_TG.X], tg[Protocol.SNAP_TG.Y])
		var remaining := tg[Protocol.SNAP_TG.REMAINING]
		var total := maxf(tg[Protocol.SNAP_TG.TOTAL], 0.01)
		var progress := clampf(1.0 - remaining / total, 0.0, 1.0)
		if int(tg[Protocol.SNAP_TG.TYPE]) == 1:
			var d := Vector2(tg[Protocol.SNAP_TG.DX], tg[Protocol.SNAP_TG.DY])
			var len := tg[Protocol.SNAP_TG.R]
			var w := tg[Protocol.SNAP_TG.W]
			var n := Vector2(-d.y, d.x) * (w * 0.5)
			var pts := PackedVector2Array([c + n, c + d * len + n, c + d * len - n, c - n])
			L.draw_colored_polygon(pts, Color(1.0, 0.45, 0.2, 0.18))
			var fill := PackedVector2Array([c + n, c + d * len * progress + n, c + d * len * progress - n, c - n])
			L.draw_colored_polygon(fill, Color(1.0, 0.35, 0.15, 0.35))
			L.draw_polyline(PackedVector2Array([c + n, c + d * len + n, c + d * len - n, c - n, c + n]), Color(1.0, 0.5, 0.2, 0.95), 3.0)
			L.draw_line(c + d * len - n * 0.6, c + d * (len + 18), Color(1.0, 0.5, 0.2, 0.95), 3.0)
			L.draw_line(c + d * len + n * 0.6, c + d * (len + 18), Color(1.0, 0.5, 0.2, 0.95), 3.0)
		else:
			var r := tg[Protocol.SNAP_TG.R]
			L.draw_circle(c, r, Color(1.0, 0.45, 0.2, 0.18))
			L.draw_circle(c, r * progress, Color(1.0, 0.35, 0.15, 0.35))
			L.draw_arc(c, r, 0, TAU, 40, Color(1.0, 0.5, 0.2, 0.95), 3.0)
			if _tg_tex != null:
				var sc := r * 2.0 / maxf(_tg_tex.get_width(), 1)
				L.draw_set_transform(c, 0.0, Vector2(sc, sc))
				L.draw_texture(_tg_tex, -_tg_tex.get_size() / 2.0, Color(1, 1, 1, 0.5))
				L.draw_set_transform(Vector2.ZERO)
	# 투사체
	for pr: PackedFloat32Array in projectiles:
		var c := Vector2(pr[Protocol.SNAP_PR.X], pr[Protocol.SNAP_PR.Y])
		var tex: Texture2D = _object_tex["proj_player"] if int(pr[Protocol.SNAP_PR.KIND]) == 1 else _object_tex["proj_enemy"]
		_draw_tex(L, tex, c, pr[Protocol.SNAP_PR.R] * 3.0, Color.WHITE)


## 서버 기믹 이벤트를 기억해 장치 시트의 성공/실패 연출을 고른다 (자동 순환하지 않는다)
func mechanic_result(mid: String, success: bool, started: bool = false) -> void:
	if started:
		_mechanic_fx[mid] = {"active": true, "success": false, "t": -1.0}
	else:
		_mechanic_fx[mid] = {"active": false, "success": success, "t": 0.0}


## 장치 시트 프레임을 그린다. 진행 중이면 activation 을 진행률로, 끝났으면 success/failure 를 1회 재생 후 마지막 프레임 유지.
## 시트가 없으면 false 를 돌려 기존 도형 표시로 넘어간다.
func _draw_device(L: Node2D, kind: int, c: Vector2, progress: float, state: int, size: float) -> bool:
	var key: String = MECHANIC_OF_KIND.get(kind, "")
	if key == "":
		return false
	var mid := "IC-" + key.substr(3)
	var fx: Dictionary = _mechanic_fx.get(mid, {})
	var sheet_id := "prop.mechanic.%s.activation" % key
	var frame_t := 0.0
	if not fx.is_empty() and not bool(fx.get("active", true)):
		sheet_id = "prop.mechanic.%s.%s" % [key, "success" if bool(fx["success"]) else "failure"]
		frame_t = clampf(float(fx["t"]) / 0.6, 0.0, 1.0)
	else:
		# 진행률 또는 상태로 activation 프레임 선택 (state 1 = 약화/노출 등 완료 대기 상태 → 마지막 프레임)
		frame_t = 1.0 if state >= 1 and kind != Protocol.ObKind.GATE else clampf(progress, 0.0, 0.999)
		if kind == Protocol.ObKind.GATE:
			frame_t = 1.0 if state == 4 else clampf(progress, 0.0, 0.999)
	if not AssetRegistry.has(sheet_id):
		return false
	var sheet := AssetRegistry.get_sheet(sheet_id)
	if bool(sheet.get("is_fallback", false)):
		return false
	var tex: Texture2D = sheet["texture"]
	var cols := int(sheet["hframes"])
	var fi := mini(int(frame_t * cols), cols - 1)
	var fs: Vector2 = sheet["frame_size"]
	var sc := size / fs.x
	var anchor: Vector2 = sheet["anchor"]
	L.draw_set_transform(c - Vector2(fs.x * anchor.x, fs.y * anchor.y) * sc, 0.0, Vector2(sc, sc))
	L.draw_texture_rect_region(tex, Rect2(Vector2.ZERO, fs), Rect2(Vector2(fi * fs.x, 0), fs))
	L.draw_set_transform(Vector2.ZERO)
	return true


func _draw_tex(L: Node2D, tex: Texture2D, c: Vector2, size: float, col: Color) -> void:
	if tex == null:
		return
	var sc := size / maxf(tex.get_width(), 1)
	L.draw_set_transform(c, 0.0, Vector2(sc, sc))
	L.draw_texture(tex, -tex.get_size() / 2.0, col)
	L.draw_set_transform(Vector2.ZERO)


func _draw_progress(L: Node2D, c: Vector2, prog: float, label: String) -> void:
	if prog > 0.0 and prog < 1.0:
		L.draw_arc(c, 30, -PI / 2, -PI / 2 + TAU * prog, 32, Color(0.6, 1.0, 0.6, 0.95), 4.0)
	var font := AssetRegistry.get_font("font.ui.main")
	L.draw_string(font, c + Vector2(-40, 44), label, HORIZONTAL_ALIGNMENT_CENTER, 80, 12, Color(1, 1, 0.85, 0.9))


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

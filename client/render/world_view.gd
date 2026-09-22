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
var hazards: Array = []           # PackedFloat32Array [x,y,w,h,slow]
var npcs: Array = []              # 마을 NPC [{id,name_ko,x,y,sprite}]
var sfx_volume: float = 0.8
var flash_reduce: bool = false
var _npc_sprites: Array = []
var boss_state: Dictionary = {}
var explore: bool = false          # 탐색 모드(클리어된 방): 문이 열려 있다
var ground_items: Dictionary = {}  # gid -> {pos, from, rarity, base, name, slot, enh, t} 바닥에 떨어진 장비 (이벤트로 갱신)
var local_pos: Vector2 = Vector2.ZERO   # 내 캐릭터 위치 (가까운 일반 장비 이름표 표시용)
var local_id: String = ""               # 내 계정 ID: 남의 개인 드랍(owner 가 다른 사람)은 그리지 않는다
var _object_tex: Dictionary = {}
var _mechanic_fx: Dictionary = {}   # mechanic id ("IC-01") -> {"success": bool, "t": sec since end, "active": bool}
const MECHANIC_OF_KIND := {Protocol.ObKind.PILLAR: "ic_01", Protocol.ObKind.GATE: "ic_02", Protocol.ObKind.CLAW_LINK: "ic_03", Protocol.ObKind.CORRIDOR: "ic_04", Protocol.ObKind.ANCHOR: "ic_05",
	Protocol.ObKind.LANTERN: "tf_01", Protocol.ObKind.SEED: "tf_02", Protocol.ObKind.SPORE_NODE: "tf_03", Protocol.ObKind.RESONANCE_LOG: "tf_04", Protocol.ObKind.FIREFLY: "tf_05", Protocol.ObKind.VAT: "tf_05",
	Protocol.ObKind.CRACK: "rk_01", Protocol.ObKind.CHANNEL_PIECE: "rk_02", Protocol.ObKind.PARASITE: "rk_03", Protocol.ObKind.ECHO: "rk_04", Protocol.ObKind.VALVE: "rk_05", Protocol.ObKind.GAUGE: "rk_05"}
const MECHANIC_ID_OF_KEY := {"ic_01": "IC-01", "ic_02": "IC-02", "ic_03": "IC-03", "ic_04": "IC-04", "ic_05": "IC-05", "tf_01": "TF-01", "tf_02": "TF-02", "tf_03": "TF-03", "tf_04": "TF-04", "tf_05": "TF-05", "rk_01": "RK-01", "rk_02": "RK-02", "rk_03": "RK-03", "rk_04": "RK-04", "rk_05": "RK-05"}
var camera := Camera2D.new()
var _ground := Sprite2D.new()
var _terrain := Node2D.new()          # 강둑 링·물가 경계 (바닥 위, 물 위, 엔티티 아래)
var _water_rects: Array = []
var _water_sprites: Array = []
var _water_asset: String = "tile.willow.water"
var _wall_asset: String = "tile.willow.wall"
var _shore_asset: String = "tile.willow.shore"
var _water_frame: int = 0
var _water_t: float = 0.0
var _decor_sprites: Array = []
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
	add_child(_terrain)
	_terrain.draw.connect(_draw_terrain)
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
			["pillar", "prop.boss.pillar"], ["gate", "prop.boss.gate"], ["husk", "prop.boss.husk"], ["corridor", "prop.boss.corridor"], ["rope", "prop.boss.rope"], ["debris", "prop.boss.debris"], ["anchor", "prop.boss.anchor"], ["platform", "prop.boss.platform"], ["claw_link", "prop.boss.claw_link"], ["turret", "prop.turret"], ["dam", "prop.dam"], ["proj_water", "vfx.projectile_water"], ["raft", "prop.raft"], ["secret", "prop.secret"]]:
		_object_tex[kind_asset[0]] = AssetRegistry.get_texture(kind_asset[1])


func setup(area_bounds: Rect2, ground_asset: String, obstacles: Array, water: Array, wall_asset: String = "tile.willow.wall", water_asset: String = "tile.willow.water", shore_asset: String = "tile.willow.shore") -> void:
	bounds = area_bounds
	_wall_asset = wall_asset
	_water_asset = water_asset
	_shore_asset = shore_asset
	_ground.texture = AssetRegistry.get_texture(ground_asset)
	_ground.region_rect = Rect2(Vector2.ZERO, bounds.size)
	_ground.position = bounds.position
	for s: Node in _obstacle_sprites:
		s.queue_free()
	_obstacle_sprites.clear()
	_water_sprites.clear()
	set_decor([])
	_obstacles = obstacles
	var oi := 0
	for ob: Dictionary in obstacles:
		if ob.has("asset") and String(ob["asset"]) == "":
			oi += 1
			continue   # 합성 장식(긴 통나무 등)이 대신 그리는 충돌 원
		var spr := _prop_sprite(String(ob.get("asset", "prop.willow.rock")), int(ob.get("frame", oi)), float(ob.get("size", float(ob.get("r", 40)) * 2.4)))
		spr.position = Vector2(float(ob["x"]), float(ob["y"]))
		add_child(spr)
		_obstacle_sprites.append(spr)
		oi += 1
	_water_rects = water
	for w: Dictionary in water:
		var ws := Sprite2D.new()
		ws.centered = false
		ws.texture = AssetRegistry.get_frame_texture(_water_asset, 0)
		ws.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		ws.region_enabled = true
		ws.region_rect = Rect2(0, 0, float(w["w"]), float(w["h"]))
		# 바닥 스프라이트의 자식으로 두어 물가 경계(_terrain) 아래에 그린다
		ws.position = Vector2(float(w["x"]), float(w["y"])) - bounds.position
		_ground.add_child(ws)
		_obstacle_sprites.append(ws)
		_water_sprites.append(ws)
	_terrain.queue_redraw()
	camera.limit_left = int(bounds.position.x) - 200
	camera.limit_top = int(bounds.position.y) - 200
	camera.limit_right = int(bounds.end.x) + 200
	camera.limit_bottom = int(bounds.end.y) + 200
	queue_redraw()


## 시트 프레임 하나를 보여주는 소품 스프라이트. frame 은 상태/변형 인덱스(열 수로 감싼다). size 는 월드 px 폭.
func _prop_sprite(asset: String, frame: int, size: float) -> Sprite2D:
	var spr := Sprite2D.new()
	var sheet := AssetRegistry.get_sheet(asset)
	spr.texture = sheet["texture"]
	spr.hframes = maxi(int(sheet["hframes"]), 1)
	spr.vframes = maxi(int(sheet["vframes"]), 1)
	spr.frame = frame % spr.hframes if not bool(sheet["is_fallback"]) else 0
	var fs: Vector2 = sheet["frame_size"]
	if bool(sheet["is_fallback"]):
		spr.hframes = 1
		spr.vframes = 1
		fs = spr.texture.get_size()
	spr.scale = Vector2.ONE * (size / maxf(fs.x, 1.0))
	var anchor: Vector2 = sheet["anchor"] if not bool(sheet["is_fallback"]) else Vector2(0.5, 0.7)
	spr.offset = Vector2(fs.x * (0.5 - anchor.x), fs.y * (0.5 - anchor.y))
	return spr


## 충돌 없는 장식 소품 (마을 작업실·모집판·좌판 등). [{asset, x, y, frame, size}]
func set_decor(list: Array) -> void:
	for d: Node in _decor_sprites:
		d.queue_free()
	_decor_sprites.clear()
	for d: Dictionary in list:
		var spr := _prop_sprite(String(d.get("asset", "")), int(d.get("frame", 0)), float(d.get("size", 120)))
		spr.position = Vector2(float(d.get("x", 0)), float(d.get("y", 0)))
		add_child(spr)
		_decor_sprites.append(spr)


func _wall_ring_available() -> bool:
	var sheet := AssetRegistry.get_sheet(_wall_asset)
	return int(sheet["hframes"]) >= 9 and not bool(sheet["is_fallback"])


func _tile(L: Node2D, tex: Texture2D, idx: int, pos: Vector2, t: float) -> void:
	L.draw_texture_rect_region(tex, Rect2(pos, Vector2(t, t)), Rect2(idx * 64.0, 0.0, 64.0, 64.0))


## 강둑 링(9장: 0 전체, 1~4 북/동/남/서 경계, 5~8 안쪽 NW/NE/SE/SW 모서리) 과 물가 경계(4장: 풀↑물↓, 물←풀→, 물↑풀↓, 풀←물→)
func _draw_terrain() -> void:
	var L := _terrain
	const T := 64.0
	if _wall_ring_available():
		var tex: Texture2D = AssetRegistry.get_sheet(_wall_asset)["texture"]
		var x0 := floorf(bounds.position.x / T) * T
		var y0 := floorf(bounds.position.y / T) * T
		var x1 := ceilf(bounds.end.x / T) * T
		var y1 := ceilf(bounds.end.y / T) * T
		# 강둑 타일의 투명 여백 아래에 어두운 수풀 바탕을 깐다 (바닥 안쪽은 덮지 않는다)
		var dark := Color(0.13, 0.19, 0.08)
		L.draw_rect(Rect2(x0 - 2 * T, y0 - 2 * T, (x1 - x0) + 4 * T, 2 * T), dark)
		L.draw_rect(Rect2(x0 - 2 * T, y1, (x1 - x0) + 4 * T, 2 * T), dark)
		L.draw_rect(Rect2(x0 - 2 * T, y0, 2 * T, y1 - y0), dark)
		L.draw_rect(Rect2(x1, y0, 2 * T, y1 - y0), dark)
		var x := x0
		while x < x1:
			_tile(L, tex, 0, Vector2(x, y0 - 2 * T), T)
			_tile(L, tex, 0, Vector2(x, y1 + T), T)
			_tile(L, tex, 3, Vector2(x, y0 - T), T)   # 위쪽 강둑: 남쪽 경계가 보인다
			_tile(L, tex, 1, Vector2(x, y1), T)       # 아래쪽 강둑: 북쪽 경계
			x += T
		var y := y0
		while y < y1:
			_tile(L, tex, 0, Vector2(x0 - 2 * T, y), T)
			_tile(L, tex, 0, Vector2(x1 + T, y), T)
			_tile(L, tex, 2, Vector2(x0 - T, y), T)   # 왼쪽 강둑: 동쪽 경계
			_tile(L, tex, 4, Vector2(x1, y), T)       # 오른쪽 강둑: 서쪽 경계
			y += T
		for c in [Vector2(x0 - 2 * T, y0 - T), Vector2(x0 - T, y0 - 2 * T), Vector2(x1, y0 - 2 * T), Vector2(x1 + T, y0 - T), Vector2(x0 - 2 * T, y1), Vector2(x0 - T, y1 + T), Vector2(x1, y1 + T), Vector2(x1 + T, y1)]:
			_tile(L, tex, 0, c, T)
		# 바깥 링의 네 귀퉁이: 볼록 모서리(9~12, v4)가 있으면 그것, 없으면 전체(0)
		var has_outer := int(AssetRegistry.get_sheet(_wall_asset)["hframes"]) >= 13
		_tile(L, tex, 9 if has_outer else 0, Vector2(x0 - 2 * T, y0 - 2 * T), T)
		_tile(L, tex, 10 if has_outer else 0, Vector2(x1 + T, y0 - 2 * T), T)
		_tile(L, tex, 11 if has_outer else 0, Vector2(x1 + T, y1 + T), T)
		_tile(L, tex, 12 if has_outer else 0, Vector2(x0 - 2 * T, y1 + T), T)
		_tile(L, tex, 7, Vector2(x0 - T, y0 - T), T)   # 안쪽 SE 모서리
		_tile(L, tex, 8, Vector2(x1, y0 - T), T)       # 안쪽 SW
		_tile(L, tex, 5, Vector2(x1, y1), T)           # 안쪽 NW
		_tile(L, tex, 6, Vector2(x0 - T, y1), T)       # 안쪽 NE
	var shore := AssetRegistry.get_sheet(_shore_asset)
	if int(shore["hframes"]) >= 4 and not bool(shore["is_fallback"]):
		var stex: Texture2D = shore["texture"]
		for w: Dictionary in _water_rects:
			var wr := Rect2(float(w["x"]), float(w["y"]), float(w["w"]), float(w["h"]))
			if wr.size.x < 2 * T or wr.size.y < 2 * T:
				continue
			var x := wr.position.x
			while x + T <= wr.end.x + 0.01:
				_tile(L, stex, 0, Vector2(x, wr.position.y), T)
				_tile(L, stex, 2, Vector2(x, wr.end.y - T), T)
				x += T
			var y := wr.position.y + T
			while y + T <= wr.end.y - T + 0.01:
				_tile(L, stex, 3, Vector2(wr.position.x, y), T)
				_tile(L, stex, 1, Vector2(wr.end.x - T, y), T)
				y += T
			# 물 사각형 귀퉁이: 물이 육지를 파고드는 오목 모서리(8~11, v4 버들강). 4장짜리 물가(습지·뿌리댐)는 직선만
			if int(shore["hframes"]) >= 12:
				_tile(L, stex, 8, wr.position, T)
				_tile(L, stex, 9, Vector2(wr.end.x - T, wr.position.y), T)
				_tile(L, stex, 10, wr.end - Vector2(T, T), T)
				_tile(L, stex, 11, Vector2(wr.position.x, wr.end.y - T), T)


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
	# 경계 벽: 강둑 타일이 없는 지역(습지·뿌리댐 임시 타일)은 단순 선으로 표시
	if not _wall_ring_available():
		draw_rect(bounds.grow(4), Color(0.25, 0.18, 0.1), false, 8.0)


func _process(dt: float) -> void:
	_telegraph_layer.queue_redraw()
	for gi: Dictionary in ground_items.values():
		gi["t"] = float(gi["t"]) + dt
	for mid: String in _mechanic_fx.keys():
		if not bool(_mechanic_fx[mid].get("active", false)):
			_mechanic_fx[mid]["t"] = float(_mechanic_fx[mid]["t"]) + dt
	# 물 2프레임 잔물결
	if not _water_sprites.is_empty():
		_water_t += dt
		var wf := int(_water_t * 2.0) % 2
		if wf != _water_frame:
			_water_frame = wf
			var tex := AssetRegistry.get_frame_texture(_water_asset, wf)
			for ws: Sprite2D in _water_sprites:
				if is_instance_valid(ws):
					ws.texture = tex
	var i := _effects.get_child_count() - 1
	while i >= 0:
		var fx: Node2D = _effects.get_child(i)
		var t := float(fx.get_meta("t", 0.0)) + dt
		var life := float(fx.get_meta("life", 0.3))
		fx.set_meta("t", t)
		var delay := float(fx.get_meta("delay", 0.0))
		if t < delay:
			i -= 1
			continue
		if delay > 0.0 and not fx.visible:
			fx.visible = true
			fx.set_meta("t", 0.0)
			fx.set_meta("delay", 0.0)
			t = 0.0
		if t >= life:
			fx.queue_free()
		else:
			var spr := fx as Sprite2D
			var fixed := int(fx.get_meta("frame", -1))
			var looping := bool(fx.get_meta("loop", false))
			var hold := bool(fx.get_meta("hold", false))
			var fps := float(fx.get_meta("fps", 8.0))
			if spr != null and spr.hframes > 1:
				if fixed >= 0:
					spr.frame = clampi(fixed, 0, spr.hframes - 1)
				elif looping:
					spr.frame = int(t * fps) % spr.hframes
				elif hold:
					spr.frame = mini(int(t * fps), spr.hframes - 1)
				else:
					spr.frame = mini(int(t / life * spr.hframes), spr.hframes - 1)
			if fixed >= 0 or looping or hold:
				fx.modulate.a = ally_vfx_alpha * clampf((life - t) / 0.35, 0.0, 1.0)
			else:
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
		_draw_frame(L, "prop.sluice_gate", clampi(st, 0, 2), Vector2(rect.position.x + rect.size.x * 0.5, rect.position.y + 10.0), 120.0)
		if st == 2:
			for i in 6:
				var y := rect.position.y + rect.size.y * (i + 0.5) / 6.0
				L.draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), Color(0.7, 0.9, 1.0, 0.35), 2.0)
	# 지역 위험 구역 (수액 웅덩이: 둔화)
	for h: PackedFloat32Array in hazards:
		var hr := Rect2(h[0], h[1], h[2], h[3])
		L.draw_rect(hr, Color(0.45, 0.2, 0.6, 0.28))
		L.draw_rect(hr, Color(0.7, 0.4, 0.9, 0.7), false, 2.0)
		for i in 4:
			var bx := hr.position.x + hr.size.x * (0.2 + 0.2 * i) + sin(Time.get_ticks_msec() / 400.0 + i) * 6.0
			L.draw_circle(Vector2(bx, hr.position.y + hr.size.y * (0.3 + 0.15 * (i % 3))), 4.0, Color(0.8, 0.5, 1.0, 0.5))
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
				_draw_frame(L, "prop.hold_point", 1 if st == 1 else 0, c + Vector2(0, 20), 90.0)
				if prog > 0.0:
					L.draw_arc(c, r + 8, -PI / 2, -PI / 2 + TAU * prog, 48, Color(0.5, 1.0, 0.6, 0.95), 6.0)
			Protocol.ObKind.VOLLEY:
				L.draw_circle(c, r, Color(0.5, 0.9, 0.4, 0.2))
				L.draw_arc(c, r, 0, TAU, 40, Color(0.6, 1.0, 0.5, 0.9), 2.0)
				_draw_frame(L, "vfx.forest_volley", int(prog * 6.0), c, r * 2.2, Color(1, 1, 1, 0.9))
			Protocol.ObKind.TRAP:
				# 설치 [0] → 대기 [1,2] 반복. 발동 [3] 은 서버 trap 이벤트에서 1회 표시한다 (자동 순환 금지)
				if not _draw_frame(L, "vfx.thorn_trap", 0 if st == 0 else 1 + int(Time.get_ticks_msec() / 260) % 2, c, r * 2.0, Color(1, 1, 1, 0.95 if st == 1 else 0.6)):
					_draw_tex(L, _object_tex["trap"], c, r * 2.0, Color(1, 1, 1, 0.9 if st == 1 else 0.5))
			Protocol.ObKind.LANTERN:
				if not _draw_device(L, kind, c, prog, st, 130):
					L.draw_circle(c, 16, Color(1.0, 0.85, 0.4) if st == 1 else Color(0.4, 0.35, 0.3))
				if st == 1:
					L.draw_circle(c, 120, Color(1.0, 0.9, 0.5, 0.08))
				_draw_progress(L, c, prog, "F 점화" if st == 0 else ("켜짐 (꺼지기까지 %d%%)" % int(prog * 100) if prog < 1.0 and prog > 0.0 else "켜짐"))
			Protocol.ObKind.SEED, Protocol.ObKind.FIREFLY:
				if st == 1:
					_draw_device(L, kind, c + Vector2(0, -40), 1.0, 0, 60)   # 운반 중: 머리 위
				elif not _draw_device(L, kind, c, prog, st, 90):
					L.draw_circle(c, 12, Color(0.6, 0.9, 0.4) if kind == Protocol.ObKind.SEED else Color(1.0, 0.95, 0.5))
				if st != 1:
					_draw_progress(L, c, prog, "F 집기" if kind == Protocol.ObKind.SEED else "F 잡기 (도망친다)")
			Protocol.ObKind.VAT:
				if not _draw_device(L, kind, c, prog, st, 130):
					L.draw_circle(c, 26, Color(0.5, 0.4, 0.3))
				_draw_progress(L, c, prog, "혼합통 %d%%" % int(prog * 100))
			Protocol.ObKind.SPORE_NODE:
				if not _draw_device(L, kind, c, prog, st, 120):
					L.draw_circle(c, 20, Color(0.8, 0.5, 0.9))
				if st == 1:
					L.draw_arc(c, 70, 0, TAU, 32, Color(1.0, 0.4, 0.7, 0.8), 3.0)
				_draw_progress(L, c, prog, "맥동 중 — 물러나세요" if st == 1 else "F 끊기")
			Protocol.ObKind.RESONANCE_LOG:
				if not _draw_device(L, kind, c, prog, 0, 120):
					L.draw_circle(c, 22, Color(0.6, 0.45, 0.3))
				L.draw_string(AssetRegistry.get_font("font.ui.main"), c + Vector2(-8, -40), str(st), HORIZONTAL_ALIGNMENT_CENTER, 16, 22, Color(1.0, 0.95, 0.6))
				_draw_progress(L, c, prog, "F %d번째" % st)
			Protocol.ObKind.CRACK:
				if not _draw_device(L, kind, c, prog, st, 120):
					L.draw_circle(c, 18, Color(0.3, 0.6, 0.9) if st == 0 else Color(0.5, 0.4, 0.3))
				_draw_progress(L, c, prog, "F 막기" if st == 0 else "막힘")
			Protocol.ObKind.CHANNEL_PIECE:
				var cur := st & 1
				var tgt := (st >> 1) & 1
				var ok := st == 4
				if not _draw_device(L, kind, c, prog, st, 120):
					L.draw_circle(c, 20, Color(0.6, 1.0, 0.7) if ok else Color.WHITE)
				L.draw_rect(Rect2(c.x - 26, c.y + 28, 24, 10), Color(0.3, 0.6, 1.0) if cur == 1 else Color(0.5, 0.4, 0.3))
				L.draw_rect(Rect2(c.x + 2, c.y + 28, 24, 10), Color(0.3, 0.6, 1.0) if tgt == 1 else Color(0.5, 0.4, 0.3), false, 2.0)
				_draw_progress(L, c + Vector2(0, 10), prog, "연결됨" if ok else "F 방향 전환 (현재→목표)")
			Protocol.ObKind.PARASITE:
				if not _draw_device(L, kind, c, prog, st, 120):
					L.draw_circle(c, 20, Color(0.5, 0.3, 0.2))
				_draw_progress(L, c, prog, "F 뽑기 (묶이면 불가)")
			Protocol.ObKind.ECHO:
				if not _draw_device(L, kind, c, prog, st, 120):
					L.draw_circle(c, 20, Color(0.7, 0.8, 1.0, 0.7))
				L.draw_arc(c, 34, -PI / 2, -PI / 2 + TAU * prog, 32, Color(0.7, 0.85, 1.0, 0.9), 3.0)
				_draw_progress(L, c, prog, "F 붙잡기 (사라지기 전에)")
			Protocol.ObKind.VALVE:
				if not _draw_device(L, kind, c, prog, st, 120):
					L.draw_circle(c, 20, Color(0.8, 0.6, 0.3) if st == 0 else Color(0.6, 1.0, 0.7))
				_draw_progress(L, c, prog, "F 밸브" if st == 0 else "돌림 — 짝을 맞추세요")
			Protocol.ObKind.GAUGE:
				L.draw_rect(Rect2(c.x - 40, c.y - 8, 80, 16), Color(0, 0, 0, 0.6))
				L.draw_rect(Rect2(c.x - 40, c.y - 8, 80 * prog, 16), Color(1.0, 0.3, 0.2) if st == 1 else Color(0.9, 0.7, 0.3))
				_draw_progress(L, c + Vector2(0, 14), prog, "압력 %d%%" % int(prog * 100))
			Protocol.ObKind.DOOR:
				_draw_door(L, c, r, prog, st)
			Protocol.ObKind.SECRET:
				if not _draw_frame(L, "prop.secret", 0, c + Vector2(0, 14), 64.0, Color(1.0, 1.0, 1.0, 0.7 + 0.3 * sin(Time.get_ticks_msec() / 250.0))):
					_draw_tex(L, _object_tex["secret"], c, 56, Color(1.0, 1.0, 1.0, 0.7 + 0.3 * sin(Time.get_ticks_msec() / 250.0)))
				_draw_progress(L, c, prog, "F 조사 (지역 비밀)")
			Protocol.ObKind.RAFT:
				L.draw_circle(c, r + 100, Color(0.9, 0.85, 0.4, 0.06))
				L.draw_arc(c, r + 100, 0, TAU, 48, Color(0.4, 0.9, 0.5, 0.6) if st == 1 else (Color(0.95, 0.4, 0.3, 0.7) if st == 2 else Color(0.9, 0.85, 0.4, 0.5)), 2.0)
				if not _draw_frame(L, "prop.raft", 1 if st == 2 else 0, c + Vector2(0, 20), 110.0):
					_draw_tex(L, _object_tex["raft"], c, 96, Color.WHITE)
				_draw_progress(L, c, prog, "호위 %d%%" % int(prog * 100) + (" · 적 접근!" if st == 2 else (" · 이동 중" if st == 1 else " · 가까이 가세요")))
			Protocol.ObKind.TURRET:
				if not _draw_frame(L, "prop.turret", 2 if st == 1 else 1, c + Vector2(0, 14), 72.0):
					_draw_tex(L, _object_tex["turret"], c + Vector2(0, -10), 64, Color.WHITE if st == 1 else Color(0.85, 0.9, 1.0))
				L.draw_arc(c, 18, -PI / 2, -PI / 2 + TAU * prog, 24, Color(0.4, 0.8, 1.0, 0.9), 3.0)
			Protocol.ObKind.DAM:
				if not _draw_frame(L, "prop.dam", 2 if prog > 0.66 else (1 if prog > 0.33 else 0), c + Vector2(0, 16), r * 2.6):
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
				var scol: Color = [Color.WHITE, Color(1.0, 0.75, 0.6), Color(0.75, 1.0, 0.8)][clampi(st, 0, 2)]
				if not _draw_frame(L, "prop.log_cover", 0 if prog > 0.5 else 1, c + Vector2(0, 16), 84.0, scol):
					_draw_tex(L, _object_tex["structure"], c + Vector2(0, -8), 72, scol)
				if st == 1:
					for i in 6:
						var a := i * TAU / 6.0
						L.draw_line(c + Vector2(cos(a), sin(a)) * (r + 2), c + Vector2(cos(a), sin(a)) * (r + 12), Color(0.9, 0.6, 0.4, 0.9), 2.0)
				elif st == 2:
					L.draw_arc(c, 120, 0, TAU, 48, Color(0.5, 1.0, 0.6, 0.35), 1.5)
				L.draw_rect(Rect2(c.x - 20, c.y - 44, 40, 5), Color(0, 0, 0, 0.6))
				L.draw_rect(Rect2(c.x - 20, c.y - 44, 40 * prog, 5), Color(0.8, 0.6, 0.3))
			Protocol.ObKind.GNAW_TREE:
				if not _draw_frame(L, "prop.gnaw_tree", 0 if prog < 0.34 else 1, c + Vector2(0, 16), 100.0):
					_draw_tex(L, _object_tex["gnaw_tree"], c + Vector2(0, -20), 84, Color.WHITE)
				_draw_progress(L, c, prog, "F 갉기")
			Protocol.ObKind.DEVICE:
				if not _draw_frame(L, "prop.device", 3 if st >= 1 else mini(int(prog * 3.0), 2), c + Vector2(0, 16), 88.0):
					_draw_tex(L, _object_tex["device"], c + Vector2(0, -10), 76, Color.WHITE if st == 0 else Color(0.6, 1.0, 0.7))
				_draw_progress(L, c, prog if st == 0 else 1.0, "F 가동" if st == 0 else "가동 완료")
			Protocol.ObKind.SLUICE_LEVER:
				var lever_up := water_zone.size() >= 5 and int(water_zone[4]) > 0
				if not _draw_frame(L, "prop.lever", 1 if lever_up else 0, c + Vector2(0, 14), 64.0):
					_draw_tex(L, _object_tex["lever"], c + Vector2(0, -10), 60, Color.WHITE)
				_draw_progress(L, c, prog, "F 수문")
			Protocol.ObKind.PILLAR:
				if not _draw_device(L, kind, c, prog, st, 150):
					if not _draw_frame(L, "prop.boss.pillar", 1 if st >= 1 else 0, c + Vector2(0, 16), 100.0):
						_draw_tex(L, _object_tex["pillar"], c + Vector2(0, -30), 100, Color.WHITE if st == 0 else Color(1.0, 0.75, 0.4))
				_draw_progress(L, c, prog, "F 갉기 (약화)" if st == 0 else "약화됨 — 돌진 유도!")
				if st == 1:
					L.draw_arc(c, 40, 0, TAU, 32, Color(1.0, 0.8, 0.3, 0.9), 3.0)
			Protocol.ObKind.GATE:
				var cur := st & 1
				var tgt := (st >> 1) & 1
				var locked := st == 4
				if not _draw_device(L, kind, c, prog, st, 140):
					if not _draw_frame(L, "prop.boss.gate", 2 if cur == 1 else 0, c + Vector2(0, 16), 84.0, Color(0.6, 1.0, 0.7) if locked else Color.WHITE):
						_draw_tex(L, _object_tex["gate"], c + Vector2(0, -20), 80, Color(0.6, 1.0, 0.7) if locked else Color.WHITE)
				L.draw_rect(Rect2(c.x - 26, c.y + 28, 24, 10), Color(0.3, 0.6, 1.0) if cur == 1 else Color(0.5, 0.4, 0.3))
				L.draw_rect(Rect2(c.x + 2, c.y + 28, 24, 10), Color(0.3, 0.6, 1.0) if tgt == 1 else Color(0.5, 0.4, 0.3), false, 2.0)
				_draw_progress(L, c + Vector2(0, 10), prog, "잠김" if locked else ("F 수문 (현재→목표)"))
			Protocol.ObKind.CLAW_LINK:
				if not _draw_device(L, kind, c, prog * 0.5 + (0.5 if st >= 1 else 0.0), 0 if st < 2 else 1, 120):
					if not _draw_frame(L, "prop.boss.claw_link", clampi(st, 0, 2), c + Vector2(0, 14), 64.0):
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
					if not _draw_frame(L, "prop.boss.corridor", 0 if st >= 1 else 1, c + Vector2(0, 16), 96.0):
						_draw_tex(L, _object_tex["corridor"], c, 90, Color.WHITE if st == 0 else Color(0.5, 0.5, 0.5))
				_draw_progress(L, c, prog, "F 통로 차단" if st == 0 else "차단됨")
			Protocol.ObKind.ROPE:
				if not _draw_frame(L, "prop.boss.rope", 1 if st >= 1 else 0, c + Vector2(0, 12), 52.0):
					_draw_tex(L, _object_tex["rope"], c, 44, Color.WHITE if st == 0 else Color(0.6, 1.0, 0.7))
				_draw_progress(L, c, prog, "F 닻줄 연결" if st == 0 else "연결됨")
			Protocol.ObKind.DEBRIS:
				if not _draw_frame(L, "prop.boss.debris", mini(int(prog * 3.0), 2), c + Vector2(0, 14), 84.0):
					_draw_tex(L, _object_tex["debris"], c, 80, Color.WHITE)
				_draw_progress(L, c, prog, "F 잔해 제거")
			Protocol.ObKind.ANCHOR:
				if not _draw_device(L, kind, c, prog, st, 150):
					if not _draw_frame(L, "prop.boss.anchor", 0 if st >= 1 else 1, c + Vector2(0, 16), 84.0):
						_draw_tex(L, _object_tex["anchor"], c + Vector2(0, -20), 80, Color.WHITE if st == 0 else Color(0.6, 1.0, 0.7))
				_draw_progress(L, c, prog, "F 고정 (줄·잔해 먼저)" if st == 0 else "고정됨")
			Protocol.ObKind.PLATFORM:
				if st != 2:
					_draw_frame(L, "vfx.whirlpool", int(Time.get_ticks_msec() / 160) % 4, c, r * 3.2, Color(1, 1, 1, 0.75))
				var pc := Color(0.9, 0.8, 0.4, 0.25) if st == 2 else Color(0.6, 0.5, 0.3, 0.2)
				L.draw_circle(c, r, pc)
				_draw_frame(L, "prop.boss.platform", 0 if st == 2 else 1, c + Vector2(0, r * 0.5), r * 1.8, Color(1, 1, 1, 0.85))
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
				var vb: Array = AssetRegistry.entry("vfx.telegraph_circle").get("visual_bounds_px", [])
				var ring_w := float(vb[0]) if vb.size() >= 1 else float(_tg_tex.get_width())
				var sc := r * 2.0 / maxf(ring_w, 1.0)
				L.draw_set_transform(c, 0.0, Vector2(sc, sc))
				L.draw_texture(_tg_tex, -_tg_tex.get_size() / 2.0, Color(1, 1, 1, 0.5))
				L.draw_set_transform(Vector2.ZERO)
	# 투사체
	for pr: PackedFloat32Array in projectiles:
		var c := Vector2(pr[Protocol.SNAP_PR.X], pr[Protocol.SNAP_PR.Y])
		var ally := int(pr[Protocol.SNAP_PR.KIND]) == 1
		if not _draw_frame(L, "vfx.projectile_pinecone" if ally else "vfx.projectile_sap", int(Time.get_ticks_msec() / 90) % 2, c, pr[Protocol.SNAP_PR.R] * 3.0):
			_draw_tex(L, _object_tex["proj_player"] if ally else _object_tex["proj_enemy"], c, pr[Protocol.SNAP_PR.R] * 3.0, Color.WHITE)
	_draw_ground_items(L)


## 서버 기믹 이벤트를 기억해 장치 시트의 성공/실패 연출을 고른다 (자동 순환하지 않는다)
func mechanic_result(mid: String, success: bool, started: bool = false) -> void:
	if started:
		_mechanic_fx[mid] = {"active": true, "success": false, "t": -1.0}
	else:
		_mechanic_fx[mid] = {"active": false, "success": success, "t": 0.0}


## 장치 시트 프레임을 그린다. 진행 중이면 activation 을 진행률로, 끝났으면 success/failure 를 1회 재생 후 마지막 프레임 유지.
## 시트가 없으면 false 를 돌려 기존 도형 표시로 넘어간다.
## 던파식 문: 통나무 아치 + 집합 반경. 잠기면 어둡게, 목표 방 유형과 인원 집합 상태를 글자로.
func _draw_door(L: Node2D, c: Vector2, r: float, prog: float, st: int) -> void:
	var dir: String = Protocol.DOOR_DIRS[st & 3]
	var ttype: String = Protocol.DOOR_TYPES[clampi((st >> 2) & 15, 0, Protocol.DOOR_TYPES.size() - 1)]
	var cleared := (st >> 6) & 1 == 1
	var locked := (st >> 7) & 1 == 1
	var inside := (st >> 8) & 7
	var along: Vector2 = Vector2(1, 0) if dir in ["n", "s"] else Vector2(0, 1)
	var wood := Color(0.45, 0.3, 0.15) if not locked else Color(0.3, 0.22, 0.14)
	var glow := Color(0.95, 0.85, 0.5, 0.18 + 0.12 * sin(Time.get_ticks_msec() / 300.0)) if not locked else Color(0.2, 0.2, 0.2, 0.12)
	L.draw_circle(c, r, glow)
	L.draw_arc(c, r, 0, TAU, 40, Color(0.95, 0.85, 0.5, 0.7) if not locked else Color(0.4, 0.4, 0.4, 0.5), 2.0)
	# 기둥 두 개와 가로대
	for k: float in [-1.0, 1.0]:
		var pc: Vector2 = c + along * 42.0 * k
		L.draw_rect(Rect2(pc - Vector2(9, 40), Vector2(18, 56)), wood)
		L.draw_rect(Rect2(pc - Vector2(9, 40), Vector2(18, 56)), Color(0.2, 0.12, 0.05), false, 2.0)
	# 가로대(남북 문) 또는 세로 들보(동서 문)
	if along.x != 0.0:
		L.draw_rect(Rect2(c + Vector2(-51, -44), Vector2(102, 14)), wood)
	else:
		L.draw_rect(Rect2(c + Vector2(-7, -51), Vector2(14, 102)), wood)
	if prog > 0.0 and prog < 1.0:
		L.draw_arc(c, r - 6, -PI / 2, -PI / 2 + TAU * prog, 40, Color(0.6, 1.0, 0.6, 0.95), 4.0)
	var font := AssetRegistry.get_font("font.ui.main")
	var tname: String = {"combat": "전투", "elite": "정예", "boss": "보스", "treasure": "보물", "shop": "상점", "rest": "모닥불", "event": "사건", "start": "시작"}.get(ttype, ttype)
	var label := "%s 문 → %s%s" % [{"n": "북", "e": "동", "s": "남", "w": "서"}.get(dir, dir), tname, " (클리어)" if cleared else ""]
	if locked:
		label = "잠김 — 방을 클리어하면 열림"
	elif inside > 0:
		label += "  모임 %d" % inside
	_text(L, font, c + Vector2(-90, r + 16), label, HORIZONTAL_ALIGNMENT_CENTER, 180, 12, Color(1, 1, 0.85, 0.95) if not locked else Color(0.7, 0.7, 0.7, 0.8))


func _draw_device(L: Node2D, kind: int, c: Vector2, progress: float, state: int, size: float) -> bool:
	var key: String = MECHANIC_OF_KIND.get(kind, "")
	if key == "":
		return false
	var mid: String = MECHANIC_ID_OF_KEY.get(key, "IC-" + key.substr(3))
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


## 시트의 프레임 하나를 앵커 기준으로 그린다 (상태 선택형 소품·루프 VFX). 시트가 없으면 false.
func _draw_frame(L: Node2D, id: String, frame: int, c: Vector2, size: float, col: Color = Color.WHITE) -> bool:
	var sheet := AssetRegistry.get_sheet(id)
	if bool(sheet.get("is_fallback", false)):
		return false
	var tex: Texture2D = sheet["texture"]
	var cols := maxi(int(sheet["hframes"]), 1)
	var fi := clampi(frame, 0, cols - 1)
	var fs: Vector2 = sheet["frame_size"]
	var sc := size / fs.x
	var anchor: Vector2 = sheet["anchor"]
	L.draw_set_transform(c - Vector2(fs.x * anchor.x, fs.y * anchor.y) * sc, 0.0, Vector2(sc, sc))
	L.draw_texture_rect_region(tex, Rect2(Vector2.ZERO, fs), Rect2(Vector2(fi * fs.x, 0), fs), col)
	L.draw_set_transform(Vector2.ZERO)
	return true


func _draw_tex(L: Node2D, tex: Texture2D, c: Vector2, size: float, col: Color) -> void:
	if tex == null:
		return
	var sc := size / maxf(tex.get_width(), 1)
	L.draw_set_transform(c, 0.0, Vector2(sc, sc))
	L.draw_texture(tex, -tex.get_size() / 2.0, col)
	L.draw_set_transform(Vector2.ZERO)


## 외곽선 있는 월드 글자 (가독성)
static func _text(L: Node2D, font: Font, pos: Vector2, text: String, align: int, width: float, size: int, col: Color) -> void:
	var sz := maxi(size, 14)
	L.draw_string_outline(font, pos, text, align, width, sz, 4, Color(0.05, 0.03, 0.01, 0.9))
	L.draw_string(font, pos, text, align, width, sz, col)


func _draw_progress(L: Node2D, c: Vector2, prog: float, label: String) -> void:
	if prog > 0.0 and prog < 1.0:
		L.draw_arc(c, 30, -PI / 2, -PI / 2 + TAU * prog, 32, Color(0.6, 1.0, 0.6, 0.95), 4.0)
	var font := AssetRegistry.get_font("font.ui.main")
	_text(L, font, c + Vector2(-40, 44), label, HORIZONTAL_ALIGNMENT_CENTER, 80, 12, Color(1, 1, 0.85, 0.9))


## 짧은 이펙트. 재생 규칙은 시트 메타(loop / hold_last / one_shot)를 따르고, frame>=0 이면 그 프레임만 고정 표시한다.
## size>0 이면 월드 px 폭을 강제한다 (보스 강타 반경 등).
func spawn_effect(asset_id: String, pos: Vector2, rotation_: float = 0.0, life: float = -1.0, size: float = -1.0, frame: int = -1, delay: float = 0.0) -> void:
	var sheet := AssetRegistry.get_sheet(asset_id)
	var spr := Sprite2D.new()
	spr.texture = sheet["texture"]
	spr.hframes = int(sheet["hframes"])
	spr.vframes = int(sheet["vframes"])
	var fs: Vector2 = sheet["frame_size"]
	var rs: Vector2 = sheet["render_size"]
	var fallback := bool(sheet.get("is_fallback", false))
	if fallback:
		spr.hframes = 1
		spr.vframes = 1
		spr.scale = Vector2(0.5, 0.5)
	else:
		spr.scale = (Vector2.ONE * (size / fs.x)) if size > 0.0 else rs / fs
		var anchor: Vector2 = sheet["anchor"]
		spr.offset = Vector2(fs.x * (0.5 - anchor.x), fs.y * (0.5 - anchor.y))
	spr.position = pos
	spr.rotation = rotation_
	var fps := maxf(float(sheet["fps"]), 1.0)
	var looping := bool(sheet["loop"])
	var hold := bool(sheet.get("hold_last", false))
	var default_life := spr.hframes / fps
	if frame >= 0 or looping:
		default_life = 1.0
	spr.set_meta("life", life if life > 0.0 else default_life)
	spr.set_meta("t", 0.0)
	spr.set_meta("fps", fps)
	spr.set_meta("loop", looping)
	spr.set_meta("hold", hold)
	spr.set_meta("frame", frame)
	spr.set_meta("delay", delay)
	if delay > 0.0:
		spr.visible = false
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
			ap.volume_db = (linear_to_db(clampf(sfx_volume, 0.0, 1.0)) + float(AssetRegistry.entry(asset_id).get("gain_db", 0.0))) if sfx_volume > 0.001 else -80.0
			ap.play()
			_audio_last[asset_id] = now
			return


## 마을 NPC 표시 (서버가 hub_info 로 준 위치·이름). 상호작용 범위 안이면 안내 링을 그린다.
func set_npcs(list: Array) -> void:
	for sp: Node in _npc_sprites:
		sp.queue_free()
	_npc_sprites.clear()
	npcs = list
	for n: Dictionary in list:
		var spr := Sprite2D.new()
		spr.texture = AssetRegistry.get_texture(String(n.get("sprite", "npc.elder_zelkova")))
		spr.position = Vector2(float(n.get("x", 0)), float(n.get("y", 0)))
		spr.scale = Vector2.ONE * (96.0 / maxf(spr.texture.get_width(), 1))
		spr.offset = Vector2(0, -40)
		add_child(spr)
		_npc_sprites.append(spr)
		var lbl := Label.new()
		lbl.text = String(n.get("name_ko", ""))
		lbl.add_theme_font_override("font", AssetRegistry.get_font("font.ui.main"))
		lbl.add_theme_font_size_override("font_size", 13)
		lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.6))
		lbl.position = spr.position + Vector2(-40, -110)
		lbl.custom_minimum_size = Vector2(80, 0)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(lbl)
		_npc_sprites.append(lbl)


func nearest_npc(pos: Vector2, max_d: float) -> Dictionary:
	var best: Dictionary = {}
	var best_d := max_d
	for n: Dictionary in npcs:
		var d := Vector2(float(n.get("x", 0)), float(n.get("y", 0))).distance_to(pos)
		if d <= best_d:
			best_d = d
			best = n
	return best


# ------------------------------------------------------------------ 바닥 장비 (Hero Siege 식: 등급 색 빛기둥 + 아이콘 + 이름표)

func set_ground_items(list: Array) -> void:
	ground_items.clear()
	for e: Dictionary in list:
		_add_ground(e, false)


func ground_spawn(e: Dictionary) -> void:
	_add_ground(e, true)


## 개인 드랍은 주인에게만 보인다. 공용(버린 장비, owner "")은 모두에게.
func ground_visible(e: Dictionary) -> bool:
	var owner := String(e.get("owner", ""))
	return owner == "" or owner == local_id


func _add_ground(e: Dictionary, animate: bool) -> void:
	if not ground_visible(e):
		return
	var pos := Vector2(float(e.get("x", 0)), float(e.get("y", 0)))
	var from := Vector2(float(e.get("fx", pos.x)), float(e.get("fy", pos.y))) if animate else pos
	ground_items[int(e.get("gid", 0))] = {"pos": pos, "from": from, "rarity": String(e.get("rarity", "common")), "base": String(e.get("base", "")),
		"name": String(e.get("name", "")), "slot": String(e.get("slot", "")), "enh": int(e.get("enh", 0)), "t": 0.0 if animate else 9.0}


func ground_remove(gid: int) -> Dictionary:
	var gi: Dictionary = ground_items.get(gid, {})
	ground_items.erase(gid)
	return gi


## 살아 있는 적이 r 안에 있으면 true (자동 공격 판단용)
func enemy_within(pos: Vector2, r: float) -> bool:
	for key: String in entities.keys():
		if not key.begins_with("e:"):
			continue
		var ev: EntityView = entities[key]
		if ev.ai_state == Protocol.EnemyAI.DEAD or ev.boss_state == BossIronclaw.BS.DEAD:
			continue
		if ev.position.distance_to(pos) <= r:
			return true
	return false


func _draw_ground_items(L: Node2D) -> void:
	if ground_items.is_empty():
		return
	var font := AssetRegistry.get_font("font.ui.main")
	var now := Time.get_ticks_msec() / 1000.0
	for gid: int in ground_items.keys():
		var gi: Dictionary = ground_items[gid]
		var rarity := String(gi["rarity"])
		var ri := Equipment.rarity_index(rarity)
		var col := Equipment.rarity_color(rarity)
		var t := float(gi["t"])
		var k := clampf(t / 0.55, 0.0, 1.0)
		var c: Vector2 = (gi["from"] as Vector2).lerp(gi["pos"], k)
		var hop := -70.0 * sin(PI * k)   # 시체에서 튀어나와 포물선으로 떨어진다
		var phase := now * 2.5 + float(gid)
		# 바닥 빛 웅덩이
		L.draw_set_transform(c, 0.0, Vector2(1.0, 0.45))
		L.draw_circle(Vector2.ZERO, 16.0 + 4.0 * ri, Color(col, 0.22 + 0.08 * sin(phase)))
		L.draw_arc(Vector2.ZERO, 18.0 + 4.0 * ri, 0.0, TAU, 32, Color(col, 0.75), 2.0)
		L.draw_set_transform(Vector2.ZERO)
		# 빛기둥: 고급 이상. 등급이 높을수록 굵고 길고 밝다
		if ri >= 1 and k >= 1.0:
			var h := 80.0 + 30.0 * ri
			var w := 8.0 + 4.0 * ri
			var pulse := 0.7 + 0.3 * sin(phase)
			for si in 8:
				var f := float(si) / 8.0
				var seg_w := w * (1.0 + f * 1.4)
				L.draw_rect(Rect2(c.x - seg_w * 0.5, c.y - h * (f + 0.125), seg_w, h * 0.125 + 1.0), Color(col.lightened(0.15), (0.75 - 0.06 * (4 - ri)) * (1.0 - f) * pulse))
			if ri >= 3:
				for si in 6:
					var a := phase * 0.8 + si * TAU / 6.0
					var sp := c + Vector2(cos(a) * (14.0 + 6.0 * ri), -30.0 - 25.0 * (0.5 + 0.5 * sin(a * 1.7 + si)))
					L.draw_circle(sp, 2.0 if ri == 3 else 2.6, Color(1.0, 0.98, 0.85, 0.85))
			if ri >= 4:
				L.draw_arc(c, 26.0 + 6.0 * sin(phase * 1.3), 0.0, TAU, 40, Color(col, 0.55), 2.0)
		# 아이콘 (등급이 높을수록 조금 크다)
		var size := 26.0 + 3.0 * ri
		var bob := sin(now * 2.0 + float(gid)) * 3.0
		var ic := c + Vector2(0.0, -20.0 + bob + hop)
		var icon_id := "icon.gear." + String(gi["base"])
		if AssetRegistry.has(icon_id) and AssetRegistry.status(icon_id) == "final":
			_draw_tex(L, AssetRegistry.get_texture(icon_id), ic, size, Color.WHITE)
		else:
			L.draw_circle(ic, size * 0.4, col)
		# 이름표: 고급 이상은 항상, 일반은 가까이 갔을 때만
		if ri >= 1 or local_pos.distance_to(c) < 140.0:
			var label := String(gi["name"]) + ((" +%d" % int(gi["enh"])) if int(gi["enh"]) > 0 else "")
			_text(L, font, ic + Vector2(-100.0, -size * 0.5 - 6.0), label, HORIZONTAL_ALIGNMENT_CENTER, 200.0, 14, col.lightened(0.25) if ri > 0 else Color(0.95, 0.95, 0.9))
		# 착지 파동 (희귀 이상)
		if ri >= 2 and t > 0.5 and t < 1.2:
			var q := (t - 0.5) / 0.7
			L.draw_arc(c, 10.0 + 60.0 * q, 0.0, TAU, 40, Color(col, 0.85 * (1.0 - q)), 3.0 * (1.0 - q) + 1.0)


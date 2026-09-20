extends SceneTree
## 임시(placeholder) 에셋 생성기. asset_manifest.json 의 `placeholder` 레시피대로 도형 PNG 와 합성 WAV 를 만든다.
## 실행: godot --headless --path . -s tools/gen_placeholders.gd
## 생성물은 "임시 도형" 이며 최종 캐릭터 에셋이 아니다 (17절). 최종 에셋은 같은 ID·규격으로 교체한다.

const MANIFEST := "res://assets/asset_manifest.json"


func _init() -> void:
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(MANIFEST)) != OK:
		push_error("manifest parse failed")
		quit(1)
		return
	var manifest: Dictionary = json.data
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/placeholders"))
	var made := 0
	var skipped := 0
	for e: Dictionary in manifest["assets"]:
		if e.get("status", "") != "placeholder" or String(e.get("path", "")) == "":
			skipped += 1
			continue
		var ok := false
		match String(e.get("type", "texture")):
			"audio":
				ok = _gen_audio(e)
			_:
				ok = _gen_image(e)
		if ok:
			made += 1
		else:
			push_error("failed: " + String(e["id"]))
	print("placeholders generated=%d skipped=%d" % [made, skipped])
	quit(0)


# ---------------------------------------------------------------- images

func _gen_image(e: Dictionary) -> bool:
	var fw: int = int(e["frame_size"][0])
	var fh: int = int(e["frame_size"][1])
	var cols: int = int(e.get("columns", 1))
	var rows: int = int(e.get("rows", 1))
	var img := Image.create(fw * cols, fh * rows, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var ph: Dictionary = e.get("placeholder", {})
	var shape: String = ph.get("shape", "box")
	for row in rows:
		for col in cols:
			var frame := Image.create(fw, fh, false, Image.FORMAT_RGBA8)
			frame.fill(Color(0, 0, 0, 0))
			_draw_frame(frame, shape, ph, e, col, row, cols)
			img.blit_rect(frame, Rect2i(0, 0, fw, fh), Vector2i(col * fw, row * fh))
	var abs_path := ProjectSettings.globalize_path(String(e["path"]))
	return img.save_png(abs_path) == OK


func _draw_frame(img: Image, shape: String, ph: Dictionary, e: Dictionary, frame: int, row: int, frames: int) -> void:
	match shape:
		"beaver": _draw_beaver(img, ph, frame, row, frames)
		"snail": _draw_snail(img, ph, frame, row, frames)
		"icon": _draw_icon(img, ph)
		"portrait": _draw_portrait(img, ph)
		"tile_ground": _draw_tile_ground(img, ph, String(e["id"]))
		"tile_wall": _draw_tile_wall(img, ph)
		"tile_water": _draw_tile_water(img, ph)
		"log": _draw_log(img, ph)
		"rock": _draw_rock(img, ph)
		"tree": _draw_tree(img, ph)
		"ring": _draw_ring_asset(img, ph)
		"spark": _draw_spark(img, ph, frame, frames)
		"arc": _draw_arc_vfx(img, ph, frame, frames)
		"shockwave": _draw_shockwave(img, ph, frame, frames)
		"halfring": _draw_halfring(img, ph)
		"panel": _draw_panel(img, ph)
		_: _fill_rect(img, 4, 4, img.get_width() - 8, img.get_height() - 8, Color.MAGENTA)


func _c(hex: String) -> Color:
	return Color.html(hex)


func _blend(img: Image, x: int, y: int, c: Color) -> void:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return
	if c.a >= 0.999:
		img.set_pixel(x, y, c)
		return
	var d := img.get_pixel(x, y)
	img.set_pixel(x, y, d.blend(c))


func _fill_rect(img: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	for yy in range(y, y + h):
		for xx in range(x, x + w):
			_blend(img, xx, yy, c)


func _fill_ellipse(img: Image, cx: float, cy: float, rx: float, ry: float, c: Color) -> void:
	for yy in range(int(cy - ry) - 1, int(cy + ry) + 2):
		for xx in range(int(cx - rx) - 1, int(cx + rx) + 2):
			var dx := (xx + 0.5 - cx) / rx
			var dy := (yy + 0.5 - cy) / ry
			if dx * dx + dy * dy <= 1.0:
				_blend(img, xx, yy, c)


func _fill_circle(img: Image, cx: float, cy: float, r: float, c: Color) -> void:
	_fill_ellipse(img, cx, cy, r, r, c)


func _ring(img: Image, cx: float, cy: float, r_out: float, r_in: float, c: Color, a0_deg: float = -180.0, a1_deg: float = 180.0) -> void:
	for yy in range(int(cy - r_out) - 1, int(cy + r_out) + 2):
		for xx in range(int(cx - r_out) - 1, int(cx + r_out) + 2):
			var dx := xx + 0.5 - cx
			var dy := yy + 0.5 - cy
			var d := sqrt(dx * dx + dy * dy)
			if d <= r_out and d >= r_in:
				var ang := rad_to_deg(atan2(dy, dx))
				if ang >= a0_deg and ang <= a1_deg:
					_blend(img, xx, yy, c)


func _triangle(img: Image, a: Vector2, b: Vector2, c_: Vector2, col: Color) -> void:
	var minx := int(min(a.x, b.x, c_.x))
	var maxx := int(max(a.x, b.x, c_.x)) + 1
	var miny := int(min(a.y, b.y, c_.y))
	var maxy := int(max(a.y, b.y, c_.y)) + 1
	for yy in range(miny, maxy):
		for xx in range(minx, maxx):
			var p := Vector2(xx + 0.5, yy + 0.5)
			var d1 := _sign(p, a, b)
			var d2 := _sign(p, b, c_)
			var d3 := _sign(p, c_, a)
			var has_neg := d1 < 0 or d2 < 0 or d3 < 0
			var has_pos := d1 > 0 or d2 > 0 or d3 > 0
			if not (has_neg and has_pos):
				_blend(img, xx, yy, col)


func _sign(p: Vector2, a: Vector2, b: Vector2) -> float:
	return (p.x - b.x) * (a.y - b.y) - (a.x - b.x) * (p.y - b.y)


## 비버: 둥근 몸, 넓은 꼬리, 앞니, 직업 무기. row: 0=down 1=up 2=left 3=right
func _draw_beaver(img: Image, ph: Dictionary, frame: int, row: int, frames: int) -> void:
	var body := _c(ph.get("body", "#8a5a2b"))
	var belly := body.lightened(0.3)
	var dark := body.darkened(0.35)
	var accent := _c(ph.get("accent", "#e2b04a"))
	var anim: String = ph.get("anim", "idle")
	var bob := 0.0
	if anim == "walk":
		bob = [0.0, -3.0, 0.0, -3.0][frame % 4]
	elif anim == "idle":
		bob = [0.0, -1.0][frame % 2]
	var facing: Vector2 = [Vector2(0, 1), Vector2(0, -1), Vector2(-1, 0), Vector2(1, 0)][row]
	var cx := 64.0
	var feet_y := 105.0
	# 그림자
	_fill_ellipse(img, cx, feet_y + 1, 22, 6, Color(0, 0, 0, 0.28))
	if anim == "down":
		_fill_ellipse(img, cx, 92, 32, 14, body)
		_fill_circle(img, cx + facing.x * 26 - (0 if facing.x != 0 else 22), 88, 14, body)
		_fill_ellipse(img, cx - facing.x * 30 + (0 if facing.x != 0 else 22), 92, 12, 8, dark)
		_fill_rect(img, int(cx) - 14, 80, 6, 2, Color.BLACK)
		_fill_rect(img, int(cx) - 6, 80, 6, 2, Color.BLACK)
		return
	var body_cy := 78.0 + bob
	var head_cy := 52.0 + bob
	# 꼬리: 바라보는 방향의 반대쪽 (납작하고 넓게)
	var tail_off := -facing * 26
	if row == 1:
		_fill_ellipse(img, cx, body_cy + 22, 16, 9, dark)
	else:
		_fill_ellipse(img, cx + tail_off.x, body_cy + tail_off.y * 0.75, 16 if row < 2 else 10, 9 if row < 2 else 14, dark)
	# 몸통·배·머리
	_fill_ellipse(img, cx, body_cy, 24, 22, body)
	if row != 1:
		_fill_ellipse(img, cx + facing.x * 4, body_cy + 5, 13, 12, belly)
	_fill_circle(img, cx + facing.x * 2, head_cy, 18, body)
	_fill_circle(img, cx - 13, head_cy - 12, 5, body)
	_fill_circle(img, cx + 13, head_cy - 12, 5, body)
	# 눈·앞니
	var eye := Color(0.1, 0.07, 0.05)
	var tooth := Color(0.98, 0.96, 0.9)
	match row:
		0:
			_fill_circle(img, cx - 7, head_cy - 2, 2.2, eye)
			_fill_circle(img, cx + 7, head_cy - 2, 2.2, eye)
			_fill_rect(img, int(cx) - 4, int(head_cy) + 7, 3, 7, tooth)
			_fill_rect(img, int(cx) + 1, int(head_cy) + 7, 3, 7, tooth)
		2:
			_fill_circle(img, cx - 9, head_cy - 2, 2.2, eye)
			_fill_rect(img, int(cx) - 16, int(head_cy) + 5, 3, 6, tooth)
		3:
			_fill_circle(img, cx + 9, head_cy - 2, 2.2, eye)
			_fill_rect(img, int(cx) + 13, int(head_cy) + 5, 3, 6, tooth)
	# 무기 (직업 강조색). 공격 프레임에서는 바라보는 방향으로 휘두른다.
	var swing := 0.0
	if anim == "attack":
		swing = [-8.0, 4.0, 18.0, 10.0][frame % 4]
	var hand: Vector2 = Vector2(cx, body_cy) + Vector2(-facing.y, facing.x) * 22 + facing * swing
	if row == 1:
		hand = Vector2(cx - 20, body_cy - 6 + swing * -1)
	_draw_weapon(img, hand, facing, String(ph.get("weapon", "hammer")), accent, dark)
	# 시전: 강조색 링
	if anim == "cast":
		var r := 26.0 + frame * 5.0
		_ring(img, cx, body_cy, r, r - 3, Color(accent, 0.8 - frame * 0.15))
	if anim == "hit":
		_fill_ellipse(img, cx, body_cy, 24, 22, Color(1, 0.2, 0.2, 0.35))
		_fill_circle(img, cx, head_cy, 18, Color(1, 0.2, 0.2, 0.35))
	# 걷기: 발
	if anim == "walk":
		var step: float = [3.0, -3.0, 3.0, -3.0][frame % 4]
		_fill_ellipse(img, cx - 9, feet_y - 2 + step, 6, 4, dark)
		_fill_ellipse(img, cx + 9, feet_y - 2 - step, 6, 4, dark)
	# 방향 표식 (임시 가독성용 삼각형)
	var tip: Vector2 = Vector2(cx, feet_y + 10) + facing * 8
	_triangle(img, tip, tip - facing * 6 + Vector2(-facing.y, facing.x) * 4, tip - facing * 6 - Vector2(-facing.y, facing.x) * 4, Color(accent, 0.9))


func _draw_weapon(img: Image, hand: Vector2, _facing: Vector2, weapon: String, accent: Color, dark: Color) -> void:
	match weapon:
		"hammer":
			_fill_rect(img, int(hand.x) - 2, int(hand.y) - 14, 4, 20, dark)
			_fill_rect(img, int(hand.x) - 8, int(hand.y) - 18, 16, 8, accent)
		"axe":
			_fill_rect(img, int(hand.x) - 2, int(hand.y) - 14, 4, 20, dark)
			_triangle(img, hand + Vector2(2, -18), hand + Vector2(12, -12), hand + Vector2(2, -6), accent)
		"sling":
			_fill_rect(img, int(hand.x) - 2, int(hand.y) - 12, 4, 16, dark)
			_fill_circle(img, hand.x, hand.y - 14, 4, accent)
		"staff":
			_fill_rect(img, int(hand.x) - 2, int(hand.y) - 22, 4, 30, dark)
			_fill_circle(img, hand.x, hand.y - 22, 5, accent)
		"nozzle":
			_fill_rect(img, int(hand.x) - 3, int(hand.y) - 6, 6, 14, dark)
			_fill_rect(img, int(hand.x) - 5, int(hand.y) - 12, 10, 6, accent)
		_:
			_fill_rect(img, int(hand.x) - 2, int(hand.y) - 10, 4, 14, accent)
	pass


func _draw_snail(img: Image, ph: Dictionary, frame: int, row: int, frames: int) -> void:
	var body := _c(ph.get("body", "#c9a26b"))
	var shell := _c(ph.get("shell", "#7b4fa0"))
	var anim: String = ph.get("anim", "idle")
	var facing: Vector2 = [Vector2(0, 1), Vector2(0, -1), Vector2(-1, 0), Vector2(1, 0)][row]
	var cx := 64.0
	var cy := 76.0
	var lunge := 0.0
	if anim == "attack":
		lunge = [-4.0, 2.0, 14.0, 8.0][frame % 4]
	elif anim == "walk":
		lunge = [0.0, 3.0, 0.0, -2.0][frame % 4]
	var alpha := 1.0
	if anim == "death":
		alpha = [0.8, 0.4][frame % 2]
	_fill_ellipse(img, cx, 105, 24, 6, Color(0, 0, 0, 0.25 * alpha))
	var bpos: Vector2 = Vector2(cx, cy + 14) + facing * (14 + lunge)
	_fill_ellipse(img, bpos.x, bpos.y, 20, 11, Color(body, alpha))
	# 더듬이
	var eye := Color(0.15, 0.1, 0.2, alpha)
	var e1: Vector2 = bpos + facing * 14 + Vector2(-facing.y, facing.x) * 6
	var e2: Vector2 = bpos + facing * 14 - Vector2(-facing.y, facing.x) * 6
	_fill_rect(img, int(e1.x) - 1, int(e1.y) - 10, 2, 10, Color(body, alpha))
	_fill_rect(img, int(e2.x) - 1, int(e2.y) - 10, 2, 10, Color(body, alpha))
	_fill_circle(img, e1.x, e1.y - 10, 2.5, eye)
	_fill_circle(img, e2.x, e2.y - 10, 2.5, eye)
	# 껍질 (검은 수액 보라색) + 나선
	var spos: Vector2 = Vector2(cx, cy) - facing * 4
	_fill_circle(img, spos.x, spos.y, 22, Color(shell, alpha))
	_ring(img, spos.x, spos.y, 14, 11, Color(shell.darkened(0.4), alpha))
	_ring(img, spos.x, spos.y, 6, 3, Color(shell.darkened(0.4), alpha))
	if anim == "death":
		_fill_rect(img, int(spos.x) - 2, int(spos.y) - 22, 3, 44, Color(0.1, 0.05, 0.15, alpha))
		_fill_rect(img, int(spos.x) - 22, int(spos.y) - 1, 44, 3, Color(0.1, 0.05, 0.15, alpha))
	if anim == "hit":
		_fill_circle(img, spos.x, spos.y, 22, Color(1, 0.3, 0.3, 0.4))
	if anim == "attack" and frame == 2:
		var tip: Vector2 = bpos + facing * 20
		_triangle(img, tip + facing * 8, tip + Vector2(-facing.y, facing.x) * 8, tip - Vector2(-facing.y, facing.x) * 8, Color(1, 0.45, 0.2, 0.9))
	pass


func _rounded_rect(img: Image, x: int, y: int, w: int, h: int, r: int, c: Color) -> void:
	_fill_rect(img, x + r, y, w - 2 * r, h, c)
	_fill_rect(img, x, y + r, w, h - 2 * r, c)
	_fill_circle(img, x + r, y + r, r, c)
	_fill_circle(img, x + w - r, y + r, r, c)
	_fill_circle(img, x + r, y + h - r, r, c)
	_fill_circle(img, x + w - r, y + h - r, r, c)


func _draw_icon(img: Image, ph: Dictionary) -> void:
	var col := _c(ph.get("color", "#e2b04a"))
	var s := img.get_width()
	_rounded_rect(img, 2, 2, s - 4, s - 4, 10, col.darkened(0.55))
	_rounded_rect(img, 5, 5, s - 10, s - 10, 8, col.darkened(0.2))
	var c := s / 2.0
	var light := col.lightened(0.5)
	match String(ph.get("glyph", "")):
		"beaver":
			_fill_circle(img, c, c - 2, 14, col.lightened(0.15))
			_fill_rect(img, int(c) - 5, int(c) + 6, 4, 7, Color.WHITE)
			_fill_rect(img, int(c) + 1, int(c) + 6, 4, 7, Color.WHITE)
			_fill_circle(img, c - 6, c - 5, 2, Color.BLACK)
			_fill_circle(img, c + 6, c - 5, 2, Color.BLACK)
		"shield":
			_ring(img, c, c, 20, 12, light, -150, -30)
			_fill_rect(img, int(c) - 14, int(c) - 2, 28, 5, light)
		"wave":
			_ring(img, c, c, 22, 18, light)
			_ring(img, c, c, 13, 9, light)
			_fill_circle(img, c, c, 4, light)
		"tree":
			_triangle(img, Vector2(c, c - 22), Vector2(c - 18, c + 10), Vector2(c + 18, c + 10), light)
			_fill_rect(img, int(c) - 4, int(c) + 10, 8, 12, col.darkened(0.6))
		"plus":
			_fill_rect(img, int(c) - 4, int(c) - 18, 8, 36, light)
			_fill_rect(img, int(c) - 18, int(c) - 4, 36, 8, light)
		"dash":
			for i in 3:
				_fill_rect(img, int(c) - 18 + i * 4, int(c) - 12 + i * 10, 30 - i * 8, 5, light)
		"snail":
			_fill_circle(img, c - 4, c - 4, 14, light)
			_ring(img, c - 4, c - 4, 8, 5, col.darkened(0.5))
			_fill_ellipse(img, c + 8, c + 12, 14, 7, col.lightened(0.25))
		_:
			_fill_circle(img, c, c, 12, light)


func _draw_portrait(img: Image, ph: Dictionary) -> void:
	var body := _c(ph.get("body", "#8a5a2b"))
	var accent := _c(ph.get("accent", "#e2b04a"))
	var s := img.get_width()
	var c := s / 2.0
	_rounded_rect(img, 0, 0, s, s, 24, Color(0.16, 0.13, 0.1, 1))
	_fill_ellipse(img, c, c + 70, 96, 60, body)
	_fill_circle(img, c, c - 10, 80, body)
	_fill_circle(img, c - 62, c - 66, 22, body)
	_fill_circle(img, c + 62, c - 66, 22, body)
	_fill_circle(img, c - 30, c - 18, 10, Color(0.1, 0.07, 0.05))
	_fill_circle(img, c + 30, c - 18, 10, Color(0.1, 0.07, 0.05))
	_fill_circle(img, c, c + 12, 12, Color(0.15, 0.1, 0.08))
	_fill_rect(img, int(c) - 18, int(c) + 22, 14, 28, Color(0.98, 0.96, 0.9))
	_fill_rect(img, int(c) + 4, int(c) + 22, 14, 28, Color(0.98, 0.96, 0.9))
	_fill_rect(img, int(c) - 90, s - 22, 180, 10, accent)


func _draw_tile_ground(img: Image, ph: Dictionary, seed_id: String) -> void:
	var base := _c(ph.get("color", "#6f8f4a"))
	var dot := _c(ph.get("dot", "#8aa860"))
	img.fill(base)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_id)
	for i in 36:
		var x := rng.randi_range(0, img.get_width() - 1)
		var y := rng.randi_range(0, img.get_height() - 1)
		_fill_circle(img, x, y, rng.randf_range(1.0, 2.5), Color(dot, 0.7))
	for i in 6:
		var x := rng.randi_range(0, img.get_width() - 1)
		var y := rng.randi_range(0, img.get_height() - 1)
		_fill_ellipse(img, x, y, 4, 2, Color(base.darkened(0.2), 0.6))


func _draw_tile_wall(img: Image, ph: Dictionary) -> void:
	var base := _c(ph.get("color", "#4a3a2a"))
	var edge := _c(ph.get("edge", "#7a6248"))
	img.fill(base)
	_fill_rect(img, 0, 0, img.get_width(), 8, edge)
	for i in 3:
		_fill_rect(img, 6 + i * 20, 20, 14, 10, base.lightened(0.12))
		_fill_rect(img, 14 + i * 20, 40, 14, 10, base.lightened(0.08))


func _draw_tile_water(img: Image, ph: Dictionary) -> void:
	var base := _c(ph.get("color", "#3b7fd9"))
	var wave := _c(ph.get("wave", "#7fb6ef"))
	img.fill(base)
	var w := img.get_width()
	for x in w:
		for k in 3:
			var y := int(10 + k * 20 + sin((x / float(w)) * TAU + k) * 3.0)
			_blend(img, x, y, wave)
			_blend(img, x, y + 1, Color(wave, 0.5))


func _draw_log(img: Image, ph: Dictionary) -> void:
	var col := _c(ph.get("color", "#7a5230"))
	_fill_ellipse(img, 64, 96, 50, 10, Color(0, 0, 0, 0.25))
	_fill_ellipse(img, 64, 72, 50, 18, col)
	_fill_circle(img, 112, 72, 16, col.lightened(0.35))
	_ring(img, 112, 72, 10, 8, col.darkened(0.3))
	_ring(img, 112, 72, 4, 2, col.darkened(0.3))


func _draw_rock(img: Image, ph: Dictionary) -> void:
	var col := _c(ph.get("color", "#7d7d7d"))
	_fill_ellipse(img, 64, 96, 44, 10, Color(0, 0, 0, 0.25))
	_fill_ellipse(img, 64, 68, 46, 34, col)
	_fill_ellipse(img, 52, 54, 20, 12, col.lightened(0.25))


func _draw_tree(img: Image, ph: Dictionary) -> void:
	# 기억나무: 굵은 둥치 + 둥근 수관 + 빛나는 기억 조각
	var trunk := _c(ph.get("color", "#5a3d22"))
	var leaf := _c(ph.get("leaf", "#6fae5a"))
	var glow := _c(ph.get("glow", "#e8d27a"))
	var s := img.get_width()
	var c := s / 2.0
	_fill_ellipse(img, c, s * 0.86, s * 0.34, s * 0.07, Color(0, 0, 0, 0.28))
	_fill_rect(img, int(c - s * 0.07), int(s * 0.45), int(s * 0.14), int(s * 0.42), trunk)
	_fill_ellipse(img, c, s * 0.86, s * 0.16, s * 0.05, trunk.darkened(0.2))
	_fill_circle(img, c - s * 0.16, s * 0.40, s * 0.17, leaf.darkened(0.1))
	_fill_circle(img, c + s * 0.16, s * 0.40, s * 0.17, leaf.darkened(0.1))
	_fill_circle(img, c, s * 0.28, s * 0.22, leaf)
	_fill_circle(img, c - s * 0.06, s * 0.22, s * 0.08, leaf.lightened(0.25))
	for i in 5:
		var a := i * TAU / 5.0
		_fill_circle(img, c + cos(a) * s * 0.2, s * 0.32 + sin(a) * s * 0.12, s * 0.02, glow)


func _draw_ring_asset(img: Image, ph: Dictionary) -> void:
	var col := _c(ph.get("color", "#ff7a3d"))
	var fill := _c(ph.get("fill", "#ff7a3d40"))
	var c := img.get_width() / 2.0
	_fill_circle(img, c, c, c - 4, fill)
	_ring(img, c, c, c - 2, c - 8, col)


func _draw_spark(img: Image, ph: Dictionary, frame: int, frames: int) -> void:
	var col := _c(ph.get("color", "#fff1a8"))
	var c := img.get_width() / 2.0
	var r := 10.0 + frame * 12.0
	var a := 1.0 - frame / float(max(frames, 1)) * 0.7
	for i in 8:
		var ang := i * TAU / 8.0
		var d := Vector2(cos(ang), sin(ang))
		var p0 := Vector2(c, c) + d * r * 0.4
		var p1 := Vector2(c, c) + d * r
		var n := Vector2(-d.y, d.x) * 2.5
		_triangle(img, p0 + n, p0 - n, p1, Color(col, a))
	_fill_circle(img, c, c, maxf(8.0 - frame * 2.0, 2.0), Color(1, 1, 1, a))


func _draw_arc_vfx(img: Image, ph: Dictionary, frame: int, frames: int) -> void:
	var col := _c(ph.get("color", "#e2b04a"))
	var c := img.get_width() / 2.0
	var r := c - 6
	var a0 := -60.0 + frame * 30.0
	_ring(img, c, c, r, r - 18, Color(col, 0.75), a0, a0 + 50.0)
	pass


func _draw_shockwave(img: Image, ph: Dictionary, frame: int, frames: int) -> void:
	var col := _c(ph.get("color", "#c9a26b"))
	var c := img.get_width() / 2.0
	var t := (frame + 1) / float(max(frames, 1))
	var r := c * t
	_ring(img, c, c, r, maxf(r - 14, 0), Color(col, 0.9 - t * 0.6))
	if r > 30:
		_ring(img, c, c, r - 24, maxf(r - 30, 0), Color(col, 0.4 - t * 0.3))


func _draw_halfring(img: Image, ph: Dictionary) -> void:
	var col := _c(ph.get("color", "#8a5a2b"))
	var c := img.get_width() / 2.0
	_ring(img, c, c, c - 4, c - 18, Color(col, 0.9), -75, 75)
	_ring(img, c, c, c - 8, c - 14, Color(col.lightened(0.4), 0.9), -70, 70)


func _draw_panel(img: Image, ph: Dictionary) -> void:
	var col := _c(ph.get("color", "#2c2419"))
	var border := _c(ph.get("border", "#8a6a45"))
	var s := img.get_width()
	_rounded_rect(img, 0, 0, s, s, 10, border)
	_rounded_rect(img, 3, 3, s - 6, s - 6, 8, col)


# ---------------------------------------------------------------- audio

func _gen_audio(e: Dictionary) -> bool:
	var ph: Dictionary = e.get("placeholder", {})
	var kind: String = ph.get("kind", "chime")
	var freq := float(ph.get("freq", 440))
	var length := float(ph.get("len", 0.2))
	var rate := 22050
	var n := int(rate * length)
	var pcm := PackedByteArray()
	pcm.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(e["id"]))
	for i in n:
		var t := i / float(rate)
		var env := 1.0 - t / length
		var v := 0.0
		match kind:
			"thud":
				v = sin(TAU * freq * t * (1.0 - t * 2.0)) * env * env + rng.randf_range(-0.2, 0.2) * env * env * env
			"squish":
				v = rng.randf_range(-1.0, 1.0) * env * env * 0.6 + sin(TAU * freq * t) * env * 0.3
			"whoosh":
				var w := sin(PI * t / length)
				v = rng.randf_range(-1.0, 1.0) * w * w * 0.5
			_:
				v = (sin(TAU * freq * t) * 0.6 + sin(TAU * freq * 2.0 * t) * 0.25) * env * env
		var s := int(clampf(v, -1.0, 1.0) * 28000.0)
		pcm.encode_s16(i * 2, s)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = pcm
	return wav.save_to_wav(ProjectSettings.globalize_path(String(e["path"]))) == OK

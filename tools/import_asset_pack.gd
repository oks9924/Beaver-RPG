extends SceneTree
## 에셋팩(v1 beaver_assets, v2 beaver_combat_v2, v3-A beaver_assets_v3a, v3-B~E beaver_assets_v3bce) 임포트 도구.
## 실행: godot --headless -s tools/import_asset_pack.gd -- --packs=<압축을 푼 폴더> [--only=char.guardian]
## v3 는 v1·v2 위에 애니메이션 단위로 덮어쓴다(파생본 → 최종본). v3 팩이 없으면 v1·v2 만 처리한다.
## - 팩의 방향/프레임별 PNG 를 이 프로젝트의 시트 규격(행=down/up/left/right, 열=프레임)으로 합성해 assets/final/ 에 쓴다.
## - 팩에 없는 동작(이동·피격·다운·사망·시전 등)은 기본 자세에서 파생(bob/lean/tint/rotate/fade)하고 status="derived" 로 표시한다.
## - asset_manifest.json 의 해당 ID 에 final_path·규격·출처·제공/연결 상태를 기록한다. 코드는 계속 ID 만 참조한다.
## 원본 시트·프레임 PNG 는 저장소가 아니라 GitHub Release(assets-raw-v1) 에 보관한다 (docs/asset_plan.md).

const MANIFEST := "res://assets/asset_manifest.json"
const OUT_DIR := "res://assets/final/"
const DIRS_PACK := ["down", "up", "left", "right"]   # 이 프로젝트의 행 순서
const ANCHOR := [0.5, 0.828]                          # (64,106)/128 = (256,424)/512 = (128,212)/256

var packs_dir: String = ""
var v1: Dictionary = {}
var v2: Dictionary = {}
var v3a: Dictionary = {}
var v3b: Dictionary = {}
var manifest: Dictionary = {}
var made: int = 0
var only: String = ""
var report: Array = []


func _init() -> void:
	var args := {}
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.find("=") > 0:
			args[a.substr(2, a.find("=") - 2)] = a.substr(a.find("=") + 1)
	packs_dir = String(args.get("packs", ""))
	only = String(args.get("only", ""))
	if packs_dir == "" or not DirAccess.dir_exists_absolute(packs_dir):
		printerr("usage: --packs=<dir with beaver_assets/ and beaver_combat_v2/>")
		quit(2)
		return
	v1 = _read_json(packs_dir.path_join("beaver_assets/manifest.json"))
	v2 = _read_json(packs_dir.path_join("beaver_combat_v2/manifest.json"))
	if FileAccess.file_exists(packs_dir.path_join("beaver_assets_v3a/manifest.json")):
		v3a = _read_json(packs_dir.path_join("beaver_assets_v3a/manifest.json"))
	if FileAccess.file_exists(packs_dir.path_join("beaver_assets_v3bce/manifest.json")):
		v3b = _read_json(packs_dir.path_join("beaver_assets_v3bce/manifest.json"))
	var mj := JSON.new()
	mj.parse(FileAccess.get_file_as_string(MANIFEST))
	manifest = mj.data
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_run()
	var f := FileAccess.open(MANIFEST, FileAccess.WRITE)
	f.store_string(JSON.stringify(manifest, "\t", false))
	f.close()
	print("import done: %d sheets written" % made)
	for r in report:
		print("  " + r)
	quit(0)


func _read_json(path: String) -> Dictionary:
	var j := JSON.new()
	if j.parse(FileAccess.get_file_as_string(path)) != OK:
		printerr("cannot parse " + path)
		return {}
	return j.data


# ------------------------------------------------------------------ 팩 프레임 읽기

## 팩 actor 의 state 를 방향별 프레임 배열로 읽는다: {"down": [Image,...], "up": [...], ...}
func _pack_frames(pack: Dictionary, root: String, actor_id: String, state: String) -> Dictionary:
	var actor: Dictionary = pack.get("actors", {}).get(actor_id, {})
	if actor.is_empty():
		return {}
	var out := {}
	for d in DIRS_PACK:
		var anim: Dictionary = actor["animations"].get("%s_%s" % [state, d], {})
		if anim.is_empty():
			return {}
		var imgs: Array = []
		for rel: String in anim["frames"]:
			var img := Image.new()
			if img.load(packs_dir.path_join(root).path_join(rel)) != OK:
				printerr("missing frame " + rel)
				return {}
			imgs.append(img)
		out[d] = imgs
	out["_fps"] = float(actor["animations"]["%s_down" % state].get("fps", 8))
	out["_loop"] = bool(actor["animations"]["%s_down" % state].get("loop", false))
	out["_contact"] = int(actor["animations"]["%s_down" % state].get("visual_contact_frame", -1))
	return out


## 고정 시점 장치: {"all": [Image x4]}
func _pack_fixed(actor_id: String, state: String) -> Dictionary:
	var actor: Dictionary = v2.get("actors", {}).get(actor_id, {})
	var anim: Dictionary = actor.get("animations", {}).get(state + "_fixed", {})
	if anim.is_empty():
		return {}
	var imgs: Array = []
	for rel: String in anim["frames"]:
		var img := Image.new()
		if img.load(packs_dir.path_join("beaver_combat_v2").path_join(rel)) != OK:
			return {}
		imgs.append(img)
	return {"all": imgs, "_fps": float(anim.get("fps", 6)), "_loop": bool(anim.get("loop", false))}


# ------------------------------------------------------------------ 파생 변환

func _shift(img: Image, dx: int, dy: int) -> Image:
	var out := Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	out.blit_rect(img, Rect2i(0, 0, img.get_width(), img.get_height()), Vector2i(dx, dy))
	return out


func _tint(img: Image, col: Color, amount: float) -> Image:
	var out := img.duplicate() as Image
	for y in out.get_height():
		for x in out.get_width():
			var c := out.get_pixel(x, y)
			if c.a > 0.01:
				var t := c.lerp(col, amount)
				t.a = c.a
				out.set_pixel(x, y, t)
	return out


func _fade(img: Image, alpha: float) -> Image:
	var out := img.duplicate() as Image
	for y in out.get_height():
		for x in out.get_width():
			var c := out.get_pixel(x, y)
			if c.a > 0.0:
				c.a *= alpha
				out.set_pixel(x, y, c)
	return out


func _desaturate(img: Image, amount: float) -> Image:
	var out := img.duplicate() as Image
	for y in out.get_height():
		for x in out.get_width():
			var c := out.get_pixel(x, y)
			if c.a > 0.01:
				var g := c.get_luminance()
				var t := c.lerp(Color(g, g, g, c.a), amount)
				t.a = c.a
				out.set_pixel(x, y, t)
	return out


func _lying(img: Image, facing_x: int) -> Image:
	var out := img.duplicate() as Image
	out.rotate_90(CLOCKWISE if facing_x >= 0 else COUNTERCLOCKWISE)
	# 회전 후 발이 옆을 보므로 몸을 바닥선(anchor) 근처로 내린다
	return _shift(out, 0, int(img.get_height() * 0.16))


func _scaled(img: Image, s: float, anchor_y: float) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	var r := img.duplicate() as Image
	r.resize(int(w * s), int(h * s), Image.INTERPOLATE_LANCZOS)
	var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	var ax := int(w * 0.5 - r.get_width() * 0.5)
	var ay := int(h * anchor_y - r.get_height() * anchor_y)
	out.blit_rect(r, Rect2i(0, 0, r.get_width(), r.get_height()), Vector2i(ax, ay))
	return out


## 기본 자세 1장에서 동작을 파생한다. kind: idle2 | walk | attack | cast | hit | down | death | molt
func _derive(base: Dictionary, kind: String) -> Dictionary:
	var out := {}
	for d in DIRS_PACK:
		var src: Image = base[d][0]
		var facing_x := 1 if d == "right" else (-1 if d == "left" else 0)
		var facing_y := 1 if d == "down" else (-1 if d == "up" else 0)
		var frames: Array = []
		match kind:
			"idle2":
				frames = [src, _shift(src, 0, -1)]
			"walk":
				for i in 4:
					var dy: int = [0, -3, 0, -3][i]
					var dx: int = [0, 1, 0, -1][i]
					frames.append(_shift(src, dx, dy))
			"attack":
				for i in 4:
					var push: int = [-4, 2, 10, 4][i]
					frames.append(_shift(src, push * facing_x, push * facing_y))
			"cast":
				for i in 4:
					var s: float = [1.0, 1.04, 1.08, 1.03][i]
					frames.append(_tint(_scaled(src, s, ANCHOR[1]), Color(1.0, 0.95, 0.7), [0.0, 0.1, 0.25, 0.1][i]))
			"hit":
				frames = [_tint(_shift(src, -3 * facing_x if facing_x != 0 else 3, 0), Color(1, 0.3, 0.3), 0.45)]
			"down":
				frames = [_lying(src, facing_x if facing_x != 0 else 1)]
			"death":
				frames = [_fade(_shift(src, 0, 3), 0.7), _fade(_shift(src, 0, 8), 0.35)]
			"molt":
				frames = [_desaturate(src, 0.8), _shift(_desaturate(src, 0.8), 2, 0)]
		out[d] = frames
	out["_fps"] = {"idle2": 3.0, "walk": 8.0, "attack": 10.0, "cast": 8.0, "hit": 1.0, "down": 1.0, "death": 4.0, "molt": 2.0}[kind]
	out["_loop"] = kind in ["idle2", "walk", "molt"]
	out["_contact"] = 2 if kind == "attack" else -1
	return out


# ------------------------------------------------------------------ 시트 합성

func _compose(frames: Dictionary, frame_px: int, rows: Array) -> Image:
	var cols: int = (frames[rows[0]] as Array).size()
	var sheet := Image.create(frame_px * cols, frame_px * rows.size(), false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0, 0, 0, 0))
	for r in rows.size():
		var list: Array = frames[rows[r]]
		for c in cols:
			var img: Image = list[c]
			if img.get_width() != frame_px:
				img = img.duplicate()
				img.resize(frame_px, frame_px, Image.INTERPOLATE_LANCZOS)
			if img.get_format() != Image.FORMAT_RGBA8:
				img.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(img, Rect2i(0, 0, frame_px, frame_px), Vector2i(c * frame_px, r * frame_px))
	return sheet


func _entry(id: String) -> Dictionary:
	for e: Dictionary in manifest["assets"]:
		if e["id"] == id:
			return e
	var e := {"id": id, "type": "sprite_sheet", "status": "planned", "path": "", "final_path": ""}
	manifest["assets"].append(e)
	return e


## 시트를 쓰고 매니페스트 항목을 갱신한다.
func _emit(id: String, frames: Dictionary, frame_px: int, render_px: int, status: String, source: Dictionary, linked: bool, hitbox: String = "", rows: Array = DIRS_PACK) -> void:
	if only != "" and not id.begins_with(only):
		return
	if frames.is_empty():
		report.append("SKIP %s (no frames)" % id)
		return
	var sheet := _compose(frames, frame_px, rows)
	var file := OUT_DIR + id.replace(".", "_") + ".png"
	var err := sheet.save_png(ProjectSettings.globalize_path(file))
	if err != OK:
		report.append("FAIL %s save %d" % [id, err])
		return
	var cols: int = (frames[rows[0]] as Array).size()
	var e := _entry(id)
	e["type"] = "sprite_sheet"
	e["status"] = status
	e["final_path"] = file
	e["frame_size"] = [frame_px, frame_px]
	e["source_size"] = [frame_px * cols, frame_px * rows.size()]
	e["columns"] = cols
	e["rows"] = rows.size()
	e["directions"] = rows if rows.size() == 4 else ["all"]
	var ev := {}
	if int(frames.get("_contact", -1)) >= 0:
		ev["hit"] = int(frames["_contact"])
	e["animation"] = {"name": id.get_slice(".", id.get_slice_count(".") - 1), "frames": range(cols), "fps": float(frames.get("_fps", 8.0)), "loop": bool(frames.get("_loop", false)), "event_frames": ev}
	e["anchor"] = ANCHOR
	e["render_size"] = [render_px, render_px]
	if hitbox != "":
		e["hitbox_ref"] = hitbox
	e["source"] = source
	e["provided"] = status == "final"
	e["linked"] = linked
	e["verified"] = "not_run"
	e["placeholder_kept"] = e.get("path", "") != ""
	made += 1
	report.append("%s %s <- %s" % [status.to_upper().left(3), id, source.get("method", "")])


func _src(pack: String, actor: String, state: String, method: String = "pack", origin: String = "GitHub Release assets-raw-v1") -> Dictionary:
	return {"pack": pack, "actor": actor, "animation": state, "method": method, "license": "project-internal (in-house generated art, see pack README)", "origin": origin}


# ------------------------------------------------------------------ 매핑

func _run() -> void:
	const P := 128
	const B := 256   # 보스 512 원본을 256 으로 축소 (README: 512 는 파일 해상도일 뿐)
	const D := 256   # 장치
	# --- 플레이어 (v1)
	var classes := {"guardian": "player_guardian", "pinecone": "player_ranger", "sawtooth": "player_berserker", "sapshaman": "player_shaman", "hydro": "player_engineer"}
	for cid: String in classes.keys():
		var actor: String = classes[cid]
		var linked := cid in ["guardian", "pinecone"]
		var idle := _pack_frames(v1, "beaver_assets", actor, "idle")
		if idle.is_empty():
			report.append("SKIP class %s" % cid)
			continue
		_emit("char.%s.idle" % cid, _derive(idle, "idle2"), P, 112, "final", _src("beaver_assets_v1", actor, "idle", "pack + derived 2nd frame (1px bob)"), linked, "hit.player_default")
		var walk := _pack_frames(v1, "beaver_assets", actor, "walk")
		if walk.is_empty():
			_emit("char.%s.walk" % cid, _derive(idle, "walk"), P, 112, "derived", _src("beaver_assets_v1", actor, "idle", "derived:bob"), linked, "hit.player_default")
		else:
			_emit("char.%s.walk" % cid, walk, P, 112, "final", _src("beaver_assets_v1", actor, "walk"), linked, "hit.player_default")
		var atk := _pack_frames(v1, "beaver_assets", actor, "attack")
		if atk.is_empty():
			_emit("char.%s.attack" % cid, _derive(idle, "attack"), P, 112, "derived", _src("beaver_assets_v1", actor, "idle", "derived:lean"), linked, "hit.player_default")
		else:
			atk["_contact"] = 2
			_emit("char.%s.attack" % cid, atk, P, 112, "final", _src("beaver_assets_v1", actor, "attack"), linked, "hit.player_default")
		for slot in ["q", "e", "r"]:
			var sk := _pack_frames(v1, "beaver_assets", actor, "skill_" + slot)
			if sk.is_empty():
				_emit("char.%s.cast_%s" % [cid, slot], _derive(idle, "cast"), P, 112, "derived", _src("beaver_assets_v1", actor, "idle", "derived:pulse"), linked, "hit.player_default")
			else:
				_emit("char.%s.cast_%s" % [cid, slot], sk, P, 112, "final", _src("beaver_assets_v1", actor, "skill_" + slot), linked, "hit.player_default")
		_emit("char.%s.cast" % cid, _derive(idle, "cast"), P, 112, "derived", _src("beaver_assets_v1", actor, "idle", "derived:pulse"), linked, "hit.player_default")
		_emit("char.%s.hit" % cid, _derive(idle, "hit"), P, 112, "derived", _src("beaver_assets_v1", actor, "idle", "derived:tint"), linked, "hit.player_default")
		_emit("char.%s.down" % cid, _derive(idle, "down"), P, 112, "derived", _src("beaver_assets_v1", actor, "idle", "derived:rotate"), linked, "hit.player_default")
		# 초상·아이콘: 정면 기본 자세에서 파생
		_emit_single("portrait.%s" % cid, _crop_scale(idle["down"][0], Rect2i(20, 4, 88, 88), 256), "derived", _src("beaver_assets_v1", actor, "idle", "derived:crop"), linked)
		_emit_single("icon.class.%s" % cid, _crop_scale(idle["down"][0], Rect2i(20, 4, 88, 88), 64), "derived", _src("beaver_assets_v1", actor, "idle", "derived:crop"), linked)
	var g_idle := _pack_frames(v1, "beaver_assets", "player_guardian", "idle")
	if not g_idle.is_empty():
		_emit_single("ui.app_icon", _crop_scale(g_idle["down"][0], Rect2i(16, 0, 96, 96), 256), "derived", _src("beaver_assets_v1", "player_guardian", "idle", "derived:crop"), true)
	# --- 일반 적 (v2 우선, 없으면 v1)
	var enemies := {"sap_snail": ["enemy_sap_slug", "sap_spit"], "thorn_boar": ["enemy_thorn_boar", "tusk_charge"], "black_bird": ["enemy_black_crow", "beak_dive"],
		"shell_soldier": ["enemy_shell_soldier", "claw_strike"], "spore_mushroom": ["enemy_spore_mushroom", "spore_burst"], "root_puppet": ["enemy_root_puppet", "root_lash"],
		"reed_frog": ["enemy_reed_frog", "reed_thrust"], "river_leech": ["enemy_river_leech", "suction_bite"], "lantern_moth": ["enemy_lantern_moth", "luminous_dust"],
		"woodjaw_beetle": ["enemy_woodjaw_beetle", "mandible_crush"], "gear_crab": ["enemy_gear_crab", "gear_clamp"], "sap_totem": ["enemy_sap_totem", "sap_pulse"]}
	for eid: String in enemies.keys():
		var actor: String = enemies[eid][0]
		var atk_state: String = enemies[eid][1]
		var linked := eid in ["sap_snail", "thorn_boar", "black_bird"]
		var hb := "hit.%s_body" % eid
		var idle := _pack_frames(v2, "beaver_combat_v2", actor, "idle")
		if idle.is_empty():
			idle = _pack_frames(v1, "beaver_assets", actor, "idle")
		if idle.is_empty():
			report.append("SKIP enemy %s" % eid)
			continue
		var render := 100
		_emit("enemy.%s.idle" % eid, _derive(idle, "idle2"), P, render, "final", _src("beaver_combat_v2", actor, "idle", "pack + derived 2nd frame"), linked, hb)
		var atk := _pack_frames(v2, "beaver_combat_v2", actor, atk_state)
		if atk.is_empty():
			_emit("enemy.%s.attack" % eid, _derive(idle, "attack"), P, render, "derived", _src("beaver_combat_v2", actor, "idle", "derived:lean"), linked, hb)
		else:
			_emit("enemy.%s.attack" % eid, atk, P, render, "final", _src("beaver_combat_v2", actor, atk_state), linked, hb)
		_emit("enemy.%s.walk" % eid, _derive(idle, "walk"), P, render, "derived", _src("beaver_combat_v2", actor, "idle", "derived:bob"), linked, hb)
		_emit("enemy.%s.hit" % eid, _derive(idle, "hit"), P, render, "derived", _src("beaver_combat_v2", actor, "idle", "derived:tint"), linked, hb)
		_emit("enemy.%s.death" % eid, _derive(idle, "death"), P, render, "derived", _src("beaver_combat_v2", actor, "idle", "derived:fade"), linked, hb)
		_emit_single("icon.enemy.%s" % eid, _crop_scale(idle["down"][0], Rect2i(16, 8, 96, 96), 64), "derived", _src("beaver_combat_v2", actor, "idle", "derived:crop"), linked)
	# --- 보스 (v2)
	var bosses := {"ironclaw": ["boss_ironclaw", ["claw_sweep", "straight_charge", "rock_throw", "ground_slam"]], "lantern_toad": ["boss_lantern_toad", ["jump_slam", "tongue_lance", "sap_throw", "body_bash"]], "root_king": ["boss_root_king", ["root_sweep", "pressure_jet", "root_eruption", "splinter_fan"]]}
	for bid: String in bosses.keys():
		var actor: String = bosses[bid][0]
		var linked := bid == "ironclaw"
		var hb := "hit.boss_%s" % bid
		var idle := _pack_frames(v2, "beaver_combat_v2", actor, "idle")
		if idle.is_empty():
			report.append("SKIP boss %s" % bid)
			continue
		var render := 240
		_emit("boss.%s.idle" % bid, _derive(idle, "idle2"), B, render, "final", _src("beaver_combat_v2", actor, "idle", "pack (512→256) + derived 2nd frame"), linked, hb)
		_emit("boss.%s.walk" % bid, _derive(idle, "walk"), B, render, "derived", _src("beaver_combat_v2", actor, "idle", "derived:bob"), linked, hb)
		var first := true
		for pat: String in bosses[bid][1]:
			var pf := _pack_frames(v2, "beaver_combat_v2", actor, pat)
			pf["_contact"] = 2
			_emit("boss.%s.%s" % [bid, pat], pf, B, render, "final", _src("beaver_combat_v2", actor, pat), linked, hb)
			if first:
				_emit("boss.%s.attack" % bid, pf, B, render, "final", _src("beaver_combat_v2", actor, pat + " (generic attack alias)"), linked, hb)
				first = false
		var ch := _pack_frames(v2, "beaver_combat_v2", actor, "mechanic_channel")
		_emit("boss.%s.cast" % bid, ch, B, render, "final", _src("beaver_combat_v2", actor, "mechanic_channel"), linked, hb)
		var wp := _pack_frames(v2, "beaver_combat_v2", actor, "weakpoint_exposed")
		wp["_loop"] = true
		_emit("boss.%s.stagger" % bid, wp, B, render, "final", _src("beaver_combat_v2", actor, "weakpoint_exposed"), linked, hb)
		_emit("boss.%s.exposed" % bid, wp, B, render, "final", _src("beaver_combat_v2", actor, "weakpoint_exposed"), linked, hb)
		_emit("boss.%s.molt" % bid, _derive(idle, "molt"), B, render, "derived", _src("beaver_combat_v2", actor, "idle", "derived:desaturate"), linked, hb)
		_emit("boss.%s.hit" % bid, _derive(idle, "hit"), B, render, "derived", _src("beaver_combat_v2", actor, "idle", "derived:tint"), linked, hb)
		_emit("boss.%s.death" % bid, _derive(idle, "death"), B, render, "derived", _src("beaver_combat_v2", actor, "idle", "derived:fade"), linked, hb)
		_emit("boss.%s.down" % bid, _derive(idle, "down"), B, render, "derived", _src("beaver_combat_v2", actor, "idle", "derived:rotate"), linked, hb)
		_emit_single("portrait.%s" % bid, _crop_scale(idle["down"][0], Rect2i(64, 32, 384, 384), 256), "derived", _src("beaver_combat_v2", actor, "idle", "derived:crop"), linked)
	# --- 기믹 장치 (v2, 고정 시점)
	for mid: String in v2.get("mechanics", {}).keys():
		var actor: String = v2["mechanics"][mid]["prop_actor_id"]
		var key := mid.to_lower().replace("-", "_")   # ic_01
		var linked := mid.begins_with("IC-")
		for state in ["activation", "success", "failure"]:
			var fr := _pack_fixed(actor, state)
			_emit("prop.mechanic.%s.%s" % [key, state], fr, D, 128, "final", _src("beaver_combat_v2", actor, state + "_fixed"), linked, "", ["all"])
	_run_v3a()
	_run_v3b()
	# 팩 참조 문서 정보
	manifest["packs"] = {
		"beaver_assets_v1": {"root": "GitHub Release assets-raw-v1 / 비버_RPG_에셋팩_v1.zip", "manifest": "assets/packs/beaver_assets_v1/manifest.json", "status": v1.get("status", ""), "note": "플레이어 5직업 기본 자세, 수호목수 이동·공격·Q/E/R, 적 12·보스 3 기본 자세"},
		"beaver_combat_v2": {"root": "GitHub Release assets-raw-v1 / 비버_RPG_전투애니메이션_v2.zip", "manifest": "assets/packs/beaver_combat_v2/manifest.json", "status": v2.get("status", ""), "note": "적 공격 12, 보스 패턴 4×3, 시전·약점 노출, 기믹 장치 15종 진행/성공/실패"},
	}
	if not v3a.is_empty():
		manifest["packs"]["beaver_assets_v3a"] = {"root": "GitHub Release assets-raw-v3 / _RPG_._v3_A.zip", "manifest": "assets/packs/beaver_assets_v3a/manifest.json", "status": v3a.get("status", ""), "note": "요청서 v3 A: 사수 8동작, 수호목수 피격·다운·사망·갉기, 적 3종 이동·피격·사망(+멧돼지 돌진), 가재 이동·피격·사망·탈피·빈 껍질"}
	if not v3b.is_empty():
		manifest["packs"]["beaver_assets_v3bce"] = {"root": "GitHub Release assets-raw-v3 / _RPG_._v3_B-E.zip", "manifest": "assets/packs/beaver_assets_v3bce/manifest.json", "status": v3b.get("status", ""), "note": "요청서 v3 B~E: VFX 16, 버들강 타일 6·소품 13, 아이콘 24, UI 9"}
	manifest["import_tool"] = "tools/import_asset_pack.gd"


func _crop_scale(img: Image, rect: Rect2i, size: int) -> Image:
	var r := Rect2i(rect.position, rect.size).intersection(Rect2i(0, 0, img.get_width(), img.get_height()))
	var out := img.get_region(r)
	out.resize(size, size, Image.INTERPOLATE_LANCZOS)
	if out.get_format() != Image.FORMAT_RGBA8:
		out.convert(Image.FORMAT_RGBA8)
	return out


func _emit_single(id: String, img: Image, status: String, source: Dictionary, linked: bool) -> void:
	if only != "" and not id.begins_with(only):
		return
	var file := OUT_DIR + id.replace(".", "_") + ".png"
	if img.save_png(ProjectSettings.globalize_path(file)) != OK:
		report.append("FAIL %s" % id)
		return
	var e := _entry(id)
	if String(e.get("type", "")) == "":
		e["type"] = "texture"
	if String(e.get("type", "")) == "sprite_sheet":
		e["type"] = "texture"
	e["status"] = status
	e["final_path"] = file
	e["frame_size"] = [img.get_width(), img.get_height()]
	e["source_size"] = [img.get_width(), img.get_height()]
	e["columns"] = 1
	e["rows"] = 1
	e["source"] = source
	e["provided"] = status == "final"
	e["linked"] = linked
	e["verified"] = "not_run"
	made += 1
	report.append("%s %s <- %s" % [status.to_upper().left(3), id, source.get("method", "")])


# ------------------------------------------------------------------ v3 (assets-raw-v3)

const V3_ORIGIN := "GitHub Release assets-raw-v3"


## 방향 없는 팩 애니메이션(<state>_all / default_all) 을 읽는다: {"all": [Image...], "_fps", "_loop", "_hold", "_mode", "_segments", "_labels", "_w", "_h"}
func _pack_strip(pack: Dictionary, root: String, actor_id: String, anim_name: String) -> Dictionary:
	var actor: Dictionary = pack.get("actors", {}).get(actor_id, {})
	var anim: Dictionary = actor.get("animations", {}).get(anim_name, {})
	if anim.is_empty():
		return {}
	var imgs: Array = []
	for rel: String in anim["frames"]:
		var img := Image.new()
		if img.load(packs_dir.path_join(root).path_join(rel)) != OK:
			printerr("missing frame " + rel)
			return {}
		if img.get_format() != Image.FORMAT_RGBA8:
			img.convert(Image.FORMAT_RGBA8)
		imgs.append(img)
	var fs: Array = anim.get("frame_size", actor.get("frame_size", [imgs[0].get_width(), imgs[0].get_height()]))
	var ap: Array = anim.get("anchor_px", actor.get("anchor_px", [float(fs[0]) * 0.5, float(fs[1]) * 0.5]))
	return {"all": imgs, "_fps": float(anim.get("fps", 8)), "_loop": bool(anim.get("loop", false)), "_hold": bool(anim.get("hold_last_frame", false)),
		"_mode": String(anim.get("playback_mode", "loop" if bool(anim.get("loop", false)) else "one_shot")), "_segments": anim.get("segments", {}), "_labels": anim.get("frame_labels", []),
		"_contact": int(anim.get("visual_contact_frame", -1)), "_w": int(fs[0]), "_h": int(fs[1]), "_anchor": [float(ap[0]) / float(fs[0]), float(ap[1]) / float(fs[1])], "_actor": actor}


func _compose_strip(imgs: Array, w: int, h: int) -> Image:
	var sheet := Image.create(w * imgs.size(), h, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0, 0, 0, 0))
	for c in imgs.size():
		var img: Image = imgs[c]
		if img.get_width() != w or img.get_height() != h:
			img = img.duplicate()
			img.resize(w, h, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(img, Rect2i(0, 0, w, h), Vector2i(c * w, 0))
	return sheet


## 방향 없는 시트(열 = 프레임) 를 쓰고 매니페스트를 갱신한다. anim_extra 는 animation 에 합쳐지고 (mode/segments/hold_last), entry_extra 는 항목에 합쳐진다.
func _emit_strip(id: String, strip: Dictionary, w: int, h: int, render: Array, status: String, source: Dictionary, linked: bool, type_: String = "sprite_sheet", entry_extra: Dictionary = {}, anchor: Array = []) -> void:
	if only != "" and not id.begins_with(only):
		return
	if strip.is_empty():
		report.append("SKIP %s (no frames)" % id)
		return
	var imgs: Array = strip["all"]
	var sheet := _compose_strip(imgs, w, h)
	var file := OUT_DIR + id.replace(".", "_") + ".png"
	if sheet.save_png(ProjectSettings.globalize_path(file)) != OK:
		report.append("FAIL %s save" % id)
		return
	var e := _entry(id)
	e["type"] = type_
	e["status"] = status
	e["final_path"] = file
	e["frame_size"] = [w, h]
	e["source_size"] = [w * imgs.size(), h]
	e["columns"] = imgs.size()
	e["rows"] = 1
	e["directions"] = ["all"]
	var ev := {}
	if int(strip.get("_contact", -1)) >= 0:
		ev["hit"] = int(strip["_contact"])
	var anim := {"name": id.get_slice(".", id.get_slice_count(".") - 1), "frames": range(imgs.size()), "fps": float(strip.get("_fps", 8.0)), "loop": bool(strip.get("_loop", false)), "event_frames": ev,
		"mode": String(strip.get("_mode", "one_shot")), "hold_last": bool(strip.get("_hold", false))}
	if not (strip.get("_segments", {}) as Dictionary).is_empty():
		anim["segments"] = strip["_segments"]
	if not (strip.get("_labels", []) as Array).is_empty():
		anim["frame_labels"] = strip["_labels"]
	e["animation"] = anim
	e["anchor"] = anchor if not anchor.is_empty() else strip.get("_anchor", [0.5, 0.5])
	e["render_size"] = render
	e["source"] = source
	e["provided"] = status == "final"
	e["linked"] = linked
	e["verified"] = "not_run"
	e["placeholder_kept"] = e.get("path", "") != ""
	for k in entry_extra.keys():
		e[k] = entry_extra[k]
	made += 1
	report.append("%s %s <- %s (%d frames)" % [status.to_upper().left(3), id, source.get("method", ""), imgs.size()])


## n×n 모자이크 (64px 타일 변형을 시드로 섞어 반복 무늬를 줄인다). rotate=true 면 90° 회전도 섞는다.
func _mosaic(imgs: Array, n: int, seed_: int, rotate: bool) -> Image:
	var t: int = imgs[0].get_width()
	var out := Image.create(t * n, t * n, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	for y in n:
		for x in n:
			var img: Image = imgs[rng.randi_range(0, imgs.size() - 1)]
			if rotate:
				img = img.duplicate()
				for k in rng.randi_range(0, 3):
					img.rotate_90(CLOCKWISE)
			out.blit_rect(img, Rect2i(0, 0, t, t), Vector2i(x * t, y * t))
	return out


func _run_v3a() -> void:
	if v3a.is_empty():
		report.append("SKIP v3a (pack not found)")
		return
	const R := "beaver_assets_v3a"
	const P := 128
	const B := 256
	# 솔방울사수: v1 에 대기만 있었고 나머지는 파생본이었다 → 전부 최종본으로
	var ranger := {"walk": ["walk", -1], "attack": ["attack", 2], "cast_q": ["cast_q", 2], "cast_e": ["cast_e", 3], "cast_r": ["cast_r", 2], "hit": ["hit", -1], "down": ["down", -1], "death": ["death", -1]}
	for our: String in ranger.keys():
		var fr := _pack_frames(v3a, R, "player_ranger", ranger[our][0])
		if not fr.is_empty() and int(ranger[our][1]) >= 0:
			fr["_contact"] = int(ranger[our][1])
		_emit("char.pinecone.%s" % our, fr, P, 112, "final", _src(R, "player_ranger", ranger[our][0], "pack", V3_ORIGIN), true, "hit.player_default")
	for st in ["hit", "down", "death", "interact"]:
		_emit("char.guardian.%s" % st, _pack_frames(v3a, R, "player_guardian", st), P, 112, "final", _src(R, "player_guardian", st, "pack", V3_ORIGIN), true, "hit.player_default")
	var enemies := {"sap_snail": "enemy_sap_slug", "thorn_boar": "enemy_thorn_boar", "black_bird": "enemy_black_crow"}
	for eid: String in enemies.keys():
		var actor: String = enemies[eid]
		for st in ["walk", "hit", "death"]:
			_emit("enemy.%s.%s" % [eid, st], _pack_frames(v3a, R, actor, st), P, 100, "final", _src(R, actor, st, "pack", V3_ORIGIN), true, "hit.%s_body" % eid)
	# 멧돼지 지속 돌진 보행: 서버 상태에 별도 '돌진 중' 이 없어 아직 미연결 (attack = v2 tusk_charge 예고·접촉)
	_emit("enemy.thorn_boar.charge", _pack_frames(v3a, R, "enemy_thorn_boar", "charge"), P, 100, "final", _src(R, "enemy_thorn_boar", "charge", "pack", V3_ORIGIN), false, "hit.thorn_boar_body")
	for st in ["walk", "hit", "death", "molt"]:
		var fr := _pack_frames(v3a, R, "boss_ironclaw", st)
		if st == "molt":
			fr["_loop"] = false
		_emit("boss.ironclaw.%s" % st, fr, B, 240, "final", _src(R, "boss_ironclaw", st, "pack (512→256)", V3_ORIGIN), true, "hit.boss_ironclaw")
	# 빈 껍질: 256×256 단일 프레임 예외 (IC-04 가짜 위치 오브젝트)
	var husk := _pack_strip(v3a, R, "boss_ironclaw", "husk_all")
	if not husk.is_empty():
		_emit_strip("prop.boss.husk", husk, 256, 256, [180, 180], "final", _src(R, "boss_ironclaw", "husk_all", "pack", V3_ORIGIN), true, "texture")


func _run_v3b() -> void:
	if v3b.is_empty():
		report.append("SKIP v3bce (pack not found)")
		return
	const R := "beaver_assets_v3bce"
	# --- B: VFX (기존 render_size 유지, 없으면 표)
	var vfx_render := {"hammer_swing": 180, "log_shield": 110, "tail_shockwave": 220, "great_tree": 460, "sling_shot": 64, "acorn_scatter": 170, "thorn_trap": 104, "forest_volley": 220,
		"projectile_pinecone": 24, "projectile_sap": 24, "hit_spark": 64, "rescue_ring": 110, "heal_burst": 110, "boss_rock_impact": 200, "boss_ground_slam": 380, "whirlpool": 420}
	for key: String in vfx_render.keys():
		var strip := _pack_strip(v3b, R, "vfx_" + key, "default_all")
		if strip.is_empty():
			report.append("SKIP vfx_%s" % key)
			continue
		var id := "vfx." + key
		var rs: int = int(vfx_render[key])
		var linked := not key in ["whirlpool"]   # 소용돌이는 IC-05 발판 아래 루프로 연결
		_emit_strip(id, strip, int(strip["_w"]), int(strip["_h"]), [rs, rs], "final", _src(R, "vfx_" + key, "default_all", "pack", V3_ORIGIN), true, "sprite_sheet", {}, [0.5, 0.5])
	# --- C: 타일. 바닥은 4변형을 4×4 모자이크로 합쳐 반복 무늬를 줄인다 (ground Sprite2D 가 통째로 반복).
	var g := _pack_strip(v3b, R, "tile_willow_ground", "default_all")
	if not g.is_empty():
		_emit_single("tile.willow.ground", _mosaic(g["all"], 4, 11, false), "final", _src(R, "tile_willow_ground", "default_all", "pack: 4 variants → 4×4 seeded mosaic", V3_ORIGIN), true)
		_entry("tile.willow.ground")["layer"] = "ground"
	var hub := _pack_strip(v3b, R, "tile_hub_ground", "default_all")
	if not hub.is_empty():
		_emit_single("tile.hub.ground", _mosaic([hub["all"][0]], 4, 5, true), "final", _src(R, "tile_hub_ground", "default_all[0]", "pack: frame 0 → 4×4 rotated mosaic", V3_ORIGIN), true)
		_entry("tile.hub.ground")["layer"] = "ground"
		_emit_strip("tile.hub.planks", {"all": [hub["all"][1]], "_fps": 1.0, "_mode": "select_frame"}, 64, 64, [64, 64], "final", _src(R, "tile_hub_ground", "default_all[1]", "pack", V3_ORIGIN), false, "texture")
	for t in [["tile.willow.wall", "tile_willow_wall", true, "collision"], ["tile.willow.water", "tile_willow_water", true, "hazard"], ["tile.willow.shore", "tile_willow_shore", true, "ground"], ["tile.willow.bridge", "tile_willow_bridge", false, "ground"]]:
		var strip := _pack_strip(v3b, R, t[1], "default_all")
		_emit_strip(t[0], strip, 64, 64, [64, 64], "final", _src(R, t[1], "default_all", "pack", V3_ORIGIN), bool(t[2]), "texture", {"layer": t[3]}, [0.0, 0.0])
	# --- C: 소품 (상태 = 프레임 선택; 코드가 frame index 를 고른다)
	var props := {"prop.gnaw_tree": ["prop_gnaw_tree", 84, true], "prop.device": ["prop_device", 76, true], "prop.lever": ["prop_lever", 60, true], "prop.sluice_gate": ["prop_sluice_gate", 120, true],
		"prop.log_cover": ["prop_log_cover", 72, true], "prop.willow.log": ["prop_willow_log", 96, true], "prop.willow.rock": ["prop_willow_rock", 96, true], "prop.hold_point": ["prop_hold_point", 90, true],
		"prop.campfire": ["prop_campfire", 96, true], "prop.stall": ["prop_stall", 120, true], "prop.hub.memory_tree": ["prop_memory_tree", 260, true], "prop.hub.workshop": ["prop_workshop", 150, true], "prop.hub.board": ["prop_expedition_board", 110, true]}
	for id: String in props.keys():
		var strip := _pack_strip(v3b, R, props[id][0], "default_all")
		var rs: int = int(props[id][1])
		_emit_strip(id, strip, int(strip.get("_w", 256)), int(strip.get("_h", 256)), [rs, rs], "final", _src(R, props[id][0], "default_all", "pack", V3_ORIGIN), bool(props[id][2]), "sprite_sheet", {"hitbox_ref": "obstacle"} if id in ["prop.willow.log", "prop.willow.rock", "prop.gnaw_tree"] else {})
	# --- D: 아이콘 (64×64 단일)
	var icons := {"icon.skill.guardian.q": "icon_skill_guardian_q", "icon.skill.guardian.e": "icon_skill_guardian_e", "icon.skill.guardian.r": "icon_skill_guardian_r",
		"icon.skill.pinecone.q": "icon_skill_ranger_q", "icon.skill.pinecone.e": "icon_skill_ranger_e", "icon.skill.pinecone.r": "icon_skill_ranger_r", "icon.heal": "icon_heal", "icon.dodge": "icon_dodge"}
	for r in ["oak_heart", "sharp_incisors", "river_stone", "quick_paws", "sap_amber", "hunters_tooth", "kin_bond", "thorn_tail", "heavy_paddle", "acorn_pouch"]:
		icons["icon.relic." + r] = "icon_relic_" + r
	for st in ["slow", "bleed", "shield", "mark", "stagger", "wet"]:
		icons["icon.status." + st] = "icon_status_" + st
	for id: String in icons.keys():
		var strip := _pack_strip(v3b, R, icons[id], "default_all")
		if strip.is_empty():
			report.append("SKIP " + id)
			continue
		var linked := not id.begins_with("icon.status.mark") and not id.begins_with("icon.status.stagger") and not id.begins_with("icon.status.wet")
		_emit_single(id, strip["all"][0], "final", _src(R, icons[id], "default_all", "pack", V3_ORIGIN), linked)
	# --- E: UI
	var panel := _pack_strip(v3b, R, "ui_panel", "default_all")
	if not panel.is_empty():
		_emit_strip("ui.panel.default", panel, 96, 96, [96, 96], "final", _src(R, "ui_panel", "default_all", "pack", V3_ORIGIN), true, "nine_slice", {"nine_slice_margin": 12})
	var btn := _pack_strip(v3b, R, "ui_button", "default_all")
	if not btn.is_empty():
		for i in 3:
			var bid: String = ["ui.button.default", "ui.button.hover", "ui.button.pressed"][i]
			_emit_strip(bid, {"all": [btn["all"][i]], "_fps": 1.0, "_mode": "select_frame"}, 96, 48, [96, 48], "final", _src(R, "ui_button", "default_all[%d]" % i, "pack", V3_ORIGIN), true, "nine_slice", {"nine_slice_margin": 12})
	var reward := _pack_strip(v3b, R, "ui_card_reward", "default_all")
	_emit_strip("ui.card.reward", reward, 256, 352, [200, 275], "final", _src(R, "ui_card_reward", "default_all", "pack", V3_ORIGIN), true, "sprite_sheet", {"frame_labels": ["relic", "upgrade"]}, [0.0, 0.0])
	var route := _pack_strip(v3b, R, "ui_card_route", "default_all")
	_emit_strip("ui.card.route", route, 256, 160, [208, 130], "final", _src(R, "ui_card_route", "default_all", "pack", V3_ORIGIN), true, "sprite_sheet", {"frame_labels": ["combat", "event", "shop", "rest", "boss"]}, [0.0, 0.0])
	var hp := _pack_strip(v3b, R, "ui_bar_hp", "default_all")
	if not hp.is_empty():
		var a: Dictionary = hp["_actor"]
		_emit_strip("ui.bar.hp", hp, 256, 24, [256, 24], "final", _src(R, "ui_bar_hp", "default_all", "pack", V3_ORIGIN), true, "sprite_sheet", {"frame_labels": ["frame", "fill"], "fill_rect_px": a.get("fill_rect_px", [17, 8, 222, 9]), "layer_order_back_to_front": ["fill", "frame"]}, [0.0, 0.0])
	var bb := _pack_strip(v3b, R, "ui_bar_boss", "default_all")
	if not bb.is_empty():
		var a: Dictionary = bb["_actor"]
		_emit_strip("ui.bar.boss", bb, 512, 32, [512, 32], "final", _src(R, "ui_bar_boss", "default_all", "pack", V3_ORIGIN), true, "sprite_sheet", {"frame_labels": ["frame"], "fill_rect_px": a.get("suggested_fill_rect_px", [80, 12, 354, 11])}, [0.0, 0.0])
	var logo := _pack_strip(v3b, R, "ui_title_logo", "default_all")
	if not logo.is_empty():
		_emit_single("ui.title.logo", logo["all"][0], "final", _src(R, "ui_title_logo", "default_all", "pack (문양·리본만, 제목은 폰트)", V3_ORIGIN), true)
	var app := _pack_strip(v3b, R, "ui_app_icon", "default_all")
	if not app.is_empty():
		_emit_single("ui.app_icon", app["all"][0], "final", _src(R, "ui_app_icon", "default_all", "pack", V3_ORIGIN), true)
		_entry("ui.app_icon")["type"] = "icon"
	var pf := _pack_strip(v3b, R, "ui_frame_portrait", "default_all")
	if not pf.is_empty():
		_emit_single("ui.frame.portrait", pf["all"][0], "final", _src(R, "ui_frame_portrait", "default_all", "pack", V3_ORIGIN), true)

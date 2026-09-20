extends Node
## 에셋 ID → 실제 파일 해석기. 코드와 데이터는 파일 경로 대신 ID만 사용한다.
## 해석 순서: asset_overrides 디렉터리 > manifest.final_path > manifest.path(placeholder) > 런타임 대체 도형.
## 이미지는 Godot import 파이프라인 대신 런타임 로드(Image.load_png_from_buffer)로 읽는다.
## 그래서 export 이후에도 실행 파일 옆 `asset_overrides/` 에 같은 규격의 파일을 넣으면 재빌드 없이 교체된다.

const MANIFEST_PATH := "res://assets/asset_manifest.json"

var manifest: Dictionary = {}
var entries: Dictionary = {}          # id -> entry
var _texture_cache: Dictionary = {}   # id -> Texture2D
var _font_cache: Dictionary = {}
var _audio_cache: Dictionary = {}
var _fallback_texture: Texture2D
var missing_ids: PackedStringArray = []   # 런타임에 대체 도형으로 그린 ID (AST-01 로그)
var override_dir: String = ""
var headless: bool = false


func _ready() -> void:
	headless = DisplayServer.get_name() == "headless"
	load_manifest()
	override_dir = _resolve_override_dir()


func load_manifest() -> void:
	entries.clear()
	if not FileAccess.file_exists(MANIFEST_PATH):
		push_error("[AssetRegistry] manifest missing: " + MANIFEST_PATH)
		return
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(MANIFEST_PATH)) != OK:
		push_error("[AssetRegistry] manifest parse error: " + json.get_error_message())
		return
	manifest = json.data
	for e: Dictionary in manifest.get("assets", []):
		entries[e["id"]] = e


func _resolve_override_dir() -> String:
	var rel: String = manifest.get("override_dir_relative_to_executable", "asset_overrides")
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://").path_join(rel)
	return OS.get_executable_path().get_base_dir().path_join(rel)


func has(id: String) -> bool:
	return entries.has(id)


func entry(id: String) -> Dictionary:
	return entries.get(id, {})


func status(id: String) -> String:
	return String(entry(id).get("status", "unknown"))


## ID가 가리키는 실제 파일 경로. 없으면 "".
func resolve_path(id: String) -> String:
	var e := entry(id)
	if e.is_empty():
		return ""
	var ext := _ext_for(e)
	if override_dir != "":
		var p := override_dir.path_join(id + "." + ext)
		if FileAccess.file_exists(p):
			return p
	var fp: String = e.get("final_path", "")
	if fp != "" and _exists(fp):
		return fp
	var pp: String = e.get("path", "")
	if pp != "" and _exists(pp):
		return pp
	return ""


## export 된 빌드에서는 원본 png/ttf/wav 가 아니라 import 된 리소스(.ctex/.fontdata/.sample)만 pck 에 들어간다.
## 그래서 res:// 경로는 FileAccess 뿐 아니라 ResourceLoader 로도 존재 여부를 확인한다.
func _exists(path: String) -> bool:
	if FileAccess.file_exists(path):
		return true
	return path.begins_with("res://") and ResourceLoader.exists(path)


func _ext_for(e: Dictionary) -> String:
	match String(e.get("type", "texture")):
		"font": return "ttf"
		"audio": return "wav"
		_: return "png"


func get_texture(id: String) -> Texture2D:
	if _texture_cache.has(id):
		return _texture_cache[id]
	var tex: Texture2D = null
	var path := resolve_path(id)
	if path != "":
		if path.begins_with("res://") and ResourceLoader.exists(path, "Texture2D"):
			tex = load(path) as Texture2D
		if tex == null and FileAccess.file_exists(path):
			var img := Image.new()
			var err := img.load_png_from_buffer(FileAccess.get_file_as_bytes(path))
			if err == OK:
				tex = ImageTexture.create_from_image(img)
			else:
				push_warning("[AssetRegistry] cannot decode %s (%s): %d" % [id, path, err])
	if tex == null:
		if not missing_ids.has(id):
			missing_ids.append(id)
			push_warning("[AssetRegistry] fallback texture for asset id '%s'" % id)
		tex = _get_fallback_texture()
	_texture_cache[id] = tex
	return tex


## 스프라이트 시트 정보. Sprite2D 의 hframes/vframes 와 애니메이션 재생에 필요한 값을 돌려준다.
func get_sheet(id: String) -> Dictionary:
	var e := entry(id)
	var tex := get_texture(id)
	var cols: int = int(e.get("columns", 1))
	var rows: int = int(e.get("rows", 1))
	var anim: Dictionary = e.get("animation", {})
	var frame_size: Array = e.get("frame_size", [tex.get_width() / max(cols, 1), tex.get_height() / max(rows, 1)])
	var anchor: Array = e.get("anchor", manifest.get("spec", {}).get("anchor_default", [0.5, 0.82]))
	var render: Array = e.get("render_size", frame_size)
	return {
		"id": id,
		"texture": tex,
		"hframes": cols,
		"vframes": rows,
		"directions": e.get("directions", ["all"]),
		"frames": anim.get("frames", range(cols)),
		"fps": float(anim.get("fps", 1)),
		"loop": bool(anim.get("loop", true)),
		"event_frames": anim.get("event_frames", {}),
		"frame_size": Vector2(frame_size[0], frame_size[1]),
		"anchor": Vector2(anchor[0], anchor[1]),
		"render_size": Vector2(render[0], render[1]),
		"is_fallback": tex == _fallback_texture,
	}


func get_font(id: String) -> Font:
	if _font_cache.has(id):
		return _font_cache[id]
	var path := resolve_path(id)
	var font: Font = null
	if path != "":
		if path.begins_with("res://") and ResourceLoader.exists(path, "Font"):
			font = load(path) as Font
		if font == null:
			var ff := FontFile.new()
			if ff.load_dynamic_font(path) == OK:
				font = ff
	if font == null:
		push_warning("[AssetRegistry] font fallback for '%s'" % id)
		font = ThemeDB.fallback_font
	_font_cache[id] = font
	return font


func get_audio(id: String) -> AudioStream:
	if _audio_cache.has(id):
		return _audio_cache[id]
	var path := resolve_path(id)
	var stream: AudioStream = null
	if path != "":
		if path.begins_with("res://") and ResourceLoader.exists(path, "AudioStream"):
			stream = load(path) as AudioStream
		if stream == null and path.ends_with(".wav") and FileAccess.file_exists(path):
			stream = AudioStreamWAV.load_from_file(path)
	if stream == null and not missing_ids.has(id):
		missing_ids.append(id)
	_audio_cache[id] = stream
	return stream


func _get_fallback_texture() -> Texture2D:
	if _fallback_texture == null:
		var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
		for y in 64:
			for x in 64:
				var checker := ((x / 8) + (y / 8)) % 2 == 0
				img.set_pixel(x, y, Color(1, 0, 1, 0.9) if checker else Color(0, 0, 0, 0.9))
		_fallback_texture = ImageTexture.create_from_image(img)
	return _fallback_texture


## 검수 도구와 개발 화면용 요약.
func report() -> Dictionary:
	var counts := {"placeholder": 0, "final": 0, "derived": 0, "planned": 0, "unknown": 0, "file_missing": []}
	for id: String in entries.keys():
		var st := status(id)
		counts[st] = int(counts.get(st, 0)) + 1
		if st != "planned" and resolve_path(id) == "":
			counts["file_missing"].append(id)
	counts["runtime_fallbacks"] = Array(missing_ids)
	return counts

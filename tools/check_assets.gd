extends Node
## 에셋 검수 (AST-01 자동 항목): 매니페스트의 모든 항목에 대해 파일 존재, 규격(크기·프레임·알파), 애니메이션 프레임 범위,
## 데이터 파일이 참조하는 에셋 ID 의 존재 여부를 확인한다. 실행: godot --headless --path . -- --tool=check_assets

var launch_args: Dictionary = {}
var problems: PackedStringArray = []
var checked: int = 0


func _ready() -> void:
	for id: String in AssetRegistry.entries.keys():
		_check_entry(id, AssetRegistry.entry(id))
	_check_data_refs()
	var rep := AssetRegistry.report()
	print("asset check: %d entries checked, placeholder=%d final=%d planned=%d problems=%d" % [checked, rep["placeholder"], rep["final"], rep["planned"], problems.size()])
	for p in problems:
		printerr("  " + p)
	get_tree().quit(1 if problems.size() > 0 else 0)


func _check_entry(id: String, e: Dictionary) -> void:
	checked += 1
	var status := String(e.get("status", ""))
	if status == "planned":
		return
	var path := AssetRegistry.resolve_path(id)
	if path == "":
		problems.append("%s: file missing (%s)" % [id, e.get("path", "")])
		return
	if status == "final" and String(e.get("final_path", "")) == "" and not path.begins_with(AssetRegistry.override_dir):
		problems.append("%s: status final but final_path empty" % id)
	match String(e.get("type", "texture")):
		"font", "audio":
			return
	var img := Image.new()
	if img.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK:
		problems.append("%s: cannot decode png" % id)
		return
	var cols := int(e.get("columns", 1))
	var rows := int(e.get("rows", 1))
	var fs: Array = e.get("frame_size", [img.get_width() / cols, img.get_height() / rows])
	if img.get_width() != int(fs[0]) * cols or img.get_height() != int(fs[1]) * rows:
		problems.append("%s: size %dx%d != frame %sx%s * %dx%d" % [id, img.get_width(), img.get_height(), fs[0], fs[1], cols, rows])
	if not img.detect_alpha() and String(e.get("type", "")) != "texture" or (String(e.get("type", "")) == "sprite_sheet" and img.detect_alpha() == Image.ALPHA_NONE):
		problems.append("%s: no alpha channel for sprite" % id)
	var anim: Dictionary = e.get("animation", {})
	for f in anim.get("frames", []):
		if int(f) < 0 or int(f) >= cols:
			problems.append("%s: animation frame %d out of range (columns %d)" % [id, int(f), cols])
	for ev_name: String in anim.get("event_frames", {}).keys():
		var f := int(anim["event_frames"][ev_name])
		if f < 0 or f >= cols:
			problems.append("%s: event frame '%s'=%d out of range" % [id, ev_name, f])
	var anchor: Array = e.get("anchor", [0.5, 0.82])
	if float(anchor[0]) < 0.0 or float(anchor[0]) > 1.0 or float(anchor[1]) < 0.0 or float(anchor[1]) > 1.0:
		problems.append("%s: anchor out of 0..1" % id)


func _check_data_refs() -> void:
	# classes / enemies / rooms 가 참조하는 에셋 ID 가 매니페스트에 있는지
	for cid: String in ContentDB.classes.keys():
		var c: Dictionary = ContentDB.classes[cid]
		if not bool(c.get("implemented", false)):
			continue
		var prefix := String(c.get("assets", {}).get("sprite", ""))
		for anim in ["idle", "walk", "attack", "cast", "hit", "down"]:
			_require(prefix + "." + anim, "class " + cid)
		_require(String(c.get("assets", {}).get("icon", "")), "class " + cid)
		for k in ["q", "e", "r"]:
			var sk: Dictionary = c.get("skills", {}).get(k, {})
			_require(String(sk.get("assets", {}).get("icon", "")), "skill %s.%s" % [cid, k])
			_require(String(sk.get("assets", {}).get("vfx", "")), "skill %s.%s vfx" % [cid, k])
	for eid: String in ContentDB.enemies.keys():
		var en: Dictionary = ContentDB.enemies[eid]
		if not bool(en.get("implemented", false)):
			continue
		var prefix := String(en.get("assets", {}).get("sprite", ""))
		for anim in ["idle", "walk", "attack", "hit", "death"]:
			_require(prefix + "." + anim, "enemy " + eid)
		_require(String(en.get("attack", {}).get("telegraph_asset", "")), "enemy %s telegraph" % eid)
	for rid: String in ContentDB.rooms.keys():
		var r: Dictionary = ContentDB.rooms[rid]
		for k in ["ground", "wall", "water"]:
			_require(String(r.get("assets", {}).get(k, "")), "room %s %s" % [rid, k])
		for ob: Dictionary in r.get("obstacles", []):
			_require(String(ob.get("asset", "")), "room %s obstacle" % rid)


func _require(id: String, ctx: String) -> void:
	if id == "":
		problems.append("%s: empty asset id" % ctx)
	elif not AssetRegistry.has(id):
		problems.append("%s: unknown asset id '%s'" % [ctx, id])
	elif AssetRegistry.status(id) != "planned" and AssetRegistry.resolve_path(id) == "":
		problems.append("%s: asset '%s' has no file" % [ctx, id])
	elif AssetRegistry.status(id) == "planned":
		problems.append("%s: asset '%s' is only planned (no file) but referenced by implemented content" % [ctx, id])

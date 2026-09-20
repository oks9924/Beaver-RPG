extends Node
## 모든 .gd 스크립트를 autoload 가 있는 환경에서 로드해 파싱·컴파일 오류를 찾는다.
## 실행: godot --headless --path . -- --tool=lint_all

var launch_args: Dictionary = {}


func _ready() -> void:
	var files: Array = []
	_collect("res://", files)
	var failed := 0
	for f: String in files:
		var s: Script = load(f)
		if s == null:
			failed += 1
			printerr("LOAD FAILED: " + f)
	print("lint: %d scripts, %d failed" % [files.size(), failed])
	get_tree().quit(1 if failed > 0 else 0)


func _collect(dir: String, out: Array) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	d.list_dir_begin()
	var n := d.get_next()
	while n != "":
		if d.current_is_dir():
			if not n.begins_with(".") and n != "build":
				_collect(dir.path_join(n), out)
		elif n.ends_with(".gd"):
			out.append(dir.path_join(n))
		n = d.get_next()

extends Node
## 부트 진입점. 전용 서버 export(feature "dedicated_server") 또는 `-- --server` 인자로 서버를,
## `-- --tool=<name>` 으로 tools/<name>.gd 를(autoload 포함 환경에서) 실행하고,
## 그 외에는 설치형 클라이언트를 띄운다. 서버와 클라이언트는 같은 프로젝트를 공유하지만
## 다른 프로세스로 실행되며 서로의 노드에 의존하지 않는다.

func _ready() -> void:
	var args := Protocol.parse_user_args()
	if args.has("tool"):
		var path := "res://tools/%s.gd" % String(args["tool"])
		var script: GDScript = load(path)
		if script == null or not script.can_instantiate():
			printerr("tool not found or failed to compile: " + path)
			get_tree().quit(2)
			return
		var tool_node: Node = script.new()
		tool_node.name = "Tool"
		if "launch_args" in tool_node:
			tool_node.launch_args = args
		add_child(tool_node)
		return
	var is_server := OS.has_feature("dedicated_server") or (args.has("server") and args["server"] is bool)
	var script_path := "res://server/server_main.gd" if is_server else "res://client/client_main.gd"
	var main_script: GDScript = load(script_path)
	var main: Node = main_script.new()
	main.name = "ServerMain" if is_server else "ClientMain"
	main.launch_args = args
	add_child(main)

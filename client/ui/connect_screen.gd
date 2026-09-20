class_name ConnectScreen
extends Control
## 서버 선택·주소 입력·최근 접속. 온라인 상태와 정원은 hello 이후 표시한다.

signal connect_requested(address: String, port: int)

var settings: ClientSettings
var status_label: Label
var address_edit: LineEdit
var port_edit: LineEdit
var server_list: ItemList
var connect_btn: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var panel := UIKit.panel(Vector2(520, 0))
	var v := UIKit.vbox(10)
	panel.add_child(v)
	v.add_child(UIKit.label("꼬리원정대: 검은 물결", 28, Color(0.98, 0.85, 0.45)))
	v.add_child(UIKit.label("서버 선택  (클라이언트 %s · 프로토콜 %d · 콘텐츠 %s)" % [Protocol.BUILD_VERSION, Protocol.PROTOCOL_VERSION, Protocol.CONTENT_VERSION], 13, Color(0.7, 0.7, 0.65)))
	server_list = ItemList.new()
	server_list.custom_minimum_size = Vector2(0, 140)
	server_list.item_selected.connect(_on_select)
	v.add_child(server_list)
	var h := UIKit.hbox()
	address_edit = UIKit.line_edit("서버 주소 (예: 127.0.0.1)")
	address_edit.size_flags_horizontal = SIZE_EXPAND_FILL
	port_edit = UIKit.line_edit("포트")
	port_edit.custom_minimum_size = Vector2(90, 0)
	port_edit.text = str(Protocol.DEFAULT_PORT)
	h.add_child(address_edit)
	h.add_child(port_edit)
	v.add_child(h)
	var h2 := UIKit.hbox()
	connect_btn = UIKit.button("접속", _on_connect)
	h2.add_child(connect_btn)
	h2.add_child(UIKit.button("목록에 추가", _on_add))
	h2.add_child(UIKit.button("종료", func() -> void: get_tree().quit()))
	v.add_child(h2)
	status_label = UIKit.label("", 14, Color(0.95, 0.7, 0.6))
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size = Vector2(480, 40)
	v.add_child(status_label)
	add_child(UIKit.center(panel))
	address_edit.text_submitted.connect(func(_t: String) -> void: _on_connect())


func refresh(s: ClientSettings) -> void:
	settings = s
	server_list.clear()
	for srv: Dictionary in settings.data["servers"]:
		server_list.add_item("%s  —  %s:%d" % [srv["name"], srv["address"], int(srv["port"])])
	var recent: Array = settings.data.get("recent", [])
	if not recent.is_empty():
		var parts: PackedStringArray = String(recent[0]).split(":")
		address_edit.text = parts[0]
		if parts.size() > 1:
			port_edit.text = parts[1]
	elif not settings.data["servers"].is_empty():
		address_edit.text = String(settings.data["servers"][0]["address"])
		port_edit.text = str(int(settings.data["servers"][0]["port"]))


func set_status(text: String, busy: bool = false) -> void:
	status_label.text = text
	connect_btn.disabled = busy


func _on_select(i: int) -> void:
	var srv: Dictionary = settings.data["servers"][i]
	address_edit.text = String(srv["address"])
	port_edit.text = str(int(srv["port"]))


func _on_add() -> void:
	var addr := address_edit.text.strip_edges()
	if addr == "":
		return
	settings.add_recent(addr, int(port_edit.text))
	refresh(settings)


func _on_connect() -> void:
	var addr := address_edit.text.strip_edges()
	var port := int(port_edit.text)
	if addr == "" or port <= 0 or port > 65535:
		set_status("주소와 포트를 확인하세요.")
		return
	connect_requested.emit(addr, port)

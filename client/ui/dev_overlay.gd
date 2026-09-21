class_name DevOverlay
extends Label
## F3 개발용 화면: FPS, 지연, 서버 처리 시간, 연결 상태, 엔티티 수, 시드, 에셋 대체 수.

func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_TOP_LEFT)
	position = Vector2(440, 8)
	add_theme_font_size_override("font_size", 14)
	add_theme_color_override("font_color", Color(0.8, 1.0, 0.8))
	visible = false


func update_info(net: NetClient, world: WorldView, room: Dictionary, seq: int, pending: int) -> void:
	var rep := AssetRegistry.report()
	text = "FPS %d · ping %dms · 서버 tick %.2fms · 상태 %d\n엔티티 %d · 예고 %d · 시드 %s · N %s · 입력 seq %d (미확인 %d)\n에셋: 임시 %d / 확정 %d / 파생 %d / 예정 %d · 런타임 대체 %d" % [
		Engine.get_frames_per_second(), net.ping_ms, net.server_tick_ms, net.state, world.entities.size(), world.telegraphs.size(),
		room.get("seed", "-"), room.get("n", "-"), seq, pending, rep.get("placeholder", 0), rep.get("final", 0), rep.get("derived", 0), rep.get("planned", 0), rep.get("runtime_fallbacks", []).size()]

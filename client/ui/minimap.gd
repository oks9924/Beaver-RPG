class_name Minimap
extends Control
## 전투 미니맵 (18절): 방 경계 안의 아군·적·목표물·보스·핑을 축소해 그린다. Tab 으로 큰 지도(경로 포함) 전환.

var bounds: Rect2 = Rect2(0, 0, 1200, 800)
var players: Array = []      # [pos, is_me, downed]
var enemies: Array = []      # [pos, elite]
var objectives: Array = []   # [pos, kind]
var boss_pos: Vector2 = Vector2.ZERO
var has_boss: bool = false
var pings: Array = []        # [pos, t_left, nick]
var big: bool = false
var route_text: String = ""


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(180, 120)


func _process(dt: float) -> void:
	var i := pings.size() - 1
	while i >= 0:
		pings[i][1] = float(pings[i][1]) - dt
		if float(pings[i][1]) <= 0.0:
			pings.remove_at(i)
		i -= 1
	queue_redraw()


func _draw() -> void:
	var w := 320.0 if big else 180.0
	var h := w * bounds.size.y / maxf(bounds.size.x, 1.0)
	draw_rect(Rect2(0, 0, w, h), Color(0.05, 0.08, 0.05, 0.75))
	draw_rect(Rect2(0, 0, w, h), Color(0.6, 0.55, 0.4, 0.9), false, 1.5)
	var sx := w / maxf(bounds.size.x, 1.0)
	var sy := h / maxf(bounds.size.y, 1.0)
	for o in objectives:
		var p: Vector2 = Vector2((o[0].x - bounds.position.x) * sx, (o[0].y - bounds.position.y) * sy)
		draw_rect(Rect2(p - Vector2(3, 3), Vector2(6, 6)), Color(0.9, 0.85, 0.4))
	for e in enemies:
		var p: Vector2 = Vector2((e[0].x - bounds.position.x) * sx, (e[0].y - bounds.position.y) * sy)
		draw_circle(p, 3.5 if e[1] else 2.0, Color(0.95, 0.35, 0.3))
	if has_boss:
		var p := Vector2((boss_pos.x - bounds.position.x) * sx, (boss_pos.y - bounds.position.y) * sy)
		draw_circle(p, 6.0, Color(1.0, 0.5, 0.2))
	for pl in players:
		var p: Vector2 = Vector2((pl[0].x - bounds.position.x) * sx, (pl[0].y - bounds.position.y) * sy)
		draw_circle(p, 4.0 if pl[1] else 3.0, Color(1.0, 0.4, 0.3) if pl[2] else (Color(0.5, 1.0, 0.6) if pl[1] else Color(0.5, 0.75, 1.0)))
	for pg in pings:
		var p: Vector2 = Vector2((pg[0].x - bounds.position.x) * sx, (pg[0].y - bounds.position.y) * sy)
		draw_arc(p, 6.0 + 4.0 * sin(float(pg[1]) * 6.0), 0, TAU, 16, Color(1.0, 0.9, 0.3), 2.0)
	if big and route_text != "":
		draw_string(AssetRegistry.get_font("font.ui.main"), Vector2(0, h + 18), route_text, HORIZONTAL_ALIGNMENT_LEFT, w + 200, 12, Color(0.95, 0.92, 0.85))

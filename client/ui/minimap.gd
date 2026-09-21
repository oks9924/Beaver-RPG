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
var dungeon: Dictionary = {}      # RUN_STATE.dungeon (격자: rooms {"x,y": {x,y,type,cleared,visited,doors}})
var current_cell: String = ""
const TYPE_MARK := {"combat": "전", "elite": "정", "boss": "보", "treasure": "물", "shop": "상", "rest": "휴", "event": "사", "?": "?"}
const TYPE_COLOR := {"combat": Color(0.75, 0.7, 0.6), "elite": Color(0.95, 0.55, 0.3), "boss": Color(1.0, 0.35, 0.3), "treasure": Color(1.0, 0.85, 0.4), "shop": Color(0.5, 0.85, 1.0), "rest": Color(0.6, 1.0, 0.7), "event": Color(0.85, 0.7, 1.0), "?": Color(0.5, 0.5, 0.5)}


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
	# 던전 격자: 큰 지도에서는 방 지도 왼쪽(파티 패널과 겹치지 않게), 작은 지도에서는 아래에
	if big:
		var cell := 34.0
		var gw := float(int(dungeon.get("cols", 5))) * (cell + 4.0)
		if route_text != "":
			draw_string(AssetRegistry.get_font("font.ui.main"), Vector2(-gw - 12.0, h + 18), route_text, HORIZONTAL_ALIGNMENT_LEFT, w + gw, 12, Color(0.95, 0.92, 0.85))
		_draw_grid(Vector2(-gw - 12.0, 0), cell)
	else:
		_draw_grid(Vector2(0, h + 6.0), 20.0)


## 던파식 던전 격자: 방문한 방은 채움, 현재 방은 테두리, 보스는 처음부터 표시. 드러난 방만 유형 글자.
func _draw_grid(origin: Vector2, cell: float) -> void:
	if dungeon.is_empty():
		return
	var cols := int(dungeon.get("cols", 5))
	var rows := int(dungeon.get("rows", 3))
	var gap := 4.0
	var font := AssetRegistry.get_font("font.ui.main")
	draw_rect(Rect2(origin - Vector2(3, 3), Vector2(cols * (cell + gap) + 6, rows * (cell + gap) + 6)), Color(0.05, 0.08, 0.05, 0.7))
	var rooms: Dictionary = dungeon.get("rooms", {})
	for k: String in rooms.keys():
		var r: Dictionary = rooms[k]
		var x := float(int(r["x"])) * (cell + gap)
		var y := float(int(r["y"])) * (cell + gap)
		var rect := Rect2(origin + Vector2(x, y), Vector2(cell, cell))
		var t := String(r.get("type", "?"))
		var col: Color = TYPE_COLOR.get(t, TYPE_COLOR["?"])
		var fill := col
		fill.a = 0.85 if bool(r.get("visited", false)) else 0.35
		draw_rect(rect, fill)
		if bool(r.get("cleared", false)):
			draw_line(rect.position + Vector2(3, 3), rect.end - Vector2(3, 3), Color(0, 0, 0, 0.5), 1.5)
		if k == current_cell:
			draw_rect(rect.grow(1.5), Color(1.0, 1.0, 0.6), false, 2.0)
		elif k == String(dungeon.get("boss", "")):
			draw_rect(rect, Color(1.0, 0.4, 0.3), false, 1.5)
		# 문: 이웃 방향으로 짧은 선
		for d: String in r.get("doors", []):
			var c := rect.get_center()
			var dv: Vector2 = {"n": Vector2(0, -1), "s": Vector2(0, 1), "e": Vector2(1, 0), "w": Vector2(-1, 0)}.get(d, Vector2.ZERO)
			draw_line(c + dv * cell * 0.5, c + dv * (cell * 0.5 + gap), Color(0.95, 0.9, 0.7), 2.0)
		var mark: String = TYPE_MARK.get(t, "?")
		draw_string(font, rect.position + Vector2(0, cell * 0.72), mark, HORIZONTAL_ALIGNMENT_CENTER, cell, int(cell * 0.5), Color(0.05, 0.05, 0.05) if fill.a > 0.5 else Color(0.9, 0.9, 0.9))

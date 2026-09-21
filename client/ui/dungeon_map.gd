class_name DungeonMap
extends Control
## 던파식 던전 격자 지도 (화면 좌측 상단 고정). 방문한 방은 채움, 현재 방은 노란 테두리, 보스는 처음부터 빨간 테두리.
## 드러난 방(이웃)만 유형 글자를 보여 준다. Tab(큰 지도)에서는 칸이 커진다.

var dungeon: Dictionary = {}      # RUN_STATE.dungeon (rooms {"x,y": {x,y,type,cleared,visited,doors}})
var current_cell: String = ""
var title: String = ""
var big: bool = false
const TYPE_MARK := {"combat": "전", "elite": "정", "boss": "보", "treasure": "물", "shop": "상", "rest": "휴", "event": "사", "?": "?"}
const TYPE_COLOR := {"combat": Color(0.75, 0.7, 0.6), "elite": Color(0.95, 0.55, 0.3), "boss": Color(1.0, 0.35, 0.3), "treasure": Color(1.0, 0.85, 0.4), "shop": Color(0.5, 0.85, 1.0), "rest": Color(0.6, 1.0, 0.7), "event": Color(0.85, 0.7, 1.0), "?": Color(0.5, 0.5, 0.5)}


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(160, 110)


func _process(_dt: float) -> void:
	queue_redraw()


## 그려지는 크기 (px). 팀원 지도(미니맵)가 이 폭에 맞춰 아래에 붙는다.
func size_px() -> Vector2:
	var cell := 34.0 if big else 24.0
	var gap := 4.0
	var cols := int(dungeon.get("cols", 5))
	var rows := int(dungeon.get("rows", 3))
	var top := 20.0 if title != "" else 0.0
	return Vector2(cols * (cell + gap) + 4.0, rows * (cell + gap) + top + 4.0)


func _draw() -> void:
	if dungeon.is_empty():
		return
	var cell := 34.0 if big else 24.0
	var gap := 4.0
	var rows := int(dungeon.get("rows", 3))
	var font := AssetRegistry.get_font("font.ui.main")
	var sz := size_px()
	var gw := sz.x + 4.0
	var top := 20.0 if title != "" else 0.0
	var title_w := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 8.0 if title != "" else 0.0
	draw_rect(Rect2(Vector2(-4, -4), Vector2(maxf(gw + 4, title_w), rows * (cell + gap) + top + 8)), Color(0.05, 0.08, 0.05, 0.7))
	if title != "":
		draw_string_outline(font, Vector2(2, 12), title, HORIZONTAL_ALIGNMENT_LEFT, gw + 220, 14, 3, Color(0.05, 0.03, 0.01, 0.9))
		draw_string(font, Vector2(2, 12), title, HORIZONTAL_ALIGNMENT_LEFT, gw + 220, 14, Color(0.95, 0.92, 0.85))
	var origin := Vector2(2, top + 2)
	var rooms: Dictionary = dungeon.get("rooms", {})
	for k: String in rooms.keys():
		var r: Dictionary = rooms[k]
		var rect := Rect2(origin + Vector2(float(int(r["x"])) * (cell + gap), float(int(r["y"])) * (cell + gap)), Vector2(cell, cell))
		var t := String(r.get("type", "?"))
		var fill: Color = TYPE_COLOR.get(t, TYPE_COLOR["?"])
		fill.a = 0.85 if bool(r.get("visited", false)) else 0.35
		draw_rect(rect, fill)
		if bool(r.get("cleared", false)):
			draw_line(rect.position + Vector2(3, 3), rect.end - Vector2(3, 3), Color(0, 0, 0, 0.5), 1.5)
		if k == current_cell:
			draw_rect(rect.grow(1.5), Color(1.0, 1.0, 0.6), false, 2.0)
		elif k == String(dungeon.get("boss", "")):
			draw_rect(rect, Color(1.0, 0.4, 0.3), false, 1.5)
		for d: String in r.get("doors", []):
			var c := rect.get_center()
			var dv: Vector2 = {"n": Vector2(0, -1), "s": Vector2(0, 1), "e": Vector2(1, 0), "w": Vector2(-1, 0)}.get(d, Vector2.ZERO)
			draw_line(c + dv * cell * 0.5, c + dv * (cell * 0.5 + gap), Color(0.95, 0.9, 0.7), 2.0)
		var mark: String = TYPE_MARK.get(t, "?")
		draw_string_outline(font, rect.position + Vector2(0, cell * 0.72), mark, HORIZONTAL_ALIGNMENT_CENTER, cell, int(cell * 0.5), 3, Color(0.05, 0.03, 0.01, 0.9))
		draw_string(font, rect.position + Vector2(0, cell * 0.72), mark, HORIZONTAL_ALIGNMENT_CENTER, cell, int(cell * 0.5), Color(0.05, 0.05, 0.05) if fill.a > 0.5 else Color(0.9, 0.9, 0.9))

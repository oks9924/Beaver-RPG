class_name TextureBar
extends Control
## 틀+채움 두 장(같은 캔버스)으로 된 체력바. 채움을 뒤에, 틀을 앞에 놓고 채움만 비율로 자른다.
## 채움 그림이 없으면(보스바) 매니페스트의 fill_rect_px 안에 단색으로 채운다. 시트가 없으면 단순 막대로 대체한다.

var max_value: float = 100.0
var value: float = 100.0
var fill_color: Color = Color(0.3, 0.85, 0.35)
var _frame_id: String = ""
var _fs: Vector2 = Vector2(256, 24)
var _rect: Rect2 = Rect2(17, 8, 222, 9)
var _has_fill_layer: bool = false
var _ok: bool = false


func setup(frame_id: String, color: Color, width: float) -> void:
	_frame_id = frame_id
	fill_color = color
	var sheet := AssetRegistry.get_sheet(frame_id)
	_ok = not bool(sheet["is_fallback"]) and AssetRegistry.status(frame_id) == "final"
	_fs = sheet["frame_size"]
	_has_fill_layer = int(sheet["hframes"]) >= 2
	var fr: Array = AssetRegistry.entry(frame_id).get("fill_rect_px", [])
	if fr.size() == 4:
		_rect = Rect2(float(fr[0]), float(fr[1]), float(fr[2]), float(fr[3]))
	custom_minimum_size = Vector2(width, (_fs.y * width / _fs.x) if _ok else 18.0)


func _process(_dt: float) -> void:
	queue_redraw()


func _draw() -> void:
	var frac := clampf(value / maxf(max_value, 1.0), 0.0, 1.0)
	if not _ok:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.1, 0.08, 0.06))
		draw_rect(Rect2(0, 0, size.x * frac, size.y), fill_color)
		return
	var sheet := AssetRegistry.get_sheet(_frame_id)
	var tex: Texture2D = sheet["texture"]
	var sc := size.x / _fs.x
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(sc, sc))
	var cut := _rect.position.x + _rect.size.x * frac
	if _has_fill_layer:
		draw_texture_rect_region(tex, Rect2(0, 0, cut, _fs.y), Rect2(_fs.x, 0, cut, _fs.y))
	else:
		draw_rect(Rect2(_rect.position, Vector2(_rect.size.x * frac, _rect.size.y)), fill_color)
	draw_texture_rect_region(tex, Rect2(Vector2.ZERO, _fs), Rect2(Vector2.ZERO, _fs))
	draw_set_transform(Vector2.ZERO)

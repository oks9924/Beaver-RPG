class_name AudioDirector
extends Node
## 배경 음악·환경음 재생. 에셋 ID 로만 가져오며 같은 곡이면 다시 시작하지 않는다. 음량은 설정값(0~1)과 매니페스트의 권장 음량(dB)을 합친다.

var music_volume: float = 0.8
var ambient_volume: float = 0.6
var _bgm := AudioStreamPlayer.new()
var _amb := AudioStreamPlayer.new()
var _bgm_id: String = ""
var _amb_id: String = ""


func _ready() -> void:
	_bgm.bus = "Master"
	_amb.bus = "Master"
	add_child(_bgm)
	add_child(_amb)


func set_music(id: String) -> void:
	if id == _bgm_id and _bgm.playing:
		return
	_bgm_id = id
	_play(_bgm, id, music_volume)


func set_ambience(id: String) -> void:
	if id == _amb_id and _amb.playing:
		return
	_amb_id = id
	_play(_amb, id, ambient_volume)


func apply_volumes(music: float, ambient: float) -> void:
	music_volume = music
	ambient_volume = ambient
	_bgm.volume_db = _db(_bgm_id, music)
	_amb.volume_db = _db(_amb_id, ambient)


func stop_all() -> void:
	_bgm.stop()
	_amb.stop()
	_bgm_id = ""
	_amb_id = ""


func _play(p: AudioStreamPlayer, id: String, vol: float) -> void:
	p.stop()
	if id == "":
		return
	var stream := AssetRegistry.get_audio(id)
	if stream == null:
		return
	p.stream = stream
	p.volume_db = _db(id, vol)
	p.play()


func _db(id: String, vol: float) -> float:
	if vol <= 0.001:
		return -80.0
	return linear_to_db(clampf(vol, 0.0, 1.0)) + float(AssetRegistry.entry(id).get("gain_db", 0.0))

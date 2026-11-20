extends Node
## 程序化音效系统：不依赖外部音频文件，用代码合成短音效。
## 通过 autoload 注册为单例 Sound，任意处调用 Sound.play("shoot") 即可。

const SAMPLE_RATE := 22050
## 同时存在的播放器上限：子弹密集时如果无限 new 会一直堆节点
const MAX_PLAYERS := 12

var _players: Array[AudioStreamPlayer] = []
var _streams: Dictionary = {}


func _ready() -> void:
	_streams = {
		"shoot": _shoot(),
		"hit": _hit(),
		"explosion": _explosion(),
		"place": _place(),
		"sell": _sell(),
		"wave": _wave(),
		"leak": _leak(),
		"levelup": _levelup(),
		"click": _click(),
		"death": _death(),
	}


## 播放音效；若同时播放过多会自动加新播放器
func play(sound_name: String, volume_db: float = 0.0) -> void:
	var s: AudioStream = _streams.get(sound_name)
	if s == null:
		return
	var p := _get_player()
	p.stream = s
	p.volume_db = volume_db
	p.play()


func _get_player() -> AudioStreamPlayer:
	for p in _players:
		if p != null and is_instance_valid(p) and not p.playing:
			return p
	# 已经到上限：抢占「播得最靠后」的那个（音效都很短，听不出被截断）
	if _players.size() >= MAX_PLAYERS:
		var pick: AudioStreamPlayer = _players[0]
		var far := -1.0
		for p in _players:
			if p == null or not is_instance_valid(p):
				continue
			var pos := p.get_playback_position()
			if pos > far:
				far = pos
				pick = p
		return pick
	var p := AudioStreamPlayer.new()
	add_child(p)
	_players.append(p)
	return p


# ---------------------------------------------------------------- 合成

static func _to_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in range(samples.size()):
		var v := clampi(int(samples[i] * 32767.0), -32768, 32767)
		bytes.encode_s16(i * 2, v)
	wav.data = bytes
	return wav


## 填充一段固定时长的样本
static func _buf(dur: float) -> PackedFloat32Array:
	var s := PackedFloat32Array()
	s.resize(int(dur * SAMPLE_RATE))
	return s


static func _shoot() -> AudioStreamWAV:
	var s := _buf(0.07)
	for i in range(s.size()):
		var t := float(i) / SAMPLE_RATE
		var env := pow(1.0 - float(i) / s.size(), 2.0)
		s[i] = sin(TAU * 760.0 * t) * 0.7 * env
	return _to_wav(s)


static func _hit() -> AudioStreamWAV:
	var s := _buf(0.06)
	for i in range(s.size()):
		var t := float(i) / SAMPLE_RATE
		var env := pow(1.0 - float(i) / s.size(), 3.0)
		s[i] = sin(TAU * 320.0 * t) * 0.6 * env
	return _to_wav(s)


static func _explosion() -> AudioStreamWAV:
	var s := _buf(0.30)
	var seed_v := 0
	for i in range(s.size()):
		var t := float(i) / SAMPLE_RATE
		var env := pow(1.0 - float(i) / s.size(), 2.5)
		seed_v = (seed_v * 1103515245 + 12345) & 0x7fffffff
		var noise := (float(seed_v % 1000) / 500.0 - 1.0)
		s[i] = (noise * 0.9 + sin(TAU * 120.0 * t) * 0.3) * env
	return _to_wav(s)


static func _place() -> AudioStreamWAV:
	var s := _buf(0.09)
	for i in range(s.size()):
		var t := float(i) / SAMPLE_RATE
		var env := pow(1.0 - float(i) / s.size(), 2.0)
		s[i] = sin(TAU * 210.0 * t) * 0.65 * env
	return _to_wav(s)


static func _sell() -> AudioStreamWAV:
	var s := _buf(0.12)
	for i in range(s.size()):
		var t := float(i) / SAMPLE_RATE
		var f := 520.0 - 260.0 * (float(i) / s.size())
		var env := pow(1.0 - float(i) / s.size(), 2.0)
		s[i] = sin(TAU * f * t) * 0.5 * env
	return _to_wav(s)


static func _wave() -> AudioStreamWAV:
	var s := _buf(0.40)
	for i in range(s.size()):
		var t := float(i) / SAMPLE_RATE
		var env := pow(1.0 - float(i) / s.size(), 1.5)
		s[i] = (sin(TAU * 180.0 * t) + sin(TAU * 270.0 * t) * 0.5) * 0.5 * env
	return _to_wav(s)


static func _leak() -> AudioStreamWAV:
	var s := _buf(0.20)
	for i in range(s.size()):
		var t := float(i) / SAMPLE_RATE
		var f := 620.0 - 380.0 * (float(i) / s.size())
		var env := pow(1.0 - float(i) / s.size(), 2.0)
		s[i] = sin(TAU * f * t) * 0.55 * env
	return _to_wav(s)


static func _levelup() -> AudioStreamWAV:
	var s := _buf(0.16)
	for i in range(s.size()):
		var t := float(i) / SAMPLE_RATE
		var env := sin(PI * float(i) / s.size())
		var note := 520.0 if float(i) / s.size() < 0.5 else 780.0
		s[i] = sin(TAU * note * t) * 0.5 * env
	return _to_wav(s)


static func _click() -> AudioStreamWAV:
	var s := _buf(0.04)
	for i in range(s.size()):
		var t := float(i) / SAMPLE_RATE
		var env := pow(1.0 - float(i) / s.size(), 3.0)
		s[i] = sin(TAU * 980.0 * t) * 0.45 * env
	return _to_wav(s)


static func _death() -> AudioStreamWAV:
	var s := _buf(0.24)
	var seed_v := 0
	for i in range(s.size()):
		var t := float(i) / SAMPLE_RATE
		var env := pow(1.0 - float(i) / s.size(), 2.0)
		seed_v = (seed_v * 1103515245 + 12345) & 0x7fffffff
		var noise := (float(seed_v % 1000) / 500.0 - 1.0)
		s[i] = (noise * 0.6 + sin(TAU * 90.0 * t) * 0.3) * env
	return _to_wav(s)

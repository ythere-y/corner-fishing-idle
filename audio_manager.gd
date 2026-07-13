extends Node

const MANIFEST_PATH := "res://assets/audio/audio_manifest.json"
const SETTINGS_PATH := "user://audio_settings.json"
const SFX_POOL_SIZE := 8
const SILENT_DB := -80.0

const DEFAULT_COOLDOWNS_MS := {
	"ui_click": 55,
	"ui_error": 120,
	"coin": 100,
	"cast": 180,
	"bobber_splash": 160,
	"bite": 250,
	# 里程碑音都比一次性音效长得多，抢在自己的尾音上重播会糊成一片。
	"sfx_achievement": 700,     # 一次 _check_achievements 可能连解锁数个成就
	"sfx_new_species": 400,     # 双钩可能一竿上两条新鱼
	"sfx_record": 400,
	"sfx_cat_steal": 1200,      # 猫连续得手时别变成猫叫机关枪
	"sfx_event_appear": 500,
	"sfx_fish_struggle": 300,
	"sfx_competition_win": 1500,
	"sfx_spot_unlock": 1500,
}

var master_volume := 0.8
var sfx_volume := 0.85
var ambience_volume := 0.42
var music_volume := 0.30   # BGM 坐在环境床「之下」：这是桌面挂件，不是播放器
var music_enabled := true  # 与音量分开：关掉后重开能记住原音量
var muted := false

var _streams := {}
var _metadata := {}
var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_next := 0
var _ambience_player: AudioStreamPlayer   # water base 层 player（保留旧名以兼容引用）
var _last_played_ms := {}

# —— BGM：白昼曲 / 夜曲两条，按时段交叉淡入淡出 ——
# 与环境床同构（gain/target + _process 推进），但换曲比换环境床更慢，避免"切歌感"。
const MUSIC_FADE := 4.0
const MUSIC_TRACKS := ["bgm_day", "bgm_night"]
var _music := {}          # id -> {player, gain, target}
var _music_key := ""      # 当前应当发声的曲目 id，相同则不重排

# —— 咬钩→上鱼那 0.9 秒的张力循环 ——
# 独占一个 player：它是唯一的「持续」音效，塞进 8 音轨轮转池会被下一发 play_sfx 掐断。
# 淡入要快（张力必须立刻建立），淡出要慢一点（免得上鱼瞬间出现一个硬切）。
const TENSION_FADE_IN := 0.10
const TENSION_FADE_OUT := 0.22
const TENSION_TRIM_DB := -3.0   # 它一直在响，比一次性音效再压低一档
var _tension: AudioStreamPlayer
var _tension_gain := 0.0
var _tension_target := 0.0

# —— 分层环境音床：多条循环音叠加，按「钓点生态 × 昼夜时段」配方平滑淡入淡出 ——
# 缺素材的层自动不建 player、配方里也被跳过 → 零素材时优雅退化为现有单层水声，不报错不退化。
# 即使只剩 water 一层，配方里的时段动态增益（夜静/晨昏柔/白昼足）也能听出氛围差异。
const AMB_FADE := 2.5   # 层增益淡入淡出到位的近似秒数（柔和过渡，绝不突变）
const AMBIENCE_LAYERS := [
	"ambience_water_loop",  # 通用静水底噪（已有素材；多数淡水钓点的 base）
	"amb_stream_loop",      # 急流溪声（山溪/河湾，比 water 更有流动感）
	"amb_birds_day",        # 白昼林鸟啁啾（淡水/林地，昼与晨昏）
	"amb_wind_loop",        # 旷野风声（湖泊/极地，轻铺）
	"amb_night_insects",    # 夜虫（暖季夜晚，非极地/海洋）
	"amb_waves_loop",       # 海浪涌动（海洋钓点 base）
	"amb_gulls_day",        # 海鸥（海岸，昼）
	"amb_cave_drip",        # 洞穴水滴回声（cavern_pool base）
]
# 钓点 → 生态分类（决定环境床配方）；未列出的回退 freshwater。
const SPOT_BIOME := {
	"river_bend": "freshwater", "still_lake": "lake", "mountain_stream": "stream",
	"urban_pond": "freshwater", "coast_pier": "sea", "estuary": "sea",
	"deep_sea": "sea", "coral_reef": "sea", "polar_lake": "polar", "cavern_pool": "cavern",
}
var _amb := {}                 # id -> {player, gain, target}
var _amb_scene_key := ""       # 当前 "biome|phase"，相同则不重排配方


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_manifest()
	_build_players()
	_load_settings()
	_apply_current_volumes()


func _exit_tree() -> void:
	stop_ambience()
	stop_music()
	stop_tension()
	for player in _sfx_players:
		player.stop()
		player.stream = null
	for id in _amb:
		_amb[id]["player"].stream = null
	for id in _music:
		_music[id]["player"].stream = null
	if _tension != null:
		_tension.stop()
		_tension.stream = null
	_amb.clear()
	_music.clear()
	_streams.clear()
	_metadata.clear()


func has(id: String) -> bool:
	return _streams.has(id)


func play(id: String) -> void:
	if id == "ambience_water_loop":
		start_ambience()
	else:
		play_sfx(id)


func play_ui(id: String) -> void:
	play_sfx(id)


func play_sfx(id: String) -> void:
	if muted or not _streams.has(id) or _is_on_cooldown(id):
		return
	if _sfx_players.is_empty():
		return
	var player := _sfx_players[_sfx_next]
	_sfx_next = (_sfx_next + 1) % _sfx_players.size()
	player.stop()
	player.stream = _streams[id]
	player.volume_db = _sfx_db()
	player.play()


## 兼容旧入口：未设置过场景时，起一个默认淡水白昼床（正常路径走 set_ambience_scene）。
func start_ambience() -> void:
	if _amb_scene_key == "":
		set_ambience_scene("river_bend", "day")


func stop_ambience() -> void:
	for id in _amb:
		_amb[id]["target"] = 0.0
		_amb[id]["gain"] = 0.0
		var pl: AudioStreamPlayer = _amb[id]["player"]
		if pl.playing:
			pl.stop()


## 按「钓点生态 × 时段」铺设环境床：出现的层淡入到目标增益，未出现的层淡出到 0。
## 缺素材的层（未建 player）自动跳过；同一配方重复调用直接返回，不打断当前过渡。
func set_ambience_scene(spot_key: String, phase: String) -> void:
	set_music_scene(phase)   # 同一处调用点已覆盖开局/换时段/换钓点三种情形
	var biome := str(SPOT_BIOME.get(spot_key, "freshwater"))
	var key := biome + "|" + phase
	if key == _amb_scene_key:
		return
	_amb_scene_key = key
	var recipe := _ambience_recipe(biome, phase)
	for id in _amb:
		var want := float(recipe.get(id, 0.0))
		_amb[id]["target"] = want
		if want > 0.0:
			var pl: AudioStreamPlayer = _amb[id]["player"]
			if not pl.playing:
				pl.play()


## 按时段选 BGM（夜曲只在 night，其余时段用白昼曲），交叉淡入淡出。
## 缺素材的曲目不建 player，这里自动跳过 → 零 BGM 时静默退化，不报错。
func set_music_scene(phase: String) -> void:
	var want := "bgm_night" if phase == "night" else "bgm_day"
	if want == _music_key:
		return
	_music_key = want
	_apply_music_targets()


func _apply_music_targets() -> void:
	for id in _music:
		var on: bool = music_enabled and not muted and id == _music_key
		_music[id]["target"] = 1.0 if on else 0.0
		if on:
			var pl: AudioStreamPlayer = _music[id]["player"]
			if not pl.playing:
				pl.play()


func stop_music() -> void:
	for id in _music:
		_music[id]["target"] = 0.0
		_music[id]["gain"] = 0.0
		var pl: AudioStreamPlayer = _music[id]["player"]
		if pl.playing:
			pl.stop()


## 咬钩后拉起张力循环。`tier` 越高音越沉——同一段素材靠变调承担全部体型表达。
func start_tension(tier: int) -> void:
	if muted or _tension == null or _tension.stream == null:
		return
	_tension.pitch_scale = clampf(1.08 - 0.05 * float(tier), 0.78, 1.10)
	if not _tension.playing:
		_tension.play()
	_tension_target = 1.0


func stop_tension() -> void:
	_tension_target = 0.0


## 环境床配方：返回 {层id: 相对增益0..1}。先按生态选层，再叠加全局时段动态。
func _ambience_recipe(biome: String, phase: String) -> Dictionary:
	var r := {}
	var night := phase == "night"
	var golden := phase == "dawn" or phase == "dusk"
	match biome:
		"sea":
			r["amb_waves_loop"] = 1.0
			r["ambience_water_loop"] = 0.25       # 海浪缺素材时仍有水声兜底
			if not night:
				r["amb_gulls_day"] = 0.6 if phase == "day" else 0.4
		"cavern":
			r["amb_cave_drip"] = 0.9
			r["ambience_water_loop"] = 0.3
		"stream":
			r["amb_stream_loop"] = 0.9
			r["ambience_water_loop"] = 0.4
			if not night:
				r["amb_birds_day"] = 0.5 if phase == "day" else 0.35
		"lake":
			r["ambience_water_loop"] = 0.7
			r["amb_wind_loop"] = 0.45
			if not night:
				r["amb_birds_day"] = 0.4 if phase == "day" else 0.3
			if night:
				r["amb_night_insects"] = 0.35
		"polar":
			r["ambience_water_loop"] = 0.5
			r["amb_wind_loop"] = 0.7              # 极地风更显，无虫鸟
		_:  # freshwater
			r["ambience_water_loop"] = 0.8
			if not night:
				r["amb_birds_day"] = 0.55 if phase == "day" else 0.4
			if night:
				r["amb_night_insects"] = 0.4
	# 全局时段动态：夜最静、晨昏略柔、白昼最足（只有 water 一层时也能听出差异）
	var bed := 1.0
	if night:
		bed = 0.7
	elif golden:
		bed = 0.88
	for k in r:
		r[k] = clampf(float(r[k]) * bed, 0.0, 1.0)
	return r


## 每帧把环境层 / BGM / 张力层的增益平滑推向各自目标，并据此设音量；
## 淡出到 0 的 player 停播省资源。三组各有自己的淡变时长。
func _process(delta: float) -> void:
	_advance_layers(_amb, delta / AMB_FADE, _amb_layer_db)
	_advance_layers(_music, delta / MUSIC_FADE, _music_layer_db)
	_advance_tension(delta)


## 把一组 {id: {player, gain, target}} 的增益推进一步。`to_db` 决定该组的音量口径。
func _advance_layers(layers: Dictionary, step: float, to_db: Callable) -> void:
	for id in layers:
		var L: Dictionary = layers[id]
		var g: float = move_toward(float(L["gain"]), float(L["target"]), step)
		if g == float(L["gain"]):
			continue
		L["gain"] = g
		var pl: AudioStreamPlayer = L["player"]
		pl.volume_db = to_db.call(g)
		if g <= 0.0001 and float(L["target"]) <= 0.0 and pl.playing:
			pl.stop()


func _advance_tension(delta: float) -> void:
	if _tension == null:
		return
	var rising := _tension_target > _tension_gain
	var step := delta / (TENSION_FADE_IN if rising else TENSION_FADE_OUT)
	var g: float = move_toward(_tension_gain, _tension_target, step)
	if g == _tension_gain:
		return
	_tension_gain = g
	_tension.volume_db = _tension_db(g)
	if g <= 0.0001 and _tension_target <= 0.0 and _tension.playing:
		_tension.stop()


func _amb_layer_db(gain: float) -> float:
	if muted or gain <= 0.001:
		return SILENT_DB
	return _linear_volume_to_db(master_volume * ambience_volume * gain)


func _music_layer_db(gain: float) -> float:
	if muted or not music_enabled or gain <= 0.001:
		return SILENT_DB
	return _linear_volume_to_db(master_volume * music_volume * gain)


func _tension_db(gain: float) -> float:
	if muted or gain <= 0.001:
		return SILENT_DB
	var linear := master_volume * sfx_volume * gain * db_to_linear(TENSION_TRIM_DB)
	return _linear_volume_to_db(linear)


func set_master_volume(value: float) -> void:
	master_volume = clampf(value, 0.0, 1.0)
	_apply_current_volumes()
	_save_settings()


func set_sfx_volume(value: float) -> void:
	sfx_volume = clampf(value, 0.0, 1.0)
	_apply_current_volumes()
	_save_settings()


func set_ambience_volume(value: float) -> void:
	ambience_volume = clampf(value, 0.0, 1.0)
	_apply_current_volumes()
	_save_settings()


func set_music_volume(value: float) -> void:
	music_volume = clampf(value, 0.0, 1.0)
	_apply_current_volumes()
	_save_settings()


func set_music_enabled(value: bool) -> void:
	music_enabled = value
	_apply_music_targets()   # 关 → 淡出；开 → 当前时段那条淡回来
	_apply_current_volumes()
	_save_settings()


func set_muted(value: bool) -> void:
	muted = value
	if muted:
		stop_tension()
	_apply_music_targets()
	_apply_current_volumes()
	_save_settings()


func _load_manifest() -> void:
	_streams.clear()
	_metadata.clear()
	if not FileAccess.file_exists(MANIFEST_PATH):
		push_warning("Audio manifest missing: %s" % MANIFEST_PATH)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	if not (parsed is Dictionary):
		push_warning("Audio manifest is not a dictionary: %s" % MANIFEST_PATH)
		return
	for id in parsed:
		var entry: Variant = parsed[id]
		if not (entry is Dictionary):
			continue
		var path := str(entry.get("path", ""))
		if path == "" or not ResourceLoader.exists(path):
			push_warning("Audio asset missing for id '%s': %s" % [str(id), path])
			continue
		var stream := load(path) as AudioStream
		if stream == null:
			push_warning("Audio asset failed to load for id '%s': %s" % [str(id), path])
			continue
		stream = _configure_stream_looping(stream, bool(entry.get("loop", false)))
		_streams[str(id)] = stream
		_metadata[str(id)] = entry


func _configure_stream_looping(stream: AudioStream, should_loop: bool) -> AudioStream:
	if not should_loop:
		return stream
	var copy := stream.duplicate()
	if copy is AudioStreamWAV:
		copy.loop_mode = AudioStreamWAV.LOOP_FORWARD
		copy.loop_begin = 0
		# 必须显式设循环终点为全长帧数：导入档 loop_mode=Disabled 时 loop_end=0，
		# 仅运行时改 LOOP_FORWARD 会让循环区间退化为 [0,0] → 卡在首帧 = 无声。
		copy.loop_end = int(round(copy.get_length() * copy.mix_rate))
	elif copy is AudioStreamMP3:
		copy.loop = true
	elif copy is AudioStreamOggVorbis:
		copy.loop = true
	return copy


func _build_players() -> void:
	for i in range(SFX_POOL_SIZE):
		var player := AudioStreamPlayer.new()
		player.name = "SfxPlayer%d" % i
		add_child(player)
		_sfx_players.append(player)
	# 环境床：仅为「素材已就位」的层建 player（缺素材的层不建，配方里被跳过）
	for id in AMBIENCE_LAYERS:
		if not _streams.has(id):
			continue
		var pl := AudioStreamPlayer.new()
		pl.name = "Amb_" + id
		pl.stream = _streams[id]
		pl.volume_db = SILENT_DB     # 初始静音，由床淡入
		add_child(pl)
		_amb[id] = {"player": pl, "gain": 0.0, "target": 0.0}
		if id == "ambience_water_loop":
			_ambience_player = pl    # 保留旧引用语义
	# BGM：同样只为已就位的曲目建 player
	for id in MUSIC_TRACKS:
		if not _streams.has(id):
			continue
		var pl := AudioStreamPlayer.new()
		pl.name = "Music_" + id
		pl.stream = _streams[id]
		pl.volume_db = SILENT_DB
		add_child(pl)
		_music[id] = {"player": pl, "gain": 0.0, "target": 0.0}
	# 张力循环：独占 player，不进 sfx 轮转池
	if _streams.has("sfx_reel_tension"):
		_tension = AudioStreamPlayer.new()
		_tension.name = "ReelTension"
		_tension.stream = _streams["sfx_reel_tension"]
		_tension.volume_db = SILENT_DB
		add_child(_tension)


func _is_on_cooldown(id: String) -> bool:
	var cooldown_ms := int(DEFAULT_COOLDOWNS_MS.get(id, 0))
	if cooldown_ms <= 0:
		return false
	var now := Time.get_ticks_msec()
	var last := int(_last_played_ms.get(id, -cooldown_ms))
	if now - last < cooldown_ms:
		return true
	_last_played_ms[id] = now
	return false


func _sfx_db() -> float:
	if muted:
		return SILENT_DB
	return _linear_volume_to_db(master_volume * sfx_volume)


func _ambience_db() -> float:
	if muted:
		return SILENT_DB
	return _linear_volume_to_db(master_volume * ambience_volume)


func _linear_volume_to_db(value: float) -> float:
	if value <= 0.001:
		return SILENT_DB
	return linear_to_db(clampf(value, 0.001, 1.0))


func _apply_current_volumes() -> void:
	for player in _sfx_players:
		player.volume_db = _sfx_db()
	for id in _amb:
		_amb[id]["player"].volume_db = _amb_layer_db(float(_amb[id]["gain"]))
	for id in _music:
		_music[id]["player"].volume_db = _music_layer_db(float(_music[id]["gain"]))
	if _tension != null:
		_tension.volume_db = _tension_db(_tension_gain)


func _load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS_PATH))
	if not (parsed is Dictionary):
		return
	master_volume = clampf(float(parsed.get("master", master_volume)), 0.0, 1.0)
	sfx_volume = clampf(float(parsed.get("sfx", sfx_volume)), 0.0, 1.0)
	ambience_volume = clampf(float(parsed.get("ambience", ambience_volume)), 0.0, 1.0)
	music_volume = clampf(float(parsed.get("music", music_volume)), 0.0, 1.0)
	music_enabled = bool(parsed.get("music_on", music_enabled))
	muted = bool(parsed.get("muted", muted))


func _save_settings() -> void:
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({
		"master": master_volume,
		"sfx": sfx_volume,
		"ambience": ambience_volume,
		"music": music_volume,
		"music_on": music_enabled,
		"muted": muted,
	}))

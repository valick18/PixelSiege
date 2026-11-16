extends Node
# Autoload "Net": мережа (ENet), LAN-пошук серверів, UPnP, налаштування, звуки, дані класів і рецептів.

const PORT := 24565
const DISCOVERY_PORT := 24566
const MAX_PLAYERS := 20
const REACH := 90.0
const CLASSES := {
	"warrior": {"label": "Warrior", "dmg": 25, "range": 36.0, "dig": 2, "cd": 0.45, "color": Color("b03a2e"), "ability": "Charge", "ab_cd": 8.0},
	"archer": {"label": "Archer", "dmg": 12, "range": 220.0, "dig": 1, "cd": 0.7, "color": Color("1e8449"), "ability": "Backflip", "ab_cd": 8.0},
	"engineer": {"label": "Engineer", "dmg": 10, "range": 32.0, "dig": 4, "cd": 0.5, "color": Color("ca6f1e"), "ability": "Bridge", "ab_cd": 10.0},
	"support": {"label": "Support", "dmg": 8, "range": 32.0, "dig": 1, "cd": 0.5, "color": Color("7d3c98"), "ability": "Heal aura", "ab_cd": 15.0},
}
const TEAM_COLORS := [Color("2e86de"), Color("e74c3c")]
const TEAM_NAMES := ["Blue", "Red"]
const RESOURCES := ["wood", "stone", "metal"]
const RECIPES := {
	"ladder": {"cost": {"wood": 2}, "n": 2},
	"torch": {"cost": {"wood": 1, "stone": 1}, "n": 4},
	"spikes": {"cost": {"wood": 2, "metal": 1}, "n": 2},
	"tnt": {"cost": {"stone": 2, "metal": 2}, "n": 1},
	"firebomb": {"cost": {"wood": 2, "stone": 1}, "n": 1},
	"spawn": {"cost": {"wood": 10, "stone": 5}, "n": 1},
	"storage": {"cost": {"wood": 8, "stone": 2}, "n": 1},
	"catapult": {"cost": {"wood": 20, "stone": 10, "metal": 10}, "n": 1},
	"medkit": {"cost": {"wood": 2, "metal": 1}, "n": 1},
	"food": {"cost": {"wood": 1}, "n": 2},
}
const ITEM_BLOCK := {"wood": 3, "stone": 2, "metal": 4, "ladder": 9, "torch": 10, "spikes": 11, "tnt": 12, "spawn": 13, "catapult": 14, "storage": 15}
const RES_LIST := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const ACTION_KEYS := {"left": KEY_A, "right": KEY_D, "up": KEY_W, "down": KEY_S, "jump": KEY_SPACE, "crouch": KEY_CTRL, "run": KEY_SHIFT}

signal players_changed
signal connect_failed

var players := {}  # peer_id -> {name, team, cls}
var memory := {}   # name -> {team, cls}  (повернення після розриву)
var my_name := "Player"
var join_password := ""
var server_password := ""
var server_name := "Server"
var max_players := 20
var world_seed := 0
var map_size := 0  # 0 = small, 1 = medium
var last_msg := ""
var external_ip := ""
var settings := {"music": 0.7, "sfx": 0.8, "fullscreen": false, "res": 0, "keys": {}}

var found := {}  # ip -> {info, t}
var _bc: PacketPeerUDP
var _bc_t := 0.0
var _listener: PacketPeerUDP
var _upnp_thread: Thread
var _sfx := {}
var _tex := {}
var _pool: Array = []
var _pool_i := 0
var _music: AudioStreamPlayer


func _ready() -> void:
	load_settings()
	_setup_input()
	_setup_audio()
	apply_settings()
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _exit_tree() -> void:
	_close_peer()
	if _upnp_thread and _upnp_thread.is_started():
		_upnp_thread.wait_to_finish()


# ------------------------------------------------------------ settings / input / audio
func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load("user://settings.cfg") != OK:
		return
	settings.music = cf.get_value("a", "music", 0.7)
	settings.sfx = cf.get_value("a", "sfx", 0.8)
	settings.fullscreen = cf.get_value("v", "fullscreen", false)
	settings.res = cf.get_value("v", "res", 0)
	settings.keys = cf.get_value("k", "keys", {})


func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("a", "music", settings.music)
	cf.set_value("a", "sfx", settings.sfx)
	cf.set_value("v", "fullscreen", settings.fullscreen)
	cf.set_value("v", "res", settings.res)
	cf.set_value("k", "keys", settings.keys)
	cf.save("user://settings.cfg")


func apply_settings() -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), linear_to_db(maxf(0.0001, settings.music)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), linear_to_db(maxf(0.0001, settings.sfx)))
	if settings.fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(RES_LIST[clampi(settings.res, 0, 2)])


func bind_key(action: String, keycode: int) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	InputMap.action_erase_events(action)
	var e := InputEventKey.new()
	e.physical_keycode = keycode
	InputMap.action_add_event(action, e)


func _setup_input() -> void:
	for a in ACTION_KEYS:
		bind_key(a, settings.keys.get(a, ACTION_KEYS[a]))


func _make_wav(freq: float, dur: float, noise: float, decay: float) -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / rate
		var s := sin(TAU * freq * t) * (1.0 - noise) + randf_range(-1.0, 1.0) * noise
		data.encode_s16(i * 2, int(clampf(s * exp(-t * decay), -1.0, 1.0) * 28000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w


func _setup_audio() -> void:
	for bn in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bn) == -1:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bn)
	_sfx = {
		"hit": _make_wav(180, 0.12, 0.6, 25), "dig": _make_wav(120, 0.08, 0.8, 40),
		"place": _make_wav(300, 0.08, 0.2, 35), "boom": _make_wav(60, 0.7, 0.9, 5),
		"pickup": _make_wav(700, 0.1, 0.0, 25), "hurt": _make_wav(150, 0.2, 0.5, 12),
		"craft": _make_wav(500, 0.15, 0.1, 15), "flag": _make_wav(440, 0.3, 0.0, 6),
		"thunder": _make_wav(45, 0.9, 0.8, 3), "fire": _make_wav(90, 0.15, 0.9, 20),
	}
	for i in 8:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool.append(p)
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	add_child(_music)
	var d := DirAccess.open("res://assets/music")
	if d:
		for f in d.get_files():
			var fn := f.trim_suffix(".import")
			if fn.get_extension() in ["ogg", "mp3", "wav"]:
				var s = load("res://assets/music/" + fn)
				if s:
					if "loop" in s:
						s.loop = true
					_music.stream = s
					_music.play()
					break


func tex(path: String) -> Texture2D:
	if not _tex.has(path):
		_tex[path] = load(path) if ResourceLoader.exists(path) else null
	return _tex[path]


func play(n: String) -> void:
	if not _sfx.has(n):
		return
	var p: AudioStreamPlayer = _pool[_pool_i]
	_pool_i = (_pool_i + 1) % _pool.size()
	p.stream = _sfx[n]
	p.play()


# ------------------------------------------------------------ discovery / upnp
func start_listen() -> void:
	if _listener:
		return
	_listener = PacketPeerUDP.new()
	if _listener.bind(DISCOVERY_PORT, "*") != OK:
		_listener = null


func stop_listen() -> void:
	if _listener:
		_listener.close()
		_listener = null
	found.clear()


func _process(dt: float) -> void:
	if _bc and multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_bc_t += dt
		if _bc_t >= 1.0:
			_bc_t = 0.0
			var info := {"name": server_name, "players": players.size(), "max": max_players, "pw": server_password != ""}
			_bc.put_packet(JSON.stringify(info).to_utf8_buffer())
	if _listener:
		while _listener.get_available_packet_count() > 0:
			var ip := _listener.get_packet_ip()
			var d = JSON.parse_string(_listener.get_packet().get_string_from_utf8())
			if d is Dictionary:
				found[ip] = {"info": d, "t": Time.get_ticks_msec() / 1000.0}
		var now := Time.get_ticks_msec() / 1000.0
		for ip in found.keys():
			if now - found[ip].t > 4.0:
				found.erase(ip)


func _upnp_setup() -> void:
	var u := UPNP.new()
	if u.discover(2000, 2, "InternetGatewayDevice") == UPNP.UPNP_RESULT_SUCCESS:
		var gw := u.get_gateway()
		if gw and gw.is_valid_gateway():
			u.add_port_mapping(PORT, PORT, "PixelSiege", "UDP")
			external_ip = u.query_external_address()


# ------------------------------------------------------------ host / join
func _close_peer() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null


func host_game(maxp: int, seed_text: String) -> int:
	_close_peer()
	var peer := ENetMultiplayerPeer.new()
	max_players = clampi(maxp, 2, MAX_PLAYERS)
	var err := peer.create_server(PORT, max_players - 1)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	var t := seed_text.strip_edges()
	if t == "":
		world_seed = randi()
	elif t.is_valid_int():
		world_seed = int(t)
	else:
		world_seed = t.hash()
	players = {1: {"name": my_name, "team": 0, "cls": "warrior"}}
	memory = {my_name: {"team": 0, "cls": "warrior"}}
	_bc = PacketPeerUDP.new()
	_bc.set_broadcast_enabled(true)
	_bc.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	_upnp_thread = Thread.new()
	_upnp_thread.start(_upnp_setup)
	return OK


func join_game(ip: String) -> int:
	_close_peer()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip if ip != "" else "127.0.0.1", PORT)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	return OK


func leave(msg: String = "") -> void:
	last_msg = msg
	if _bc:
		_bc.close()
		_bc = null
	_close_peer()
	players.clear()
	get_tree().change_scene_to_file("res://scenes/menu.tscn")


func _on_connected() -> void:
	reg.rpc_id(1, my_name, join_password)


func _on_connection_failed() -> void:
	multiplayer.multiplayer_peer = null
	last_msg = "Connection failed"
	connect_failed.emit()


func _on_server_disconnected() -> void:
	leave("Disconnected from server (host left or connection lost)")


func _on_peer_disconnected(id: int) -> void:
	if multiplayer.is_server():
		players.erase(id)
		set_players.rpc(players)


@rpc("any_peer", "reliable")
func reg(pname: String, pw: String) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if server_password != "" and pw != server_password:
		kick.rpc_id(id, "Wrong password")
		await get_tree().create_timer(0.4).timeout
		if multiplayer.multiplayer_peer:
			multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	pname = pname.substr(0, 16)
	var team := 0
	var cls := "warrior"
	if memory.has(pname):
		team = memory[pname].team
		cls = memory[pname].cls
	else:
		var c0 := 0
		var c1 := 0
		for pid in players:
			if players[pid].team == 0:
				c0 += 1
			else:
				c1 += 1
		team = 0 if c0 <= c1 else 1
		memory[pname] = {"team": team, "cls": cls}
	players[id] = {"name": pname, "team": team, "cls": cls}
	join_ok.rpc_id(id, world_seed, map_size, players)
	set_players.rpc(players)


@rpc("authority", "reliable")
func join_ok(seed_value: int, size: int, plist: Dictionary) -> void:
	world_seed = seed_value
	map_size = size
	players = plist
	get_tree().change_scene_to_file("res://scenes/game.tscn")


@rpc("authority", "reliable")
func kick(reason: String) -> void:
	last_msg = reason


@rpc("authority", "call_local", "reliable")
func set_players(plist: Dictionary) -> void:
	players = plist
	if multiplayer.is_server():
		for id in players:
			memory[players[id].name] = {"team": players[id].team, "cls": players[id].cls}
	players_changed.emit()

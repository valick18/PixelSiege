extends Node
# Autoload "Net": мережа (ENet або Steam P2P), LAN-пошук, UPnP, налаштування, звуки,
# дані класів, інструментів, рецептів і робочих станцій.

const LookS = preload("res://scripts/look.gd")
const PORT := 24565
const DISCOVERY_PORT := 24566
const MAX_PLAYERS := 20
const REACH := 90.0
const HOTBAR := 7        # слоти предметів на панелі (клавіші 4-0)
const INV_SIZE := 21     # 7 на панелі + 14 у рюкзаку (Tab)
const TOOL_SLOTS := 3    # окремі слоти інструментів (клавіші 1-3)
const VOLLEY_HOLD := 2.5 # скільки секунд тримати ЛКМ з луком для залпу декількома стрілами
const STRIKE_HOLD := 1.5 # скільки секунд тримати ЛКМ зі зброєю ближнього бою для сильного удару (Warrior)
const ARROW_REFILL := 20 # стріл на старті / після респавну; до цієї кількості поповнюються біля точки спавна або робочого столу

# Три класи, у кожного не більше однієї здібності:
#   Warrior  - Power Strike: затиснути ЛКМ зі зброєю на 1.5 с -> сильний удар (звичайний удар - коли відпускаєте ЛКМ)
#   Archer   - Multi-shot: затиснути ЛКМ з луком на 2.5 с -> віяло з 5 стріл ("hold": true, клавіші немає)
#   Builder  - без здібностей
const CLASSES := {
	"warrior": {
		"label": "Warrior", "color": Color("b03a2e"),
		"role": "Front-line fighter. Sword combos, spear reach, breaks enemy lines.",
		"tools": ["sword", "spear"],
		"abilities": [
			{"name": "Power Strike", "short": "Strike", "key": "LMB", "hold": true, "hold_time": STRIKE_HOLD, "cd": 8.0, "desc": "Hold LMB with a weapon for 1.5 s: heavy blow, 45 damage, ignores block, huge knockback. Normal attacks happen when you release LMB"},
		],
	},
	"archer": {
		"label": "Archer", "color": Color("1e8449"),
		"role": "Ranged damage. Hold LMB to draw the bow, release to shoot. Arrows refill to 20 at a spawn point or a workbench.",
		"tools": ["bow", "dagger"],
		"abilities": [
			{"name": "Multi-shot", "short": "Volley", "key": "LMB", "hold": true, "hold_time": VOLLEY_HOLD, "cd": 6.0, "desc": "Hold LMB with the bow for 2.5 s to shoot a fan of 5 arrows"},
		],
	},
	"engineer": {
		"label": "Builder", "color": Color("ca6f1e"),
		"role": "The only class with a pickaxe and an axe: mines blocks, chops trees, builds the base. No abilities.",
		"tools": ["pickaxe", "axe", "hammer"],
		"abilities": [],
	},
}

# kind: melee (ЛКМ - удар по дузі), dig (кирка: тільки блоки), chop (сокира: тільки дерева), bow (затиснути ЛКМ)
const TOOLS := {
	"sword": {"label": "Sword", "kind": "melee", "dmg": 22, "range": 40.0, "arc": 120.0, "cd": 0.42, "kb": 190.0},
	"spear": {"label": "Spear", "kind": "melee", "dmg": 18, "range": 60.0, "arc": 45.0, "cd": 0.6, "kb": 240.0},
	"dagger": {"label": "Dagger", "kind": "melee", "dmg": 11, "range": 30.0, "arc": 130.0, "cd": 0.28, "kb": 110.0},
	"hammer": {"label": "Hammer", "kind": "melee", "dmg": 12, "range": 34.0, "arc": 110.0, "cd": 0.5, "kb": 200.0},
	"pickaxe": {"label": "Pickaxe", "kind": "dig", "dmg": 7, "range": 32.0, "arc": 100.0, "cd": 0.5, "kb": 100.0, "power": 2, "dig_cd": 0.22},
	"axe": {"label": "Axe", "kind": "chop", "dmg": 10, "range": 34.0, "arc": 100.0, "cd": 0.55, "kb": 140.0, "power": 2, "dig_cd": 0.25},
	"bow": {"label": "Bow", "kind": "bow", "dmg": 8, "dmg_max": 30, "speed": 260.0, "speed_max": 640.0, "draw": 0.75, "cd": 0.3},
}

const KITS := {
	"warrior": [["medkit", 1], ["food", 2]],
	"archer": [["arrow", ARROW_REFILL], ["food", 2], ["torch", 2]],
	"engineer": [["wood", 20], ["stone", 10], ["platform", 6], ["wall", 10], ["torch", 2]],
}

const TEAM_COLORS := [Color("2e86de"), Color("e74c3c")]
const TEAM_NAMES := ["Blue", "Red"]
const RESOURCES := ["wood", "stone", "metal"]
const STATIONS := {"hand": "Hands", "workbench": "Workbench", "siege_workshop": "Siege workshop"}
const CATEGORIES := ["All", "Building", "Defense", "Siege", "Light", "Consumables", "Stations"]
const RECIPES := {
	"workbench": {"cost": {"wood": 10}, "n": 1, "station": "hand", "cat": "Stations", "desc": "Place it and press E to craft advanced items"},
	"ladder": {"cost": {"wood": 2}, "n": 3, "station": "hand", "cat": "Building", "desc": "Climb with W/S"},
	"wall": {"cost": {"stone": 1}, "n": 4, "station": "hand", "cat": "Building", "desc": "Back wall: blocks in front of a wall never collapse. Place it with LMB, break it with the pickaxe"},
	"platform": {"cost": {"wood": 1}, "n": 3, "station": "hand", "cat": "Building", "desc": "One-way: jump up through it, S+Space to drop down"},
	"torch": {"cost": {"wood": 1, "stone": 1}, "n": 4, "station": "hand", "cat": "Light", "desc": "Small warm light"},
	"campfire": {"cost": {"wood": 5, "stone": 2}, "n": 1, "station": "hand", "cat": "Light", "desc": "Big light, slowly heals allies standing nearby"},
	"food": {"cost": {"wood": 1}, "n": 2, "station": "hand", "cat": "Consumables", "desc": "Restores 20 HP"},
	"arrow": {"cost": {"wood": 1, "stone": 1}, "n": 10, "station": "hand", "cat": "Consumables", "desc": "Bow ammo. Arrows stuck in blocks can sometimes be picked up again"},
	"lantern": {"cost": {"metal": 2, "wood": 1}, "n": 1, "station": "workbench", "cat": "Light", "desc": "Bright light that does not burn"},
	"door": {"cost": {"wood": 6, "metal": 1}, "n": 1, "station": "workbench", "cat": "Building", "desc": "Team door: lets your team through, blocks enemies"},
	"hatch": {"cost": {"wood": 4, "metal": 1}, "n": 1, "station": "workbench", "cat": "Defense", "desc": "Trapdoor: press E to open / close it under enemies"},
	"spikes": {"cost": {"wood": 2, "metal": 1}, "n": 2, "station": "workbench", "cat": "Defense", "desc": "Hurts enemies that step on it"},
	"arrow_trap": {"cost": {"stone": 6, "metal": 3, "wood": 2}, "n": 1, "station": "workbench", "cat": "Defense", "desc": "Wall trap: shoots arrows at enemies in line"},
	"storage": {"cost": {"wood": 8, "stone": 2}, "n": 1, "station": "workbench", "cat": "Building", "desc": "Team storage chest (E deposit, G take)"},
	"spawn": {"cost": {"wood": 10, "stone": 5}, "n": 1, "station": "workbench", "cat": "Building", "desc": "Forward respawn point"},
	"medkit": {"cost": {"wood": 2, "metal": 1}, "n": 1, "station": "workbench", "cat": "Consumables", "desc": "Restores 40 HP"},
	"firebomb": {"cost": {"wood": 2, "stone": 1}, "n": 1, "station": "workbench", "cat": "Siege", "desc": "Sets an area on fire"},
	"tnt": {"cost": {"stone": 2, "metal": 2}, "n": 1, "station": "workbench", "cat": "Siege", "desc": "Explosive block, light it with the pickaxe or fire"},
	"siege_workshop": {"cost": {"wood": 20, "stone": 10, "metal": 4}, "n": 1, "station": "workbench", "cat": "Stations", "desc": "Station for catapults and ballistas"},
	"catapult": {"cost": {"wood": 20, "stone": 10, "metal": 10}, "n": 1, "station": "siege_workshop", "cat": "Siege", "desc": "E to fire (1 stone ammo)"},
	"ballista": {"cost": {"wood": 15, "metal": 8}, "n": 1, "station": "siege_workshop", "cat": "Siege", "desc": "Stationary heavy crossbow, E to fire (2 wood ammo)"},
}
const ITEM_BLOCK := {"wood": 3, "stone": 2, "metal": 4, "ladder": 9, "torch": 10, "spikes": 11, "tnt": 12, "spawn": 13, "catapult": 14, "storage": 15, "platform": 17, "door": 18, "workbench": 19, "siege_workshop": 20, "ballista": 21, "campfire": 22, "lantern": 23, "hatch": 24, "arrow_trap": 26}
const STRUCT_ITEMS := ["spikes", "spawn", "catapult", "storage", "door", "workbench", "siege_workshop", "ballista", "hatch", "arrow_trap", "campfire", "lantern"]
const RES_LIST := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const ACTION_KEYS := {"left": KEY_A, "right": KEY_D, "up": KEY_W, "down": KEY_S, "jump": KEY_SPACE, "crouch": KEY_CTRL, "run": KEY_SHIFT}

signal players_changed
signal connect_failed
signal host_ready

var players := {}  # peer_id -> {name, team, cls, look}
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
var settings := {"music": 0.7, "sfx": 0.8, "fullscreen": false, "res": 0, "keys": {}, "look": {}}
# Steam P2P (необов'язково): працює лише якщо в проєкт додано GodotSteam (singleton "Steam" + SteamMultiplayerPeer)
var steam_on := false
var steam_lobby := 0
var _steam_hosting := false

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
	_steam_init()
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _exit_tree() -> void:
	_close_peer()
	if _upnp_thread and _upnp_thread.is_started():
		_upnp_thread.wait_to_finish()


func my_look() -> Dictionary:
	return LookS.sanitize(settings.get("look", {}))


func tools_of(cname: String) -> Array:
	return CLASSES.get(cname, CLASSES.warrior)["tools"]


func abilities_of(cname: String) -> Array:
	return CLASSES.get(cname, CLASSES.warrior)["abilities"]


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
	settings.look = cf.get_value("p", "look", {})
	my_name = cf.get_value("p", "name", my_name)


func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("a", "music", settings.music)
	cf.set_value("a", "sfx", settings.sfx)
	cf.set_value("v", "fullscreen", settings.fullscreen)
	cf.set_value("v", "res", settings.res)
	cf.set_value("k", "keys", settings.keys)
	cf.set_value("p", "look", settings.look)
	cf.set_value("p", "name", my_name)
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
		"swing": _make_wav(260, 0.09, 0.85, 30), "bow": _make_wav(520, 0.12, 0.3, 30),
		"chop": _make_wav(200, 0.1, 0.5, 35), "death": _make_wav(110, 0.5, 0.4, 6),
		"splash": _make_wav(80, 0.25, 0.95, 12), "smash": _make_wav(70, 0.3, 0.75, 10),
	}
	for i in 10:
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
	p.pitch_scale = randf_range(0.92, 1.08)
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
	if steam_on:
		Engine.get_singleton("Steam").call("run_callbacks")
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


# ------------------------------------------------------------ Steam P2P (NAT traversal через Steam relay)
func steam_available() -> bool:
	return Engine.has_singleton("Steam") and ClassDB.class_exists("SteamMultiplayerPeer")


func _steam_init() -> void:
	if not steam_available():
		return
	var steam = Engine.get_singleton("Steam")
	var res = steam.call("steamInitEx")
	steam_on = true
	if res is Dictionary and int(res.get("status", 0)) != 0:
		steam_on = false
		return
	steam.connect("lobby_created", _on_steam_lobby_created)
	steam.connect("lobby_joined", _on_steam_lobby_joined)


func host_steam(maxp: int, seed_text: String) -> int:
	if not steam_on:
		return ERR_UNAVAILABLE
	_close_peer()
	_prepare_host(maxp, seed_text)
	_steam_hosting = true
	Engine.get_singleton("Steam").call("createLobby", 2, max_players)  # 2 = public lobby
	return OK


func join_steam(lobby_id: int) -> int:
	if not steam_on:
		return ERR_UNAVAILABLE
	_close_peer()
	_steam_hosting = false
	Engine.get_singleton("Steam").call("joinLobby", lobby_id)
	return OK


func _on_steam_lobby_created(result: int, lobby_id: int) -> void:
	if result != 1:
		last_msg = "Steam lobby could not be created"
		connect_failed.emit()
		return
	steam_lobby = lobby_id
	var peer = ClassDB.instantiate("SteamMultiplayerPeer")
	peer.call("create_host", 0)
	multiplayer.multiplayer_peer = peer
	last_msg = "Steam lobby: %d" % lobby_id
	host_ready.emit()


func _on_steam_lobby_joined(lobby_id: int, _perm: int, _locked: bool, response: int) -> void:
	if _steam_hosting:
		return
	if response != 1:
		last_msg = "Cannot join Steam lobby"
		connect_failed.emit()
		return
	steam_lobby = lobby_id
	var owner_id = Engine.get_singleton("Steam").call("getLobbyOwner", lobby_id)
	var peer = ClassDB.instantiate("SteamMultiplayerPeer")
	peer.call("create_client", owner_id, 0)
	multiplayer.multiplayer_peer = peer


# ------------------------------------------------------------ host / join
func _close_peer() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null


func _prepare_host(maxp: int, seed_text: String) -> void:
	max_players = clampi(maxp, 2, MAX_PLAYERS)
	var t := seed_text.strip_edges()
	if t == "":
		world_seed = randi()
	elif t.is_valid_int():
		world_seed = int(t)
	else:
		world_seed = t.hash()
	players = {1: {"name": my_name, "team": 0, "cls": "warrior", "look": my_look()}}
	memory = {my_name: {"team": 0, "cls": "warrior"}}


func host_game(maxp: int, seed_text: String) -> int:
	_close_peer()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, clampi(maxp, 2, MAX_PLAYERS) - 1)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	_prepare_host(maxp, seed_text)
	_bc = PacketPeerUDP.new()
	_bc.set_broadcast_enabled(true)
	_bc.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	_upnp_thread = Thread.new()
	_upnp_thread.start(_upnp_setup)
	return OK


func join_game(ip: String) -> int:
	ip = ip.strip_edges()
	if ip.begins_with("steam:"):
		return join_steam(int(ip.substr(6)))
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
	if steam_on and steam_lobby != 0:
		Engine.get_singleton("Steam").call("leaveLobby", steam_lobby)
		steam_lobby = 0
	_close_peer()
	players.clear()
	get_tree().change_scene_to_file("res://scenes/menu.tscn")


func _on_connected() -> void:
	reg.rpc_id(1, my_name, join_password, my_look())


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


func team_counts(exclude: int = 0) -> Array:
	var c := [0, 0]
	for pid in players:
		if pid != exclude:
			c[int(players[pid].team)] += 1
	return c


@rpc("any_peer", "reliable")
func reg(pname: String, pw: String, look: Dictionary = {}) -> void:
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
		if not CLASSES.has(cls):
			cls = "warrior"
	else:
		var c := team_counts()
		team = 0 if c[0] <= c[1] else 1
		memory[pname] = {"team": team, "cls": cls}
	players[id] = {"name": pname, "team": team, "cls": cls, "look": LookS.sanitize(look)}
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

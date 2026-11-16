extends Node2D
# Матч. Хост (peer 1) авторитетний: блоки, інвентар, бій, вибухи, вогонь, прапори, рахунок, погода.

const T := 16
const PREP_TIME := 120.0
const RESPAWN := 15.0
const WIN_SCORE := 3
const MAX_SPAWNS := 3
const MAX_STORAGE := 2
const WorldS = preload("res://scripts/world.gd")
const PlayerS = preload("res://scripts/player.gd")
const OverlayS = preload("res://scripts/overlay.gd")
const SettingsS = preload("res://scripts/settings.gd")
const HotbarS = preload("res://scripts/hotbar.gd")
const HELP_TEXT := "WASD move | Space jump | Shift run | Ctrl crouch | LMB use/dig | RMB attack | X block | Z dodge | Q ability\n1-0 slot | E use item/catapult | R/G deposit/take storage | C craft | F1-F4 class (at base) | Esc menu"
const ITEM_ORDER := ["wood", "stone", "metal", "ladder", "torch", "spikes", "tnt", "firebomb", "spawn", "storage", "catapult", "medkit", "food"]
const ITEM_COLORS := {"wood": Color("b9854a"), "stone": Color("95a5a6"), "metal": Color("cfd8dc"), "ladder": Color("8d6e63"), "torch": Color("ffb300"), "spikes": Color("90a4ae"), "tnt": Color("c0392b"), "firebomb": Color("ff7043"), "spawn": Color("26c6da"), "storage": Color("8d6e43"), "catapult": Color("6d4c41"), "medkit": Color("ef5350"), "food": Color("66bb6a")}

var world
var players_root: Node2D
var mod: CanvasModulate
var st := {}          # host: id -> state
var cl := {}          # all: id -> {hp, inv, dead}
var edits := {}       # cell -> [block, team]
var block_hp := {}
var structs := {}     # host: cell -> {type, team, ready_at, cd}
var fuses := {}       # host: cell -> seconds
var drops := {}       # id -> {pos, item, n}
var drop_id := 1
var store := [{"wood": 0, "stone": 0, "metal": 0}, {"wood": 0, "stone": 0, "metal": 0}]
var score := [0, 0]
var winner := -1
var end_rows := []
var flags := []
var prep_left := PREP_TIME
var match_time := 0.0
var match_over := false
var respawn_at := 0.0
var weather := "clear"
var wind := 0.0
var flash := 0.0
var fx := []
var note := ""
var note_t := 0.0
var ui_open := false
var weather_t := 40.0
var supply_t := 90.0
var light_t := 8.0
var save_t := 30.0
var check_t := 0.0
var t_fire := 0.0
var t_spk := 0.0
var t_pick := 0.0
var t_sync := 0.0
var hud_top: Label
var hud_bottom: Label
var hud_msg: Label
var hud_help: Label
var hud_note: Label
var hud_store: Label
var hp_bg: ColorRect
var hp_fill: ColorRect
var slot_bg: Array = []
var slot_lb: Array = []
var slot_ic: Array = []
var slot_ct: Array = []
var _icons := {}
var rain_k := 1.0
var daylight := 1.0
var help_t := 25.0
var help_on := false
var hud_panel: NinePatchRect
var hp_hi: ColorRect
var heart: TextureRect
var craft_panel: PanelContainer
var pause_panel: PanelContainer
var settings_ui: Control


func _ready() -> void:
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	world = WorldS.new()
	add_child(world)
	players_root = Node2D.new()
	players_root.name = "Players"
	add_child(players_root)
	mod = CanvasModulate.new()
	add_child(mod)
	_build_hud()
	Net.players_changed.connect(_sync_player_nodes)
	_start_match(Net.world_seed, Net.map_size)
	if not multiplayer.is_server():
		req_sync.rpc_id(1)


# ------------------------------------------------------------ inventory helpers
func _empty_inv() -> Array:
	var inv := []
	for i in 10:
		inv.append({})
	return inv


func _inv_count(inv: Array, item: String) -> int:
	var n := 0
	for e in inv:
		if e.get("i", "") == item:
			n += e.n
	return n


func _inv_add(inv: Array, item: String, n: int) -> int:
	var mx := 50 if item in Net.RESOURCES else 10
	for e in inv:
		if n <= 0:
			break
		if e.get("i", "") == item and e.n < mx:
			var k := mini(n, mx - e.n)
			e.n += k
			n -= k
	for i in inv.size():
		if n <= 0:
			break
		if inv[i].is_empty():
			var k2 := mini(n, mx)
			inv[i] = {"i": item, "n": k2}
			n -= k2
	return n


func _inv_take(inv: Array, item: String, n: int) -> int:
	var left := n
	for i in inv.size():
		if left <= 0:
			break
		if inv[i].get("i", "") == item:
			var k := mini(left, inv[i].n)
			inv[i].n -= k
			left -= k
			if inv[i].n <= 0:
				inv[i] = {}
	return n - left


func _kit(cname: String) -> Array:
	var inv := _empty_inv()
	var items := [["wood", 5]]
	match cname:
		"warrior": items.append(["medkit", 1])
		"archer": items.append(["food", 2])
		"engineer": items = [["wood", 15], ["stone", 5], ["torch", 2]]
		"support": items.append(["medkit", 3])
	for it in items:
		_inv_add(inv, it[0], it[1])
	return inv


func _new_state(cname: String = "warrior") -> Dictionary:
	return {"hp": 100, "inv": _kit(cname), "dead_until": 0.0, "atk": 0.0, "ab": 0.0, "dig": 0.0, "dodge": 0.0, "block": false, "block_since": 0.0, "inv_until": 0.0, "last_pos": Vector2.ZERO, "k": 0, "d": 0, "c": 0}


# ------------------------------------------------------------ match lifecycle
func _start_match(seed_value: int, size: int) -> void:
	edits.clear()
	block_hp.clear()
	structs.clear()
	fuses.clear()
	drops.clear()
	store = [{"wood": 0, "stone": 0, "metal": 0}, {"wood": 0, "stone": 0, "metal": 0}]
	score = [0, 0]
	winner = -1
	end_rows = []
	match_over = false
	prep_left = PREP_TIME
	match_time = 0.0
	weather = "clear"
	wind = 0.0
	supply_t = 90.0
	fx.clear()
	world.generate(seed_value, size)
	flags = [
		{"carrier": 0, "home": true, "pos": world.flag_pos(0)},
		{"carrier": 0, "home": true, "pos": world.flag_pos(1)},
	]
	for p in players_root.get_children():
		p.reset_to_spawn(world.spawn_pos(p.team))
		p.set_dead(false)
	_sync_player_nodes()
	if multiplayer.is_server():
		for id in Net.players:
			st[id] = _new_state(Net.players[id].cls)
			st[id].last_pos = world.spawn_pos(Net.players[id].team)
			_push_state(id)


func _sync_player_nodes() -> void:
	var srv := multiplayer.is_server()
	for id in Net.players:
		var info = Net.players[id]
		var p = players_root.get_node_or_null(str(id))
		if p == null:
			p = PlayerS.new()
			p.setup(id, info.team, info.cls, self, world)
			players_root.add_child(p)
			p.reset_to_spawn(world.spawn_pos(info.team))
		else:
			p.team = info.team
			p.cls = info.cls
		if srv and not st.has(id):
			st[id] = _new_state(info.cls)
			_push_state(id)
	for p in players_root.get_children():
		if not Net.players.has(p.id):
			_drop_flag_of(p.id)
			st.erase(p.id)
			cl.erase(p.id)
			p.queue_free()


func _sid() -> int:
	var s := multiplayer.get_remote_sender_id()
	return 1 if s == 0 else s


func _push_state(id: int) -> void:
	var s = st[id]
	c_state.rpc(id, s.hp, s.inv.duplicate(true), s.dead_until > 0.0)


func _push_store() -> void:
	c_store.rpc(store)


func _broadcast_fire() -> void:
	c_fire.rpc(world.fire.keys())


func _note(target: int, text: String) -> void:
	c_note.rpc(target, text)


func _send_edits(list: Array) -> void:
	c_edits.rpc(list)


# ------------------------------------------------------------ sync RPCs
@rpc("any_peer", "reliable")
func req_sync() -> void:
	if not multiplayer.is_server():
		return
	var snap := {}
	for id in st:
		snap[id] = {"hp": st[id].hp, "inv": st[id].inv.duplicate(true), "dead": st[id].dead_until > 0.0}
	var d := {"edits": edits, "score": score, "flags": flags, "prep": prep_left, "mt": match_time, "cl": snap, "win": winner, "fire": world.fire.keys(), "drops": drops, "store": store, "weather": weather, "wind": wind, "rows": end_rows}
	c_full.rpc_id(_sid(), d)


@rpc("authority", "reliable")
func c_full(d: Dictionary) -> void:
	edits = d.edits
	for c in edits:
		world.set_cell(c, edits[c][0], edits[c][1])
	score = d.score
	flags = d.flags
	prep_left = d.prep
	match_time = d.mt
	cl = d.cl
	winner = d.win
	match_over = winner >= 0
	drops = d.drops
	store = d.store
	weather = d.weather
	wind = d.wind
	end_rows = d.rows
	world.fire.clear()
	for c in d.fire:
		world.fire[c] = 1.0
	for id in cl:
		var p = players_root.get_node_or_null(str(id))
		if p:
			p.set_dead(cl[id].dead)


@rpc("authority", "call_local", "reliable")
func c_state(id: int, hp: int, inv: Array, dead: bool) -> void:
	cl[id] = {"hp": hp, "inv": inv, "dead": dead}
	var p = players_root.get_node_or_null(str(id))
	if p:
		p.set_dead(dead)
	if id == multiplayer.get_unique_id() and dead:
		respawn_at = Time.get_ticks_msec() / 1000.0 + RESPAWN


@rpc("authority", "call_local", "reliable")
func c_respawn(id: int, pos: Vector2) -> void:
	var p = players_root.get_node_or_null(str(id))
	if p:
		p.reset_to_spawn(pos)


@rpc("authority", "call_local", "reliable")
func c_tp(id: int, pos: Vector2) -> void:
	var p = players_root.get_node_or_null(str(id))
	if p:
		p.reset_to_spawn(pos)


@rpc("authority", "call_local", "reliable")
func c_edits(list: Array) -> void:
	for e in list:
		if e[1] == 0 and fx.size() < 150:
			var old: int = world.get_cell(e[0])
			if old != 0:
				var dc: Color = world.COLORS.get(old, Color.GRAY)
				for k in 3:
					fx.append({"k": "deb", "a": Vector2(e[0]) * T + Vector2(randf_range(2, 14), randf_range(2, 14)), "v": Vector2(randf_range(-40, 40), randf_range(-90, -20)), "c": dc, "t": 0.5})
		edits[e[0]] = [e[1], e[2]]
		world.set_cell(e[0], e[1], e[2])
	if not list.is_empty():
		Net.play("place" if list[0][1] != 0 else "dig")


@rpc("authority", "call_local", "reliable")
func c_knock(id: int, v: Vector2) -> void:
	var p = players_root.get_node_or_null(str(id))
	if p and p.is_multiplayer_authority():
		p.apply_knock(v)


@rpc("authority", "call_local", "unreliable")
func c_fx(a: Vector2, b: Vector2, kind: int) -> void:
	if kind == 0:
		fx.append({"k": "slash", "a": a, "b": b, "t": 0.18})
	else:
		fx.append({"k": "line", "a": a, "b": b, "t": 0.12, "c": Color("f1c40f")})
	Net.play("hit")


@rpc("authority", "call_local", "unreliable")
func c_anim(id: int, kind: int) -> void:
	var p = players_root.get_node_or_null(str(id))
	if p:
		p.anim(kind)


@rpc("authority", "call_local", "reliable")
func c_path(pts: PackedVector2Array) -> void:
	fx.append({"k": "path", "pts": pts, "t": 0.6})


@rpc("authority", "call_local", "reliable")
func c_boom(pos: Vector2, r: float) -> void:
	fx.append({"k": "circle", "a": pos, "r": r, "t": 0.35})
	Net.play("boom")


@rpc("authority", "call_local", "unreliable")
func c_sfx(n: String) -> void:
	Net.play(n)


@rpc("authority", "call_local", "reliable")
func c_flags(fl: Array) -> void:
	flags = fl
	Net.play("flag")


@rpc("authority", "call_local", "reliable")
func c_score(sc: Array, win: int, rows: Array) -> void:
	score = sc
	winner = win
	end_rows = rows
	match_over = win >= 0


@rpc("authority", "unreliable")
func c_time(prep: float, mt: float) -> void:
	prep_left = prep
	match_time = mt


@rpc("authority", "reliable")
func c_fire(cells: Array) -> void:
	world.fire.clear()
	for c in cells:
		world.fire[c] = 1.0


@rpc("authority", "call_local", "reliable")
func c_drops(d: Dictionary) -> void:
	drops = d


@rpc("authority", "call_local", "reliable")
func c_store(s: Array) -> void:
	store = s


@rpc("authority", "call_local", "reliable")
func c_weather(kind: String, w: float) -> void:
	weather = kind
	wind = w


@rpc("authority", "call_local", "reliable")
func c_flash() -> void:
	flash = 1.0
	Net.play("thunder")


@rpc("authority", "call_local", "reliable")
func c_note(target: int, text: String) -> void:
	if target == 0 or target == multiplayer.get_unique_id():
		note = text
		note_t = 4.0


@rpc("authority", "call_local", "reliable")
func new_match(seed_value: int) -> void:
	Net.world_seed = seed_value
	_start_match(seed_value, Net.map_size)


# ------------------------------------------------------------ client -> host helpers
func send_use(cell: Vector2i, slot: int) -> void:
	var inv: Array = cl.get(multiplayer.get_unique_id(), {}).get("inv", [])
	if slot < inv.size() and not Net.ITEM_BLOCK.has(inv[slot].get("i", "")):
		Net.play("dig")
	if multiplayer.is_server():
		req_use(cell, slot)
	else:
		req_use.rpc_id(1, cell, slot)


func send_attack(dir: Vector2) -> void:
	if multiplayer.is_server():
		req_attack(dir)
	else:
		req_attack.rpc_id(1, dir)


func send_ability(dir: Vector2) -> void:
	if multiplayer.is_server():
		req_ability(dir)
	else:
		req_ability.rpc_id(1, dir)


func send_class(c: String) -> void:
	if multiplayer.is_server():
		req_class(c)
	else:
		req_class.rpc_id(1, c)


func send_interact(dir: Vector2, slot: int) -> void:
	if multiplayer.is_server():
		req_interact(dir, slot)
	else:
		req_interact.rpc_id(1, dir, slot)


func send_store(dep: bool) -> void:
	if multiplayer.is_server():
		req_store(dep)
	else:
		req_store.rpc_id(1, dep)


func send_craft(r: String) -> void:
	if multiplayer.is_server():
		req_craft(r)
	else:
		req_craft.rpc_id(1, r)


func send_block(on: bool) -> void:
	if multiplayer.is_server():
		req_block(on)
	else:
		req_block.rpc_id(1, on)


func send_dodge(face: int) -> void:
	if multiplayer.is_server():
		req_dodge(face)
	else:
		req_dodge.rpc_id(1, face)


# ------------------------------------------------------------ host: requests
func _actor(id: int):
	var s = st.get(id)
	var p = players_root.get_node_or_null(str(id))
	if s == null or p == null or s.dead_until > 0.0 or not Net.players.has(id):
		return null
	return [s, p]


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _count_structs(kind: String, team: int) -> int:
	var n := 0
	for c in structs:
		if structs[c].type == kind and structs[c].team == team:
			n += 1
	return n


func _near_store(id: int, p) -> bool:
	var team: int = Net.players[id].team
	if p.position.distance_to(world.flag_pos(team)) < 110.0:
		return true
	for c in structs:
		if structs[c].type == "storage" and structs[c].team == team and p.position.distance_to(Vector2(c) * T + Vector2(8, 8)) < 80.0:
			return true
	return false


@rpc("any_peer", "reliable")
func req_use(cell: Vector2i, slot: int) -> void:
	if not multiplayer.is_server():
		return
	var id := _sid()
	var a = _actor(id)
	if a == null:
		return
	var s = a[0]
	var p = a[1]
	var now := _now()
	if now < s.dig:
		return
	s.dig = now + 0.08
	slot = clampi(slot, 0, 9)
	var item: String = s.inv[slot].get("i", "")
	var reach := 200.0 if item == "firebomb" else Net.REACH
	if p.position.distance_to(Vector2(cell) * T + Vector2(8, 8)) > reach:
		return
	if Net.ITEM_BLOCK.has(item):
		_do_place(id, s, p, cell, slot, item)
	elif item == "firebomb":
		_do_firebomb(id, s, cell, slot)
	else:
		_do_dig(id, s, cell)


func _consume(s, slot: int) -> void:
	s.inv[slot].n -= 1
	if s.inv[slot].n <= 0:
		s.inv[slot] = {}


func _do_place(id: int, s, p, cell: Vector2i, slot: int, item: String) -> void:
	if cell.y < 0 or world.get_cell(cell) != world.AIR:
		return
	var b: int = Net.ITEM_BLOCK[item]
	var cc := Vector2(cell) * T + Vector2(8, 8)
	var team: int = Net.players[id].team
	if b == world.STONE or b == world.WOOD or b == world.METAL or b == world.TNT:
		for q in players_root.get_children():
			if absf(q.position.x - cc.x) < 14.0 and absf(q.position.y - cc.y) < 22.0:
				return
	if item == "spawn":
		if _count_structs("spawn", team) >= MAX_SPAWNS:
			_note(id, "Respawn point limit reached (%d)" % MAX_SPAWNS)
			return
		if cc.distance_to(world.flag_pos(team)) < 25.0 * T:
			_note(id, "Build respawn points far from your base (captured territory)")
			return
	if item == "storage" and _count_structs("storage", team) >= MAX_STORAGE:
		_note(id, "Storage limit reached (%d)" % MAX_STORAGE)
		return
	_consume(s, slot)
	block_hp.erase(cell)
	var tm := -1
	if item in ["spikes", "spawn", "catapult", "storage"]:
		tm = team
		structs[cell] = {"type": item, "team": team, "ready_at": _now() + (8.0 if item == "catapult" else 0.0), "cd": 0.0}
	_send_edits([[cell, b, tm]])
	_push_state(id)


func _do_dig(id: int, s, cell: Vector2i) -> void:
	if world.fire.has(cell):
		world.fire.erase(cell)
		_broadcast_fire()
		return
	var b: int = world.get_cell(cell)
	if b == world.AIR or b == world.BASE:
		return
	if b == world.TNT:
		if not fuses.has(cell):
			fuses[cell] = 2.0
			c_sfx.rpc("fire")
		return
	var hp: int = block_hp.get(cell, world.max_hp(b))
	hp -= int(Net.CLASSES[Net.players[id].cls]["dig"])
	if hp > 0:
		block_hp[cell] = hp
		return
	var drop: String = world.drop_of(b)
	_remove_cells([cell])
	if drop != "":
		_inv_add(s.inv, drop, 1)
	_push_state(id)


func _do_firebomb(id: int, s, cell: Vector2i, slot: int) -> void:
	_consume(s, slot)
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var c := cell + Vector2i(dx, dy)
			var b: int = world.get_cell(c)
			if world.FLAMMABLE.has(b):
				if b == world.TNT:
					fuses[c] = 0.6
				else:
					world.fire[c] = randf_range(4.0, 8.0)
	_broadcast_fire()
	c_sfx.rpc("fire")
	_push_state(id)


func _remove_cells(cells: Array) -> void:
	var list := []
	for c in cells:
		block_hp.erase(c)
		structs.erase(c)
		world.fire.erase(c)
		list.append([c, 0, -1])
	if not list.is_empty():
		_send_edits(list)


@rpc("any_peer", "reliable")
func req_attack(dir: Vector2) -> void:
	if not multiplayer.is_server():
		return
	var id := _sid()
	var a = _actor(id)
	if a == null or match_over or dir == Vector2.ZERO:
		return
	var s = a[0]
	var p = a[1]
	var now := _now()
	if now < s.atk or s.block:
		return
	var cname: String = Net.players[id].cls
	var cls: Dictionary = Net.CLASSES[cname]
	s.atk = now + cls["cd"]
	c_anim.rpc(id, 0)
	dir = dir.normalized()
	if cname == "archer":
		dir = dir.rotated(wind * 0.06)
	c_fx.rpc(p.position, p.position + dir * cls["range"], 1 if cname == "archer" else 0)
	if prep_left > 0.0:
		return
	var my_team: int = Net.players[id].team
	for oid in st:
		if oid == id or not Net.players.has(oid) or Net.players[oid].team == my_team or st[oid].dead_until > 0.0:
			continue
		var q = players_root.get_node_or_null(str(oid))
		if q == null:
			continue
		var rel: Vector2 = q.position - p.position
		var along := rel.dot(dir)
		if along < -4.0 or along > cls["range"] + 8.0 or absf(rel.cross(dir)) > 16.0:
			continue
		if world.ray_blocked(p.position, q.position):
			continue
		_damage(oid, int(cls["dmg"]), dir * 160.0 + Vector2(0, -90), id, true)
	# атака по спорудах противника в зоні ближнього бою (переривання будівництва)
	if cname != "archer":
		var tc := Vector2i(floori((p.position.x + dir.x * 26.0) / T), floori((p.position.y + dir.y * 26.0) / T))
		if structs.has(tc) and structs[tc].team != my_team:
			_do_dig(id, s, tc)


func _damage(oid: int, amount: int, kb: Vector2, src: int, melee: bool) -> void:
	if prep_left > 0.0 or match_over or not st.has(oid):
		return
	var s = st[oid]
	var now := _now()
	if now < s.inv_until or s.dead_until > 0.0:
		return
	if melee and s.block:
		if now - s.block_since < 0.25:
			if src != 0 and st.has(src):
				c_knock.rpc(src, -kb * 1.5)
			c_sfx.rpc("hit")
			return
		amount = int(amount * 0.3)
	s.hp -= amount
	c_knock.rpc(oid, kb)
	c_sfx.rpc("hurt")
	c_anim.rpc(oid, 2)
	if s.hp <= 0:
		_kill(oid, src)
	_push_state(oid)


func _kill(oid: int, src: int) -> void:
	var s = st[oid]
	s.hp = 0
	s.dead_until = _now() + RESPAWN
	s.d += 1
	s.block = false
	if src != 0 and st.has(src) and Net.players.has(src) and Net.players.has(oid) and Net.players[src].team != Net.players[oid].team:
		st[src].k += 1
	_drop_flag_of(oid)
	var q = players_root.get_node_or_null(str(oid))
	if q:
		for i in 10:
			var e: Dictionary = s.inv[i]
			if e.get("i", "") in Net.RESOURCES:
				var half := int(e.n * 0.5)
				if half > 0:
					_spawn_drop(q.position, e.i, half)
					e.n -= half


func _spawn_drop(pos: Vector2, item: String, n: int) -> void:
	drops[drop_id] = {"pos": world.drop_pos(pos), "item": item, "n": n}
	drop_id += 1
	c_drops.rpc(drops)


@rpc("any_peer", "reliable")
func req_ability(dir: Vector2) -> void:
	if not multiplayer.is_server():
		return
	var id := _sid()
	var a = _actor(id)
	if a == null:
		return
	var s = a[0]
	var p = a[1]
	var now := _now()
	if now < s.ab:
		return
	var cname: String = Net.players[id].cls
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	dir = dir.normalized()
	match cname:
		"warrior":
			c_knock.rpc(id, dir * 320.0 + Vector2(0, -60))
		"archer":
			c_knock.rpc(id, Vector2(-signf(dir.x) * 220.0, -280.0))
		"engineer":
			var row := floori((p.position.y + 14.5) / T)
			var sgn := 1 if dir.x >= 0.0 else -1
			var list := []
			for i in range(1, 6):
				if _inv_count(s.inv, "wood") - list.size() < 1:
					break
				var c := Vector2i(floori(p.position.x / T) + sgn * i, row)
				if world.get_cell(c) == world.AIR:
					list.append([c, world.WOOD, -1])
			if list.is_empty():
				return
			_inv_take(s.inv, "wood", list.size())
			_send_edits(list)
			_push_state(id)
		"support":
			for oid in st:
				if not Net.players.has(oid) or Net.players[oid].team != Net.players[id].team or st[oid].dead_until > 0.0:
					continue
				var q = players_root.get_node_or_null(str(oid))
				if q and q.position.distance_to(p.position) < 90.0:
					st[oid].hp = mini(100, st[oid].hp + 30)
					_push_state(oid)
	s.ab = now + float(Net.CLASSES[cname]["ab_cd"])


@rpc("any_peer", "reliable")
func req_block(on: bool) -> void:
	if not multiplayer.is_server():
		return
	var s = st.get(_sid())
	if s == null or s.dead_until > 0.0:
		return
	if on and not s.block:
		s.block_since = _now()
	s.block = on


@rpc("any_peer", "reliable")
func req_dodge(face: int) -> void:
	if not multiplayer.is_server():
		return
	var id := _sid()
	var a = _actor(id)
	if a == null:
		return
	var s = a[0]
	var now := _now()
	if now < s.dodge:
		return
	s.dodge = now + 1.4
	s.inv_until = now + 0.35
	c_knock.rpc(id, Vector2(face * 300.0, -40.0))
	c_anim.rpc(id, 1)


@rpc("any_peer", "reliable")
func req_class(cname: String) -> void:
	if not multiplayer.is_server() or not Net.CLASSES.has(cname):
		return
	var id := _sid()
	var s = st.get(id)
	var p = players_root.get_node_or_null(str(id))
	if s == null or p == null or not Net.players.has(id):
		return
	var near_base: bool = p.position.distance_to(world.flag_pos(Net.players[id].team)) < 120.0
	if not (s.dead_until > 0.0 or near_base):
		return
	Net.players[id].cls = cname
	Net.set_players.rpc(Net.players)


@rpc("any_peer", "reliable")
func req_interact(dir: Vector2, slot: int) -> void:
	if not multiplayer.is_server():
		return
	var id := _sid()
	var a = _actor(id)
	if a == null:
		return
	var s = a[0]
	var p = a[1]
	slot = clampi(slot, 0, 9)
	var item: String = s.inv[slot].get("i", "")
	if item == "medkit" or item == "food":
		if s.hp >= 100:
			return
		s.hp = mini(100, s.hp + (40 if item == "medkit" else 20))
		_consume(s, slot)
		_push_state(id)
		c_sfx.rpc("pickup")
		return
	var team: int = Net.players[id].team
	var now := _now()
	for c in structs:
		var sc = structs[c]
		if sc.type != "catapult" or sc.team != team or p.position.distance_to(Vector2(c) * T + Vector2(8, 8)) > 48.0:
			continue
		if now < sc.ready_at:
			_note(id, "Catapult is still under construction")
			return
		if now < sc.cd:
			_note(id, "Catapult is reloading")
			return
		if _inv_take(s.inv, "stone", 1) == 0:
			_note(id, "Catapult needs 1 stone as ammo")
			return
		sc.cd = now + 6.0
		_push_state(id)
		_fire_catapult(c, dir, id)
		return


func _fire_catapult(cell: Vector2i, dir: Vector2, id: int) -> void:
	var pos := Vector2(cell) * T + Vector2(8, -4)
	var v := dir.normalized() * 420.0
	var pts := PackedVector2Array([pos])
	var team: int = Net.players[id].team
	for i in 220:
		v.y += 500.0 * 0.02
		v.x += wind * 60.0 * 0.02
		pos += v * 0.02
		if i % 4 == 0:
			pts.append(pos)
		if pos.x < 0.0 or pos.x > world.w * T or pos.y > world.h * T:
			break
		if world.is_solid(floori(pos.x / T), floori(pos.y / T)):
			break
		var caught := false
		for oid in st:
			if Net.players.has(oid) and Net.players[oid].team != team and st[oid].dead_until <= 0.0:
				var q = players_root.get_node_or_null(str(oid))
				if q and q.position.distance_to(pos) < 14.0:
					caught = true
		if caught:
			break
	pts.append(pos)
	c_path.rpc(pts)
	_explode(pos, 52.0, 9.0, id)


@rpc("any_peer", "reliable")
func req_store(dep: bool) -> void:
	if not multiplayer.is_server():
		return
	var id := _sid()
	var a = _actor(id)
	if a == null:
		return
	var s = a[0]
	var p = a[1]
	if not _near_store(id, p):
		_note(id, "Go to your base flag or a storage chest")
		return
	var team: int = Net.players[id].team
	if dep:
		for i in 10:
			var e: Dictionary = s.inv[i]
			if e.get("i", "") in Net.RESOURCES:
				store[team][e.i] += e.n
				s.inv[i] = {}
	else:
		for r in Net.RESOURCES:
			var take := mini(store[team][r], 20)
			var left := _inv_add(s.inv, r, take)
			store[team][r] -= take - left
	_push_store()
	_push_state(id)
	c_sfx.rpc("pickup")


@rpc("any_peer", "reliable")
func req_craft(rname: String) -> void:
	if not multiplayer.is_server() or not Net.RECIPES.has(rname):
		return
	var id := _sid()
	var a = _actor(id)
	if a == null:
		return
	var s = a[0]
	var p = a[1]
	var team: int = Net.players[id].team
	var near := _near_store(id, p)
	var rec: Dictionary = Net.RECIPES[rname]
	for k in rec.cost:
		var have := _inv_count(s.inv, k)
		if near and k in Net.RESOURCES:
			have += store[team][k]
		if have < rec.cost[k]:
			_note(id, "Not enough %s" % k)
			return
	var test: Array = s.inv.duplicate(true)
	if _inv_add(test, rname, rec.n) > 0:
		_note(id, "Inventory full")
		return
	for k in rec.cost:
		var need: int = rec.cost[k]
		need -= _inv_take(s.inv, k, need)
		if need > 0:
			store[team][k] -= need
	_inv_add(s.inv, rname, rec.n)
	_push_state(id)
	_push_store()
	c_sfx.rpc("craft")


# ------------------------------------------------------------ host: explosions, fire, flags
func _explode(pos: Vector2, radius: float, power: float, src: int) -> void:
	var cr := int(radius / T) + 1
	var center := Vector2i(floori(pos.x / T), floori(pos.y / T))
	var removed := []
	for dx in range(-cr, cr + 1):
		for dy in range(-cr, cr + 1):
			var c := center + Vector2i(dx, dy)
			var b: int = world.get_cell(c)
			if b == world.AIR or b == world.BASE or c.y < 0:
				continue
			var d := pos.distance_to(Vector2(c) * T + Vector2(8, 8))
			if d > radius:
				continue
			var hp: float = float(block_hp.get(c, world.max_hp(b))) - power * (1.0 - d / radius)
			if hp <= 0.0:
				removed.append(c)
				if b == world.TNT and not fuses.has(c):
					fuses[c] = 0.15
			else:
				block_hp[c] = int(ceil(hp))
				if world.FLAMMABLE.has(b) and b != world.TNT and randf() < 0.3:
					world.fire[c] = randf_range(4.0, 8.0)
	_remove_cells(removed)
	for oid in st:
		var q = players_root.get_node_or_null(str(oid))
		if q == null or st[oid].dead_until > 0.0:
			continue
		var dist: float = q.position.distance_to(pos)
		if dist < radius * 1.3:
			var k := 1.0 - dist / (radius * 1.3)
			_damage(oid, int(power * 8.0 * k), (q.position - pos).normalized() * 380.0 * k + Vector2(0, -220.0 * k), src, false)
	c_boom.rpc(pos, radius)
	_broadcast_fire()


func _drop_flag_of(id: int) -> void:
	if not multiplayer.is_server() or flags.is_empty():
		return
	for t in 2:
		if flags[t].carrier == id:
			flags[t].carrier = 0
			flags[t].home = false
			flags[t].pos = world.drop_pos(flags[t].pos)
			c_flags.rpc(flags)


func _rows() -> Array:
	var rows := []
	for id in st:
		if Net.players.has(id):
			rows.append([Net.players[id].name, Net.players[id].team, st[id].k, st[id].d, st[id].c])
	return rows


func _flag_logic() -> void:
	var changed := false
	for t in 2:
		var f = flags[t]
		if f.carrier != 0:
			var c = players_root.get_node_or_null(str(f.carrier))
			if c:
				f.pos = c.position + Vector2(0, 10)
			continue
		for id in st:
			if st[id].dead_until > 0.0 or not Net.players.has(id):
				continue
			var q = players_root.get_node_or_null(str(id))
			if q == null or q.position.distance_to(f.pos) > 26.0:
				continue
			if Net.players[id].team != t:
				f.carrier = id
				f.home = false
				changed = true
				break
			elif not f.home:
				f.pos = world.flag_pos(t)
				f.home = true
				changed = true
				break
	for id in st:
		if st[id].dead_until > 0.0 or not Net.players.has(id):
			continue
		var team: int = Net.players[id].team
		var enemy := 1 - team
		if flags[enemy].carrier != id or not flags[team].home:
			continue
		var q = players_root.get_node_or_null(str(id))
		if q and q.position.distance_to(flags[team].pos) < 30.0:
			flags[enemy].carrier = 0
			flags[enemy].home = true
			flags[enemy].pos = world.flag_pos(enemy)
			score[team] += 1
			st[id].c += 1
			changed = true
			if score[team] >= WIN_SCORE:
				winner = team
				match_over = true
				_end_match()
			c_score.rpc(score, winner, _rows())
	if changed:
		c_flags.rpc(flags)


func _end_match() -> void:
	await get_tree().create_timer(10.0).timeout
	if is_inside_tree():
		new_match.rpc(randi())


func _respawn_pos(team: int) -> Vector2:
	var opts := [world.spawn_pos(team)]
	for c in structs:
		if structs[c].type == "spawn" and structs[c].team == team:
			opts.append(Vector2(c.x * T + 8, (c.y + 1) * T - 15))
	return opts[randi() % opts.size()]


func _fire_tick() -> void:
	if world.fire.is_empty():
		return
	var raining := weather == "rain" or weather == "storm"
	var kill := []
	var add := {}
	for c in world.fire.keys():
		if raining and randf() < 0.35 and _exposed(c):
			world.fire.erase(c)
			continue
		world.fire[c] -= 0.5
		var b: int = world.get_cell(c)
		if b == world.AIR:
			world.fire.erase(c)
			continue
		if b == world.TNT:
			fuses[c] = 0.5
			world.fire.erase(c)
			continue
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if world.FLAMMABLE.has(world.get_cell(n)) and not world.fire.has(n) and not add.has(n) and randf() < 0.2:
				add[n] = randf_range(4.0, 8.0)
		if world.fire[c] <= 0.0:
			kill.append(c)
	for n in add:
		world.fire[n] = add[n]
	_remove_cells(kill)
	for oid in st:
		var q = players_root.get_node_or_null(str(oid))
		if q and st[oid].dead_until <= 0.0 and world.fire.has(Vector2i(floori(q.position.x / T), floori(q.position.y / T))):
			_damage(oid, 6, Vector2(0, -60), 0, false)
	_broadcast_fire()


func _spikes_tick() -> void:
	for c in structs:
		if structs[c].type != "spikes":
			continue
		var cc := Vector2(c) * T + Vector2(8, 8)
		for oid in st:
			if not Net.players.has(oid) or Net.players[oid].team == structs[c].team or st[oid].dead_until > 0.0:
				continue
			var q = players_root.get_node_or_null(str(oid))
			if q and absf(q.position.x - cc.x) < 14.0 and absf(q.position.y - cc.y) < 20.0:
				_damage(oid, 8, Vector2(0, -120), 0, false)


func _exposed(c: Vector2i) -> bool:
	# true, якщо над клітинкою немає твердих блоків (дощ/блискавка сюди дістають)
	for yy in range(c.y - 1, -1, -1):
		if world.is_solid(c.x, yy):
			return false
	return true


func _pickups() -> void:
	var changed := false
	for did in drops.keys():
		var d = drops[did]
		for oid in st:
			if st[oid].dead_until > 0.0:
				continue
			var q = players_root.get_node_or_null(str(oid))
			if q == null or q.position.distance_to(d.pos) > 22.0:
				continue
			var left := _inv_add(st[oid].inv, d.item, d.n)
			if left < d.n:
				changed = true
				_push_state(oid)
				c_sfx.rpc("pickup")
			if left <= 0:
				drops.erase(did)
				break
			d.n = left
	if changed:
		c_drops.rpc(drops)


func _lightning() -> void:
	var x: int = randi() % world.w
	var y := 0
	while y < world.h - 1 and world.get_cell(Vector2i(x, y)) == world.AIR:
		y += 1
	var c := Vector2i(x, y)
	if world.FLAMMABLE.has(world.get_cell(c)):
		world.fire[c] = randf_range(5.0, 9.0)
		_broadcast_fire()
	c_flash.rpc()


func _save_match() -> void:
	var arr := []
	for c in edits:
		arr.append([c.x, c.y, edits[c][0], edits[c][1]])
	var data := {"server": Net.server_name, "seed": Net.world_seed, "size": Net.map_size, "score": score, "edits": arr}
	var f := FileAccess.open("user://match_save.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))


func _physics_process(dt: float) -> void:
	prep_left = maxf(0.0, prep_left - dt)
	match_time += dt
	flash = maxf(0.0, flash - dt * 1.5)
	note_t = maxf(0.0, note_t - dt)
	for e in fx:
		e.t -= dt
		if e.k == "deb":
			e.a += e.v * dt
			e.v = Vector2(e.v.x, e.v.y + 400.0 * dt)
	fx = fx.filter(func(e): return e.t > 0.0)
	if not multiplayer.is_server():
		return
	var now := _now()
	for id in st:
		var s = st[id]
		if s.dead_until > 0.0 and now >= s.dead_until:
			var team: int = Net.players[id].team if Net.players.has(id) else 0
			s.dead_until = 0.0
			s.hp = 100
			s.inv = _kit(Net.players[id].cls if Net.players.has(id) else "warrior")
			var pos := _respawn_pos(team)
			s.last_pos = pos
			_push_state(id)
			c_respawn.rpc(id, pos)
	if prep_left <= 0.0 and not match_over:
		_flag_logic()
	for c in fuses.keys():
		fuses[c] -= dt
		if fuses[c] <= 0.0:
			fuses.erase(c)
			_explode(Vector2(c) * T + Vector2(8, 8), 64.0, 14.0, 0)
	t_fire += dt
	if t_fire >= 0.5:
		t_fire = 0.0
		_fire_tick()
		_spikes_tick()
	t_pick += dt
	if t_pick >= 0.2:
		t_pick = 0.0
		_pickups()
	check_t += dt
	if check_t >= 0.5:
		check_t = 0.0
		for id in st:
			var q = players_root.get_node_or_null(str(id))
			if id == 1 or q == null or st[id].dead_until > 0.0:
				continue
			if st[id].last_pos == Vector2.ZERO:
				st[id].last_pos = q.position
			elif q.position.distance_to(st[id].last_pos) > 450.0:
				c_tp.rpc(id, st[id].last_pos)
			else:
				st[id].last_pos = q.position
	weather_t -= dt
	if weather_t <= 0.0:
		weather_t = randf_range(60.0, 120.0)
		var kinds := ["clear", "clear", "rain", "fog", "storm"]
		c_weather.rpc(kinds[randi() % kinds.size()], randf_range(-1.0, 1.0))
	if weather == "storm":
		light_t -= dt
		if light_t <= 0.0:
			light_t = randf_range(6.0, 12.0)
			_lightning()
	if prep_left <= 0.0 and not match_over:
		supply_t -= dt
		if supply_t <= 0.0:
			supply_t = 90.0
			var cx: float = world.w * T * 0.5 + randf_range(-60.0, 60.0)
			_spawn_drop(Vector2(cx, 0), "metal", 10)
			_spawn_drop(Vector2(cx + 16.0, 0), "stone", 15)
			_spawn_drop(Vector2(cx - 16.0, 0), "wood", 20)
			_note(0, "Supply drop in the middle of the map!")
	save_t -= dt
	if save_t <= 0.0:
		save_t = 30.0
		_save_match()
	t_sync += dt
	if t_sync >= 1.0:
		t_sync = 0.0
		c_time.rpc(prep_left, match_time)


# ------------------------------------------------------------ drawing
func _process(dt: float) -> void:
	var t := fmod(match_time, 480.0) / 480.0
	var keys := [Color(1, 1, 1), Color(1.0, 0.72, 0.56), Color(0.3, 0.36, 0.68), Color(0.96, 0.78, 0.74), Color(1, 1, 1)]
	var f := t * 4.0
	var ki := clampi(int(f), 0, 3)
	var col: Color = keys[ki].lerp(keys[ki + 1], smoothstep(0.0, 1.0, f - ki))
	if weather == "storm":
		col = col.darkened(0.25)
	elif weather == "rain" or weather == "fog":
		col = col.darkened(0.1)
	mod.color = col
	daylight = clampf(inverse_lerp(0.4, 0.95, (col.r + col.g + col.b) / 3.0), 0.0, 1.0)
	help_t = maxf(0.0, help_t - dt)
	var lp = players_root.get_node_or_null(str(multiplayer.get_unique_id()))
	var covered := false
	if lp:
		covered = not _exposed(Vector2i(floori(lp.position.x / T), floori(lp.position.y / T)))
	rain_k = move_toward(rain_k, 0.0 if covered else 1.0, dt * 3.0)
	queue_redraw()
	_update_hud()


func _cam_pos() -> Vector2:
	var p = players_root.get_node_or_null(str(multiplayer.get_unique_id()))
	return p.position if p else Vector2(world.w * T * 0.5, 0)


func _parallax(path: String, speed: float, base_y: float, col: Color, cam: Vector2, ref_y: float) -> float:
	var tx = Net.tex(path)
	if tx == null:
		return base_y
	var w: float = tx.get_width()
	var h: float = tx.get_height()
	var y := roundf(base_y + (cam.y - ref_y) * (1.0 - speed) * 0.5)
	var x0 := roundf(cam.x - fposmod(cam.x * speed, w) - w)
	for k in 5:
		draw_texture_rect(tx, Rect2(x0 + k * w, y - h, w, h), false, col)
	return y


func _draw() -> void:
	if world.w == 0:
		return
	var surf_y: float = world.h * 0.35 * T
	var cam := _cam_pos()
	var tm := Time.get_ticks_msec() / 1000.0
	var top := cam.y - 200.0
	draw_rect(Rect2(cam.x - 900, top - 3000, 1800, 3000), Color("2f63b8"))
	draw_rect(Rect2(cam.x - 900, top + 390, 1800, 3000), Color("c8e6f9"))
	var sky = Net.tex("res://assets/sky.png")
	if sky:
		draw_texture_rect(sky, Rect2(floorf((cam.x - 900) / 4.0) * 4.0, roundf(top), 1800, 400), true)
	var ang := fmod(match_time, 480.0) / 480.0 * TAU
	if daylight < 0.5:
		for i in 70:
			var sx := cam.x + fposmod(i * 97.0 - cam.x * 0.02, 1400.0) - 700.0
			var sy := top + 10.0 + fposmod(i * 53.0, 190.0)
			var tw := 0.6 + 0.4 * sin(tm * 3.0 + i)
			draw_rect(Rect2(roundf(sx), roundf(sy), 1, 1), Color(1, 1, 1, clampf((0.5 - daylight) * 2.5, 0.0, 1.0) * tw))
	var sun = Net.tex("res://assets/sun.png")
	var moon = Net.tex("res://assets/moon.png")
	if sun and cos(ang) > -0.15:
		draw_texture_rect(sun, Rect2(roundf(cam.x + sin(ang) * 280.0 - 24.0), roundf(cam.y - 40.0 - cos(ang) * 120.0 - 24.0), 48, 48), false)
	if moon and cos(ang) < 0.15:
		draw_texture_rect(moon, Rect2(roundf(cam.x - sin(ang) * 280.0 - 24.0), roundf(cam.y - 40.0 + cos(ang) * 120.0 - 24.0), 48, 48), false)
	var cloud = Net.tex("res://assets/clouds.png")
	if cloud:
		for i in 7:
			var cx := fposmod(i * 260.0 + tm * 4.0 - cam.x * 0.06, 1820.0) - 910.0 + cam.x
			draw_texture_rect_region(cloud, Rect2(roundf(cx), roundf(top + 18.0 + (i % 3) * 26.0), 96, 44), Rect2((i % 3) * 96, 0, 96, 44))
	var ref := surf_y - 20.0
	_parallax("res://assets/mountains_far.png", 0.08, surf_y + 50.0, Color.WHITE, cam, ref)
	_parallax("res://assets/mountains_near.png", 0.18, surf_y + 58.0, Color.WHITE, cam, ref)
	_parallax("res://assets/trees_far.png", 0.32, surf_y + 66.0, Color.WHITE, cam, ref)
	var fb := _parallax("res://assets/forest_near.png", 0.5, surf_y + 76.0, Color.WHITE, cam, ref)
	draw_rect(Rect2(cam.x - 900, fb - 1, 1800, 4000), Color("25504a"))
	# ambient particles: pollen by day, fireflies at night, dust underground
	var underground := cam.y > surf_y + 100.0
	for i in 34:
		var mx := cam.x + fposmod(i * 131.0 + tm * (6.0 + (i % 3) * 3.0), 700.0) - 350.0
		var my := cam.y + fposmod(i * 71.0 + sin(tm * 0.7 + i) * 24.0 - tm * 5.0, 400.0) - 200.0
		if underground:
			draw_rect(Rect2(mx, my, 1, 1), Color(0.8, 0.75, 0.7, 0.35))
		elif daylight < 0.45:
			var gl := 0.5 + 0.5 * sin(tm * 2.5 + i * 1.7)
			draw_circle(Vector2(mx, my), 2.2, Color(0.8, 1.0, 0.3, 0.14 * gl))
			draw_rect(Rect2(mx, my, 1.5, 1.5), Color(1.0, 1.0, 0.5, 0.9 * gl))
		else:
			draw_rect(Rect2(mx, my, 1.5, 1.5), Color(1.0, 1.0, 0.85, 0.55))
	var ftex := [Net.tex("res://assets/flag_blue.png"), Net.tex("res://assets/flag_red.png")]
	for t in 2:
		var f = flags[t]
		var base: Vector2 = f.pos
		if f.carrier != 0:
			var c = players_root.get_node_or_null(str(f.carrier))
			if c:
				base = c.position + Vector2(0, 10)
		if ftex[t]:
			draw_texture_rect_region(ftex[t], Rect2(base.x - 3, base.y - 30, 18, 30), Rect2((int(tm * 4.0) % 3) * 18, 0, 18, 30))
		else:
			draw_line(base, base + Vector2(0, -26), Color("5d4037"), 2.0)
			draw_colored_polygon(PackedVector2Array([base + Vector2(0, -26), base + Vector2(14, -20), base + Vector2(0, -14)]), Net.TEAM_COLORS[t])
	var items = Net.tex("res://assets/items.png")
	for did in drops:
		var d = drops[did]
		var idx: int = ITEM_ORDER.find(d.item)
		if items and idx >= 0:
			draw_texture_rect_region(items, Rect2(d.pos + Vector2(-8, -16 + sin(tm * 3.0 + did) * 1.5), Vector2(16, 16)), Rect2(idx * 16, 0, 16, 16))
		else:
			draw_rect(Rect2(d.pos + Vector2(-5, -10), Vector2(10, 10)), ITEM_COLORS.get(d.item, Color.WHITE))
	for e in fx:
		match e.k:
			"slash":
				var stx = Net.tex("res://assets/slash.png")
				if stx:
					draw_set_transform(e.a, (e.b - e.a).angle(), Vector2.ONE)
					draw_texture_rect_region(stx, Rect2(4, -20, 40, 40), Rect2(clampi(int((1.0 - e.t / 0.18) * 3.0), 0, 2) * 40, 0, 40, 40))
					draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				else:
					draw_line(e.a, e.b, Color.WHITE, 2.0)
			"line":
				draw_line(e.a, e.b, Color(1, 0.9, 0.4, 0.35), 5.0)
				draw_line(e.a, e.b, e.c, 2.0)
			"circle":
				var bt = Net.tex("res://assets/boom.png")
				if bt:
					var fr := clampi(int((1.0 - e.t / 0.35) * 6.0), 0, 5)
					var sz: float = e.r * 2.6
					draw_texture_rect_region(bt, Rect2(e.a - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), Rect2(fr * 64, 0, 64, 64))
				else:
					draw_circle(e.a, e.r * (1.0 - e.t / 0.35 * 0.5), Color(1.0, 0.6, 0.1, clampf(e.t * 2.5, 0.0, 0.8)))
			"path":
				if e.pts.size() > 1:
					draw_polyline(e.pts, Color(0.95, 0.9, 0.4, 0.8), 2.0)
			"deb":
				draw_rect(Rect2(e.a, Vector2(2, 2)), Color(e.c.r, e.c.g, e.c.b, clampf(e.t * 3.0, 0.0, 1.0)))


func _icon(item: String) -> Texture2D:
	if not _icons.has(item):
		var at = Net.tex("res://assets/items.png")
		var idx: int = ITEM_ORDER.find(item)
		if at == null or idx < 0:
			_icons[item] = null
		else:
			var a := AtlasTexture.new()
			a.atlas = at
			a.region = Rect2(idx * 16, 0, 16, 16)
			_icons[item] = a
	return _icons[item]


# ------------------------------------------------------------ HUD
func _mk_label(size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color(0.05, 0.06, 0.12))
	l.add_theme_constant_override("outline_size", 5)
	return l


func _tex_rect(path: String, size: Vector2) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = Net.tex(path)
	tr.size = size
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return tr


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	var fxl := CanvasLayer.new()
	fxl.layer = 5
	add_child(fxl)
	var ov := OverlayS.new()
	ov.game = self
	ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fxl.add_child(ov)
	ov.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var hbar := HotbarS.new()
	hbar.game = self
	hbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(hbar)
	hbar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud_panel = NinePatchRect.new()
	hud_panel.texture = Net.tex("res://assets/ui_panel.png")
	for m in ["left", "top", "right", "bottom"]:
		hud_panel.set("patch_margin_" + m, 6)
	hud_panel.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	hud_panel.size = Vector2(760, 62)
	layer.add_child(hud_panel)
	hud_panel.visible = false
	hud_top = _mk_label(18)
	hud_bottom = _mk_label(14)
	hud_msg = _mk_label(24)
	hud_help = _mk_label(12)
	hud_note = _mk_label(18)
	hud_store = _mk_label(13)
	hud_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hp_bg = ColorRect.new()
	hp_bg.color = Color(0.06, 0.07, 0.13, 0.92)
	hp_bg.size = Vector2(208, 22)
	hp_fill = ColorRect.new()
	hp_fill.color = Color("d63a3a")
	hp_fill.position = Vector2(3, 3)
	hp_bg.add_child(hp_fill)
	hp_hi = ColorRect.new()
	hp_hi.color = Color(1, 0.6, 0.6, 0.45)
	hp_hi.position = Vector2(3, 3)
	hp_bg.add_child(hp_hi)
	heart = _tex_rect("res://assets/ui_heart.png", Vector2(24, 24))
	for n in [hud_top, hud_bottom, hud_msg, hud_help, hud_note, hud_store, hp_bg, heart]:
		layer.add_child(n)
	hud_top.visible = false
	hp_bg.visible = false
	heart.visible = false
	for i in 10:
		var bg := _tex_rect("res://assets/ui_slot.png", Vector2(54, 54))
		layer.add_child(bg)
		bg.visible = false
		var lb := _mk_label(11)
		lb.add_theme_constant_override("outline_size", 3)
		lb.position = Vector2(5, 1)
		bg.add_child(lb)
		var ic := _tex_rect("res://assets/items.png", Vector2(28, 28))
		ic.position = Vector2(13, 14)
		bg.add_child(ic)
		var ct := _mk_label(12)
		ct.add_theme_constant_override("outline_size", 3)
		ct.position = Vector2(34, 34)
		bg.add_child(ct)
		slot_bg.append(bg)
		slot_lb.append(lb)
		slot_ic.append(ic)
		slot_ct.append(ct)
	craft_panel = PanelContainer.new()
	craft_panel.visible = false
	var cv := VBoxContainer.new()
	craft_panel.add_child(cv)
	var ct2 := Label.new()
	ct2.text = "Crafting (uses inventory, and team storage near base)"
	cv.add_child(ct2)
	for r in Net.RECIPES:
		var cost := ""
		for k in Net.RECIPES[r].cost:
			cost += "%d %s  " % [Net.RECIPES[r].cost[k], k]
		var b := Button.new()
		b.text = "%s x%d   [%s]" % [r, Net.RECIPES[r].n, cost.strip_edges()]
		b.icon = _icon(r)
		b.pressed.connect(send_craft.bind(r))
		cv.add_child(b)
	layer.add_child(craft_panel)
	craft_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	craft_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	craft_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	pause_panel = PanelContainer.new()
	pause_panel.visible = false
	var pv := VBoxContainer.new()
	pv.custom_minimum_size = Vector2(240, 0)
	pause_panel.add_child(pv)
	for item in [["Resume", _close_pause], ["Settings", _open_settings], ["Leave match", func(): Net.leave("")]]:
		var b2 := Button.new()
		b2.text = item[0]
		b2.pressed.connect(item[1])
		pv.add_child(b2)
	layer.add_child(pause_panel)
	pause_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	pause_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pause_panel.grow_vertical = Control.GROW_DIRECTION_BOTH


func _refresh_ui_flag() -> void:
	ui_open = craft_panel.visible or pause_panel.visible or settings_ui != null


func _close_pause() -> void:
	pause_panel.visible = false
	_refresh_ui_flag()


func _open_settings() -> void:
	if settings_ui:
		return
	settings_ui = SettingsS.new()
	pause_panel.get_parent().add_child(settings_ui)
	settings_ui.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	settings_ui.grow_horizontal = Control.GROW_DIRECTION_BOTH
	settings_ui.grow_vertical = Control.GROW_DIRECTION_BOTH
	settings_ui.closed.connect(func(): settings_ui.queue_free(); settings_ui = null; _refresh_ui_flag())
	_refresh_ui_flag()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_H:
			help_on = not help_on
		elif event.physical_keycode == KEY_C and not pause_panel.visible and settings_ui == null:
			craft_panel.visible = not craft_panel.visible
			_refresh_ui_flag()
		elif event.physical_keycode == KEY_ESCAPE:
			if settings_ui:
				return
			if craft_panel.visible:
				craft_panel.visible = false
			else:
				pause_panel.visible = not pause_panel.visible
			_refresh_ui_flag()


func _update_hud() -> void:
	var vs := get_viewport().get_visible_rect().size
	var me := multiplayer.get_unique_id()
	var d: Dictionary = cl.get(me, {"hp": 100, "inv": _empty_inv(), "dead": false})
	var p = players_root.get_node_or_null(str(me))
	var phase := "BATTLE"
	if prep_left > 0.0:
		phase = "PREP %d:%02d" % [floori(prep_left / 60.0), int(prep_left) % 60]
	var fl := ""
	for t in 2:
		var f = flags[t]
		var state := "home"
		if f.carrier != 0:
			state = "CARRIED"
		elif not f.home:
			state = "DROPPED"
		fl += "%s flag: %s    " % [Net.TEAM_NAMES[t], state]
	var tod: String = ["Day", "Sunset", "Night", "Dawn"][floori(fmod(match_time, 480.0) / 120.0)]
	hud_panel.position = Vector2(vs.x * 0.5 - 380, 6)
	hud_top.text = "BLUE %d : %d RED   |   first to %d   |   %s   |   %s, %s\n%s" % [score[0], score[1], WIN_SCORE, phase, tod, weather, fl]
	hud_top.position = Vector2(vs.x * 0.5 - 360, 9)
	var extra := ""
	if multiplayer.is_server() and Net.external_ip != "":
		extra = "\nServer address: %s (port %d)" % [Net.external_ip, Net.PORT]
	hud_help.visible = help_on or help_t > 0.0
	hud_help.text = HELP_TEXT + extra + "\n[H] hide / show help"
	hud_help.size = Vector2(340, 120)
	hud_help.position = Vector2(12, 8)
	var sel := 0
	var cname := "warrior"
	var ab_left := 0.0
	var team := 0
	if p:
		sel = p.selected
		cname = p.cls
		team = p.team
		ab_left = maxf(0.0, p.ab_until - Time.get_ticks_msec() / 1000.0)
	var inv: Array = d.inv
	var tex_n := Net.tex("res://assets/ui_slot.png")
	var tex_s := Net.tex("res://assets/ui_slot_sel.png")
	for i in 10:
		var bg: TextureRect = slot_bg[i]
		bg.position = Vector2(vs.x * 0.5 - 288 + i * 58, vs.y - 66)
		bg.texture = tex_s if i == sel else tex_n
		var e: Dictionary = inv[i] if i < inv.size() else {}
		(slot_lb[i] as Label).text = "%d" % ((i + 1) % 10)
		var ic: TextureRect = slot_ic[i]
		var ct: Label = slot_ct[i]
		if e.is_empty():
			ic.texture = null
			ct.text = ""
		else:
			ic.texture = _icon(e.i)
			ct.text = "%d" % e.n if e.n > 1 else ""
	var cdata: Dictionary = Net.CLASSES[cname]
	hud_bottom.text = "%s   |   Q: %s %s" % [cdata["label"], cdata["ability"], ("(%ds)" % ceili(ab_left)) if ab_left > 0.0 else "(ready)"]
	hud_bottom.position = Vector2(14, vs.y - 74)
	heart.position = Vector2(12, vs.y - 50)
	hp_bg.position = Vector2(40, vs.y - 48)
	var wfill := 202.0 * clampf(d.hp / 100.0, 0.0, 1.0)
	hp_fill.size = Vector2(wfill, 16)
	hp_hi.size = Vector2(wfill, 6)
	var s_: Dictionary = store[team]
	hud_store.text = "Team storage: wood %d  stone %d  metal %d" % [s_.wood, s_.stone, s_.metal]
	hud_store.position = Vector2(14, vs.y - 96)
	hud_note.text = note if note_t > 0.0 else ""
	hud_note.position = Vector2(vs.x * 0.5 - 220, vs.y * 0.55)
	if match_over:
		var txt := "%s team wins!  (new map in a few seconds)\n" % Net.TEAM_NAMES[winner]
		for r in end_rows:
			txt += "\n%s [%s]   K %d   D %d   Flags %d" % [r[0], Net.TEAM_NAMES[r[1]], r[2], r[3], r[4]]
		hud_msg.text = txt
	elif d.dead:
		hud_msg.text = "You died. Respawn in %d s (F1-F4: change class)" % maxi(0, ceili(respawn_at - Time.get_ticks_msec() / 1000.0))
	else:
		hud_msg.text = ""
	hud_msg.position = Vector2(vs.x * 0.5 - 260, vs.y * 0.22)

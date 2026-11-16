extends Node2D
# Матч (оркестратор). Хост (peer 1) авторитетний. Ігрова логіка рознесена по менеджерах (scripts/managers):
#   CombatManager       - бій, стріли, здібності, бафи, пастки
#   BuildingManager     - копання, будівництво, робочі столи, крафт, сховище, інвентар, відновлення ресурсів
#   FireExplosionSystem - вогонь, вибухи, катапульта
#   FlagManager         - прапори, рахунок, кінець матчу
#   SaveManager         - збереження матчу
# Тут залишились: життєвий цикл матчу, мережеві RPC (точки входу запитів і розсилка стану), вітер, ефекти, HUD і вікна.
# Погода: дощ, гроза і туман прибрані з гри, погода завжди ясна (змінюється лише вітер).

const T := 16
const PREP_TIME := 120.0
const RESPAWN := 15.0
const WIN_SCORE := 3
const WorldS = preload("res://scripts/world.gd")
const PlayerS = preload("res://scripts/player.gd")
const OverlayS = preload("res://scripts/overlay.gd")
const SettingsS = preload("res://scripts/settings.gd")
const HotbarS = preload("res://scripts/hotbar.gd")
const InvS = preload("res://scripts/inventory.gd")
const LookS = preload("res://scripts/look.gd")
const CombatS = preload("res://scripts/managers/CombatManager.gd")
const BuildingS = preload("res://scripts/managers/BuildingManager.gd")
const FireS = preload("res://scripts/managers/FireExplosionSystem.gd")
const FlagS = preload("res://scripts/managers/FlagManager.gd")
const SaveS = preload("res://scripts/managers/SaveManager.gd")
const PhysS = preload("res://scripts/managers/WorldPhysics.gd")
const CraftUIS = preload("res://scripts/ui/craft_ui.gd")
const InvUIS = preload("res://scripts/ui/inventory_ui.gd")
const TeamUIS = preload("res://scripts/ui/team_select.gd")
const ClassUIS = preload("res://scripts/ui/class_select.gd")
const HELP_TEXT := "WASD move | Space jump | S+Space drop through platform | Shift run | Ctrl crouch\n1-3 tools | 4-0 items | Wheel switch | LMB attack / dig / place (hold LMB to draw the bow) | RMB block / tool swing\nAbilities: Warrior hold LMB 1.5 s = Power Strike (normal hit on release) | Archer hold LMB 2.5 s = Multi-shot | Builder: none\nArrows refill to 20 at your spawn point or workbench | Back walls (craft: Wall) hold blocks in front of them\nX block (tap right before a hit = parry) | Z dodge | E use: workbench, catapult, ballista, hatch, chest, storage | G take from storage\nC craft | Tab inventory | B class | M team | F1-F3 quick class | Esc menu"

var world
var players_root: Node2D
var fx_layer: Node2D
var mod: CanvasModulate
var combat
var building
var fire_sys
var flags_mgr
var saver
var physics
var falling := {}     # усі: id -> {p, vy, b, hit} (падаючі блоки)
var st := {}          # host: id -> стан гравця
var cl := {}          # усі: id -> {hp, inv, dead}
var edits := {}       # cell -> [block, team]
var block_hp := {}
var structs := {}     # host: cell -> {type, team, ready_at, cd}
var fuses := {}       # host: cell -> seconds
var drops := {}       # id -> {pos, item, n, owner, lock}
var drop_id := 1
var arrows := {}      # усі: id -> {p, v, k, team, g, life, stuck}
var arrow_meta := {}  # host: id -> {src, dmg}
var arrow_id := 1
var cracks := {}      # усі: cell -> 0..1
var wall_edits := {}  # усі: cell -> 0/1 (зміни задніх стін відносно згенерованого світу)
var store := [{"wood": 0, "stone": 0, "metal": 0}, {"wood": 0, "stone": 0, "metal": 0}]
var score := [0, 0]
var winner := -1
var end_rows := []
var flags := []
var prep_left := PREP_TIME
var match_time := 0.0
var match_over := false
var respawn_at := 0.0
var weather := "clear"  # завжди "clear": дощу, грози і туману більше немає
var wind := 0.0
var flash := 0.0
var fx := []
var note := ""
var note_t := 0.0
var ui_open := false
var weather_t := 40.0   # таймер зміни вітру
var supply_t := 90.0
var check_t := 0.0
var t_pick := 0.0
var t_sync := 0.0
var t_refill := 0.0
var rain_k := 1.0       # 1 = гравець під відкритим небом (для променів світла), 0 = під дахом / під землею
var daylight := 1.0
var help_t := 25.0
var help_on := false
var hud_layer: CanvasLayer
var hud_msg: Label
var hud_help: Label
var hud_note: Label
var hud_store: Label
var craft_ui
var inv_ui
var team_ui
var class_ui
var pause_panel: PanelContainer
var settings_ui: Control


func _ready() -> void:
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	world = WorldS.new()
	add_child(world)
	players_root = Node2D.new()
	players_root.name = "Players"
	add_child(players_root)
	fx_layer = Node2D.new()
	fx_layer.name = "FX"
	add_child(fx_layer)
	fx_layer.draw.connect(_draw_fx)
	mod = CanvasModulate.new()
	add_child(mod)
	combat = _mgr(CombatS, "CombatManager")
	building = _mgr(BuildingS, "BuildingManager")
	fire_sys = _mgr(FireS, "FireExplosionSystem")
	flags_mgr = _mgr(FlagS, "FlagManager")
	saver = _mgr(SaveS, "SaveManager")
	physics = _mgr(PhysS, "WorldPhysics")
	_build_hud()
	Net.players_changed.connect(_sync_player_nodes)
	_start_match(Net.world_seed, Net.map_size)
	if not multiplayer.is_server():
		req_sync.rpc_id(1)
	_show.call_deferred(team_ui)


func _mgr(script, n: String) -> Node:
	var m = script.new()
	m.name = n
	m.g = self
	add_child(m)
	return m


# ------------------------------------------------------------ допоміжні функції для менеджерів
func now() -> float:
	return Time.get_ticks_msec() / 1000.0


func player_node(id: int):
	return players_root.get_node_or_null(str(id))


func actor(id: int):
	var s = st.get(id)
	var p = player_node(id)
	if s == null or p == null or s.dead_until > 0.0 or not Net.players.has(id):
		return null
	return [s, p]


func count_structs(kind: String, team: int) -> int:
	var n := 0
	for c in structs:
		if structs[c].type == kind and int(structs[c].team) == team:
			n += 1
	return n


func push_state(id: int) -> void:
	var s = st[id]
	c_state.rpc(id, s.hp, s.inv.duplicate(true), s.dead_until > 0.0)


func push_store() -> void:
	c_store.rpc(store)


func note_to(target: int, text: String) -> void:
	c_note.rpc(target, text)


func send_edits(list: Array) -> void:
	var olds := []
	for e in list:
		olds.append(world.get_cell(e[0]))
	c_edits.rpc(list)
	if multiplayer.is_server():
		physics.after_edits(list, olds)


# Задні стіни (world.bg): 1 = є стіна. Стіна тримає блоки перед собою (див. WorldPhysics).
func has_wall(c: Vector2i) -> bool:
	if c.x < 0 or c.y < 0 or c.x >= world.w or c.y >= world.h:
		return false
	return world.bg[c.y * world.w + c.x] == 1


func _set_wall(c: Vector2i, v: int) -> void:
	if c.x < 0 or c.y < 0 or c.x >= world.w or c.y >= world.h:
		return
	world.bg[c.y * world.w + c.x] = v


func send_walls(list: Array) -> void:
	c_walls.rpc(list)
	if multiplayer.is_server():
		physics.after_walls(list)


# Видаляє клітинки (двері видаляються цілком: нижня + верхня клітинка).
func remove_cells(cells: Array) -> void:
	var list := []
	var seen := {}
	var queue := cells.duplicate()
	while not queue.is_empty():
		var c: Vector2i = queue.pop_back()
		if seen.has(c):
			continue
		seen[c] = true
		if world.get_cell(c) == world.DOOR:
			for d in [Vector2i(0, -1), Vector2i(0, 1)]:
				if world.get_cell(c + d) == world.DOOR and not seen.has(c + d):
					queue.append(c + d)
		block_hp.erase(c)
		structs.erase(c)
		world.fire.erase(c)
		list.append([c, 0, -1])
	if not list.is_empty():
		send_edits(list)


func spawn_drop(pos: Vector2, item: String, n: int, owner: int = 0) -> void:
	drops[drop_id] = {"pos": world.drop_pos(pos), "item": item, "n": n, "owner": owner, "lock": now() + 1.5}
	drop_id += 1
	c_drops.rpc(drops)


func _kit(cname: String) -> Array:
	var inv := InvS.empty()
	for it in Net.KITS.get(cname, []):
		InvS.add(inv, it[0], it[1])
	return inv


func _new_state(cname: String = "warrior") -> Dictionary:
	return {"hp": 100, "inv": _kit(cname), "dead_until": 0.0, "atk": 0.0, "dig": 0.0, "use": 0.0, "dodge": 0.0, "block": false, "block_since": 0.0, "inv_until": 0.0, "last_pos": Vector2.ZERO, "k": 0, "d": 0, "c": 0, "combo": 0, "last_swing": 0.0, "buffs": {}, "ab0": 0.0, "team_set": false, "cls_set": false}


# ------------------------------------------------------------ життєвий цикл матчу
func _start_match(seed_value: int, size: int) -> void:
	edits.clear()
	block_hp.clear()
	structs.clear()
	fuses.clear()
	drops.clear()
	arrows.clear()
	arrow_meta.clear()
	cracks.clear()
	wall_edits.clear()
	building.reset()
	physics.reset()
	falling.clear()
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
			push_state(id)


func _sync_player_nodes() -> void:
	var srv := multiplayer.is_server()
	for id in Net.players:
		var info = Net.players[id]
		var p = player_node(id)
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
			push_state(id)
	for p in players_root.get_children():
		if not Net.players.has(p.id):
			flags_mgr.drop_flag_of(p.id)
			st.erase(p.id)
			cl.erase(p.id)
			p.queue_free()


func _sid() -> int:
	var s := multiplayer.get_remote_sender_id()
	return 1 if s == 0 else s


# ------------------------------------------------------------ клієнт -> хост
func _req(method: String, args: Array) -> void:
	if multiplayer.is_server():
		callv(method, args)
	else:
		callv("rpc_id", [1, method] + args)


func send_use(cell: Vector2i, slot: int) -> void:
	_req("req_use", [cell, slot])


func send_dig(cell: Vector2i, tool: String) -> void:
	_req("req_dig", [cell, tool])


func send_swing(dir: Vector2, tool: String) -> void:
	_req("req_swing", [dir, tool])


func send_shoot(dir: Vector2, k: float) -> void:
	_req("req_shoot", [dir, k])


func send_ability(idx: int, dir: Vector2) -> void:
	_req("req_ability", [idx, dir])


func send_class(c: String) -> void:
	_req("req_class", [c])


func send_team(t: int) -> void:
	_req("req_team", [t])


func send_interact(dir: Vector2) -> void:
	_req("req_interact", [dir])


func send_store(dep: bool) -> void:
	_req("req_store", [dep])


func send_craft(r: String, times: int = 1) -> void:
	_req("req_craft", [r, times])


func send_block(on: bool) -> void:
	_req("req_block", [on])


func send_dodge(face: int) -> void:
	_req("req_dodge", [face])


func send_swap(a: int, b: int) -> void:
	_req("req_swap", [a, b])


func send_drop(slot: int) -> void:
	_req("req_drop", [slot])


func send_sort() -> void:
	_req("req_sort", [])


# Робочі станції своєї команди поруч з локальним гравцем (для вікна крафту).
func local_stations() -> Dictionary:
	var out := {"hand": true, "workbench": false, "siege_workshop": false}
	var p = player_node(multiplayer.get_unique_id())
	if p == null:
		return out
	var pc := Vector2i(floori(p.position.x / T), floori(p.position.y / T))
	for dx in range(-4, 5):
		for dy in range(-4, 5):
			var c := pc + Vector2i(dx, dy)
			var b: int = world.get_cell(c)
			if (b == world.WORKBENCH or b == world.SIEGE_WS) and int(world.owner_team.get(c, -1)) == p.team:
				if p.position.distance_to(Vector2(c) * T + Vector2(8, 8)) < 60.0:
					out["workbench" if b == world.WORKBENCH else "siege_workshop"] = true
	return out


func interact_local(dir: Vector2) -> void:
	var p = player_node(multiplayer.get_unique_id())
	if p == null:
		return
	var pc := Vector2i(floori(p.position.x / T), floori(p.position.y / T))
	for dx in range(-3, 4):
		for dy in range(-3, 4):
			var c := pc + Vector2i(dx, dy)
			var b: int = world.get_cell(c)
			if b in [world.CATAPULT, world.BALLISTA, world.HATCH, world.HATCH_OPEN, world.RUIN_CHEST] and p.position.distance_to(Vector2(c) * T + Vector2(8, 8)) < 48.0:
				send_interact(dir)
				return
	var stn := local_stations()
	if stn.workbench or stn.siege_workshop:
		_show(craft_ui)
		return
	send_interact(dir)


# ------------------------------------------------------------ хост: точки входу запитів
@rpc("any_peer", "reliable")
func req_use(cell: Vector2i, slot: int) -> void:
	if multiplayer.is_server():
		building.use(_sid(), cell, slot)


@rpc("any_peer", "reliable")
func req_dig(cell: Vector2i, tool: String) -> void:
	if multiplayer.is_server():
		building.dig(_sid(), cell, tool)


@rpc("any_peer", "reliable")
func req_swing(dir: Vector2, tool: String) -> void:
	if multiplayer.is_server():
		combat.swing(_sid(), dir, tool)


@rpc("any_peer", "reliable")
func req_shoot(dir: Vector2, k: float) -> void:
	if multiplayer.is_server():
		combat.shoot(_sid(), dir, k)


@rpc("any_peer", "reliable")
func req_ability(idx: int, dir: Vector2) -> void:
	if multiplayer.is_server():
		combat.ability(_sid(), idx, dir)


@rpc("any_peer", "reliable")
func req_interact(dir: Vector2) -> void:
	if multiplayer.is_server():
		building.interact(_sid(), dir)


@rpc("any_peer", "reliable")
func req_store(dep: bool) -> void:
	if multiplayer.is_server():
		building.store_op(_sid(), dep)


@rpc("any_peer", "reliable")
func req_craft(r: String, times: int) -> void:
	if multiplayer.is_server():
		building.craft(_sid(), r, times)


@rpc("any_peer", "reliable")
func req_swap(a: int, b: int) -> void:
	if multiplayer.is_server():
		building.swap(_sid(), a, b)


@rpc("any_peer", "reliable")
func req_drop(slot: int) -> void:
	if multiplayer.is_server():
		building.drop(_sid(), slot)


@rpc("any_peer", "reliable")
func req_sort() -> void:
	if multiplayer.is_server():
		building.sort(_sid())


@rpc("any_peer", "reliable")
func req_block(on: bool) -> void:
	if not multiplayer.is_server():
		return
	var s = st.get(_sid())
	if s == null or s.dead_until > 0.0:
		return
	if on and not s.block:
		s.block_since = now()
	s.block = on


@rpc("any_peer", "reliable")
func req_dodge(face: int) -> void:
	if not multiplayer.is_server():
		return
	var id := _sid()
	var a = actor(id)
	if a == null:
		return
	var s = a[0]
	var t := now()
	if t < s.dodge:
		return
	s.dodge = t + 1.4
	s.inv_until = t + 0.35
	c_knock.rpc(id, Vector2(signf(face) * 300.0, -40.0))
	c_anim.rpc(id, 1)


@rpc("any_peer", "reliable")
func req_class(cname: String) -> void:
	if not multiplayer.is_server() or not Net.CLASSES.has(cname):
		return
	var id := _sid()
	var s = st.get(id)
	var p = player_node(id)
	if s == null or p == null or not Net.players.has(id):
		return
	var near_base: bool = p.position.distance_to(world.flag_pos(Net.players[id].team)) < 120.0
	if not (s.dead_until > 0.0 or near_base or prep_left > 0.0 or not s.cls_set):
		note_to(id, "Change class at your base, during preparation or while dead")
		return
	if not s.cls_set and s.dead_until <= 0.0:
		s.inv = _kit(cname)
		push_state(id)
	s.cls_set = true
	Net.players[id].cls = cname
	Net.set_players.rpc(Net.players)


@rpc("any_peer", "reliable")
func req_team(t: int) -> void:
	if not multiplayer.is_server() or t < 0 or t > 1:
		return
	var id := _sid()
	var s = st.get(id)
	if s == null or not Net.players.has(id):
		return
	if int(Net.players[id].team) == t:
		s.team_set = true
		return
	if s.team_set and prep_left <= 0.0 and s.dead_until <= 0.0:
		note_to(id, "You can switch teams during preparation or while dead")
		return
	var c := Net.team_counts(id)
	if c[t] > c[1 - t]:
		note_to(id, "%s team is full, teams must stay balanced" % Net.TEAM_NAMES[t])
		return
	s.team_set = true
	flags_mgr.drop_flag_of(id)
	Net.players[id].team = t
	Net.set_players.rpc(Net.players)
	var pos: Vector2 = world.spawn_pos(t)
	s.last_pos = pos
	c_respawn.rpc(id, pos)


# ------------------------------------------------------------ синхронізація (хост -> усі)
@rpc("any_peer", "reliable")
func req_sync() -> void:
	if not multiplayer.is_server():
		return
	var snap := {}
	for id in st:
		snap[id] = {"hp": st[id].hp, "inv": st[id].inv.duplicate(true), "dead": st[id].dead_until > 0.0}
	var d := {"edits": edits, "score": score, "flags": flags, "prep": prep_left, "mt": match_time, "cl": snap, "win": winner, "fire": world.fire.keys(), "drops": drops, "store": store, "weather": weather, "wind": wind, "rows": end_rows, "trees": world.trees, "walls": wall_edits}
	c_full.rpc_id(_sid(), d)


@rpc("authority", "reliable")
func c_full(d: Dictionary) -> void:
	edits = d.edits
	for c in edits:
		world.set_cell(c, edits[c][0], edits[c][1])
	world.trees = d.trees
	wall_edits = d.get("walls", {})
	for c in wall_edits:
		_set_wall(c, int(wall_edits[c]))
	score = d.score
	flags = d.flags
	prep_left = d.prep
	match_time = d.mt
	cl = d.cl
	winner = d.win
	match_over = winner >= 0
	drops = d.drops
	store = d.store
	weather = "clear"
	wind = d.wind
	end_rows = d.rows
	world.fire.clear()
	for c in d.fire:
		world.fire[c] = 1.0
	for id in cl:
		var p = player_node(id)
		if p:
			p.set_dead(cl[id].dead)


@rpc("authority", "call_local", "reliable")
func c_state(id: int, hp: int, inv: Array, dead: bool) -> void:
	cl[id] = {"hp": hp, "inv": inv, "dead": dead}
	var p = player_node(id)
	if p:
		p.set_dead(dead)
	if id == multiplayer.get_unique_id() and dead and respawn_at < now():
		respawn_at = now() + RESPAWN


@rpc("authority", "call_local", "reliable")
func c_respawn(id: int, pos: Vector2) -> void:
	var p = player_node(id)
	if p:
		p.reset_to_spawn(pos)


@rpc("authority", "call_local", "reliable")
func c_tp(id: int, pos: Vector2) -> void:
	var p = player_node(id)
	if p:
		p.reset_to_spawn(pos)


@rpc("authority", "call_local", "reliable")
func c_edits(list: Array) -> void:
	var noisy := false
	for e in list:
		var old: int = world.get_cell(e[0])
		var watery: bool = e[1] == world.WATER or old == world.WATER
		if not watery:
			noisy = true
		if e[1] == 0 and fx.size() < 150 and not watery:
			if old != 0:
				var dc: Color = world.COLORS.get(old, Color.GRAY)
				for k in 3:
					fx.append({"k": "deb", "a": Vector2(e[0]) * T + Vector2(randf_range(2, 14), randf_range(2, 14)), "v": Vector2(randf_range(-40, 40), randf_range(-90, -20)), "c": dc, "t": 0.5})
		edits[e[0]] = [e[1], e[2]]
		cracks.erase(e[0])
		world.set_cell(e[0], e[1], e[2])
	if noisy:
		Net.play("place" if list[0][1] != 0 else "dig")


@rpc("authority", "call_local", "reliable")
func c_walls(list: Array) -> void:
	for e in list:
		var c: Vector2i = e[0]
		var v: int = int(e[1])
		if v == 0 and has_wall(c) and fx.size() < 150:
			for k in 3:
				fx.append({"k": "deb", "a": Vector2(c) * T + Vector2(randf_range(2, 14), randf_range(2, 14)), "v": Vector2(randf_range(-30, 30), randf_range(-60, -10)), "c": Color(0.42, 0.36, 0.34), "t": 0.5})
		wall_edits[c] = v
		_set_wall(c, v)
	if not list.is_empty():
		Net.play("place" if int(list[0][1]) != 0 else "dig")


# Блок, що впав з великої висоти, розбивається на уламки.
@rpc("authority", "call_local", "reliable")
func c_shatter(pos: Vector2, b: int) -> void:
	var dc: Color = world.COLORS.get(b, Color.GRAY)
	for k in 8:
		fx.append({"k": "deb", "a": pos + Vector2(randf_range(-6, 6), randf_range(-4, 6)), "v": Vector2(randf_range(-90, 90), randf_range(-150, -40)), "c": dc, "t": 0.7})


@rpc("authority", "call_local", "reliable")
func c_knock(id: int, v: Vector2) -> void:
	var p = player_node(id)
	if p and p.is_multiplayer_authority():
		p.apply_knock(v)


# kind: 0 удар по дузі, 1 лінія, 2 вихор, 3 ударна хвиля (Power Strike), 4 лікування / ремонт
@rpc("authority", "call_local", "unreliable")
func c_fx(a: Vector2, b: Vector2, kind: int) -> void:
	match kind:
		0: fx.append({"k": "slash", "a": a, "b": b, "t": 0.18})
		1: fx.append({"k": "line", "a": a, "b": b, "t": 0.12, "c": Color("f1c40f")})
		2: fx.append({"k": "spin", "a": a, "r": a.distance_to(b), "t": 0.3})
		3: fx.append({"k": "ring", "a": a, "r": a.distance_to(b), "t": 0.5, "c": Color(1.0, 0.85, 0.35)})
		4: fx.append({"k": "ring", "a": a, "r": a.distance_to(b), "t": 0.5, "c": Color(0.45, 1.0, 0.55)})


@rpc("authority", "call_local", "unreliable")
func c_anim(id: int, kind: int) -> void:
	var p = player_node(id)
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


# Погода завжди ясна (дощ / гроза / туман прибрані), передається лише вітер.
@rpc("authority", "call_local", "reliable")
func c_weather(_kind: String, w: float) -> void:
	weather = "clear"
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
func c_arrow(aid: int, pos: Vector2, v: Vector2, kind: int, team: int, grav: float) -> void:
	arrows[aid] = {"p": pos, "v": v, "k": kind, "team": team, "g": grav, "life": 4.0, "stuck": 0.0}


@rpc("authority", "call_local", "reliable")
func c_arrow_end(aid: int, pos: Vector2, stuck: bool) -> void:
	if not arrows.has(aid):
		return
	if stuck:
		arrows[aid].p = pos
		arrows[aid].stuck = 3.0
	else:
		arrows.erase(aid)


@rpc("authority", "call_local", "unreliable")
func c_crack(cell: Vector2i, k: float) -> void:
	if k <= 0.0:
		cracks.erase(cell)
	else:
		cracks[cell] = k


@rpc("authority", "call_local", "reliable")
func c_tree(x: int, top: int, kind: int) -> void:
	world.add_tree(x, top, kind)


@rpc("authority", "call_local", "reliable")
func c_buff(id: int, n: String, dur: float) -> void:
	var p = player_node(id)
	if p:
		p.add_buff(n, dur)


@rpc("authority", "call_local", "reliable")
func c_death(id: int, pos: Vector2) -> void:
	var tc: Color = Net.TEAM_COLORS[int(Net.players.get(id, {}).get("team", 0))]
	for i in 16:
		var c := tc if i % 2 == 0 else Color(0.8, 0.1, 0.1)
		fx.append({"k": "deb", "a": pos + Vector2(randf_range(-5, 5), randf_range(-10, 8)), "v": Vector2(randf_range(-70, 70), randf_range(-160, -40)), "c": c, "t": 0.9})
	Net.play("death")


@rpc("authority", "call_local", "unreliable")
func c_dmg(pos: Vector2, n: int) -> void:
	fx.append({"k": "num", "a": pos + Vector2(randf_range(-4, 4), 0), "n": n, "t": 0.8})


@rpc("authority", "call_local", "reliable")
func c_fall(fid: int, pos: Vector2, b: int) -> void:
	falling[fid] = {"p": pos, "y0": pos.y, "vy": 0.0, "b": b, "hit": {}}


@rpc("authority", "call_local", "reliable")
func c_fall_end(fid: int) -> void:
	falling.erase(fid)


@rpc("authority", "call_local", "reliable")
func new_match(seed_value: int) -> void:
	Net.world_seed = seed_value
	_start_match(seed_value, Net.map_size)


# ------------------------------------------------------------ хост: підбір предметів
func _pickups() -> void:
	var changed := false
	var t := now()
	for did in drops.keys():
		var d = drops[did]
		for oid in st:
			if st[oid].dead_until > 0.0:
				continue
			if int(d.get("owner", 0)) == oid and t < float(d.get("lock", 0.0)):
				continue
			var q = player_node(oid)
			if q == null or q.position.distance_to(d.pos) > 22.0:
				continue
			var left := InvS.add(st[oid].inv, d.item, int(d.n))
			if left < int(d.n):
				changed = true
				push_state(oid)
				c_sfx.rpc("pickup")
			if left <= 0:
				drops.erase(did)
				break
			d.n = left
	if changed:
		c_drops.rpc(drops)


# Поповнення стріл до ARROW_REFILL біля своєї бази / точки спавна / робочого столу.
func _at_refill_point(team: int, pos: Vector2) -> bool:
	if pos.distance_to(world.flag_pos(team)) < 110.0:
		return true
	for c in structs:
		var sc = structs[c]
		if (sc.type == "spawn" or sc.type == "workbench") and int(sc.team) == team and pos.distance_to(Vector2(c) * T + Vector2(8, 8)) < 64.0:
			return true
	return false


func _refill_arrows() -> void:
	for id in st:
		var s = st[id]
		if s.dead_until > 0.0 or not Net.players.has(id) or not "bow" in Net.tools_of(Net.players[id].cls):
			continue
		var have := InvS.count(s.inv, "arrow")
		if have >= Net.ARROW_REFILL:
			continue
		var q = player_node(id)
		if q == null or not _at_refill_point(int(Net.players[id].team), q.position):
			continue
		var want: int = Net.ARROW_REFILL - have
		var left := InvS.add(s.inv, "arrow", want)
		if left < want:
			push_state(id)
			note_to(id, "Arrows refilled: %d" % (have + want - left))


func _exposed(c: Vector2i) -> bool:
	for yy in range(c.y - 1, -1, -1):
		if world.is_solid(c.x, yy):
			return false
	return true


func _respawn_pos(team: int) -> Vector2:
	var opts := [world.spawn_pos(team)]
	for c in structs:
		if structs[c].type == "spawn" and int(structs[c].team) == team:
			opts.append(Vector2(c.x * T + 8, (c.y + 1) * T - 15))
	return opts[randi() % opts.size()]


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
		elif e.k == "num":
			e.a += Vector2(0, -28.0 * dt)
	fx = fx.filter(func(e): return e.t > 0.0)
	combat.sim(dt)
	physics.sim_falling(dt)
	if not multiplayer.is_server():
		return
	var t := now()
	for id in st:
		var s = st[id]
		if s.dead_until > 0.0 and t >= s.dead_until:
			var team: int = Net.players[id].team if Net.players.has(id) else 0
			s.dead_until = 0.0
			s.hp = 100
			s.buffs = {}
			s.inv = _kit(Net.players[id].cls if Net.players.has(id) else "warrior")
			var pos := _respawn_pos(team)
			s.last_pos = pos
			c_respawn.rpc(id, pos)
			push_state(id)
	if prep_left <= 0.0 and not match_over:
		flags_mgr.tick()
	fire_sys.tick(dt)
	combat.tick(dt)
	building.tick(dt)
	saver.tick(dt)
	physics.tick(dt)
	t_refill += dt
	if t_refill >= 1.0:
		t_refill = 0.0
		_refill_arrows()
	t_pick += dt
	if t_pick >= 0.2:
		t_pick = 0.0
		_pickups()
	check_t += dt
	if check_t >= 0.5:
		check_t = 0.0
		for id in st:
			var q = player_node(id)
			if id == 1 or q == null or st[id].dead_until > 0.0:
				continue
			if st[id].last_pos == Vector2.ZERO:
				st[id].last_pos = q.position
			elif q.position.distance_to(st[id].last_pos) > 450.0:
				c_tp.rpc(id, st[id].last_pos)
			else:
				st[id].last_pos = q.position
	# лише зміна вітру: дощу, грози й туману в грі більше немає
	weather_t -= dt
	if weather_t <= 0.0:
		weather_t = randf_range(60.0, 120.0)
		c_weather.rpc("clear", randf_range(-1.0, 1.0))
	if prep_left <= 0.0 and not match_over:
		supply_t -= dt
		if supply_t <= 0.0:
			supply_t = 90.0
			var cx: float = world.w * T * 0.5 + randf_range(-60.0, 60.0)
			spawn_drop(Vector2(cx, 0), "metal", 10)
			spawn_drop(Vector2(cx + 16.0, 0), "stone", 15)
			spawn_drop(Vector2(cx - 16.0, 0), "wood", 20)
			note_to(0, "Supply drop in the middle of the map!")
	t_sync += dt
	if t_sync >= 1.0:
		t_sync = 0.0
		c_time.rpc(prep_left, match_time)


# ------------------------------------------------------------ малювання
func _process(dt: float) -> void:
	var tt := fmod(match_time, 480.0) / 480.0
	var keys := [Color(1, 1, 1), Color(1.0, 0.72, 0.56), Color(0.3, 0.36, 0.68), Color(0.96, 0.78, 0.74), Color(1, 1, 1)]
	var f := tt * 4.0
	var ki := clampi(int(f), 0, 3)
	var col: Color = keys[ki].lerp(keys[ki + 1], smoothstep(0.0, 1.0, f - ki))
	mod.color = col
	daylight = clampf(inverse_lerp(0.4, 0.95, (col.r + col.g + col.b) / 3.0), 0.0, 1.0)
	help_t = maxf(0.0, help_t - dt)
	var lp = player_node(multiplayer.get_unique_id())
	var covered := false
	if lp:
		covered = not _exposed(Vector2i(floori(lp.position.x / T), floori(lp.position.y / T)))
	rain_k = move_toward(rain_k, 0.0 if covered else 1.0, dt * 3.0)
	queue_redraw()
	fx_layer.queue_redraw()
	_update_hud()


# Позиція реальної (згладженої) камери: фон малюється відносно неї, тому не смикається при ходьбі / стрибках.
func _cam_pos() -> Vector2:
	var cam := get_viewport().get_camera_2d()
	if cam:
		return cam.get_screen_center_position()
	var p = player_node(multiplayer.get_unique_id())
	return p.position if p else Vector2(world.w * T * 0.5, 0)


func _parallax(path: String, speed: float, base_y: float, cam: Vector2, ref_y: float) -> float:
	var tx = Net.tex(path)
	if tx == null:
		return base_y
	var w: float = tx.get_width()
	var h: float = tx.get_height()
	var y := roundf(base_y + (cam.y - ref_y) * (1.0 - speed) * 0.5)
	var x0 := roundf(cam.x - fposmod(cam.x * speed, w) - w)
	for k in 5:
		draw_texture_rect(tx, Rect2(x0 + k * w, y - h, w, h), false)
	return y


func _draw() -> void:
	if world.w == 0:
		return
	var surf_y: float = world.h * 0.35 * T
	var cam := _cam_pos()
	var tm := now()
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
	_parallax("res://assets/mountains_far.png", 0.08, surf_y + 50.0, cam, ref)
	_parallax("res://assets/mountains_near.png", 0.18, surf_y + 58.0, cam, ref)
	_parallax("res://assets/trees_far.png", 0.32, surf_y + 66.0, cam, ref)
	var fb := _parallax("res://assets/forest_near.png", 0.5, surf_y + 76.0, cam, ref)
	draw_rect(Rect2(cam.x - 900, fb - 1, 1800, 4000), Color("25504a"))
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
		var fl = flags[t]
		var base: Vector2 = fl.pos
		if fl.carrier != 0:
			var c = player_node(fl.carrier)
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
		LookS.draw_icon(self, d.item, Rect2(d.pos + Vector2(-8, -16 + sin(tm * 3.0 + did) * 1.5), Vector2(16, 16)), items)


# Ефекти над світом і гравцями: стріли, дуги ударів, тріщини блоків, числа шкоди, вибухи.
func _draw_fx() -> void:
	var ci := fx_layer
	var font := ThemeDB.fallback_font
	for c in cracks:
		var k: float = cracks[c]
		var o := Vector2(c) * T
		var cc := Color(0, 0, 0, 0.35 + 0.35 * k)
		ci.draw_line(o + Vector2(8, 8), o + Vector2(3, 3), cc, 1.0)
		ci.draw_line(o + Vector2(8, 8), o + Vector2(13, 5), cc, 1.0)
		if k > 0.4:
			ci.draw_line(o + Vector2(8, 8), o + Vector2(5, 14), cc, 1.0)
			ci.draw_line(o + Vector2(8, 8), o + Vector2(14, 12), cc, 1.0)
		if k > 0.7:
			ci.draw_line(o + Vector2(3, 3), o + Vector2(1, 9), cc, 1.0)
			ci.draw_line(o + Vector2(13, 5), o + Vector2(15, 1), cc, 1.0)
	for aid in arrows:
		var a: Dictionary = arrows[aid]
		var v: Vector2 = a.v
		var dv := v.normalized() if v.length() > 1.0 else Vector2.RIGHT
		var ln := 14.0 if int(a.k) == 3 else 9.0
		var tail: Vector2 = a.p - dv * ln
		match int(a.k):
			1:
				ci.draw_circle(a.p, 3.0, Color(1.0, 0.55, 0.1, 0.5))
				ci.draw_line(tail, a.p, Color(1.0, 0.75, 0.3), 1.5)
			3:
				ci.draw_line(tail, a.p, Color(0.45, 0.32, 0.2), 2.5)
				ci.draw_line(a.p - dv * 3.0, a.p, Color(0.85, 0.88, 0.92), 3.0)
			_:
				ci.draw_line(tail, a.p, Color(0.85, 0.7, 0.45), 1.2)
				ci.draw_line(a.p - dv * 2.5, a.p, Color(0.9, 0.92, 0.95), 2.0)
				ci.draw_line(tail, tail + dv * 2.0 + dv.orthogonal() * 1.5, Color(0.95, 0.95, 0.95), 1.0)
	for fid in falling:
		var fb: Dictionary = falling[fid]
		_draw_block(ci, int(fb.b), Rect2(fb.p - Vector2(8, 8), Vector2(T, T)))
	for e in fx:
		match e.k:
			"slash":
				var dir: Vector2 = e.b - e.a
				var r := dir.length()
				var an := dir.angle()
				var prog: float = 1.0 - float(e.t) / 0.18
				var al: float = clampf(e.t / 0.18, 0.0, 1.0)
				ci.draw_arc(e.a, r * 0.85, an - 1.1, an - 1.1 + 2.2 * prog, 12, Color(1, 1, 1, 0.8 * al), 3.0)
				ci.draw_arc(e.a, r * 0.6, an - 1.0, an - 1.0 + 2.0 * prog, 10, Color(0.8, 0.9, 1.0, 0.45 * al), 2.0)
			"spin":
				ci.draw_arc(e.a, e.r * (1.0 - e.t), 0.0, TAU, 32, Color(1, 1, 1, e.t * 2.5), 3.0)
			"ring":
				var c: Color = e.c
				ci.draw_arc(e.a, e.r * (1.0 - e.t / 0.5), 0.0, TAU, 40, Color(c.r, c.g, c.b, e.t * 1.6), 2.0)
			"line":
				ci.draw_line(e.a, e.b, Color(1, 0.9, 0.4, 0.35), 5.0)
				ci.draw_line(e.a, e.b, e.c, 2.0)
			"circle":
				var bt = Net.tex("res://assets/boom.png")
				if bt:
					var fr := clampi(int((1.0 - e.t / 0.35) * 6.0), 0, 5)
					var sz: float = e.r * 2.6
					ci.draw_texture_rect_region(bt, Rect2(e.a - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), Rect2(fr * 64, 0, 64, 64))
				else:
					ci.draw_circle(e.a, e.r * (1.0 - e.t / 0.35 * 0.5), Color(1.0, 0.6, 0.1, clampf(e.t * 2.5, 0.0, 0.8)))
			"path":
				if e.pts.size() > 1:
					ci.draw_polyline(e.pts, Color(0.95, 0.9, 0.4, 0.8), 2.0)
			"deb":
				ci.draw_rect(Rect2(e.a, Vector2(2, 2)), Color(e.c.r, e.c.g, e.c.b, clampf(e.t * 3.0, 0.0, 1.0)))
			"num":
				var txt: String = "PARRY" if int(e.n) < 0 else str(e.n)
				var nc := Color(0.6, 0.85, 1.0) if int(e.n) < 0 else Color(1.0, 0.92, 0.5)
				nc.a = clampf(e.t * 2.0, 0.0, 1.0)
				ci.draw_string_outline(font, e.a - Vector2(20, 0), txt, HORIZONTAL_ALIGNMENT_CENTER, 40, 9, 3, Color(0, 0, 0, nc.a))
				ci.draw_string(font, e.a - Vector2(20, 0), txt, HORIZONTAL_ALIGNMENT_CENTER, 40, 9, nc)


func _draw_block(ci: CanvasItem, b: int, r: Rect2) -> void:
	if b == physics.WALL_FALL:
		if world.tex_wall:
			ci.draw_texture_rect_region(world.tex_wall, r, Rect2(0, 0, 16, 16), Color(0.85, 0.85, 0.9))
		else:
			ci.draw_rect(r, Color(0.42, 0.36, 0.34))
	elif b == world.DIRT and world.tex_dirt:
		ci.draw_texture_rect_region(world.tex_dirt, r, Rect2(15 * 64, 64, 16, 16))
	elif (b == world.STONE or b == world.ORE) and world.tex_stone:
		ci.draw_texture_rect_region(world.tex_stone, r, Rect2(15 * 64, 0, 16, 16))
		if b == world.ORE and world.tex_ore:
			ci.draw_texture_rect_region(world.tex_ore, r, Rect2(0, 0, 16, 16))
	elif b >= world.WATER:
		LookS.draw_block_shape(ci, b, r, Color(0.6, 0.6, 0.6), now(), true)
	elif world.atlas:
		ci.draw_texture_rect_region(world.atlas, r, Rect2(b * 16, 0, 16, 16))
	else:
		ci.draw_rect(r, world.COLORS.get(b, Color.WHITE))


# ------------------------------------------------------------ HUD і вікна
func _mk_label(size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color(0.05, 0.06, 0.12))
	l.add_theme_constant_override("outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _center(c: Control) -> void:
	c.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	c.grow_horizontal = Control.GROW_DIRECTION_BOTH
	c.grow_vertical = Control.GROW_DIRECTION_BOTH


func _build_hud() -> void:
	hud_layer = CanvasLayer.new()
	hud_layer.layer = 10
	add_child(hud_layer)
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
	hud_layer.add_child(hbar)
	hbar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud_msg = _mk_label(24)
	hud_help = _mk_label(12)
	hud_note = _mk_label(18)
	hud_store = _mk_label(13)
	hud_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hud_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for n in [hud_msg, hud_help, hud_note, hud_store]:
		hud_layer.add_child(n)
	craft_ui = CraftUIS.new()
	inv_ui = InvUIS.new()
	team_ui = TeamUIS.new()
	class_ui = ClassUIS.new()
	for wnd in [craft_ui, inv_ui, team_ui, class_ui]:
		wnd.game = self
		wnd.visible = false
		hud_layer.add_child(wnd)
		_center(wnd)
	team_ui.chosen.connect(func(_t): team_ui.visible = false; _show(class_ui))
	class_ui.chosen.connect(func(_c): class_ui.visible = false; _refresh_ui_flag())
	pause_panel = PanelContainer.new()
	pause_panel.visible = false
	var pv := VBoxContainer.new()
	pv.custom_minimum_size = Vector2(260, 0)
	pause_panel.add_child(pv)
	var items := [["Resume", _close_all], ["Change team (M)", func(): _show(team_ui)], ["Change class (B)", func(): _show(class_ui)], ["Settings", _open_settings], ["Leave match", func(): Net.leave("")]]
	for it in items:
		var b2 := Button.new()
		b2.text = it[0]
		b2.focus_mode = Control.FOCUS_NONE
		b2.pressed.connect(it[1])
		pv.add_child(b2)
	hud_layer.add_child(pause_panel)
	_center(pause_panel)


func _windows() -> Array:
	return [craft_ui, inv_ui, team_ui, class_ui, pause_panel]


func _show(wnd) -> void:
	for x in _windows():
		if x != wnd:
			x.visible = false
	wnd.visible = true
	if wnd.has_method("open"):
		wnd.open()
	# вікно стискається до свого вмісту і ставиться по центру (щоб не розтягувалось на весь екран)
	wnd.reset_size()
	_center(wnd)
	_refresh_ui_flag()


func _toggle(wnd) -> void:
	if wnd.visible:
		wnd.visible = false
		_refresh_ui_flag()
	else:
		_show(wnd)


func _close_all() -> void:
	for x in _windows():
		x.visible = false
	_refresh_ui_flag()


func _refresh_ui_flag() -> void:
	var any := settings_ui != null
	for x in _windows():
		if x.visible:
			any = true
	ui_open = any


func _open_settings() -> void:
	if settings_ui:
		return
	pause_panel.visible = false
	settings_ui = SettingsS.new()
	hud_layer.add_child(settings_ui)
	_center(settings_ui)
	settings_ui.closed.connect(func(): settings_ui.queue_free(); settings_ui = null; _refresh_ui_flag())
	_refresh_ui_flag()


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo) or settings_ui:
		return
	match event.physical_keycode:
		KEY_H:
			help_on = not help_on
		KEY_C:
			_toggle(craft_ui)
		KEY_TAB, KEY_I:
			_toggle(inv_ui)
			get_viewport().set_input_as_handled()
		KEY_B:
			_toggle(class_ui)
		KEY_M:
			_toggle(team_ui)
		KEY_ESCAPE:
			var any := false
			for x in _windows():
				any = any or x.visible
			if any:
				_close_all()
			else:
				_show(pause_panel)
			get_viewport().set_input_as_handled()


func _update_hud() -> void:
	var vs := get_viewport().get_visible_rect().size
	var me := multiplayer.get_unique_id()
	var d: Dictionary = cl.get(me, {"hp": 100, "inv": InvS.empty(), "dead": false})
	var p = player_node(me)
	var team: int = p.team if p else 0
	var extra := ""
	if multiplayer.is_server() and Net.external_ip != "":
		extra = "\nServer address: %s (port %d)" % [Net.external_ip, Net.PORT]
	if Net.steam_lobby != 0:
		extra += "\nSteam lobby: steam:%d" % Net.steam_lobby
	hud_help.visible = help_on or help_t > 0.0
	hud_help.text = HELP_TEXT + extra + "\n[H] hide / show help"
	hud_help.size = Vector2(420, 160)
	hud_help.position = Vector2(12, 92)
	var s_: Dictionary = store[team]
	hud_store.text = "Team storage: wood %d  stone %d  metal %d" % [s_.wood, s_.stone, s_.metal]
	hud_store.position = Vector2(14, vs.y - 128)
	hud_note.text = note if note_t > 0.0 else ""
	hud_note.size = Vector2(600, 30)
	hud_note.position = Vector2(vs.x * 0.5 - 300, vs.y * 0.6)
	if match_over:
		var txt := "%s team wins!  (new map in a few seconds)\n" % Net.TEAM_NAMES[winner]
		for r in end_rows:
			txt += "\n%s [%s]   K %d   D %d   Flags %d" % [r[0], Net.TEAM_NAMES[r[1]], r[2], r[3], r[4]]
		hud_msg.text = txt
	elif d.dead:
		hud_msg.text = "You died. Respawn in %d s   (B: change class)" % maxi(0, ceili(respawn_at - now()))
	else:
		hud_msg.text = ""
	hud_msg.size = Vector2(600, 40)
	hud_msg.position = Vector2(vs.x * 0.5 - 300, vs.y * 0.22)

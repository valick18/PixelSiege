extends Node
# BuildingManager: копання (блоки і задні стіни - лише киркою, дерева - лише сокирою, обидва є тільки в Будівельника),
# розміщення блоків, задніх стін і споруд, робочі столи та крафт, командне сховище, операції з інвентарем,
# двері / люки / скрині руїн, відновлення дерев і руди, лікування біля багаття. Працює на хості.

const InvS = preload("res://scripts/inventory.gd")
const T := 16
const MAX_SPAWNS := 3
const MAX_STORAGE := 2
const STATION_RANGE := 60.0
const WALL_HP := 3
const LOOT := [["metal", 4, 8], ["stone", 6, 12], ["wood", 8, 16], ["medkit", 1, 2], ["tnt", 1, 2], ["firebomb", 1, 2], ["lantern", 1, 1], ["food", 2, 4]]

var g
var regrow_trees := {}  # x -> час
var regrow_ore := {}    # cell -> час
var wall_hp := {}       # cell -> міцність задньої стіни
var t_regrow := 0.0
var t_heal := 0.0
var _hint_t := {}


func reset() -> void:
	regrow_trees.clear()
	regrow_ore.clear()
	wall_hp.clear()


func hint(id: int, text: String) -> void:
	var now: float = g.now()
	if now < float(_hint_t.get(id, 0.0)):
		return
	_hint_t[id] = now + 1.5
	g.note_to(id, text)


func _center(c: Vector2i) -> Vector2:
	return Vector2(c) * T + Vector2(8, 8)


func give(s, p, item: String, n: int) -> void:
	var left := InvS.add(s.inv, item, n)
	if left > 0:
		g.spawn_drop(p.position, item, left)


# ------------------------------------------------------------ копання / рубка
func dig(id: int, cell: Vector2i, tool: String) -> void:
	var a = g.actor(id)
	if a == null:
		return
	var s = a[0]
	var p = a[1]
	if not tool in Net.tools_of(Net.players[id].cls):
		hint(id, "Only the Builder can mine blocks and chop trees")
		return
	var td: Dictionary = Net.TOOLS.get(tool, {})
	var kind: String = td.get("kind", "")
	if kind != "dig" and kind != "chop":
		return
	var now: float = g.now()
	if now < s.dig:
		return
	s.dig = now + float(td.dig_cd) * 0.85
	if p.position.distance_to(_center(cell)) > Net.REACH + 8.0:
		return
	var w = g.world
	if w.fire.has(cell):
		w.fire.erase(cell)
		g.fire_sys.broadcast()
		return
	var b: int = w.get_cell(cell)
	if b == w.BASE:
		return
	# задня стіна: ламається киркою, якщо перед нею немає блока
	if b == w.AIR or b == w.WATER:
		if kind == "dig" and g.has_wall(cell):
			_dig_wall(id, s, p, cell, int(td.power))
		return
	var is_tree: bool = b in w.TREE_BLOCKS
	if kind == "chop" and not is_tree:
		hint(id, "The axe only chops trees. Use the pickaxe (1) for blocks and walls")
		return
	if kind == "dig" and is_tree:
		hint(id, "Use the axe (2) to chop trees")
		return
	if b == w.TNT:
		if not g.fuses.has(cell):
			g.fuses[cell] = 2.0
			g.c_sfx.rpc("fire")
		return
	if b == w.RUIN_CHEST:
		open_chest(id, cell)
		return
	var mx: int = w.max_hp(b)
	var hp: int = int(g.block_hp.get(cell, mx)) - int(td.power)
	g.c_sfx.rpc("chop" if is_tree else "dig")
	if hp > 0:
		g.block_hp[cell] = hp
		g.c_crack.rpc(cell, 1.0 - float(hp) / float(mx))
		return
	if is_tree:
		var tc: Array = w.tree_cells(cell)
		g.remove_cells(tc)
		give(s, p, "wood", tc.size() * 2)
		regrow_trees[cell.x] = now + randf_range(90.0, 150.0)
		g.push_state(id)
		return
	var drop: String = w.drop_of(b)
	g.remove_cells([cell])
	if b == w.ORE:
		regrow_ore[cell] = now + randf_range(180.0, 300.0)
	if drop != "":
		give(s, p, drop, 1)
	g.push_state(id)


func _dig_wall(id: int, s, p, cell: Vector2i, power: int) -> void:
	var hp: int = int(wall_hp.get(cell, WALL_HP)) - power
	g.c_sfx.rpc("dig")
	if hp > 0:
		wall_hp[cell] = hp
		g.c_crack.rpc(cell, 1.0 - float(hp) / float(WALL_HP))
		return
	wall_hp.erase(cell)
	g.c_crack.rpc(cell, 0.0)
	g.send_walls([[cell, 0]])
	give(s, p, "wall", 1)
	g.push_state(id)


# Шкода блоку від зброї / болтів (облога). Не дає ресурсів.
func damage_block(cell: Vector2i, power: int) -> void:
	var w = g.world
	var b: int = w.get_cell(cell)
	if b == w.AIR or b == w.BASE or b == w.WATER:
		return
	if b == w.TNT:
		if not g.fuses.has(cell):
			g.fuses[cell] = 1.0
		return
	var mx: int = w.max_hp(b)
	var hp: int = int(g.block_hp.get(cell, mx)) - power
	if hp > 0:
		g.block_hp[cell] = hp
		g.c_crack.rpc(cell, 1.0 - float(hp) / float(mx))
	else:
		g.remove_cells([cell])


# ------------------------------------------------------------ використання предмета (ЛКМ)
func use(id: int, cell: Vector2i, slot: int) -> void:
	var a = g.actor(id)
	if a == null:
		return
	var s = a[0]
	var p = a[1]
	var now: float = g.now()
	if now < float(s.use):
		return
	s.use = now + 0.1
	slot = clampi(slot, 0, InvS.HOTBAR - 1)
	var item: String = s.inv[slot].get("i", "")
	if item == "":
		return
	if item in Net.ARROWS:
		s["arrow"] = item
		g.note_to(id, "%s loaded: shoot with bow" % item.replace("_", " ").capitalize())
		return
	if item == "shop_kit" or item == "bomb" or item == "rope":
		return
	if item == "medkit" or item == "food":
		if int(s.hp) >= 100:
			hint(id, "Health is already full")
			return
		s.hp = mini(100, int(s.hp) + (40 if item == "medkit" else 20))
		InvS.consume(s.inv, slot)
		g.push_state(id)
		g.c_sfx.rpc("pickup")
		return
	var reach := 200.0 if item == "firebomb" else Net.REACH
	if p.position.distance_to(_center(cell)) > reach + 8.0:
		return
	if item == "firebomb":
		InvS.consume(s.inv, slot)
		g.fire_sys.ignite_area(cell, 1, true)
		g.push_state(id)
		return
	if item == "wall":
		_place_wall(id, s, cell, slot)
		return
	if Net.ITEM_BLOCK.has(item):
		_place(id, s, p, cell, slot, item)


# Задня стіна: ставиться в будь-яку клітинку без твердого блока, де ще немає стіни.
# Стіна без опори (не з'єднана через стіни / блоки з землею) одразу падає і повертається предметом.
func _place_wall(id: int, s, cell: Vector2i, slot: int) -> void:
	var w = g.world
	if cell.y < 0 or cell.x < 0 or cell.x >= w.w or cell.y >= w.h - 1:
		return
	if g.has_wall(cell) or w.is_solid(cell.x, cell.y):
		return
	InvS.consume(s.inv, slot)
	wall_hp.erase(cell)
	g.send_walls([[cell, 1]])
	g.push_state(id)


func _place(id: int, s, p, cell: Vector2i, slot: int, item: String) -> void:
	var w = g.world
	var cur: int = w.get_cell(cell)
	if cell.y < 0 or (cur != w.AIR and cur != w.WATER):
		return
	var b: int = Net.ITEM_BLOCK[item]
	var team: int = Net.players[id].team
	var cells := [cell]
	if b == w.DOOR:
		var up := cell + Vector2i(0, -1)
		var cu: int = w.get_cell(up)
		if cu != w.AIR and cu != w.WATER:
			hint(id, "A door needs 2 free cells (place it on the lower one)")
			return
		cells.append(up)
	if b in [w.STONE, w.WOOD, w.METAL, w.TNT, w.DOOR, w.HATCH, w.ARROW_TRAP]:
		for c in cells:
			var cc := _center(c)
			for q in g.players_root.get_children():
				if absf(q.position.x - cc.x) < 14.0 and absf(q.position.y - cc.y) < 22.0 and (b != w.DOOR or q.team != team):
					return
	var now: float = g.now()
	if item == "spawn":
		if g.count_structs("spawn", team) >= MAX_SPAWNS:
			hint(id, "Respawn point limit reached (%d)" % MAX_SPAWNS)
			return
		if _center(cell).distance_to(w.flag_pos(team)) < 25.0 * T:
			hint(id, "Build respawn points far from your base")
			return
	if item == "storage" and g.count_structs("storage", team) >= MAX_STORAGE:
		hint(id, "Storage limit reached (%d)" % MAX_STORAGE)
		return
	InvS.consume(s.inv, slot)
	var tm := -1
	if item in Net.STRUCT_ITEMS:
		tm = team
		var build := 8.0 if item == "catapult" else (5.0 if item == "ballista" else 0.0)
		g.structs[cell] = {"type": item, "team": team, "ready_at": now + build, "cd": 0.0}
	var list := []
	for c in cells:
		g.block_hp.erase(c)
		list.append([c, b, tm])
	g.send_edits(list)
	g.push_state(id)


# ------------------------------------------------------------ взаємодія (E)
func interact(id: int, dir: Vector2) -> void:
	var a = g.actor(id)
	if a == null:
		return
	var s = a[0]
	var p = a[1]
	var w = g.world
	var team: int = Net.players[id].team
	var now: float = g.now()
	var pc := Vector2i(floori(p.position.x / T), floori(p.position.y / T))
	var best := Vector2i(-1, -1)
	var best_d := 1e9
	for dx in range(-3, 4):
		for dy in range(-3, 4):
			var c := pc + Vector2i(dx, dy)
			var b: int = w.get_cell(c)
			var ok: bool = b == w.RUIN_CHEST or ((b == w.HATCH or b == w.HATCH_OPEN) and int(w.owner_team.get(c, -1)) == team)
			var d: float = p.position.distance_to(_center(c))
			if ok and d < 46.0 and d < best_d:
				best = c
				best_d = d
	if best_d < 1e8:
		var bb: int = w.get_cell(best)
		if bb == w.RUIN_CHEST:
			open_chest(id, best)
		else:
			g.send_edits([[best, w.HATCH_OPEN if bb == w.HATCH else w.HATCH, team]])
		return
	for c in g.structs:
		var sc = g.structs[c]
		if int(sc.team) != team or p.position.distance_to(_center(c)) > 48.0:
			continue
		if sc.type != "catapult" and sc.type != "ballista":
			continue
		if now < float(sc.ready_at):
			hint(id, "%s is still under construction" % String(sc.type).capitalize())
			return
		if now < float(sc.cd):
			hint(id, "%s is reloading" % String(sc.type).capitalize())
			return
		if sc.type == "catapult":
			if InvS.take(s.inv, "stone", 1) == 0:
				hint(id, "Catapult needs 1 stone as ammo")
				return
			sc.cd = now + 6.0
			g.push_state(id)
			g.fire_sys.fire_catapult(c, dir, id)
		else:
			if InvS.count(s.inv, "wood") < 2:
				hint(id, "Ballista needs 2 wood as ammo")
				return
			InvS.take(s.inv, "wood", 2)
			sc.cd = now + 4.0
			g.push_state(id)
			g.combat.fire_ballista(id, c, dir)
		return
	if near_store(id, p):
		store_op(id, true)
	else:
		hint(id, "Nothing to use here (E: workbench, catapult, ballista, hatch, chest, storage)")


func open_chest(id: int, cell: Vector2i) -> void:
	var a = g.actor(id)
	if a == null:
		return
	var got := PackedStringArray()
	var pool := LOOT.duplicate()
	pool.shuffle()
	for i in 3:
		var l: Array = pool[i]
		var n := randi_range(int(l[1]), int(l[2]))
		give(a[0], a[1], l[0], n)
		got.append("%d %s" % [n, l[0]])
	g.send_edits([[cell, g.world.AIR, -1]])
	g.push_state(id)
	g.c_sfx.rpc("pickup")
	g.note_to(id, "Ancient chest: " + ", ".join(got))


# ------------------------------------------------------------ сховище
func near_store(id: int, p) -> bool:
	var team: int = Net.players[id].team
	if p.position.distance_to(g.world.flag_pos(team)) < 110.0:
		return true
	for c in g.structs:
		if g.structs[c].type == "storage" and int(g.structs[c].team) == team and p.position.distance_to(_center(c)) < 80.0:
			return true
	return false


func store_op(id: int, dep: bool) -> void:
	var a = g.actor(id)
	if a == null:
		return
	var s = a[0]
	var p = a[1]
	if not near_store(id, p):
		hint(id, "Go to your base flag or a storage chest")
		return
	var team: int = Net.players[id].team
	if dep:
		for i in s.inv.size():
			var e: Dictionary = s.inv[i]
			if e.get("i", "") in Net.RESOURCES:
				g.store[team][e.i] = int(g.store[team][e.i]) + int(e.n)
				s.inv[i] = {}
	else:
		for r in Net.RESOURCES:
			var take := mini(int(g.store[team][r]), 20)
			var left := InvS.add(s.inv, r, take)
			g.store[team][r] = int(g.store[team][r]) - (take - left)
	g.push_store()
	g.push_state(id)
	g.c_sfx.rpc("pickup")


# ------------------------------------------------------------ крафт
func near_station(team: int, pos: Vector2, kind: String) -> bool:
	if kind == "hand":
		return true
	for c in g.structs:
		var sc = g.structs[c]
		if sc.type == kind and int(sc.team) == team and pos.distance_to(_center(c)) < STATION_RANGE:
			return true
	return false


func craft(id: int, rname: String, times: int) -> void:
	if not Net.RECIPES.has(rname):
		return
	var a = g.actor(id)
	if a == null:
		return
	var s = a[0]
	var p = a[1]
	var team: int = Net.players[id].team
	var rec: Dictionary = Net.RECIPES[rname]
	if not near_station(team, p.position, rec.station):
		hint(id, "Needs a %s nearby" % Net.STATIONS[rec.station])
		return
	var need_cls: String = rec.get("cls", "")
	if need_cls != "" and Net.players[id].cls != need_cls:
		hint(id, "Only %s can craft this" % Net.CLASSES[need_cls].label)
		return
	var need_shop: String = rec.get("shop", "")
	if need_shop != "" and not g._near_shop(p, team, need_shop):
		hint(id, "Go to your team's %s (press E next to it)" % Net.SHOPS[need_shop].label)
		return
	var near := near_store(id, p)
	var made := 0
	for k in clampi(times, 1, 10):
		var err := _craft_once(s, team, near, rec, rname)
		if err != "":
			if made == 0:
				hint(id, err)
			break
		made += 1
	if made > 0:
		g.push_state(id)
		g.push_store()
		g.c_sfx.rpc("craft")
		g.note_to(id, "Crafted %s x%d" % [rname.capitalize(), made * int(rec.n)])


func _craft_once(s, team: int, near: bool, rec: Dictionary, rname: String) -> String:
	for k in rec.cost:
		var have := InvS.count(s.inv, k)
		if near and k in Net.RESOURCES:
			have += int(g.store[team][k])
		if have < int(rec.cost[k]):
			return "Not enough %s" % k
	var test: Array = s.inv.duplicate(true)
	var out_item: String = rec.get("item", rname)
	if InvS.add(test, out_item, int(rec.n)) > 0:
		return "Inventory full"
	for k in rec.cost:
		var need: int = rec.cost[k]
		need -= InvS.take(s.inv, k, need)
		if need > 0:
			g.store[team][k] = int(g.store[team][k]) - need
	InvS.add(s.inv, out_item, int(rec.n))
	return ""


# ------------------------------------------------------------ інвентар
func swap(id: int, a_: int, b_: int) -> void:
	var s = g.st.get(id)
	if s == null or s.dead_until > 0.0:
		return
	InvS.swap(s.inv, a_, b_)
	g.push_state(id)


func drop(id: int, slot: int) -> void:
	var a = g.actor(id)
	if a == null or slot < 0 or slot >= a[0].inv.size():
		return
	var e: Dictionary = a[0].inv[slot]
	if e.is_empty():
		return
	g.spawn_drop(a[1].position + Vector2(a[1].face * 16.0, 0), e.i, int(e.n), id)
	a[0].inv[slot] = {}
	g.push_state(id)


func sort(id: int) -> void:
	var s = g.st.get(id)
	if s == null:
		return
	InvS.sort_backpack(s.inv)
	g.push_state(id)


# ------------------------------------------------------------ відновлення ресурсів і багаття
func _player_near(pos: Vector2, r: float) -> bool:
	for q in g.players_root.get_children():
		if q.position.distance_to(pos) < r:
			return true
	return false


func tick(dt: float) -> void:
	var now: float = g.now()
	var w = g.world
	t_heal += dt
	if t_heal >= 1.0:
		t_heal = 0.0
		for c in g.structs:
			var sc = g.structs[c]
			if sc.type != "campfire":
				continue
			for oid in g.st:
				if not Net.players.has(oid) or int(Net.players[oid].team) != int(sc.team) or g.st[oid].dead_until > 0.0 or int(g.st[oid].hp) >= 100:
					continue
				var q = g.player_node(oid)
				if q and q.position.distance_to(_center(c)) < 48.0:
					g.st[oid].hp = mini(100, int(g.st[oid].hp) + 3)
					g.push_state(oid)
	t_regrow += dt
	if t_regrow < 3.0:
		return
	t_regrow = 0.0
	for x in regrow_trees.keys():
		if now < float(regrow_trees[x]):
			continue
		regrow_trees.erase(x)
		var y := 0
		while y < w.h - 1 and not w.is_solid(x, y) and not w.is_water(x, y):
			y += 1
		if w.get_cell(Vector2i(x, y)) != w.DIRT:
			continue
		var th := randi_range(2, 4)
		var ok := true
		for k in range(1, th + 2):
			if w.get_cell(Vector2i(x, y - k)) != w.AIR:
				ok = false
		if not ok:
			continue
		if _player_near(Vector2(x * T + 8, (y - 2) * T), 28.0):
			regrow_trees[x] = now + 20.0
			continue
		var list := []
		for k in range(1, th + 1):
			list.append([Vector2i(x, y - k), w.TRUNK, -1])
		g.c_tree.rpc(x, y - th, randi() % 4)
		g.send_edits(list)
	for c in regrow_ore.keys():
		if now < float(regrow_ore[c]):
			continue
		regrow_ore.erase(c)
		if w.get_cell(c) == w.AIR and not _player_near(_center(c), 48.0):
			g.send_edits([[c, w.ORE, -1]])


# PixelSiege patch v1 (bombs, TNT, shops, crafting, rope)

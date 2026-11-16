extends Node
# WorldPhysics (хост авторитетний):
#  1) Текуча вода - клітинковий автомат з обмеженим об'ємом: вода падає вниз, тече вбік до ближнього схилу,
#     під тиском (вода зверху) заповнює бокові порожнини. Обробляються лише "активні" клітинки біля змін.
#  2) Обвал блоків - після кожної зміни перевіряється, чи сусідні блоки ще з'єднані з опорою.
#     Задні стіни входять у ту саму конструкцію: стіна тримає блоки перед собою і сусідні стіни,
#     але сама теж має триматися (через інші стіни / блоки) за корінну породу (BASE / край карти).
#     Конструкція (блоки + стіни), яка ні на чому не тримається, падає повністю: блоки і стіни.
#     Стіна, що впала, стає предметом "wall". Падаючий блок завдає шкоди і стає на землю.
#     Якщо блок падав з великої висоти (BREAK_HEIGHT), він розбивається, а частина ресурсу випадає предметом.

const T := 16
const SUPPORT_LIMIT := 400   # група більша за це вважається масивом землі (не падає)
const WATER_TICK := 0.12
const WATER_BUDGET := 140
const FALL_G := 900.0
const BREAK_HEIGHT := 5.0 * 16.0  # падіння з 5+ блоків: блок розбивається
const BREAK_DROP_CHANCE := 0.5    # шанс, що з розбитого блока випаде ресурс
const DIRS := [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]
const NEAR := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(1, -1), Vector2i(-1, -1)]
const EXTRA := [6, 9, 17, 18, 25]  # стовбур, драбина, платформа, двері, відкритий люк - теж тримаються / падають
const WALL_FALL := 99  # id падаючої задньої стіни (лише для анімації падіння)

var g
var water_active := {}
var t_water := 0.0
var fall_id := 1


func reset() -> void:
	water_active.clear()


func _structural(b: int) -> bool:
	return g.world._solid[b] == 1 or b in EXTRA


# Клітинка є частиною конструкції: несучий блок або задня стіна.
func _node(c: Vector2i) -> bool:
	var b: int = g.world.get_cell(c)
	if b == g.world.BASE:
		return false
	return _structural(b) or g.has_wall(c)


func _center(c: Vector2i) -> Vector2:
	return Vector2(c) * T + Vector2(8, 8)


# Викликається з game.send_edits() після будь-якої зміни клітинок.
func after_edits(list: Array, olds: Array) -> void:
	var w = g.world
	var checked := {}
	for i in list.size():
		var c: Vector2i = list[i][0]
		var nb: int = list[i][1]
		var ob: int = olds[i]
		for d in NEAR:
			if w.get_cell(c + d) == w.WATER:
				water_active[c + d] = true
		if nb == w.WATER:
			water_active[c] = true
		var was_s := _structural(ob)
		var is_s := _structural(nb)
		if was_s and not is_s:
			for d in DIRS:
				var n: Vector2i = c + d
				if _node(n) and not checked.has(n):
					_check(n, checked)
		elif is_s and not was_s and nb != w.BASE and not checked.has(c):
			_check(c, checked)


# Викликається з game.send_walls(): прибрана задня стіна могла бути єдиною опорою.
# Нова стіна теж перевіряється: стіна в повітрі без опори одразу падає.
func after_walls(list: Array) -> void:
	var checked := {}
	for e in list:
		var c: Vector2i = e[0]
		for n in [c, c + Vector2i(0, 1), c + Vector2i(0, -1), c + Vector2i(1, 0), c + Vector2i(-1, 0)]:
			if _node(n) and not checked.has(n):
				_check(n, checked)


func _check(start: Vector2i, checked: Dictionary) -> void:
	var w = g.world
	var comp: Array = []
	var seen := {start: true}
	var stack: Array = [start]
	var grounded := false
	while not stack.is_empty() and not grounded:
		var c: Vector2i = stack.pop_back()
		comp.append(c)
		if comp.size() > SUPPORT_LIMIT:
			grounded = true
			break
		for d in DIRS:
			var n: Vector2i = c + d
			if seen.has(n):
				continue
			if w.get_cell(n) == w.BASE:
				grounded = true
				break
			if _node(n):
				seen[n] = true
				stack.append(n)
	for c in seen:
		checked[c] = true
	if not grounded:
		_collapse(comp)


func _collapse(comp: Array) -> void:
	var w = g.world
	var inset := {}
	for c in comp:
		inset[c] = true
	var remove: Array = []
	var walls: Array = []
	for c in comp:
		var cb: int = w.get_cell(c)
		if _structural(cb):
			remove.append(c)
		elif cb != w.AIR and cb != w.WATER:
			# факел, шипи тощо, що висіли на стіні
			var di: String = w.drop_of(cb)
			if di != "":
				g.spawn_drop(_center(c), di, 1)
			remove.append(c)
		if g.has_wall(c):
			walls.append(c)
	# декор і споруди, що стояли на блоках, які падають, стають предметами
	for c in comp:
		if not _structural(w.get_cell(c)):
			continue
		var up: Vector2i = c + Vector2i(0, -1)
		while not inset.has(up):
			var ub: int = w.get_cell(up)
			if ub == w.AIR or ub == w.WATER or ub == w.BASE or _structural(ub):
				break
			var it: String = w.drop_of(ub)
			if it != "":
				g.spawn_drop(_center(up), it, 1)
			remove.append(up)
			inset[up] = true
			up += Vector2i(0, -1)
	for c in comp:
		var fb: int = w.get_cell(c)
		if _structural(fb):
			g.c_fall.rpc(fall_id, _center(c), fb)
			fall_id += 1
	for c in walls:
		g.c_fall.rpc(fall_id, _center(c) + Vector2(0, 0.5), WALL_FALL)
		fall_id += 1
	if not walls.is_empty():
		var wl := []
		for c in walls:
			wl.append([c, 0])
		g.c_walls.rpc(wl)
	g.remove_cells(remove)
	g.c_sfx.rpc("dig")


# Падіння блоків симулюється на всіх пірах (для плавності), приземлення і шкоду вирішує хост.
func sim_falling(dt: float) -> void:
	var srv: bool = g.multiplayer.is_server()
	var w = g.world
	for fid in g.falling.keys():
		if not g.falling.has(fid):
			continue
		var f: Dictionary = g.falling[fid]
		var vy := minf(float(f.vy) + FALL_G * dt, 600.0)
		f.vy = vy
		var p: Vector2 = f.p
		p.y += vy * dt
		f.p = p
		if p.y > w.h * T + 32.0:
			g.falling.erase(fid)
			continue
		if not srv:
			continue
		_hit_players(f, p, vy)
		var cx := floori(p.x / T)
		var below := floori((p.y + 8.0) / T)
		if w.is_solid(cx, below) or w.is_platform(cx, below):
			_land(fid, int(f.b), Vector2i(cx, below - 1), p.y - float(f.get("y0", p.y)))


func _hit_players(f: Dictionary, p: Vector2, vy: float) -> void:
	if vy < 80.0 or int(f.b) == WALL_FALL:
		return
	var heavy: bool = int(f.b) in [2, 4, 5, 26, 27]
	for oid in g.st:
		if g.st[oid].dead_until > 0.0 or f.hit.has(oid):
			continue
		var q = g.player_node(oid)
		if q and absf(q.position.x - p.x) < 14.0 and absf(q.position.y - p.y) < 22.0:
			f.hit[oid] = true
			var dmg := int((14.0 + vy * 0.05) * (1.5 if heavy else 1.0))
			g.combat.damage(oid, dmg, Vector2(signf(q.position.x - p.x + 0.01) * 120.0, 60.0), 0, false)


func _land(fid: int, b: int, cell: Vector2i, fall_dist: float) -> void:
	var w = g.world
	g.c_fall_end.rpc(fid)
	var cc := _center(cell)
	if b == WALL_FALL:
		if fall_dist >= BREAK_HEIGHT:
			g.c_shatter.rpc(cc, w.STONE)
			if randf() < BREAK_DROP_CHANCE:
				g.spawn_drop(cc, "wall", 1)
		else:
			g.spawn_drop(cc, "wall", 1)
		g.c_sfx.rpc("dig")
		return
	# падіння з великої висоти: блок розбивається повністю, частина ресурсу випадає на землю
	if fall_dist >= BREAK_HEIGHT:
		g.c_shatter.rpc(cc, b)
		var res: String = w.drop_of(b)
		if res != "" and randf() < BREAK_DROP_CHANCE:
			g.spawn_drop(cc, res, 1)
		g.c_sfx.rpc("dig")
		return
	var cur: int = w.get_cell(cell)
	var blocked := false
	for q in g.players_root.get_children():
		if absf(q.position.x - cc.x) < 14.0 and absf(q.position.y - cc.y) < 22.0:
			blocked = true
	if w._solid[b] == 1 and (cur == w.AIR or cur == w.WATER) and not blocked:
		g.send_edits([[cell, b, -1]])
	else:
		var it: String = w.drop_of(b)
		if it != "":
			g.spawn_drop(cc, it, 1)
	g.c_sfx.rpc("place")


# ------------------------------------------------------------ вода
func tick(dt: float) -> void:
	t_water += dt
	if t_water < WATER_TICK or water_active.is_empty():
		return
	t_water = 0.0
	var w = g.world
	var keys: Array = water_active.keys()
	water_active = {}
	keys.sort_custom(func(a, b): return a.y > b.y)
	var moves := []
	var next := {}
	var budget := WATER_BUDGET
	for c in keys:
		if budget <= 0:
			next[c] = true
			continue
		if w.get_cell(c) != w.WATER:
			continue
		var tgt := _flow_target(c)
		if tgt == c:
			continue
		budget -= 1
		w.set_cell(c, w.AIR)
		w.set_cell(tgt, w.WATER)
		moves.append([c, w.AIR, -1])
		moves.append([tgt, w.WATER, -1])
		next[tgt] = true
		for d in NEAR:
			if w.get_cell(c + d) == w.WATER:
				next[c + d] = true
	for c in next:
		water_active[c] = true
	if not moves.is_empty():
		g.send_edits(moves)


func _flow_target(c: Vector2i) -> Vector2i:
	var w = g.world
	var down := c + Vector2i(0, 1)
	if w.get_cell(down) == w.AIR:
		return down
	var dirs := [-1, 1] if randf() < 0.5 else [1, -1]
	var pressured: bool = w.get_cell(c + Vector2i(0, -1)) == w.WATER
	for dx in dirs:
		var side := c + Vector2i(dx, 0)
		if w.get_cell(side) != w.AIR:
			continue
		if w.get_cell(side + Vector2i(0, 1)) == w.AIR or pressured:
			return side
	for dx in dirs:
		if _drop_ahead(c, dx, 6):
			return c + Vector2i(dx, 0)
	return c


func _drop_ahead(c: Vector2i, dx: int, n: int) -> bool:
	var w = g.world
	for i in range(1, n + 1):
		var x := c + Vector2i(dx * i, 0)
		if w.get_cell(x) != w.AIR:
			return false
		var under: int = w.get_cell(x + Vector2i(0, 1))
		if under == w.AIR:
			return true
		if under != w.WATER and w._solid[under] == 0:
			return false
	return false

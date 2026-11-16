extends Node
# FireExplosionSystem: розповсюдження вогню (вода його зупиняє, дощ гасить), вибухи TNT та катапульти,
# ланцюгові детонації, блискавки під час грози. Працює лише на хості.

const T := 16
var g
var t_fire := 0.0
var light_t := 8.0


func broadcast() -> void:
	g.c_fire.rpc(g.world.fire.keys())


func _near_water(c: Vector2i) -> bool:
	var w = g.world
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if w.get_cell(c + d) == w.WATER:
			return true
	return false


func ignite_area(cell: Vector2i, r: int, sound: bool = true) -> void:
	var w = g.world
	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			var c := cell + Vector2i(dx, dy)
			var b: int = w.get_cell(c)
			if not w.FLAMMABLE.has(b) or _near_water(c):
				continue
			if b == w.TNT:
				g.fuses[c] = 0.6
			else:
				w.fire[c] = randf_range(4.0, 8.0)
	broadcast()
	if sound:
		g.c_sfx.rpc("fire")


func exposed(c: Vector2i) -> bool:
	for yy in range(c.y - 1, -1, -1):
		if g.world.is_solid(c.x, yy):
			return false
	return true


func explode(pos: Vector2, radius: float, power: float, src: int) -> void:
	var w = g.world
	var cr := int(radius / T) + 1
	var center := Vector2i(floori(pos.x / T), floori(pos.y / T))
	var removed := []
	for dx in range(-cr, cr + 1):
		for dy in range(-cr, cr + 1):
			var c := center + Vector2i(dx, dy)
			var b: int = w.get_cell(c)
			if b == w.AIR or b == w.BASE or b == w.WATER or c.y < 0:
				continue
			var d := pos.distance_to(Vector2(c) * T + Vector2(8, 8))
			if d > radius:
				continue
			var hp: float = float(g.block_hp.get(c, w.max_hp(b))) - power * (1.0 - d / radius)
			if hp <= 0.0:
				if b == w.TNT:
					if not g.fuses.has(c):
						g.fuses[c] = 0.15
					continue
				removed.append(c)
			else:
				g.block_hp[c] = int(ceil(hp))
				if w.FLAMMABLE.has(b) and b != w.TNT and randf() < 0.3:
					w.fire[c] = randf_range(4.0, 8.0)
	g.remove_cells(removed)
	for oid in g.st:
		var q = g.player_node(oid)
		if q == null or g.st[oid].dead_until > 0.0:
			continue
		var dist: float = q.position.distance_to(pos)
		if dist < radius * 1.3:
			var k := 1.0 - dist / (radius * 1.3)
			g.combat.damage(oid, int(power * 8.0 * k), (q.position - pos).normalized() * 380.0 * k + Vector2(0, -220.0 * k), src, false)
	g.c_boom.rpc(pos, radius)
	broadcast()


func fire_catapult(cell: Vector2i, dir: Vector2, id: int) -> void:
	var w = g.world
	if dir == Vector2.ZERO:
		dir = Vector2(1, -1)
	var pos := Vector2(cell) * T + Vector2(8, -4)
	var v := dir.normalized() * 420.0
	var pts := PackedVector2Array([pos])
	var team: int = Net.players[id].team
	for i in 220:
		v.y += 500.0 * 0.02
		v.x += g.wind * 60.0 * 0.02
		pos += v * 0.02
		if i % 4 == 0:
			pts.append(pos)
		if pos.x < 0.0 or pos.x > w.w * T or pos.y > w.h * T:
			break
		if w.blocks_for(floori(pos.x / T), floori(pos.y / T), team):
			break
		var caught := false
		for oid in g.st:
			if Net.players.has(oid) and int(Net.players[oid].team) != team and g.st[oid].dead_until <= 0.0:
				var q = g.player_node(oid)
				if q and q.position.distance_to(pos) < 14.0:
					caught = true
		if caught:
			break
	pts.append(pos)
	g.c_path.rpc(pts)
	explode(pos, 52.0, 9.0, id)


func _fire_tick() -> void:
	var w = g.world
	if w.fire.is_empty():
		return
	var raining: bool = g.weather == "rain" or g.weather == "storm"
	var kill := []
	var add := {}
	for c in w.fire.keys():
		if (raining and randf() < 0.35 and exposed(c)) or _near_water(c):
			w.fire.erase(c)
			continue
		w.fire[c] = float(w.fire[c]) - 0.5
		var b: int = w.get_cell(c)
		if b == w.AIR:
			w.fire.erase(c)
			continue
		if b == w.TNT:
			g.fuses[c] = 0.5
			w.fire.erase(c)
			continue
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if w.FLAMMABLE.has(w.get_cell(n)) and not w.fire.has(n) and not add.has(n) and not _near_water(n) and randf() < 0.2:
				add[n] = randf_range(4.0, 8.0)
		if float(w.fire[c]) <= 0.0:
			kill.append(c)
	for n in add:
		w.fire[n] = add[n]
	g.remove_cells(kill)
	for oid in g.st:
		var q = g.player_node(oid)
		if q and g.st[oid].dead_until <= 0.0 and w.fire.has(Vector2i(floori(q.position.x / T), floori(q.position.y / T))):
			g.combat.damage(oid, 6, Vector2(0, -60), 0, false)
	broadcast()


func _lightning() -> void:
	var w = g.world
	var x: int = randi() % w.w
	var y := 0
	while y < w.h - 1 and w.get_cell(Vector2i(x, y)) == w.AIR:
		y += 1
	var c := Vector2i(x, y)
	if w.FLAMMABLE.has(w.get_cell(c)):
		w.fire[c] = randf_range(5.0, 9.0)
		broadcast()
	g.c_flash.rpc()


func tick(dt: float) -> void:
	for c in g.fuses.keys():
		g.fuses[c] = float(g.fuses[c]) - dt
		if float(g.fuses[c]) <= 0.0:
			g.fuses.erase(c)
			g.remove_cells([c])
			explode(Vector2(c) * T + Vector2(8, 8), 64.0, 14.0, 0)
	t_fire += dt
	if t_fire >= 0.5:
		t_fire = 0.0
		_fire_tick()
	if g.weather == "storm":
		light_t -= dt
		if light_t <= 0.0:
			light_t = randf_range(6.0, 12.0)
			_lightning()

extends Node
# CombatManager: удари по дузі (меч, спис, кинджал, булава...), комбо з 3 ударів, лук з натягом і фізичні стріли,
# здібності класів (Q / R / F), бафи, шипи, настінні пастки, балісти, шкода і смерть.
# Всі рішення приймає хост; стріли симулюються на всіх пірах однаково (для плавності), але влучання рахує лише хост.

const InvS = preload("res://scripts/inventory.gd")
const T := 16
const ARROW_G := 420.0

var g  # game.gd
var t_spk := 0.0


func has_buff(oid: int, n: String) -> bool:
	return g.st.has(oid) and float(g.st[oid].buffs.get(n, 0.0)) > g.now()


func add_buff(oid: int, n: String, dur: float) -> void:
	if not g.st.has(oid):
		return
	g.st[oid].buffs[n] = g.now() + dur
	g.c_buff.rpc(oid, n, dur)


func dmg_mult(src: int) -> float:
	return 1.5 if has_buff(src, "rage") else 1.0


func _team(id: int) -> int:
	return int(Net.players[id].team) if Net.players.has(id) else -1


func _enemies_of(id: int) -> Array:
	var out: Array = []
	var my := _team(id)
	for oid in g.st:
		if oid == id or not Net.players.has(oid) or int(Net.players[oid].team) == my or g.st[oid].dead_until > 0.0:
			continue
		var q = g.player_node(oid)
		if q:
			out.append([oid, q])
	return out


# ------------------------------------------------------------ ближній бій
func swing(id: int, dir: Vector2, tool: String) -> void:
	var a = g.actor(id)
	if a == null or g.match_over or dir == Vector2.ZERO:
		return
	var s = a[0]
	var p = a[1]
	if not tool in Net.tools_of(Net.players[id].cls) or not Net.TOOLS.has(tool):
		return
	var td: Dictionary = Net.TOOLS[tool]
	if td.kind == "bow":
		return
	var now: float = g.now()
	if now < s.atk or s.block:
		return
	s.atk = now + float(td.cd) * 0.85
	s.combo = (int(s.combo) + 1) % 3 if now - float(s.last_swing) < 0.9 else 0
	s.last_swing = now
	var mult := 1.5 if int(s.combo) == 2 else 1.0
	dir = dir.normalized()
	var rng := float(td.range)
	var origin: Vector2 = p.position + Vector2(0, -2)
	g.c_anim.rpc(id, 0)
	g.c_fx.rpc(origin, origin + dir * rng, 0)
	var my := _team(id)
	var hit := false
	if g.prep_left <= 0.0:
		var half_arc := deg_to_rad(float(td.arc) * 0.5)
		for e in _enemies_of(id):
			var q = e[1]
			var rel: Vector2 = q.position - origin
			var dist := rel.length()
			if dist > rng + 12.0:
				continue
			if dist > 14.0 and absf(rel.angle_to(dir)) > half_arc:
				continue
			if g.world.ray_blocked(origin, q.position, my):
				continue
			var dmg := int(float(td.dmg) * mult * dmg_mult(id))
			damage(e[0], dmg, dir * float(td.kb) * mult + Vector2(0, -110), id, true)
			hit = true
	# удар по ворожих спорудах / ремонт молотком власних
	var tc := Vector2i(floori((origin.x + dir.x * 22.0) / T), floori((origin.y + dir.y * 22.0) / T))
	var owner = g.world.owner_team.get(tc)
	if owner != null:
		if int(owner) != my:
			g.building.damage_block(tc, 3 if tool == "hammer" else 2)
		elif tool == "hammer" and g.block_hp.has(tc):
			g.block_hp.erase(tc)
			g.c_crack.rpc(tc, 0.0)
			g.c_fx.rpc(Vector2(tc) * T + Vector2(8, 8), Vector2(tc) * T + Vector2(20, 8), 4)
	if hit:
		g.c_sfx.rpc("hit")


# ------------------------------------------------------------ лук і стріли
func shoot(id: int, dir: Vector2, charge: float) -> void:
	var a = g.actor(id)
	if a == null or g.match_over or dir == Vector2.ZERO:
		return
	var s = a[0]
	var p = a[1]
	if not "bow" in Net.tools_of(Net.players[id].cls):
		return
	var now: float = g.now()
	if now < s.atk:
		return
	var td: Dictionary = Net.TOOLS.bow
	s.atk = now + float(td.cd) * 0.85
	var k := clampf(charge, 0.15, 1.0)
	dir = dir.normalized()
	var spd := lerpf(float(td.speed), float(td.speed_max), k)
	var dmg := int(lerpf(float(td.dmg), float(td.dmg_max), k * k))
	spawn_arrow(_bow_origin(p, dir), dir * spd, 0, _team(id), id, dmg)
	g.c_anim.rpc(id, 0)


func _bow_origin(p, dir: Vector2) -> Vector2:
	return p.position + Vector2(0, -1 + (5 if p.crouch else 0)) + dir * 10.0


# kind: 0 стріла, 1 вогняна стріла, 2 стріла пастки, 3 болт балісти
func spawn_arrow(pos: Vector2, v: Vector2, kind: int, team: int, src: int, dmg: int, grav: float = ARROW_G) -> void:
	var aid: int = g.arrow_id
	g.arrow_id += 1
	g.arrow_meta[aid] = {"src": src, "dmg": dmg}
	g.c_arrow.rpc(aid, pos, v, kind, team, grav)


func sim(dt: float) -> void:
	var srv: bool = g.multiplayer.is_server()
	var w = g.world
	for aid in g.arrows.keys():
		var a: Dictionary = g.arrows[aid]
		if float(a.stuck) > 0.0:
			a.stuck = float(a.stuck) - dt
			if float(a.stuck) <= 0.0:
				g.arrows.erase(aid)
			continue
		a.life = float(a.life) - dt
		if float(a.life) <= 0.0:
			g.arrows.erase(aid)
			g.arrow_meta.erase(aid)
			continue
		var v: Vector2 = a.v
		v.y += float(a.g) * dt
		if int(a.k) <= 1:
			v.x += g.wind * 20.0 * dt
		a.v = v
		var from: Vector2 = a.p
		var to := from + v * dt
		var steps := int(from.distance_to(to) / 4.0) + 1
		var done := false
		for i in range(1, steps + 1):
			var pt := from.lerp(to, float(i) / steps)
			if pt.y > w.h * T or pt.x < 0.0 or pt.x > w.w * T:
				g.arrows.erase(aid)
				g.arrow_meta.erase(aid)
				done = true
				break
			if srv:
				var victim := _arrow_victim(pt, int(a.team))
				if victim != 0:
					_arrow_hit_player(aid, a, victim, pt)
					done = true
					break
			var cell := Vector2i(floori(pt.x / T), floori(pt.y / T))
			if w.blocks_for(cell.x, cell.y, int(a.team)):
				a.p = pt
				a.stuck = 3.0
				if srv:
					_arrow_hit_block(aid, a, cell, pt)
				done = true
				break
		if not done:
			a.p = to


func _arrow_victim(pt: Vector2, team: int) -> int:
	for oid in g.st:
		if not Net.players.has(oid) or int(Net.players[oid].team) == team or g.st[oid].dead_until > 0.0:
			continue
		var q = g.player_node(oid)
		if q and absf(pt.x - q.position.x) < 7.0 and absf(pt.y - q.position.y) < 15.0:
			return oid
	return 0


func _arrow_hit_player(aid: int, a: Dictionary, oid: int, pt: Vector2) -> void:
	var meta: Dictionary = g.arrow_meta.get(aid, {"src": 0, "dmg": 10})
	var src: int = meta.src
	var v: Vector2 = a.v
	var kb := v.normalized() * (320.0 if int(a.k) == 3 else 170.0) + Vector2(0, -60)
	damage(oid, int(float(meta.dmg) * dmg_mult(src)), kb, src, true, false)
	if int(a.k) == 1:
		g.fire_sys.ignite_area(Vector2i(floori(pt.x / T), floori(pt.y / T)), 1, false)
	g.arrow_meta.erase(aid)
	g.c_arrow_end.rpc(aid, pt, false)


func _arrow_hit_block(aid: int, a: Dictionary, cell: Vector2i, pt: Vector2) -> void:
	var meta: Dictionary = g.arrow_meta.get(aid, {"src": 0, "dmg": 10})
	match int(a.k):
		1: g.fire_sys.ignite_area(cell, 1, true)
		3: g.building.damage_block(cell, 4)
	g.arrow_meta.erase(aid)
	g.c_arrow_end.rpc(aid, pt, true)


func fire_ballista(id: int, cell: Vector2i, dir: Vector2) -> void:
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	dir = dir.normalized()
	var pos := Vector2(cell) * T + Vector2(8, 6) + dir * 12.0
	spawn_arrow(pos, dir * 760.0, 3, _team(id), id, 45, 90.0)
	g.c_sfx.rpc("bow")


# ------------------------------------------------------------ здібності Q / R / F
func ability(id: int, idx: int, dir: Vector2) -> void:
	var a = g.actor(id)
	if a == null or g.match_over:
		return
	var s = a[0]
	var p = a[1]
	idx = clampi(idx, 0, 2)
	var now: float = g.now()
	var key := "ab%d" % idx
	if now < float(s.get(key, 0.0)):
		return
	var cname: String = Net.players[id].cls
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	dir = dir.normalized()
	var sgn := 1.0 if dir.x >= 0.0 else -1.0
	var team := _team(id)
	var ok := true
	match "%s%d" % [cname, idx]:
		"warrior0":
			g.c_knock.rpc(id, Vector2(sgn * 380.0, -60.0))
			_area_hits(id, p.position + Vector2(sgn * 40.0, 0), 44.0, 15, Vector2(sgn * 260.0, -140.0), false)
		"warrior1":
			_area_hits(id, p.position, 48.0, 18, Vector2(240.0, -120.0), true)
			g.c_fx.rpc(p.position, p.position + Vector2(48, 0), 2)
		"warrior2":
			_team_buff(id, p.position, 110.0, "rage", 6.0)
			g.c_fx.rpc(p.position, p.position + Vector2(110, 0), 3)
		"archer0":
			g.c_knock.rpc(id, Vector2(-sgn * 220.0, -280.0))
		"archer1":
			for i in 5:
				var d := Vector2.from_angle(dir.angle() + (i - 2) * 0.09)
				spawn_arrow(_bow_origin(p, d), d * 520.0, 0, team, id, 10)
			g.c_sfx.rpc("bow")
		"archer2":
			spawn_arrow(_bow_origin(p, dir), dir * 620.0, 1, team, id, 18)
			g.c_sfx.rpc("fire")
		"engineer0":
			ok = _bridge(id, s, p, int(sgn))
		"engineer1":
			ok = _wall(id, s, p, int(sgn))
		"engineer2":
			var n := 0
			for c in g.block_hp.keys():
				var ow = g.world.owner_team.get(c)
				if (ow == null or int(ow) == team) and p.position.distance_to(Vector2(c) * T + Vector2(8, 8)) < 96.0:
					g.block_hp.erase(c)
					g.c_crack.rpc(c, 0.0)
					n += 1
			g.c_fx.rpc(p.position, p.position + Vector2(96, 0), 4)
			g.note_to(id, "Repaired %d blocks" % n)
		"support0":
			for oid in g.st:
				if _team(oid) != team or g.st[oid].dead_until > 0.0:
					continue
				var q = g.player_node(oid)
				if q and q.position.distance_to(p.position) < 90.0:
					g.st[oid].hp = mini(100, int(g.st[oid].hp) + 30)
					g.push_state(oid)
			g.c_fx.rpc(p.position, p.position + Vector2(90, 0), 4)
		"support1":
			_team_buff(id, p.position, 110.0, "haste", 5.0)
			g.c_fx.rpc(p.position, p.position + Vector2(110, 0), 3)
		"support2":
			_team_buff(id, p.position, 110.0, "barrier", 5.0)
			g.c_fx.rpc(p.position, p.position + Vector2(110, 0), 3)
		_:
			ok = false
	if ok:
		s[key] = now + float(Net.CLASSES[cname].abilities[idx].cd)


func _area_hits(id: int, center: Vector2, radius: float, dmg: int, kb: Vector2, outward: bool) -> void:
	if g.prep_left > 0.0:
		return
	var my := _team(id)
	for e in _enemies_of(id):
		var q = e[1]
		if q.position.distance_to(center) > radius or g.world.ray_blocked(center, q.position, my):
			continue
		var k := kb
		if outward:
			k = Vector2(signf(q.position.x - center.x) * kb.x, kb.y)
		damage(e[0], int(dmg * dmg_mult(id)), k, id, true)


func _team_buff(id: int, pos: Vector2, r: float, n: String, dur: float) -> void:
	var my := _team(id)
	for oid in g.st:
		if _team(oid) != my or g.st[oid].dead_until > 0.0:
			continue
		var q = g.player_node(oid)
		if q and q.position.distance_to(pos) < r:
			add_buff(oid, n, dur)


func _bridge(id: int, s, p, sgn: int) -> bool:
	var w = g.world
	var row := floori((p.position.y + 14.5) / T)
	var list := []
	for i in range(1, 6):
		if InvS.count(s.inv, "wood") - list.size() < 1:
			break
		var c := Vector2i(floori(p.position.x / T) + sgn * i, row)
		var b: int = w.get_cell(c)
		if b == w.AIR or b == w.WATER:
			list.append([c, w.WOOD, -1])
	if list.is_empty():
		g.note_to(id, "Bridge needs wood and free space")
		return false
	InvS.take(s.inv, "wood", list.size())
	g.send_edits(list)
	g.push_state(id)
	return true


func _wall(id: int, s, p, sgn: int) -> bool:
	var w = g.world
	var col := floori(p.position.x / T) + sgn * 2
	var feet := floori((p.position.y + 13.0) / T)
	var list := []
	for k in 3:
		if InvS.count(s.inv, "stone") - list.size() < 1:
			break
		var c := Vector2i(col, feet - k)
		var b: int = w.get_cell(c)
		if b != w.AIR and b != w.WATER:
			continue
		var cc := Vector2(c) * T + Vector2(8, 8)
		var blocked := false
		for q in g.players_root.get_children():
			if absf(q.position.x - cc.x) < 14.0 and absf(q.position.y - cc.y) < 22.0:
				blocked = true
		if not blocked:
			list.append([c, w.STONE, -1])
	if list.is_empty():
		g.note_to(id, "Stone Wall needs stone and free space")
		return false
	InvS.take(s.inv, "stone", list.size())
	g.send_edits(list)
	g.push_state(id)
	return true


# ------------------------------------------------------------ шкода / смерть
func damage(oid: int, amount: int, kb: Vector2, src: int, blockable: bool, parry: bool = true) -> void:
	if g.prep_left > 0.0 or g.match_over or not g.st.has(oid):
		return
	var s = g.st[oid]
	var now: float = g.now()
	if now < s.inv_until or s.dead_until > 0.0:
		return
	var q = g.player_node(oid)
	if blockable and s.block:
		var front := true
		if q:
			front = kb.x * q.face <= 0.0
		if front:
			if parry and now - float(s.block_since) < 0.25:
				if src != 0 and g.st.has(src):
					g.c_knock.rpc(src, -kb * 1.5)
				g.c_sfx.rpc("hit")
				if q:
					g.c_dmg.rpc(q.position + Vector2(0, -20), -1)
				return
			amount = int(amount * 0.3)
			kb *= 0.4
	if has_buff(oid, "barrier"):
		amount = int(amount * 0.4)
	amount = maxi(1, amount)
	s.hp = int(s.hp) - amount
	g.c_knock.rpc(oid, kb)
	g.c_sfx.rpc("hurt")
	g.c_anim.rpc(oid, 2)
	if q:
		g.c_dmg.rpc(q.position + Vector2(0, -20), amount)
	if int(s.hp) <= 0:
		kill(oid, src)
	g.push_state(oid)


func kill(oid: int, src: int) -> void:
	var s = g.st[oid]
	s.hp = 0
	s.dead_until = g.now() + g.RESPAWN
	s.d = int(s.d) + 1
	s.block = false
	s.buffs = {}
	if src != 0 and g.st.has(src) and Net.players.has(src) and Net.players.has(oid) and _team(src) != _team(oid):
		g.st[src].k = int(g.st[src].k) + 1
	g.flags_mgr.drop_flag_of(oid)
	var q = g.player_node(oid)
	if q:
		g.c_death.rpc(oid, q.position)
		for i in s.inv.size():
			var e: Dictionary = s.inv[i]
			if e.get("i", "") in Net.RESOURCES:
				var half := int(int(e.n) * 0.5)
				if half > 0:
					g.spawn_drop(q.position, e.i, half)
					e.n = int(e.n) - half


# ------------------------------------------------------------ пастки (хост)
func tick(dt: float) -> void:
	t_spk += dt
	if t_spk < 0.5:
		return
	t_spk = 0.0
	var now: float = g.now()
	for c in g.structs:
		var sc = g.structs[c]
		var cc := Vector2(c) * T + Vector2(8, 8)
		if sc.type == "spikes":
			for oid in g.st:
				if _team(oid) == int(sc.team) or _team(oid) < 0 or g.st[oid].dead_until > 0.0:
					continue
				var q = g.player_node(oid)
				if q and absf(q.position.x - cc.x) < 14.0 and absf(q.position.y - cc.y) < 20.0:
					damage(oid, 8, Vector2(0, -120), 0, false)
		elif sc.type == "arrow_trap" and now >= float(sc.cd):
			for oid in g.st:
				if _team(oid) == int(sc.team) or _team(oid) < 0 or g.st[oid].dead_until > 0.0:
					continue
				var q = g.player_node(oid)
				if q == null:
					continue
				var dx: float = q.position.x - cc.x
				if absf(dx) > 10.0 * T or absf(dx) < 10.0 or absf(q.position.y - cc.y) > 18.0:
					continue
				var sgn := signf(dx)
				var start := cc + Vector2(sgn * 10.0, 0)
				if g.world.ray_blocked(start, q.position, int(sc.team)):
					continue
				spawn_arrow(start, Vector2(sgn * 560.0, -15.0), 2, int(sc.team), 0, 12, 60.0)
				sc.cd = now + 2.0
				break

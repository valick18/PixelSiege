"""game.gd new code, part 1: thrown bombs/TNT, catching, deflecting, square explosions, flying blocks."""

CODE = r'''
# ============================================================ PixelSiege patch: projectiles
const SCATTER := [1, 2, 3, 4, 5] # DIRT, STONE, WOOD, METAL, ORE: ці блоки можуть розлітатися від TNT

func send_throw(dir: Vector2, power: float, slot: int) -> void:
	if multiplayer.is_server():
		req_throw(dir, power, slot)
	else:
		req_throw.rpc_id(1, dir, power, slot)

func send_catch(dir: Vector2, power: float) -> void:
	if multiplayer.is_server():
		req_catch(dir, power)
	else:
		req_catch.rpc_id(1, dir, power)

func held_proj_id() -> int:
	var me := multiplayer.get_unique_id()
	for e in proj_view:
		if int(e[3]) == me:
			return int(e[0])
	return 0

@rpc("authority", "call_local", "unreliable_ordered")
func c_proj(list: Array) -> void:
	proj_view = list

@rpc("any_peer", "reliable")
func req_throw(dir: Vector2, power: float, slot: int) -> void:
	if not multiplayer.is_server():
		return
	var id := _sid()
	var a = actor(id)
	if a == null or dir == Vector2.ZERO:
		return
	var s = a[0]
	var p = a[1]
	slot = clampi(slot, 0, InvS.HOTBAR - 1)
	var item: String = s.inv[slot].get("i", "")
	if item != "bomb" and item != "tnt":
		return
	var t := now()
	if t < float(s.get("throw", 0.0)):
		return
	s["throw"] = t + 0.45
	InvS.consume(s.inv, slot)
	push_state(id)
	var v: Vector2 = dir.normalized() * lerpf(160.0, 440.0, clampf(power, 0.0, 1.0)) + Vector2(0, -60.0)
	_spawn_proj(item, p.position + Vector2(0, -10), v, id, Net.players[id].team, 2.2 if item == "bomb" else 3.2)
	c_anim.rpc(id, 0)
	c_sfx.rpc("fire")

# Перехоплення: F біля бомби/TNT бере її в руки, ґніт продовжує горіти.
# Повторне F / ЛКМ кидає її у бік курсора.
@rpc("any_peer", "reliable")
func req_catch(dir: Vector2, power: float) -> void:
	if not multiplayer.is_server():
		return
	var id := _sid()
	var a = actor(id)
	if a == null:
		return
	var p = a[1]
	for pid in proj:
		var e: Dictionary = proj[pid]
		if int(e.holder) == id:
			if dir == Vector2.ZERO:
				dir = Vector2(p.face, -0.3)
			e.holder = 0
			e.pos = p.position + Vector2(0, -16)
			e.vel = dir.normalized() * lerpf(180.0, 460.0, clampf(power, 0.0, 1.0)) + Vector2(0, -60.0)
			e.owner = id
			e.team = Net.players[id].team
			c_anim.rpc(id, 0)
			return
	var best := 0
	var bd := 34.0
	for pid in proj:
		var e2: Dictionary = proj[pid]
		if e2.k == "blk" or int(e2.holder) != 0:
			continue
		var d: float = p.position.distance_to(e2.pos)
		if d < bd:
			bd = d
			best = pid
	if best != 0:
		proj[best]["holder"] = id
		proj[best]["owner"] = id
		proj[best]["team"] = Net.players[id].team
		note_to(id, "Caught it! F or LMB to throw")
		c_sfx.rpc("pickup")

# Удар ближнього бою відбиває бомбу у бік удару
func _deflect_proj(id: int, from: Vector2, dir: Vector2, reach: float) -> void:
	for pid in proj:
		var e: Dictionary = proj[pid]
		if e.k == "blk" or int(e.holder) != 0:
			continue
		var rel: Vector2 = e.pos - from
		if rel.length() <= reach + 10.0 and rel.dot(dir) > -4.0:
			e.vel = dir * 380.0 + Vector2(0, -80.0)
			e.owner = id
			e.team = Net.players[id].team

func _spawn_proj(k: String, pos: Vector2, vel: Vector2, owner: int, team: int, fuse: float, b: int = 0) -> int:
	var pid := proj_id
	proj_id += 1
	proj[pid] = {"k": k, "pos": pos, "vel": vel, "owner": owner, "team": team, "fuse": fuse, "holder": 0, "b": b, "life": 0.0}
	return pid

func _proj_solid(p: Vector2) -> bool:
	return world.is_solid(floori(p.x / T), floori(p.y / T))

# Рух з відскоком. 0 = летить, 1 = торкнувся землі, 2 = вилетів за карту
func _step_body(e: Dictionary, dt: float, bounce: float) -> int:
	var v: Vector2 = e.vel
	v.y = minf(v.y + 600.0 * dt, 600.0)
	v.x += wind * 20.0 * dt
	var p: Vector2 = e.pos
	var res := 0
	var nx := p + Vector2(v.x * dt, 0)
	if _proj_solid(nx):
		v.x = -v.x * bounce
	else:
		p = nx
	var ny := p + Vector2(0, v.y * dt)
	if _proj_solid(ny):
		if v.y > 0.0:
			res = 1
			v.x *= 0.8
		v.y = -v.y * bounce
		if absf(v.y) < 40.0:
			v.y = 0.0
	else:
		p = ny
	if p.y > world.h * T or p.x < 0.0 or p.x > world.w * T:
		res = 2
	e.pos = p
	e.vel = v
	return res

func _cell_has_player(c: Vector2i) -> bool:
	var cc := Vector2(c) * T + Vector2(8, 8)
	for q in players_root.get_children():
		if absf(q.position.x - cc.x) < 14.0 and absf(q.position.y - cc.y) < 22.0:
			return true
	return false

# Уламок блоку після TNT: летить, при приземленні або стає блоком, або дропає ресурс
func _step_block(pid: int, e: Dictionary, dt: float) -> void:
	var r := _step_body(e, dt, 0.15)
	if r == 2 or float(e.life) > 5.0:
		proj.erase(pid)
		return
	var v: Vector2 = e.vel
	if r == 1 and v.length() < 60.0:
		proj.erase(pid)
		var c := Vector2i(floori(e.pos.x / T), floori(e.pos.y / T))
		if world.get_cell(c) == world.AIR and not _cell_has_player(c) and randf() < 0.6:
			send_edits([[c, int(e.b), -1]])
		else:
			var drop: String = world.drop_of(int(e.b))
			if drop != "":
				spawn_drop(e.pos, drop, 1)
		return
	if v.length() > 160.0:
		for oid in st:
			var q = player_node(oid)
			if q and st[oid].dead_until <= 0.0 and q.position.distance_to(e.pos) < 14.0:
				combat.damage(oid, 6, v.normalized() * 120.0, int(e.owner), false)

func _proj_tick(dt: float) -> void:
	if proj.is_empty() and not proj_live:
		return
	for pid in proj.keys():
		if not proj.has(pid):
			continue
		var e: Dictionary = proj[pid]
		e.life = float(e.life) + dt
		if e.k == "blk":
			_step_block(pid, e, dt)
			continue
		e.fuse = float(e.fuse) - dt
		if int(e.holder) != 0:
			var hq = player_node(e.holder)
			if hq == null or not st.has(e.holder) or st[e.holder].dead_until > 0.0:
				e.holder = 0
				e.vel = Vector2.ZERO
			else:
				e.pos = hq.position + Vector2(0, -20)
		elif _step_body(e, dt, 0.45) == 2:
			proj.erase(pid)
			continue
		if float(e.fuse) <= 0.0:
			proj.erase(pid)
			var c := Vector2i(floori(e.pos.x / T), floori(e.pos.y / T))
			if e.k == "tnt":
				_explode_square(c, 3, 14.0, int(e.owner), true)
			else:
				_explode_square(c, 1, 9.0, int(e.owner), false)
	proj_sync += dt
	if proj_sync >= 0.033 or proj.is_empty():
		proj_sync = 0.0
		proj_live = not proj.is_empty()
		var snap := []
		for pid in proj:
			var e: Dictionary = proj[pid]
			snap.append([pid, e.pos, e.k, e.holder, e.b, e.fuse])
		c_proj.rpc(snap)

# Квадратний вибух: half=1 -> 3x3 (бомба), half=3 -> 7x7 (TNT). scatter: частина блоків розлітається
func _explode_square(center: Vector2i, half: int, power: float, src: int, scatter: bool) -> void:
	var pos := Vector2(center) * T + Vector2(8, 8)
	var removed := []
	for dx in range(-half, half + 1):
		for dy in range(-half, half + 1):
			var c := center + Vector2i(dx, dy)
			if c.y < 0:
				continue
			var b: int = world.get_cell(c)
			if b == world.AIR or b == world.BASE:
				continue
			if b == world.TNT and c != center:
				if not fuses.has(c):
					fuses[c] = 0.2
				continue
			removed.append(c)
			if scatter and b in SCATTER and randf() < 0.5 and proj.size() < 160:
				var off := Vector2(c - center)
				if off == Vector2.ZERO:
					off = Vector2(randf_range(-1.0, 1.0), -1.0)
				var v: Vector2 = off.normalized() * randf_range(160.0, 320.0) + Vector2(randf_range(-40.0, 40.0), -180.0)
				_spawn_proj("blk", Vector2(c) * T + Vector2(8, 8), v, src, -1, 0.0, b)
	remove_cells(removed)
	for pid in proj:
		var e: Dictionary = proj[pid]
		if e.k != "blk" and pos.distance_to(e.pos) < (half + 1) * T:
			e.fuse = minf(float(e.fuse), 0.15)
	var radius := (half + 1.5) * T
	for oid in st:
		var q = player_node(oid)
		if q == null or st[oid].dead_until > 0.0:
			continue
		var dist: float = q.position.distance_to(pos)
		if dist < radius:
			var k := 1.0 - dist / radius
			combat.damage(oid, int(power * 8.0 * k), (q.position - pos).normalized() * 380.0 * k + Vector2(0, -220.0 * k), src, false)
	c_boom.rpc(pos, (half + 0.5) * T)
	fire_sys.broadcast()

# Отрута і горіння: шкода кожні 0.5 с
func _status_tick(dt: float) -> void:
	status_t += dt
	if status_t < 0.5:
		return
	status_t = 0.0
	var t := now()
	for oid in st:
		var s = st[oid]
		if s.dead_until > 0.0:
			continue
		if float(s.get("poison_until", 0.0)) > t:
			combat.damage(oid, 3, Vector2.ZERO, int(s.get("poison_src", 0)), false)
		if float(s.get("burn_until", 0.0)) > t:
			combat.damage(oid, 2, Vector2.ZERO, 0, false)

func _draw_proj(ci: CanvasItem) -> void:
	var tm := Time.get_ticks_msec() / 1000.0
	var me = player_node(multiplayer.get_unique_id())
	for e in proj_view:
		var pos: Vector2 = e[1]
		match str(e[2]):
			"bomb":
				ci.draw_circle(pos, 4.5, Color(0.12, 0.12, 0.14))
				ci.draw_rect(Rect2(pos + Vector2(-1, -7), Vector2(2, 3)), Color(0.55, 0.45, 0.3))
				if fmod(tm * 8.0, 1.0) < 0.5:
					ci.draw_circle(pos + Vector2(0, -8), 1.5, Color(1.0, 0.8, 0.2))
			"tnt":
				ci.draw_rect(Rect2(pos - Vector2(6, 6), Vector2(12, 12)), Color("c0392b"))
				ci.draw_rect(Rect2(pos - Vector2(6, 1), Vector2(12, 2)), Color(0.95, 0.9, 0.8))
				if fmod(tm * (12.0 if float(e[5]) < 1.0 else 6.0), 1.0) < 0.5:
					ci.draw_circle(pos + Vector2(0, -8), 1.5, Color(1.0, 0.8, 0.2))
			"blk":
				ci.draw_rect(Rect2(pos - Vector2(5, 5), Vector2(10, 10)), world.COLORS.get(int(e[4]), Color.GRAY))
		if str(e[2]) != "blk" and int(e[3]) == 0 and me != null and me.position.distance_to(pos) < 34.0:
			ci.draw_string(ThemeDB.fallback_font, pos + Vector2(-3, -12), "F", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 0.6))
'''


def apply(g):
    g.append(CODE)

extends Node2D
# Тайловий світ: процедурна генерація за seed (рельєф, печери, озера, підземні джерела, руїни, дерева),
# автотайли, командні двері, односторонні платформи, люки, джерела світла.

const LookS = preload("res://scripts/look.gd")
const T := 16
const AIR := 0
const DIRT := 1
const STONE := 2
const WOOD := 3
const METAL := 4
const ORE := 5
const TRUNK := 6
const BASE := 7
const LEAF := 8
const LADDER := 9
const TORCH := 10
const SPIKES := 11
const TNT := 12
const SPAWN := 13
const CATAPULT := 14
const STORAGE := 15
const WATER := 16
const PLATFORM := 17
const DOOR := 18
const WORKBENCH := 19
const SIEGE_WS := 20
const BALLISTA := 21
const CAMPFIRE := 22
const LANTERN := 23
const HATCH := 24
const HATCH_OPEN := 25
const ARROW_TRAP := 26
const RUIN_BRICK := 27
const RUIN_CHEST := 28
const FLAMMABLE := [3, 6, 8, 9, 10, 12, 13, 14, 15, 17, 18, 19, 20, 21, 24, 25]
const TREE_BLOCKS := [6, 8]
const SOLID := [1, 2, 3, 4, 5, 7, 12, 24, 26, 27]
const HP := {1: 2, 2: 4, 3: 2, 4: 8, 5: 4, 6: 2, 8: 1, 9: 1, 10: 1, 11: 3, 12: 3, 13: 10, 14: 20, 15: 15, 17: 1, 18: 6, 19: 6, 20: 12, 21: 14, 22: 3, 23: 3, 24: 5, 25: 5, 26: 8, 27: 6, 28: 2}
const DROPS := {2: "stone", 3: "wood", 4: "metal", 5: "metal", 6: "wood", 9: "ladder", 10: "torch", 11: "spikes", 13: "spawn", 14: "catapult", 15: "storage", 17: "platform", 18: "door", 19: "workbench", 20: "siege_workshop", 21: "ballista", 22: "campfire", 23: "lantern", 24: "hatch", 25: "hatch", 26: "arrow_trap", 27: "stone"}
const COLORS := {
	1: Color("8e5a3a"), 2: Color("737d92"), 3: Color("b9854a"), 4: Color("aab7c4"), 5: Color("e6b800"),
	6: Color("5d3a35"), 7: Color("2c3e50"), 8: Color("4a9a4a"), 9: Color("8d6e63"), 10: Color("ffb300"),
	11: Color("90a4ae"), 12: Color("c0392b"), 13: Color("26c6da"), 14: Color("6d4c41"), 15: Color("8d6e43"),
	16: Color("3a78d0"), 17: Color("a8713e"), 18: Color("a8713e"), 19: Color("a8713e"), 20: Color("6b4426"),
	21: Color("6b4426"), 22: Color("ff8a3d"), 23: Color("ffd36b"), 24: Color("a8713e"), 25: Color("a8713e"),
	26: Color("8a93a3"), 27: Color("9c8f7a"), 28: Color("e8b33a"),
}
# block -> [texture_scale, energy, color, offset]
const LIGHTS := {10: [1.6, 1.4, Color(1.0, 0.78, 0.48), Vector2(8, 6)], 22: [2.6, 1.7, Color(1.0, 0.62, 0.3), Vector2(8, 10)], 23: [2.3, 1.5, Color(1.0, 0.93, 0.72), Vector2(8, 5)]}

var w := 0
var h := 0
var cells := PackedByteArray()
var bg := PackedByteArray()  # 1 = задня стіна (підземелля / руїни)
var flag_x := [0, 0]
var flag_y := [0, 0]
var surf := PackedInt32Array()
var trees: Array = []  # [x, top_y, kind]
var owner_team := {}
var fire := {}
var lights := {}
var _solid := PackedByteArray()
var _ltex: Texture2D
var atlas: Texture2D
var tex_dirt: Texture2D
var tex_stone: Texture2D
var tex_wall: Texture2D
var tex_ore: Texture2D
var tex_trees: Texture2D
var decor_tex: Texture2D
var fire_tex: Texture2D


func _init() -> void:
	_solid.resize(64)
	for b in SOLID:
		_solid[b] = 1


func generate(seed_value: int, size: int) -> void:
	atlas = Net.tex("res://assets/blocks.png")
	tex_dirt = Net.tex("res://assets/terrain_dirt.png")
	tex_stone = Net.tex("res://assets/terrain_stone.png")
	tex_wall = Net.tex("res://assets/wall.png")
	tex_ore = Net.tex("res://assets/ore.png")
	tex_trees = Net.tex("res://assets/trees.png")
	decor_tex = Net.tex("res://assets/decor.png")
	fire_tex = Net.tex("res://assets/fire.png")
	w = 160 if size == 0 else 240
	h = 90 if size == 0 else 120
	cells = PackedByteArray()
	cells.resize(w * h)
	bg = PackedByteArray()
	bg.resize(w * h)
	owner_team.clear()
	fire.clear()
	for k in lights:
		lights[k].queue_free()
	lights.clear()
	trees.clear()
	var n := FastNoiseLite.new()
	n.seed = seed_value
	n.frequency = 0.015
	var n2 := FastNoiseLite.new()
	n2.seed = seed_value + 7
	n2.frequency = 0.05
	var cave := FastNoiseLite.new()
	cave.seed = seed_value + 1
	cave.frequency = 0.07
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var base_h := int(h * 0.35)
	var hs := PackedInt32Array()
	hs.resize(w)
	for x in w:
		hs[x] = base_h + int(n.get_noise_1d(x) * h * 0.14 + n2.get_noise_1d(x) * 4.0)
	flag_x = [14, w - 15]
	for t in 2:
		var fx: int = flag_x[t]
		var gy: int = hs[fx]
		flag_y[t] = gy
		for x in range(fx - 16, fx + 17):
			if x < 0 or x >= w:
				continue
			var d := absi(x - fx)
			if d <= 8:
				hs[x] = gy
			else:
				var k := 1.0 - float(d - 8) / 8.0
				hs[x] = int(lerpf(float(hs[x]), float(gy), k))
	for x in w:
		var near_base := absi(x - flag_x[0]) < 9 or absi(x - flag_x[1]) < 9
		for y in h:
			var b := AIR
			if y >= hs[x]:
				b = DIRT if y < hs[x] + 4 else STONE
				if y > hs[x] + 6 and not near_base and cave.get_noise_2d(x, y) > 0.35:
					b = AIR
				elif b == STONE and y > hs[x] + 8 and rng.randf() < 0.03:
					b = ORE
			if y == h - 1:
				b = BASE
			cells[y * w + x] = b
			bg[y * w + x] = 1 if y > hs[x] else 0
	for t in 2:
		for dx in range(-1, 2):
			for dy in range(0, 3):
				_raw(flag_x[t] + dx, flag_y[t] + dy, BASE)
	_gen_lakes(rng, hs, size)
	_gen_pools(rng, hs)
	_gen_ruins(rng, hs, size)
	surf = hs
	var last_tree := -10
	for x in range(3, w - 3):
		if rng.randf() < 0.07 and x - last_tree > 4 and absi(x - flag_x[0]) > 10 and absi(x - flag_x[1]) > 10:
			if get_cell(Vector2i(x, hs[x])) != DIRT or get_cell(Vector2i(x, hs[x] - 1)) != AIR:
				continue
			last_tree = x
			var kind := rng.randi_range(0, 3)
			var th := rng.randi_range(2, 3) + (2 if kind == 3 else 0)
			for k in range(1, th + 1):
				_raw(x, hs[x] - k, TRUNK)
			trees.append([x, hs[x] - th, kind])
	queue_redraw()


func _near_flag(x: int, d: int) -> bool:
	return absi(x - flag_x[0]) < d or absi(x - flag_x[1]) < d


func _set_tile(x: int, y: int, b: int, back: int = -1) -> void:
	if x >= 0 and x < w and y >= 0 and y < h - 1:
		cells[y * w + x] = b
		if back >= 0:
			bg[y * w + x] = back


# Озера: чаша між двома берегами, рівень води = нижчий берег.
func _gen_lakes(rng: RandomNumberGenerator, hs: PackedInt32Array, size: int) -> void:
	var want := 1 + size + (1 if rng.randf() < 0.5 else 0)
	var made: Array = []
	for attempt in 40:
		if made.size() >= want:
			break
		var r := rng.randi_range(5, 9)
		var cx := rng.randi_range(22 + r, w - 23 - r)
		if _near_flag(cx, 26 + r):
			continue
		var ok := true
		for m in made:
			if absi(int(m) - cx) < 34:
				ok = false
		if not ok:
			continue
		var lvl := maxi(hs[cx - r], hs[cx + r])
		if hs[cx] < lvl - 2:
			continue
		var depth_max := rng.randi_range(3, 5)
		for x in range(cx - r + 1, cx + r):
			var f := float(x - cx) / float(r)
			var depth := int(round((1.0 - f * f) * depth_max))
			var bottom := maxi(lvl + maxi(depth, 1), hs[x])
			for y in range(mini(hs[x], lvl), lvl):
				_set_tile(x, y, AIR, 0)
			for y in range(lvl, bottom):
				_set_tile(x, y, WATER, 0)
			for y in range(bottom, bottom + 2):
				if not is_solid(x, y):
					_set_tile(x, y, DIRT)
			hs[x] = lvl
		for ex in [cx - r, cx + r]:
			for y in range(lvl, lvl + depth_max + 2):
				if not is_solid(ex, y):
					_set_tile(ex, y, DIRT)
		made.append(cx)


# Підземні джерела: вода на дні замкнених печер.
func _gen_pools(rng: RandomNumberGenerator, hs: PackedInt32Array) -> void:
	var tries := int(w * h / 300)
	for i in tries:
		var x := rng.randi_range(3, w - 4)
		var y0 := hs[x] + 12
		if y0 >= h - 4:
			continue
		var y := rng.randi_range(y0, h - 4)
		if get_cell(Vector2i(x, y)) != AIR or not is_solid(x, y + 1):
			continue
		for row in 2:
			var yy := y - row
			var xl := x
			var xr := x
			while xl > x - 14 and get_cell(Vector2i(xl - 1, yy)) == AIR and (is_solid(xl - 1, yy + 1) or get_cell(Vector2i(xl - 1, yy + 1)) == WATER):
				xl -= 1
			while xr < x + 14 and get_cell(Vector2i(xr + 1, yy)) == AIR and (is_solid(xr + 1, yy + 1) or get_cell(Vector2i(xr + 1, yy + 1)) == WATER):
				xr += 1
			if xr - xl < 2 or not is_solid(xl - 1, yy) or not is_solid(xr + 1, yy):
				break
			for xx in range(xl, xr + 1):
				_set_tile(xx, yy, WATER)


# Руїни: зруйновані цегляні споруди на поверхні та одна підземна кімната, у кожній - скриня з лутом.
func _gen_ruins(rng: RandomNumberGenerator, hs: PackedInt32Array, size: int) -> void:
	var want := 2 + size
	var made: Array = []
	for attempt in 60:
		if made.size() >= want:
			break
		var rw := rng.randi_range(9, 13)
		var rh := rng.randi_range(5, 7)
		var x0 := rng.randi_range(24, w - 24 - rw)
		var cx := x0 + rw / 2
		if _near_flag(cx, 30):
			continue
		var ok := true
		for m in made:
			if absi(int(m) - cx) < 36:
				ok = false
		var lo := 9999
		var hi := -9999
		for x in range(x0, x0 + rw):
			lo = mini(lo, hs[x])
			hi = maxi(hi, hs[x])
			if get_cell(Vector2i(x, hs[x])) == WATER or get_cell(Vector2i(x, hs[x] - 1)) == WATER:
				ok = false
		if not ok or hi - lo > 3:
			continue
		var g := hs[cx]
		var door_left := cx > w / 2
		for x in range(x0, x0 + rw):
			for y in range(g + 1, hs[x]):
				_set_tile(x, y, DIRT)
			_set_tile(x, g, RUIN_BRICK)
			for y in range(g - rh, g):
				_set_tile(x, y, AIR, 1)
			if rng.randf() < 0.6:
				_set_tile(x, g - rh, RUIN_BRICK)
		for side in 2:
			var wx := x0 if side == 0 else x0 + rw - 1
			var is_door := (side == 0) == door_left
			for y in range(g - rh, g):
				if is_door and y >= g - 2:
					continue
				if y < g - 2 and rng.randf() < 0.22:
					continue
				_set_tile(wx, y, RUIN_BRICK)
		var px := x0 + 2 + rng.randi_range(0, 1)
		for y in range(g - rng.randi_range(1, rh - 2), g):
			_set_tile(px, y, RUIN_BRICK)
		_set_tile(cx, g - 1, RUIN_CHEST)
		for x in range(x0, x0 + rw):
			hs[x] = mini(hs[x], g)
		made.append(cx)
	# підземна кімната
	for attempt in 20:
		var ux := rng.randi_range(30, w - 42)
		if _near_flag(ux + 5, 26):
			continue
		var uy := hs[ux] + rng.randi_range(18, 28)
		if uy + 6 >= h - 2:
			continue
		for x in range(ux, ux + 11):
			for y in range(uy, uy + 6):
				var edge := x == ux or x == ux + 10 or y == uy or y == uy + 5
				if edge:
					if rng.randf() > 0.15:
						_set_tile(x, y, RUIN_BRICK, 1)
				else:
					_set_tile(x, y, AIR, 1)
		_set_tile(ux + 5, uy + 4, RUIN_CHEST, 1)
		break


func _raw(x: int, y: int, b: int) -> void:
	if x >= 0 and x < w and y >= 0 and y < h:
		cells[y * w + x] = b


func get_cell(c: Vector2i) -> int:
	if c.y < 0:
		return AIR
	if c.x < 0 or c.x >= w or c.y >= h:
		return BASE
	return cells[c.y * w + c.x]


func set_cell(c: Vector2i, b: int, team: int = -1) -> void:
	_raw(c.x, c.y, b)
	if team >= 0:
		owner_team[c] = team
	else:
		owner_team.erase(c)
	if lights.has(c):
		lights[c].queue_free()
		lights.erase(c)
	if LIGHTS.has(b):
		var cfg: Array = LIGHTS[b]
		var l := PointLight2D.new()
		l.texture = _light_tex()
		l.texture_scale = cfg[0]
		l.energy = cfg[1]
		l.color = cfg[2]
		l.position = Vector2(c.x * T, c.y * T) + cfg[3]
		add_child(l)
		lights[c] = l


func add_tree(x: int, top: int, kind: int) -> void:
	for tr in trees:
		if tr[0] == x:
			tr[1] = top
			tr[2] = kind
			return
	trees.append([x, top, kind])


# Всі клітинки стовбура дерева, до якого належить клітинка c (для зрубування цілого дерева).
func tree_cells(c: Vector2i) -> Array:
	var out: Array = []
	var y := c.y
	while get_cell(Vector2i(c.x, y + 1)) in TREE_BLOCKS:
		y += 1
	while get_cell(Vector2i(c.x, y)) in TREE_BLOCKS:
		out.append(Vector2i(c.x, y))
		y -= 1
	return out


func _light_tex() -> Texture2D:
	if _ltex == null:
		var g := Gradient.new()
		g.set_color(0, Color.WHITE)
		g.set_color(1, Color(1, 1, 1, 0))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 128
		t.height = 128
		_ltex = t
	return _ltex


func light_texture() -> Texture2D:
	return _light_tex()


func is_solid(cx: int, cy: int) -> bool:
	return _solid[get_cell(Vector2i(cx, cy))] == 1


# Командні двері тверді лише для чужої команди.
func blocks_for(cx: int, cy: int, team: int) -> bool:
	var b := get_cell(Vector2i(cx, cy))
	if _solid[b] == 1:
		return true
	if b == DOOR:
		return int(owner_team.get(Vector2i(cx, cy), -1)) != team
	return false


func is_platform(cx: int, cy: int) -> bool:
	return get_cell(Vector2i(cx, cy)) == PLATFORM


func is_water(cx: int, cy: int) -> bool:
	return get_cell(Vector2i(cx, cy)) == WATER


func max_hp(b: int) -> int:
	return HP.get(b, 2)


func drop_of(b: int) -> String:
	return DROPS.get(b, "")


func flag_pos(t: int) -> Vector2:
	return Vector2(flag_x[t] * T + 8, flag_y[t] * T)


func spawn_pos(t: int) -> Vector2:
	return Vector2(flag_x[t] * T + 8 + (28 if t == 0 else -28), flag_y[t] * T - 15)


func ray_blocked(a: Vector2, b: Vector2, team: int = -1) -> bool:
	var steps := int(a.distance_to(b) / 4.0) + 1
	for i in steps:
		var p := a.lerp(b, float(i) / steps)
		var cx := floori(p.x / T)
		var cy := floori(p.y / T)
		if (blocks_for(cx, cy, team) if team >= 0 else is_solid(cx, cy)):
			return true
	return false


func drop_pos(p: Vector2) -> Vector2:
	var cx := floori(p.x / T)
	var cy := floori(p.y / T)
	while cy < h - 1 and not is_solid(cx, cy + 1) and not is_platform(cx, cy + 1):
		cy += 1
	return Vector2(p.x, (cy + 1) * T)


func _mask(x: int, y: int) -> int:
	var m := 0
	if not is_solid(x, y - 1):
		m |= 1
	if not is_solid(x + 1, y):
		m |= 2
	if not is_solid(x, y + 1):
		m |= 4
	if not is_solid(x - 1, y):
		m |= 8
	return m


func _process(_dt: float) -> void:
	var tm := Time.get_ticks_msec() / 1000.0
	for c in lights:
		if get_cell(c) == CAMPFIRE:
			lights[c].energy = 1.7 + sin(tm * 11.0 + c.x) * 0.12 + sin(tm * 7.3) * 0.08
	queue_redraw()


func _draw() -> void:
	if cells.is_empty():
		return
	var inv: Transform2D = get_canvas_transform().affine_inverse()
	var vr: Rect2 = inv * get_viewport_rect()
	var x0 := clampi(floori(vr.position.x / T) - 1, 0, w - 1)
	var x1 := clampi(floori(vr.end.x / T) + 1, 0, w - 1)
	var y0 := clampi(floori(vr.position.y / T) - 1, 0, h - 1)
	var y1 := clampi(floori(vr.end.y / T) + 1, 0, h - 1)
	var tm := Time.get_ticks_msec() / 1000.0
	var have_terrain := tex_dirt != null and tex_stone != null
	var water_cells: Array = []
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var b: int = cells[y * w + x]
			var r := Rect2(x * T, y * T, T, T)
			var kk := clampf(1.0 - float(y - surf[x] - 3) * 0.045, 0.25, 1.0)
			var md := Color(kk, kk, kk)
			var sx := (x & 3) * 16
			var sy := (y & 3) * 16
			if bg[y * w + x] == 1 and _solid[b] == 0:
				if tex_wall:
					draw_texture_rect_region(tex_wall, r, Rect2(sx, sy, 16, 16), Color(kk * 0.85, kk * 0.85, kk * 0.9))
				else:
					draw_rect(r, Color(0.16, 0.11, 0.12))
			if b == AIR:
				continue
			if b == WATER:
				water_cells.append(Vector2i(x, y))
				continue
			if have_terrain and (b == DIRT or b == STONE or b == ORE):
				var m := _mask(x, y)
				if b == DIRT:
					var gy := 0 if y <= surf[x] + 1 else 64
					draw_texture_rect_region(tex_dirt, r, Rect2(m * 64 + sx, gy + sy, 16, 16), md)
					if decor_tex and (m & 1) != 0 and y <= surf[x] + 1 and get_cell(Vector2i(x, y - 1)) == AIR:
						var hh := (x * 31 + y * 17) % 13
						if hh < 8:
							draw_texture_rect_region(decor_tex, Rect2(x * T, (y - 1) * T + 2, T, T), Rect2(hh * 16, 0, 16, 16))
				else:
					draw_texture_rect_region(tex_stone, r, Rect2(m * 64 + sx, sy, 16, 16), md)
					if b == ORE and tex_ore:
						draw_texture_rect_region(tex_ore, r, Rect2(((x * 7 + y * 3) % 3) * 16, 0, 16, 16), md)
				continue
			var ot = owner_team.get(Vector2i(x, y))
			if b >= WATER:
				var tc: Color = Net.TEAM_COLORS[ot] if ot != null else Color(0.6, 0.6, 0.6)
				LookS.draw_block_shape(self, b, r, tc, tm, get_cell(Vector2i(x, y - 1)) != b, md)
				continue
			if atlas:
				draw_texture_rect_region(atlas, r, Rect2(b * 16, ((x * 7 + y * 13) % 3) * 16, 16, 16), md)
			else:
				draw_rect(r, COLORS.get(b, Color.WHITE))
			if ot != null:
				draw_rect(Rect2(x * T + 1, y * T + 1, 3, 2), Net.TEAM_COLORS[ot])
	if tex_trees:
		for tr in trees:
			var tx: int = tr[0]
			if tx < x0 - 4 or tx > x1 + 4:
				continue
			var ty: int = tr[1]
			if get_cell(Vector2i(tx, ty)) != TRUNK:
				continue
			var kind: int = tr[2]
			draw_texture_rect_region(tex_trees, Rect2(tx * T + 8 - 32, ty * T - 64, 64, 80), Rect2(kind * 64, 0, 64, 80))
	for c in water_cells:
		LookS.draw_block_shape(self, WATER, Rect2(c.x * T, c.y * T, T, T), Color.WHITE, tm, get_cell(Vector2i(c.x, c.y - 1)) != WATER)
	for cell in fire:
		if cell.x >= x0 and cell.x <= x1 and cell.y >= y0 and cell.y <= y1:
			var o := Vector2(cell.x * T, cell.y * T)
			if fire_tex:
				draw_texture_rect_region(fire_tex, Rect2(o, Vector2(T, T)), Rect2(((int(tm * 10.0) + cell.x) % 4) * 16, 0, 16, 16))
			else:
				draw_rect(Rect2(o, Vector2(T, T)), Color(1.0, 0.5, 0.1, 0.8))

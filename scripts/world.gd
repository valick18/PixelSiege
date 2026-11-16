extends Node2D
# Тайловий світ: процедурна генерація за seed і малювання з автотайлами (округлі краї, трава, контури, задні стіни, дерева-спрайти).

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
const FLAMMABLE := [3, 6, 8, 9, 10, 12, 13, 14, 15]

const HP := {1: 2, 2: 4, 3: 2, 4: 8, 5: 4, 6: 2, 8: 1, 9: 1, 10: 1, 11: 3, 12: 3, 13: 10, 14: 20, 15: 15}
const DROPS := {2: "stone", 3: "wood", 4: "metal", 5: "metal", 6: "wood", 9: "ladder", 10: "torch", 11: "spikes", 13: "spawn", 14: "catapult", 15: "storage"}
const COLORS := {
	1: Color("8e5a3a"), 2: Color("737d92"), 3: Color("b9854a"), 4: Color("aab7c4"), 5: Color("e6b800"),
	6: Color("5d3a35"), 7: Color("2c3e50"), 8: Color("4a9a4a"), 9: Color("8d6e63"), 10: Color("ffb300"),
	11: Color("90a4ae"), 12: Color("c0392b"), 13: Color("26c6da"), 14: Color("6d4c41"), 15: Color("8d6e43"),
}

var w := 0
var h := 0
var cells := PackedByteArray()
var flag_x := [0, 0]
var flag_y := [0, 0]
var surf := PackedInt32Array()
var trees: Array = []  # [x, top_y, kind]
var owner_team := {}
var fire := {}
var lights := {}
var _ltex: Texture2D
var atlas: Texture2D
var tex_dirt: Texture2D
var tex_stone: Texture2D
var tex_wall: Texture2D
var tex_ore: Texture2D
var tex_trees: Texture2D
var decor_tex: Texture2D
var fire_tex: Texture2D


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
	surf = hs
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
	for t in 2:
		for dx in range(-1, 2):
			for dy in range(0, 3):
				_raw(flag_x[t] + dx, flag_y[t] + dy, BASE)
	var last_tree := -10
	for x in range(3, w - 3):
		if rng.randf() < 0.07 and x - last_tree > 4 and absi(x - flag_x[0]) > 10 and absi(x - flag_x[1]) > 10:
			last_tree = x
			var kind := rng.randi_range(0, 3)
			var th := rng.randi_range(2, 3) + (2 if kind == 3 else 0)
			for k in range(1, th + 1):
				_raw(x, hs[x] - k, TRUNK)
			trees.append([x, hs[x] - th, kind])
	queue_redraw()


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
	if b == TORCH:
		var l := PointLight2D.new()
		l.texture = _light_tex()
		l.texture_scale = 1.6
		l.energy = 1.4
		l.color = Color(1.0, 0.78, 0.48)
		l.position = Vector2(c.x * T + 8, c.y * T + 6)
		add_child(l)
		lights[c] = l


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
	var b := get_cell(Vector2i(cx, cy))
	return b == DIRT or b == STONE or b == WOOD or b == METAL or b == ORE or b == BASE or b == TNT


func max_hp(b: int) -> int:
	return HP.get(b, 2)


func drop_of(b: int) -> String:
	return DROPS.get(b, "")


func flag_pos(t: int) -> Vector2:
	return Vector2(flag_x[t] * T + 8, flag_y[t] * T)


func spawn_pos(t: int) -> Vector2:
	return Vector2(flag_x[t] * T + 8 + (28 if t == 0 else -28), flag_y[t] * T - 15)


func ray_blocked(a: Vector2, b: Vector2) -> bool:
	var steps := int(a.distance_to(b) / 4.0) + 1
	for i in steps:
		var p := a.lerp(b, float(i) / steps)
		if is_solid(floori(p.x / T), floori(p.y / T)):
			return true
	return false


func drop_pos(p: Vector2) -> Vector2:
	var cx := floori(p.x / T)
	var cy := floori(p.y / T)
	while cy < h - 1 and not is_solid(cx, cy + 1):
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
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var b: int = cells[y * w + x]
			var r := Rect2(x * T, y * T, T, T)
			var kk := clampf(1.0 - float(y - surf[x] - 3) * 0.045, 0.25, 1.0)
			var md := Color(kk, kk, kk)
			var sx := (x & 3) * 16
			var sy := (y & 3) * 16
			if y > surf[x] and not is_solid(x, y):
				if tex_wall:
					draw_texture_rect_region(tex_wall, r, Rect2(sx, sy, 16, 16), Color(kk * 0.85, kk * 0.85, kk * 0.9))
				else:
					draw_rect(r, Color(0.16, 0.11, 0.12))
			if b == AIR:
				continue
			if have_terrain and (b == DIRT or b == STONE or b == ORE):
				var m := _mask(x, y)
				if b == DIRT:
					var gy := 0 if y <= surf[x] + 1 else 64
					draw_texture_rect_region(tex_dirt, r, Rect2(m * 64 + sx, gy + sy, 16, 16), md)
					if decor_tex and (m & 1) != 0 and y <= surf[x] + 1:
						var hh := (x * 31 + y * 17) % 13
						if hh < 8:
							draw_texture_rect_region(decor_tex, Rect2(x * T, (y - 1) * T + 2, T, T), Rect2(hh * 16, 0, 16, 16))
				else:
					draw_texture_rect_region(tex_stone, r, Rect2(m * 64 + sx, sy, 16, 16), md)
					if b == ORE and tex_ore:
						draw_texture_rect_region(tex_ore, r, Rect2(((x * 7 + y * 3) % 3) * 16, 0, 16, 16), md)
				continue
			if atlas:
				draw_texture_rect_region(atlas, r, Rect2(b * 16, ((x * 7 + y * 13) % 3) * 16, 16, 16), md)
			else:
				draw_rect(r, COLORS.get(b, Color.WHITE))
			var ot = owner_team.get(Vector2i(x, y))
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
	for cell in fire:
		if cell.x >= x0 and cell.x <= x1 and cell.y >= y0 and cell.y <= y1:
			var o := Vector2(cell.x * T, cell.y * T)
			if fire_tex:
				draw_texture_rect_region(fire_tex, Rect2(o, Vector2(T, T)), Rect2(((int(tm * 10.0) + cell.x) % 4) * 16, 0, 16, 16))
			else:
				draw_rect(Rect2(o, Vector2(T, T)), Color(1.0, 0.5, 0.1, 0.8))

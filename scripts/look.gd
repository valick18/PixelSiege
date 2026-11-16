extends RefCounted
# Візуальний вигляд: піксельна paper-doll модель персонажа з шарів (шкіра, волосся, одяг, шапка),
# рука зі зброєю слідує за прицілом, інструменти, іконки предметів і нові блоки світу.

const SKIN := [Color("f6d5b8"), Color("e8b48f"), Color("c98e5f"), Color("8d5a36"), Color("5b3820")]
const HAIR_COLS := [Color("1c1a1f"), Color("5a3825"), Color("a0522d"), Color("e3c062"), Color("d8d8d8"), Color("b8322c"), Color("3d6fd1"), Color("5fa84f")]
const CLOTH := [Color("6c7a89"), Color("34495e"), Color("7a4a2e"), Color("2f8f4e"), Color("7d3c98"), Color("c8641e"), Color("d4ac0d"), Color("e5e8e8"), Color("23232b")]
const EYES := [Color("22303c"), Color("2e86de"), Color("27ae60"), Color("7b4a2a"), Color("8e44ad")]
const HAIR_STYLES := ["Bald", "Short", "Long", "Spiky", "Ponytail", "Mohawk"]
const HATS := ["None", "Cap", "Hood", "Helmet", "Bandana", "Crown"]
const BEARDS := ["None", "Stubble", "Full beard", "Moustache"]
const ITEM_ORDER := ["wood", "stone", "metal", "ladder", "torch", "spikes", "tnt", "firebomb", "spawn", "storage", "catapult", "medkit", "food"]
const WOOD := Color("a8713e")
const WOOD_D := Color("6b4426")
const STEEL := Color("c9d3dc")
const STEEL_HI := Color("f1f5f8")
const IRON := Color("6f7a86")
const GOLD := Color("e8b33a")
const STONE := Color("8a93a3")
const STRING := Color("efe6d0")
const RUIN := Color("9c8f7a")


static func default_look() -> Dictionary:
	return {"skin": 1, "hair": 1, "hair_col": 1, "eyes": 0, "shirt": 1, "pants": 2, "boots": 8, "hat": 0, "beard": 0, "classic": false}


static func option_counts() -> Dictionary:
	return {"skin": SKIN.size(), "hair": HAIR_STYLES.size(), "hair_col": HAIR_COLS.size(), "eyes": EYES.size(), "shirt": CLOTH.size(), "pants": CLOTH.size(), "boots": CLOTH.size(), "hat": HATS.size(), "beard": BEARDS.size()}


static func sanitize(l) -> Dictionary:
	var d := default_look()
	if l is Dictionary:
		var counts := option_counts()
		for k in counts:
			if l.has(k):
				d[k] = clampi(int(l[k]), 0, int(counts[k]) - 1)
		if l.has("classic"):
			d["classic"] = bool(l["classic"])
	return d


static func random_look() -> Dictionary:
	var d := default_look()
	var counts := option_counts()
	for k in counts:
		d[k] = randi() % int(counts[k])
	return d


static func _r(ci: CanvasItem, x: float, y: float, w: float, h: float, c: Color) -> void:
	ci.draw_rect(Rect2(x, y, w, h), c)


# pose: face, t, walk(0..1), crouch, air, tint, rot, offset, tool, aim(світовий кут), aiming, swing(-1 або 0..1), dig(-1/0..1), draw(0..1), block, item_col
static func draw_char(ci: CanvasItem, look: Dictionary, team: int, cls: String, pose: Dictionary) -> void:
	var face: int = 1 if int(pose.get("face", 1)) >= 0 else -1
	var t: float = pose.get("t", 0.0)
	var walk: float = pose.get("walk", 0.0)
	var crouch: bool = pose.get("crouch", false)
	var air: bool = pose.get("air", false)
	var tint: Color = pose.get("tint", Color.WHITE)
	var sc: float = pose.get("scale", 1.0)
	var base := Transform2D(float(pose.get("rot", 0.0)), Vector2(face, 1) * sc, 0.0, pose.get("offset", Vector2.ZERO))
	ci.draw_set_transform_matrix(base)
	var skin: Color = SKIN[int(look.skin)] * tint
	var hair: Color = HAIR_COLS[int(look.hair_col)] * tint
	var shirt: Color = CLOTH[int(look.shirt)] * tint
	var pants: Color = CLOTH[int(look.pants)] * tint
	var boots: Color = CLOTH[int(look.boots)].darkened(0.2) * tint
	var tcol: Color = Net.TEAM_COLORS[clampi(team, 0, 1)] * tint
	var cy := 5.0 if crouch else 0.0
	var ph := sin(t * 11.0) * walk
	var ly := 10.0 if crouch else 8.0
	var lh := 14.0 - ly
	var tt := -3.0 + cy
	var th := 11.0 - (2.0 if crouch else 0.0)
	if cls == "archer":
		_r(ci, -7, tt - 2, 3, 9, WOOD_D * tint)
		_r(ci, -7, tt - 4, 1, 2, STRING * tint)
		_r(ci, -5, tt - 4, 1, 2, STRING * tint)
	var bl := -1.5 if air else -ph * 2.0
	var fl := 1.5 if air else ph * 2.0
	_r(ci, -3 + bl, ly, 3, lh, pants.darkened(0.25))
	_r(ci, -3 + bl, 12, 3, 2, boots.darkened(0.2))
	var sh := Vector2(0, tt + 2)
	var back_a := PI * 0.5 + ph * 0.6
	ci.draw_line(sh + Vector2(-1, 0), sh + Vector2(-1, 0) + Vector2.from_angle(back_a) * 6.0, shirt.darkened(0.3), 3.0)
	_r(ci, 0 + fl, ly, 3, lh, pants)
	_r(ci, 0 + fl, 12, 3, 2, boots)
	_r(ci, -4, tt, 9, th, shirt)
	_r(ci, -1, tt, 3, th - 2, tcol)
	_r(ci, -4, tt + th - 3, 9, 1, WOOD_D * tint)
	match cls:
		"warrior":
			_r(ci, -4, tt - 1, 5, 3, IRON * tint)
			_r(ci, -3, tt - 1, 3, 1, STEEL * tint)
		"engineer":
			_r(ci, -4, tt + th - 4, 9, 2, GOLD.darkened(0.2) * tint)
		"support":
			_r(ci, 3, tt + 2, 1, 3, Color.WHITE * tint)
			_r(ci, 2, tt + 3, 3, 1, Color.WHITE * tint)
	var hy := -12.0 + cy
	_r(ci, -3, hy, 8, 8, skin)
	_r(ci, -1, hy + 3, 1, 2, skin.darkened(0.2))
	_r(ci, 2, hy + 3, 1, 2, Color(0.95, 0.95, 0.95) * tint)
	_r(ci, 3, hy + 3, 1, 2, EYES[int(look.eyes)] * tint)
	match int(look.beard):
		1: _r(ci, 0, hy + 6, 5, 2, skin.darkened(0.28))
		2:
			_r(ci, -1, hy + 5, 6, 3, hair)
			_r(ci, 1, hy + 8, 3, 1, hair)
		3: _r(ci, 2, hy + 5, 3, 1, hair)
	match int(look.hair):
		1:
			_r(ci, -3, hy - 1, 8, 3, hair)
			_r(ci, -3, hy + 2, 2, 3, hair)
		2:
			_r(ci, -3, hy - 1, 8, 3, hair)
			_r(ci, -4, hy + 1, 3, 9, hair)
		3:
			_r(ci, -3, hy, 8, 2, hair)
			_r(ci, -3, hy - 2, 2, 2, hair)
			_r(ci, 0, hy - 3, 2, 3, hair)
			_r(ci, 3, hy - 2, 2, 2, hair)
			_r(ci, -3, hy + 2, 2, 2, hair)
		4:
			_r(ci, -3, hy - 1, 8, 3, hair)
			_r(ci, -6, hy + 1, 3, 2, hair)
			_r(ci, -7, hy + 3, 2, 4, hair)
		5:
			_r(ci, -1, hy - 3, 3, 4, hair)
	match int(look.hat):
		1:
			_r(ci, -3, hy - 2, 8, 3, shirt.lightened(0.1))
			_r(ci, 4, hy, 4, 1, shirt.darkened(0.2))
		2:
			var hc := shirt.darkened(0.15)
			_r(ci, -4, hy - 2, 10, 3, hc)
			_r(ci, -4, hy + 1, 3, 8, hc)
			_r(ci, 5, hy - 1, 1, 4, hc)
		3:
			_r(ci, -4, hy - 2, 10, 5, IRON * tint)
			_r(ci, -2, hy - 1, 4, 1, STEEL * tint)
			_r(ci, 4, hy + 2, 1, 3, IRON * tint)
		4:
			_r(ci, -3, hy, 8, 2, tcol)
			_r(ci, -6, hy + 1, 3, 1, tcol)
			_r(ci, -7, hy + 2, 2, 1, tcol)
		5:
			_r(ci, -2, hy - 2, 7, 2, GOLD * tint)
			_r(ci, -2, hy - 4, 1, 2, GOLD * tint)
			_r(ci, 1, hy - 4, 1, 2, GOLD * tint)
			_r(ci, 4, hy - 4, 1, 2, GOLD * tint)
	# ---- передня рука + інструмент
	var tool: String = pose.get("tool", "")
	var aim: float = pose.get("aim", 0.0)
	var la := wrapf(aim if face > 0 else PI - aim, -PI, PI)
	var swing: float = pose.get("swing", -1.0)
	var dig: float = pose.get("dig", -1.0)
	var dk: float = pose.get("draw", 0.0)
	var arm := PI * 0.5 - 0.35 + ph * 0.4
	var tool_rot := -0.9
	if tool == "bow":
		arm = la if bool(pose.get("aiming", true)) else PI * 0.3
		tool_rot = 0.0
	elif tool != "":
		arm = PI * 0.25
		if swing >= 0.0:
			var e := 1.0 - pow(1.0 - swing, 3.0)
			arm = la - 1.7 + 3.0 * e
		elif dig >= 0.0:
			arm = la - 1.1 + 1.6 * sin(dig * PI)
		if bool(pose.get("block", false)):
			arm = -0.25
	var hand := sh + Vector2.from_angle(arm) * 6.0
	ci.draw_line(sh, hand, shirt.darkened(0.08), 3.0)
	_r(ci, hand.x - 1, hand.y - 1, 2, 2, skin)
	if tool != "":
		ci.draw_set_transform_matrix(base * Transform2D(arm + tool_rot, hand))
		draw_tool_local(ci, tool, dk, tint)
	elif pose.has("item_col"):
		_r(ci, hand.x - 2, hand.y - 2, 5, 5, pose.item_col * tint)
	if bool(pose.get("block", false)):
		ci.draw_set_transform_matrix(base)
		_r(ci, 5, tt - 3, 3, 12, WOOD * tint)
		_r(ci, 5, tt + 2, 3, 2, tcol)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func draw_tool_local(ci: CanvasItem, tool: String, k: float = 0.0, tint: Color = Color.WHITE) -> void:
	match tool:
		"sword":
			_r(ci, -2, -1, 4, 2, WOOD_D * tint)
			_r(ci, 2, -3, 1, 6, GOLD * tint)
			_r(ci, 3, -1, 11, 2, STEEL * tint)
			_r(ci, 3, -1, 11, 1, STEEL_HI * tint)
			ci.draw_colored_polygon(PackedVector2Array([Vector2(14, -1), Vector2(16, 0), Vector2(14, 1)]), STEEL * tint)
		"spear":
			ci.draw_line(Vector2(-8, 0), Vector2(18, 0), WOOD * tint, 1.5)
			ci.draw_colored_polygon(PackedVector2Array([Vector2(18, -2.5), Vector2(24, 0), Vector2(18, 2.5)]), STEEL * tint)
		"dagger":
			_r(ci, -1, -1, 3, 2, WOOD_D * tint)
			_r(ci, 2, -2, 1, 4, GOLD * tint)
			_r(ci, 3, -1, 6, 2, STEEL * tint)
		"mace":
			ci.draw_line(Vector2(-2, 0), Vector2(10, 0), WOOD * tint, 2.0)
			for a in 4:
				var sp := Vector2(12, 0) + Vector2.from_angle(a * PI * 0.5 + PI * 0.25) * 4.0
				_r(ci, sp.x - 1, sp.y - 1, 2, 2, STEEL * tint)
			ci.draw_circle(Vector2(12, 0), 3.5, IRON * tint)
		"hammer":
			ci.draw_line(Vector2(-2, 0), Vector2(11, 0), WOOD * tint, 2.0)
			_r(ci, 9, -4, 5, 8, IRON * tint)
			_r(ci, 9, -4, 5, 2, STEEL_HI * tint)
		"pickaxe":
			ci.draw_line(Vector2(-2, 0), Vector2(12, 0), WOOD * tint, 2.0)
			ci.draw_polyline(PackedVector2Array([Vector2(8, -7), Vector2(11, -4), Vector2(12, 0), Vector2(11, 4), Vector2(8, 7)]), STEEL * tint, 2.0)
		"axe":
			ci.draw_line(Vector2(-2, 0), Vector2(13, 0), WOOD * tint, 2.0)
			ci.draw_colored_polygon(PackedVector2Array([Vector2(9, 1), Vector2(9, -2), Vector2(14, -8), Vector2(15, -1), Vector2(14, 2)]), STEEL * tint)
		"bow":
			var pts := PackedVector2Array()
			for i in 9:
				var a := lerpf(-1.25, 1.25, i / 8.0)
				pts.append(Vector2(cos(a) * 9.0 - 6.0, sin(a) * 9.0))
			ci.draw_polyline(pts, WOOD * tint, 2.0)
			var top: Vector2 = pts[0]
			var bot: Vector2 = pts[8]
			var nock := Vector2(top.x - k * 6.0, 0)
			ci.draw_line(top, nock, STRING * tint, 1.0)
			ci.draw_line(nock, bot, STRING * tint, 1.0)
			if k > 0.02:
				ci.draw_line(nock, nock + Vector2(15, 0), WOOD.lightened(0.3) * tint, 1.0)
				ci.draw_colored_polygon(PackedVector2Array([nock + Vector2(15, -1.5), nock + Vector2(18, 0), nock + Vector2(15, 1.5)]), STEEL * tint)


static func _q(r: Rect2, x: float, y: float, w: float, h: float) -> Rect2:
	var s := r.size.x / 16.0
	return Rect2(r.position + Vector2(x, y) * s, Vector2(w, h) * s)


static func _p(r: Rect2, x: float, y: float) -> Vector2:
	return r.position + Vector2(x, y) * (r.size.x / 16.0)


# Нові блоки (id 16..28) малюються процедурно. top = верхня клітинка (для води / дверей).
static func draw_block_shape(ci: CanvasItem, b: int, r: Rect2, tcol: Color, tm: float, top: bool, md: Color = Color.WHITE) -> void:
	var s := r.size.x / 16.0
	match b:
		16:
			ci.draw_rect(r, Color(0.18, 0.42, 0.82, 0.55))
			if top:
				ci.draw_rect(_q(r, 0, 1.0 + sin(tm * 2.0 + r.position.x * 0.13), 16, 2), Color(0.75, 0.88, 1.0, 0.75))
		17:
			ci.draw_rect(_q(r, 0, 0, 16, 4), WOOD * md)
			ci.draw_rect(_q(r, 0, 3, 16, 1), WOOD_D * md)
			ci.draw_rect(_q(r, 2, 4, 2, 3), WOOD_D * md)
			ci.draw_rect(_q(r, 12, 4, 2, 3), WOOD_D * md)
		18:
			ci.draw_rect(_q(r, 2, 0, 12, 16), WOOD * md)
			ci.draw_rect(_q(r, 2, 0, 1, 16), WOOD_D * md)
			ci.draw_rect(_q(r, 13, 0, 1, 16), WOOD_D * md)
			ci.draw_rect(_q(r, 7, 0, 1, 16), WOOD_D * md)
			ci.draw_rect(_q(r, 2, 6, 12, 2), tcol)
			if top:
				ci.draw_rect(_q(r, 2, 0, 12, 2), WOOD_D * md)
			else:
				ci.draw_rect(_q(r, 10, 9, 2, 2), GOLD * md)
		19:
			ci.draw_rect(_q(r, 0, 5, 16, 3), WOOD * md)
			ci.draw_rect(_q(r, 0, 7, 16, 1), WOOD_D * md)
			ci.draw_rect(_q(r, 1, 8, 2, 8), WOOD_D * md)
			ci.draw_rect(_q(r, 13, 8, 2, 8), WOOD_D * md)
			ci.draw_rect(_q(r, 3, 3, 6, 2), STEEL * md)
			ci.draw_rect(_q(r, 11, 1, 2, 4), WOOD_D * md)
			ci.draw_rect(_q(r, 10, 1, 4, 2), IRON * md)
			ci.draw_rect(_q(r, 7, 10, 2, 2), tcol)
		20:
			ci.draw_rect(_q(r, 0, 3, 16, 13), WOOD_D * md)
			ci.draw_rect(_q(r, 1, 4, 14, 11), WOOD * md)
			ci.draw_circle(_p(r, 8, 9.5), 4.5 * s, IRON * md)
			ci.draw_circle(_p(r, 8, 9.5), 1.8 * s, WOOD_D * md)
			ci.draw_rect(_q(r, 0, 2, 16, 1), tcol)
		21:
			ci.draw_rect(_q(r, 2, 12, 12, 4), WOOD_D * md)
			ci.draw_rect(_q(r, 7, 7, 2, 5), WOOD * md)
			ci.draw_rect(_q(r, 1, 5, 14, 2), WOOD * md)
			ci.draw_polyline(PackedVector2Array([_p(r, 11, 0), _p(r, 13.5, 6), _p(r, 11, 12)]), WOOD_D * md, 2.0 * s)
			ci.draw_polyline(PackedVector2Array([_p(r, 11, 0), _p(r, 4, 6), _p(r, 11, 12)]), STRING * md, 1.0)
			ci.draw_rect(_q(r, 4, 5.5, 12, 1), STEEL * md)
			ci.draw_rect(_q(r, 2, 12, 3, 2), tcol)
		22:
			var fh := 7.0 + sin(tm * 9.0 + r.position.x) * 1.5
			ci.draw_line(_p(r, 3, 14), _p(r, 13, 11), WOOD_D * md, 2.0 * s)
			ci.draw_line(_p(r, 3, 11), _p(r, 13, 14), WOOD * md, 2.0 * s)
			ci.draw_colored_polygon(PackedVector2Array([_p(r, 4, 13), _p(r, 8, 13 - fh), _p(r, 12, 13)]), Color(1.0, 0.5, 0.12))
			ci.draw_colored_polygon(PackedVector2Array([_p(r, 6, 13), _p(r, 8, 13 - fh * 0.6), _p(r, 10, 13)]), Color(1.0, 0.9, 0.4))
			ci.draw_rect(_q(r, 1, 13, 4, 3), STONE * md)
			ci.draw_rect(_q(r, 6, 14, 4, 2), STONE.darkened(0.15) * md)
			ci.draw_rect(_q(r, 11, 13, 4, 3), STONE * md)
		23:
			ci.draw_rect(_q(r, 7, 9, 2, 7), IRON * md)
			ci.draw_rect(_q(r, 4, 1, 8, 8), IRON * md)
			ci.draw_rect(_q(r, 5, 2, 6, 6), Color(1.0, 0.86, 0.45, 0.85 + 0.15 * sin(tm * 5.0)))
			ci.draw_rect(_q(r, 5, 0, 6, 1), IRON.darkened(0.2) * md)
		24:
			ci.draw_rect(_q(r, 0, 0, 16, 5), WOOD * md)
			ci.draw_rect(_q(r, 0, 4, 16, 1), WOOD_D * md)
			ci.draw_rect(_q(r, 3, 0, 2, 5), IRON * md)
			ci.draw_rect(_q(r, 11, 0, 2, 5), IRON * md)
			ci.draw_rect(_q(r, 7, 1, 2, 2), tcol)
		25:
			ci.draw_rect(_q(r, 0, 0, 3, 16), WOOD * md)
			ci.draw_rect(_q(r, 0, 3, 3, 2), IRON * md)
			ci.draw_rect(_q(r, 0, 11, 3, 2), IRON * md)
			ci.draw_rect(_q(r, 0, 7, 3, 2), tcol)
		26:
			ci.draw_rect(r, STONE.darkened(0.25) * md)
			ci.draw_rect(_q(r, 1, 1, 14, 14), STONE * md)
			ci.draw_rect(_q(r, 0, 7, 16, 2), Color(0.08, 0.08, 0.1))
			ci.draw_rect(_q(r, 1, 1, 3, 2), tcol)
		27:
			ci.draw_rect(r, RUIN * md)
			ci.draw_rect(_q(r, 0, 7, 16, 1), RUIN.darkened(0.35) * md)
			ci.draw_rect(_q(r, 0, 15, 16, 1), RUIN.darkened(0.35) * md)
			ci.draw_rect(_q(r, 5, 0, 1, 7), RUIN.darkened(0.35) * md)
			ci.draw_rect(_q(r, 11, 8, 1, 7), RUIN.darkened(0.35) * md)
			if int(r.position.x / 16.0 + r.position.y / 16.0) % 3 == 0:
				ci.draw_rect(_q(r, 1, 0, 4, 2), Color(0.35, 0.55, 0.25) * md)
		28:
			ci.draw_rect(_q(r, 1, 6, 14, 10), WOOD_D * md)
			ci.draw_rect(_q(r, 1, 4, 14, 4), WOOD * md)
			ci.draw_rect(_q(r, 1, 8, 14, 1), GOLD * md)
			ci.draw_rect(_q(r, 7, 8, 2, 3), GOLD * md)
		29:
			var col: Color = Color("d4a017")
			ci.draw_rect(_q(r, 1, 8, 14, 8), Color("6d4c41") * md)
			ci.draw_rect(_q(r, 0, 2, 16, 4), col * md)
			for i in 4:
				ci.draw_rect(_q(r, i * 4, 2, 2, 4), col.lightened(0.4) * md)
			ci.draw_rect(_q(r, 1, 6, 1, 2), Color("4e342e") * md)
			ci.draw_rect(_q(r, 14, 6, 1, 2), Color("4e342e") * md)
		_:
			ci.draw_rect(r, Color.MAGENTA)


static func draw_icon(ci: CanvasItem, item: String, r: Rect2, items_tex: Texture2D = null) -> void:
	if Net.TOOLS.has(item):
		var s := r.size.x / 26.0
		var ang := -PI * 0.25
		ci.draw_set_transform(r.get_center() - Vector2.from_angle(ang) * 7.0 * s, ang, Vector2(s, s))
		draw_tool_local(ci, item, 0.6 if item == "bow" else 0.0)
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	if item == "arrow":
		var sd := r.size.x / 16.0
		var aa := r.position + Vector2(r.size.x * 0.2, r.size.y * 0.8)
		var bb := r.position + Vector2(r.size.x * 0.8, r.size.y * 0.2)
		var dv := (bb - aa).normalized()
		ci.draw_line(aa, bb, WOOD.lightened(0.2), maxf(1.0, sd * 1.2))
		ci.draw_colored_polygon(PackedVector2Array([bb + dv * 3.0 * sd, bb + dv.orthogonal() * 2.0 * sd, bb - dv.orthogonal() * 2.0 * sd]), STEEL)
		ci.draw_line(aa, aa + (dv + dv.orthogonal()) * 3.0 * sd, STRING, 1.0)
		ci.draw_line(aa, aa + (dv - dv.orthogonal()) * 3.0 * sd, STRING, 1.0)
		return
	if item == "bomb":
		var s := r.size.x / 16.0
		var cp := r.get_center()
		ci.draw_circle(cp, 5.0 * s, Color(0.18, 0.18, 0.22))
		ci.draw_rect(Rect2(cp.x - 1.5 * s, cp.y - 7.5 * s, 3.0 * s, 3.0 * s), Color(0.55, 0.45, 0.3))
		ci.draw_circle(cp + Vector2(0, -8.0 * s), 2.0 * s, Color(1.0, 0.8, 0.2))
		return
	if item == "rope":
		var s := r.size.x / 16.0
		var cp := r.get_center()
		ci.draw_arc(cp, 5.0 * s, 0.0, TAU, 12, Color(0.76, 0.6, 0.38), 2.5 * s)
		ci.draw_line(cp + Vector2(-3, 0) * s, cp + Vector2(5, 4) * s, Color(0.65, 0.5, 0.3), 2.0 * s)
		return
	if item == "shop_kit":
		var s := r.size.x / 16.0
		ci.draw_rect(Rect2(r.position.x + 2 * s, r.position.y + 6 * s, 12 * s, 8 * s), Color("6d4c41"))
		ci.draw_rect(Rect2(r.position.x + 1 * s, r.position.y + 2 * s, 14 * s, 4 * s), Color("d4a017"))
		return
	if item in ["fire_arrow", "bomb_arrow", "poison_arrow"]:
		var tip_col: Color = Color("ff5722") if item == "fire_arrow" else (Color("424242") if item == "bomb_arrow" else Color("7cb342"))
		var sd := r.size.x / 16.0
		var aa := r.position + Vector2(r.size.x * 0.2, r.size.y * 0.8)
		var bb := r.position + Vector2(r.size.x * 0.8, r.size.y * 0.2)
		var dv := (bb - aa).normalized()
		ci.draw_line(aa, bb, WOOD.lightened(0.2), maxf(1.0, sd * 1.2))
		ci.draw_colored_polygon(PackedVector2Array([bb + dv * 4.0 * sd, bb + dv.orthogonal() * 2.5 * sd, bb - dv.orthogonal() * 2.5 * sd]), tip_col)
		ci.draw_line(aa, aa + (dv + dv.orthogonal()) * 3.0 * sd, STRING, 1.0)
		ci.draw_line(aa, aa + (dv - dv.orthogonal()) * 3.0 * sd, STRING, 1.0)
		return
	var idx := ITEM_ORDER.find(item)
	if items_tex and idx >= 0:
		ci.draw_texture_rect_region(items_tex, r, Rect2(idx * 16, 0, 16, 16))
		return
	var b: int = Net.ITEM_BLOCK.get(item, -1)
	if b >= 16:
		draw_block_shape(ci, b, r, Net.TEAM_COLORS[0], Time.get_ticks_msec() / 1000.0, false)
		return
	ci.draw_rect(r.grow(-r.size.x * 0.15), Color(0.6, 0.6, 0.65))
	ci.draw_string(ThemeDB.fallback_font, r.position + Vector2(2, r.size.y * 0.65), item.substr(0, 2).to_upper(), HORIZONTAL_ALIGNMENT_CENTER, r.size.x - 4, int(r.size.y * 0.4))


# PixelSiege patch v1 (bombs, TNT, shops, crafting, rope)

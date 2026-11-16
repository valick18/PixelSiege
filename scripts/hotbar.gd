extends Control
# Піксельний HUD: панель рахунку, слоти інвентаря з іконками (масштаб x2, без розтягування), смуга здоров'я.

var game
const S := 48.0
const GAP := 6.0
const EDGE := Color(0.02, 0.02, 0.05, 1.0)
const RIM := Color(0.36, 0.41, 0.55)
const RIM_HI := Color(0.55, 0.62, 0.74)
const GOLD := Color(0.996, 0.682, 0.204)
const GOLD_HI := Color(0.996, 0.906, 0.38)


func _process(_dt: float) -> void:
	queue_redraw()


func _cross(r: Rect2, c: Color, k: float) -> void:
	draw_rect(Rect2(r.position.x + k, r.position.y, r.size.x - 2.0 * k, r.size.y), c)
	draw_rect(Rect2(r.position.x, r.position.y + k, r.size.x, r.size.y - 2.0 * k), c)


func _frame(r: Rect2, fill: Color, rim: Color, hi: Color) -> void:
	_cross(r.grow(2), EDGE, 4)
	_cross(r, rim, 2)
	draw_rect(r.grow(-2), fill)
	draw_rect(Rect2(r.position.x + 2, r.position.y + 2, r.size.x - 4, 2), hi)
	draw_rect(Rect2(r.position.x + 2, r.end.y - 4, r.size.x - 4, 2), Color(0, 0, 0, 0.3))


func _text(pos: Vector2, t: String, size: int, col: Color, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0) -> void:
	var f := ThemeDB.fallback_font
	draw_string_outline(f, pos, t, align, width, size, 5, Color(0.03, 0.03, 0.07))
	draw_string(f, pos, t, align, width, size, col)


func _draw() -> void:
	if game == null or game.flags.is_empty():
		return
	var vs := get_viewport_rect().size
	var me: int = game.multiplayer.get_unique_id()
	var d: Dictionary = game.cl.get(me, {})
	var inv: Array = d.get("inv", [])
	var hp: int = d.get("hp", 100)
	var p = game.players_root.get_node_or_null(str(me))
	var sel: int = p.selected if p else 0
	var items = Net.tex("res://assets/items.png")
	# ---- hotbar
	var total := 10.0 * S + 9.0 * GAP
	var x0 := floorf((vs.x - total) * 0.5)
	var y0 := vs.y - S - 16.0
	_frame(Rect2(x0 - 10, y0 - 10, total + 20, S + 20), Color(0.05, 0.05, 0.1, 0.72), Color(0.2, 0.23, 0.33), Color(0.3, 0.34, 0.46))
	for i in 10:
		var r := Rect2(x0 + i * (S + GAP), y0, S, S)
		var on := i == sel
		if on:
			_frame(r.grow(2), Color(0.22, 0.18, 0.2, 0.98), GOLD, GOLD_HI)
		else:
			_frame(r, Color(0.12, 0.13, 0.22, 0.95), RIM, RIM_HI)
		if i < inv.size() and inv[i].has("i"):
			var idx: int = game.ITEM_ORDER.find(inv[i]["i"])
			if items and idx >= 0:
				draw_texture_rect_region(items, Rect2(r.position + Vector2(8, 8), Vector2(32, 32)), Rect2(idx * 16, 0, 16, 16))
			var n: int = inv[i]["n"]
			if n > 1:
				_text(r.position + Vector2(0, S - 5), str(n), 13, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, S - 5)
		_text(r.position + Vector2(5, 13), str((i + 1) % 10), 11, GOLD_HI if on else Color(0.75, 0.8, 0.9))
	if sel < inv.size() and inv[sel].has("i"):
		_text(Vector2(x0, y0 - 18), str(inv[sel]["i"]).capitalize(), 14, GOLD_HI, HORIZONTAL_ALIGNMENT_CENTER, total)
	# ---- health
	var hb := Rect2(30, vs.y - 40, 230, 22)
	_frame(hb, Color(0.12, 0.05, 0.08, 0.95), Color(0.45, 0.2, 0.25), Color(0.6, 0.3, 0.35))
	var fw := (hb.size.x - 8) * clampf(hp / 100.0, 0.0, 1.0)
	draw_rect(Rect2(hb.position + Vector2(4, 4), Vector2(fw, hb.size.y - 8)), Color("e43b44"))
	draw_rect(Rect2(hb.position + Vector2(4, 4), Vector2(fw, 4)), Color("f6757a"))
	draw_rect(Rect2(hb.position + Vector2(4, hb.size.y - 7), Vector2(fw, 3)), Color("a22633"))
	for k in range(1, 10):
		draw_rect(Rect2(hb.position.x + 4 + (hb.size.x - 8) * k / 10.0, hb.position.y + 4, 1, hb.size.y - 8), Color(0, 0, 0, 0.25))
	var heart = Net.tex("res://assets/ui_heart.png")
	if heart:
		draw_texture_rect(heart, Rect2(hb.position + Vector2(-18, -1), Vector2(24, 24)), false)
	_text(hb.position + Vector2(0, 16), "%d / 100" % hp, 13, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, hb.size.x)
	# ---- score panel
	var pw := 520.0
	var top := Rect2(floorf((vs.x - pw) * 0.5), 8, pw, 72)
	_frame(top, Color(0.06, 0.06, 0.12, 0.8), Color(0.25, 0.29, 0.42), Color(0.36, 0.41, 0.55))
	var cxm := top.position.x + pw * 0.5
	var badges := [Rect2(cxm - 118, 16, 60, 36), Rect2(cxm + 58, 16, 60, 36)]
	for t in 2:
		var tc: Color = Net.TEAM_COLORS[t]
		var b: Rect2 = badges[t]
		_frame(b, tc.darkened(0.45), tc, tc.lightened(0.35))
		_text(Vector2(b.position.x, 45), str(game.score[t]), 26, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, b.size.x)
		var f = game.flags[t]
		var st := "HOME"
		var sc := Color(0.5, 0.9, 0.5)
		if f.carrier != 0:
			st = "TAKEN"
			sc = Color(1.0, 0.45, 0.3)
		elif not f.home:
			st = "DROPPED"
			sc = GOLD_HI
		_text(Vector2(b.position.x - 20, 70), st, 12, sc, HORIZONTAL_ALIGNMENT_CENTER, b.size.x + 40)
	_text(Vector2(cxm - 50, 42), "VS", 18, Color(0.8, 0.85, 0.95), HORIZONTAL_ALIGNMENT_CENTER, 100)
	var phase := "BATTLE"
	if game.prep_left > 0.0:
		phase = "PREP %d:%02d" % [floori(game.prep_left / 60.0), int(game.prep_left) % 60]
	_text(Vector2(top.position.x + 14, 36), phase, 15, GOLD_HI)
	_text(Vector2(top.position.x + 14, 58), "First to %d" % game.WIN_SCORE, 12, Color(0.75, 0.8, 0.9))
	var tod: String = ["Day", "Sunset", "Night", "Dawn"][floori(fmod(game.match_time, 480.0) / 120.0)]
	_text(Vector2(top.position.x, 36), tod, 15, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, pw - 14)
	_text(Vector2(top.position.x, 58), str(game.weather).capitalize(), 12, Color(0.75, 0.8, 0.9), HORIZONTAL_ALIGNMENT_RIGHT, pw - 14)

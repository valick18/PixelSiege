extends PanelContainer
# Вікно крафту (C або E біля робочого столу): вкладки категорій, сітка рецептів з іконками,
# деталі з вартістю (зелений - вистачає, червоний - ні), потрібна станція (Руки / Робочий стіл / Облогова майстерня),
# кнопки x1 / x5. Біля прапора бази або скрині-сховища ресурси беруться й із командного сховища.

const LookS = preload("res://scripts/look.gd")
const InvS = preload("res://scripts/inventory.gd")
const T := 16
var game
var cat := "All"
var selected := "workbench"
var grid: GridContainer
var title_l: Label
var desc_l: Label
var station_l: Label
var here_l: Label
var cost_box: VBoxContainer
var btn1: Button
var btn5: Button
var big_icon: Control
var cards := {}
var _t := 0.0


static func panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.08, 0.14, 0.97)
	sb.border_color = Color(0.36, 0.41, 0.55)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(12)
	return sb


func _ready() -> void:
	custom_minimum_size = Vector2(760, 460)
	add_theme_stylebox_override("panel", panel_style())
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	add_child(root)
	var head := HBoxContainer.new()
	root.add_child(head)
	var t := Label.new()
	t.text = "Crafting"
	t.add_theme_font_size_override("font_size", 22)
	head.add_child(t)
	here_l = Label.new()
	here_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	here_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	here_l.add_theme_color_override("font_color", Color(0.75, 0.8, 0.9))
	head.add_child(here_l)
	var x := Button.new()
	x.text = "  X  "
	x.focus_mode = Control.FOCUS_NONE
	x.pressed.connect(func(): visible = false; game._refresh_ui_flag())
	head.add_child(x)
	var tabs := HBoxContainer.new()
	root.add_child(tabs)
	var bg := ButtonGroup.new()
	for c in Net.CATEGORIES:
		var b := Button.new()
		b.text = c
		b.toggle_mode = true
		b.button_group = bg
		b.focus_mode = Control.FOCUS_NONE
		b.button_pressed = c == cat
		b.pressed.connect(_set_cat.bind(c))
		tabs.add_child(b)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	root.add_child(body)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(440, 340)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	grid = GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(grid)
	var det := VBoxContainer.new()
	det.custom_minimum_size = Vector2(270, 0)
	det.add_theme_constant_override("separation", 6)
	body.add_child(det)
	big_icon = Control.new()
	big_icon.custom_minimum_size = Vector2(64, 64)
	big_icon.draw.connect(func(): LookS.draw_icon(big_icon, selected, Rect2(0, 0, 64, 64), Net.tex("res://assets/items.png")))
	det.add_child(big_icon)
	title_l = Label.new()
	title_l.add_theme_font_size_override("font_size", 18)
	det.add_child(title_l)
	desc_l = Label.new()
	desc_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_l.custom_minimum_size = Vector2(260, 0)
	det.add_child(desc_l)
	station_l = Label.new()
	det.add_child(station_l)
	cost_box = VBoxContainer.new()
	det.add_child(cost_box)
	var bb := HBoxContainer.new()
	det.add_child(bb)
	btn1 = Button.new()
	btn1.text = "Craft"
	btn1.focus_mode = Control.FOCUS_NONE
	btn1.custom_minimum_size = Vector2(120, 34)
	btn1.pressed.connect(func(): game.send_craft(selected, 1))
	bb.add_child(btn1)
	btn5 = Button.new()
	btn5.text = "Craft x5"
	btn5.focus_mode = Control.FOCUS_NONE
	btn5.custom_minimum_size = Vector2(120, 34)
	btn5.pressed.connect(func(): game.send_craft(selected, 5))
	bb.add_child(btn5)
	var foot := Label.new()
	foot.text = "Near your base flag or a storage chest, team storage resources are used too.  E at a workbench opens this window."
	foot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	foot.add_theme_font_size_override("font_size", 12)
	foot.add_theme_color_override("font_color", Color(0.65, 0.7, 0.8))
	root.add_child(foot)
	_rebuild()


func open() -> void:
	_rebuild()


func _set_cat(c: String) -> void:
	cat = c
	_rebuild()


func _process(dt: float) -> void:
	if not visible:
		return
	_t += dt
	if _t >= 0.3:
		_t = 0.0
		_refresh()


func _rebuild() -> void:
	if grid == null:
		return
	for ch in grid.get_children():
		ch.queue_free()
	cards.clear()
	var items_tex = Net.tex("res://assets/items.png")
	for r in Net.RECIPES:
		if cat != "All" and Net.RECIPES[r].cat != cat:
			continue
		var b := Button.new()
		b.custom_minimum_size = Vector2(80, 80)
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = r.capitalize()
		b.pressed.connect(_select.bind(r))
		var ic := Control.new()
		ic.position = Vector2(22, 8)
		ic.size = Vector2(36, 36)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ic.draw.connect(func(): LookS.draw_icon(ic, r, Rect2(0, 0, 36, 36), items_tex))
		b.add_child(ic)
		var l := Label.new()
		l.text = r.capitalize()
		l.add_theme_font_size_override("font_size", 10)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.position = Vector2(0, 52)
		l.size = Vector2(80, 20)
		l.clip_text = true
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(l)
		grid.add_child(b)
		cards[r] = b
	_refresh()


func _select(r: String) -> void:
	selected = r
	_refresh()


func _near_store(p) -> bool:
	var w = game.world
	if p.position.distance_to(w.flag_pos(p.team)) < 110.0:
		return true
	var pc := Vector2i(floori(p.position.x / T), floori(p.position.y / T))
	for dx in range(-5, 6):
		for dy in range(-5, 6):
			var c := pc + Vector2i(dx, dy)
			if w.get_cell(c) == w.STORAGE and int(w.owner_team.get(c, -1)) == p.team and p.position.distance_to(Vector2(c) * T + Vector2(8, 8)) < 80.0:
				return true
	return false


func _have(inv: Array, k: String, near: bool, team: int) -> int:
	var n := InvS.count(inv, k)
	if near and k in Net.RESOURCES:
		n += int(game.store[team][k])
	return n


func _can(r: String, inv: Array, near: bool, team: int, stn: Dictionary) -> bool:
	var rec: Dictionary = Net.RECIPES[r]
	if not stn.get(rec.station, false):
		return false
	for k in rec.cost:
		if _have(inv, k, near, team) < int(rec.cost[k]):
			return false
	return true


func _refresh() -> void:
	if game == null or title_l == null:
		return
	var p = game.player_node(game.multiplayer.get_unique_id())
	if p == null:
		return
	var inv: Array = game.cl.get(p.id, {}).get("inv", [])
	var near := _near_store(p)
	var stn: Dictionary = game.local_stations()
	var here := "Stations nearby: Hands"
	if stn.workbench:
		here += ", Workbench"
	if stn.siege_workshop:
		here += ", Siege workshop"
	if near:
		here += "   |   team storage available"
	here_l.text = here
	for r in cards:
		var ok := _can(r, inv, near, p.team, stn)
		cards[r].self_modulate = Color(1, 1, 1) if ok else Color(0.6, 0.6, 0.65)
		cards[r].modulate = Color(1.15, 1.1, 0.8) if r == selected else Color.WHITE
	var rec: Dictionary = Net.RECIPES.get(selected, {})
	if rec.is_empty():
		return
	title_l.text = "%s  x%d" % [selected.capitalize(), int(rec.n)]
	desc_l.text = rec.get("desc", "")
	var has_st: bool = stn.get(rec.station, false)
	station_l.text = "Station: %s%s" % [Net.STATIONS[rec.station], "" if has_st else "  (not nearby)"]
	station_l.add_theme_color_override("font_color", Color(0.55, 0.95, 0.55) if has_st else Color(1.0, 0.45, 0.4))
	for ch in cost_box.get_children():
		ch.queue_free()
	for k in rec.cost:
		var have := _have(inv, k, near, p.team)
		var need: int = rec.cost[k]
		var l := Label.new()
		l.text = "  %s:  %d / %d" % [String(k).capitalize(), have, need]
		l.add_theme_color_override("font_color", Color(0.55, 0.95, 0.55) if have >= need else Color(1.0, 0.45, 0.4))
		cost_box.add_child(l)
	var ok := _can(selected, inv, near, p.team, stn)
	btn1.disabled = not ok
	btn5.disabled = not ok
	big_icon.queue_redraw()

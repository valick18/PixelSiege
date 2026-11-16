extends PanelContainer
# Вікно крафту (C або E біля робочого столу): вкладки категорій, список рецептів з іконками (ItemList),
# деталі з вартістю (зелений - вистачає, червоний - ні), потрібна станція (Руки / Робочий стіл / Облогова майстерня),
# кнопки x1 / x5. Біля прапора бази або скрині-сховища ресурси беруться й із командного сховища.
# Список рецептів - звичайні кнопки з текстом та іконкою в сітці на 3 колонки (без ScrollContainer / ItemList),
# над списком показується кількість рецептів. Якщо рецептів 0, у вікні буде червоне повідомлення, а в Output - лог.

const LookS = preload("res://scripts/look.gd")
const InvS = preload("res://scripts/inventory.gd")
const T := 16
var game
var cat := "All"
var selected := "workbench"
var list: GridContainer
var count_l: Label
var btns: Array = []
var title_l: Label
var desc_l: Label
var station_l: Label
var here_l: Label
var cost_box: VBoxContainer
var btn1: Button
var btn5: Button
var big_icon: Control
var shown: Array = []   # назви рецептів у порядку рядків ItemList
var _icons := {}
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
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(460, 300)
	body.add_child(left)
	count_l = Label.new()
	count_l.add_theme_font_size_override("font_size", 12)
	left.add_child(count_l)
	list = GridContainer.new()
	list.columns = 3
	list.add_theme_constant_override("h_separation", 4)
	list.add_theme_constant_override("v_separation", 4)
	left.add_child(list)
	var det := VBoxContainer.new()
	det.custom_minimum_size = Vector2(260, 0)
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
	desc_l.custom_minimum_size = Vector2(250, 0)
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
	# ВАЖЛИВО: Label з переносом рядків без мінімальної ширини на першому кадрі має ширину 0,
	# через що його висота стає величезною і вікно розтягується на весь екран, а весь вміст
	# (заголовок, вкладки, рецепти) опиняється за межами екрана. Саме через це крафт "був порожній".
	foot.custom_minimum_size = Vector2(730, 0)
	foot.add_theme_font_size_override("font_size", 12)
	foot.add_theme_color_override("font_color", Color(0.65, 0.7, 0.8))
	root.add_child(foot)
	_rebuild()


func open() -> void:
	_rebuild()
	_fit.call_deferred()


# Стискає вікно до його реального розміру і ставить по центру екрана.
func _fit() -> void:
	reset_size()
	if game:
		game._center(self)


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


# Іконка рецепта як текстура для ItemList: спрайт з items.png або кольоровий квадрат блока.
func _icon_tex(r: String) -> Texture2D:
	if _icons.has(r):
		return _icons[r]
	var tex: Texture2D = null
	var at = Net.tex("res://assets/items.png")
	var idx: int = LookS.ITEM_ORDER.find(r)
	if at and idx >= 0:
		var a := AtlasTexture.new()
		a.atlas = at
		a.region = Rect2(idx * 16, 0, 16, 16)
		tex = a
	else:
		var col := Color(0.62, 0.6, 0.58)
		if r == "arrow":
			col = Color(0.85, 0.7, 0.45)
		elif r == "wall":
			col = Color(0.42, 0.36, 0.34)
		elif Net.ITEM_BLOCK.has(r) and game and game.world:
			col = game.world.COLORS.get(int(Net.ITEM_BLOCK[r]), col)
		var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
		img.fill(col.darkened(0.45))
		img.fill_rect(Rect2i(1, 1, 14, 14), col)
		img.fill_rect(Rect2i(2, 2, 12, 3), col.lightened(0.25))
		tex = ImageTexture.create_from_image(img)
	_icons[r] = tex
	return tex


func _rebuild() -> void:
	if list == null:
		return
	for ch in list.get_children():
		list.remove_child(ch)
		ch.queue_free()
	btns.clear()
	shown.clear()
	for r in Net.RECIPES.keys():
		var rec: Dictionary = Net.RECIPES[r]
		if cat != "All" and String(rec.get("cat", "")) != cat:
			continue
		var b := Button.new()
		b.text = "%s x%d" % [String(r).capitalize(), int(rec.get("n", 1))]
		b.icon = _icon_tex(r)
		b.expand_icon = false
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(150, 34)
		b.focus_mode = Control.FOCUS_NONE
		b.clip_text = true
		b.tooltip_text = String(rec.get("desc", ""))
		b.add_theme_font_size_override("font_size", 11)
		b.pressed.connect(_on_pick.bind(shown.size()))
		list.add_child(b)
		btns.append(b)
		shown.append(r)
	if not shown.is_empty() and not selected in shown:
		selected = shown[0]
	if shown.is_empty():
		count_l.text = "No recipes found (Net.RECIPES has %d). Please send a screenshot of the Output panel." % Net.RECIPES.size()
		count_l.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4))
	else:
		count_l.text = "%d recipes  -  click one to see the cost" % shown.size()
		count_l.add_theme_color_override("font_color", Color(0.75, 0.8, 0.9))
	print("[Craft] category %s: %d of %d recipes shown" % [cat, shown.size(), Net.RECIPES.size()])
	_refresh()


func _on_pick(i: int) -> void:
	if i >= 0 and i < shown.size():
		_select(shown[i])


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
	var inv: Array = []
	var near := false
	var team := 0
	var stn: Dictionary = {"hand": true, "workbench": false, "siege_workshop": false}
	if p:
		inv = game.cl.get(p.id, {}).get("inv", [])
		near = _near_store(p)
		team = p.team
		stn = game.local_stations()
	var here := "Stations nearby: Hands"
	if stn.workbench:
		here += ", Workbench"
	if stn.siege_workshop:
		here += ", Siege workshop"
	if near:
		here += "   |   team storage available"
	here_l.text = here
	for i in mini(shown.size(), btns.size()):
		var ok := _can(shown[i], inv, near, team, stn)
		btns[i].self_modulate = Color(1, 1, 1) if ok else Color(0.62, 0.62, 0.68)
		btns[i].modulate = Color(1.15, 1.1, 0.8) if shown[i] == selected else Color.WHITE
	var rec: Dictionary = Net.RECIPES.get(selected, {})
	if rec.is_empty():
		return
	title_l.text = "%s  x%d" % [selected.capitalize(), int(rec.n)]
	desc_l.text = rec.get("desc", "")
	var has_st: bool = stn.get(rec.station, false)
	station_l.text = "Station: %s%s" % [Net.STATIONS[rec.station], "" if has_st else "  (not nearby)"]
	station_l.add_theme_color_override("font_color", Color(0.55, 0.95, 0.55) if has_st else Color(1.0, 0.45, 0.4))
	for ch in cost_box.get_children():
		cost_box.remove_child(ch)
		ch.queue_free()
	for k in rec.cost:
		var have := _have(inv, k, near, team)
		var need: int = rec.cost[k]
		var l := Label.new()
		l.text = "  %s:  %d / %d" % [String(k).capitalize(), have, need]
		l.add_theme_color_override("font_color", Color(0.55, 0.95, 0.55) if have >= need else Color(1.0, 0.45, 0.4))
		cost_box.add_child(l)
	var ok := p != null and _can(selected, inv, near, team, stn)
	btn1.disabled = not ok
	btn5.disabled = not ok
	big_icon.queue_redraw()

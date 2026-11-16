extends PanelContainer
# Вікно інвентаря (Tab / I): інструменти класу (тільки перегляд), 7 слотів панелі + 14 слотів рюкзака.
# ЛКМ по слоту - взяти, ЛКМ по іншому - переставити / об'єднати. ПКМ або кнопка Drop - викинути на землю.

const LookS = preload("res://scripts/look.gd")
const CraftS = preload("res://scripts/ui/craft_ui.gd")
var game
var pick := -1
var slots: Array = []
var tools_l: Label
var info_l: Label
var _t := 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(470, 0)
	add_theme_stylebox_override("panel", CraftS.panel_style())
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	add_child(root)
	var t := Label.new()
	t.text = "Inventory"
	t.add_theme_font_size_override("font_size", 22)
	root.add_child(t)
	tools_l = Label.new()
	tools_l.add_theme_color_override("font_color", Color(0.8, 0.62, 0.38))
	root.add_child(tools_l)
	for sec in [["Hotbar (keys 4-0)", 0, 7], ["Backpack", 7, 21]]:
		var l := Label.new()
		l.text = sec[0]
		l.add_theme_color_override("font_color", Color(0.75, 0.8, 0.9))
		root.add_child(l)
		var g := GridContainer.new()
		g.columns = 7
		root.add_child(g)
		for i in range(sec[1], sec[2]):
			var b := Button.new()
			b.custom_minimum_size = Vector2(58, 58)
			b.focus_mode = Control.FOCUS_NONE
			b.pressed.connect(_click.bind(i))
			b.gui_input.connect(_slot_input.bind(i))
			var ic := Control.new()
			ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
			ic.size = Vector2(58, 58)
			ic.draw.connect(_draw_slot.bind(i, ic))
			b.add_child(ic)
			g.add_child(b)
			slots.append([b, ic])
	info_l = Label.new()
	info_l.text = "LMB: pick / move   RMB: drop on the ground"
	info_l.add_theme_font_size_override("font_size", 12)
	root.add_child(info_l)
	var hb := HBoxContainer.new()
	root.add_child(hb)
	for it in [["Drop selected", _drop_sel], ["Sort backpack", func(): game.send_sort()], ["Close", func(): visible = false; game._refresh_ui_flag()]]:
		var b2 := Button.new()
		b2.text = it[0]
		b2.focus_mode = Control.FOCUS_NONE
		b2.pressed.connect(it[1])
		hb.add_child(b2)


func open() -> void:
	pick = -1
	_refresh()


func _inv() -> Array:
	return game.cl.get(game.multiplayer.get_unique_id(), {}).get("inv", [])


func _click(i: int) -> void:
	var inv := _inv()
	if pick < 0:
		if i < inv.size() and not inv[i].is_empty():
			pick = i
	else:
		if pick != i:
			game.send_swap(pick, i)
		pick = -1
	_refresh()


func _slot_input(ev: InputEvent, i: int) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT:
		game.send_drop(i)
		pick = -1


func _drop_sel() -> void:
	if pick >= 0:
		game.send_drop(pick)
		pick = -1


func _draw_slot(i: int, ic: Control) -> void:
	var inv := _inv()
	if i == pick:
		ic.draw_rect(Rect2(2, 2, 54, 54), Color(1.0, 0.8, 0.3, 0.35))
	if i >= inv.size() or inv[i].is_empty():
		return
	LookS.draw_icon(ic, inv[i].i, Rect2(13, 10, 32, 32), Net.tex("res://assets/items.png"))
	if int(inv[i].n) > 1:
		ic.draw_string(ThemeDB.fallback_font, Vector2(0, 54), str(inv[i].n), HORIZONTAL_ALIGNMENT_RIGHT, 54, 13)


func _process(dt: float) -> void:
	if not visible:
		return
	_t += dt
	if _t >= 0.2:
		_t = 0.0
		_refresh()


func _refresh() -> void:
	if game == null:
		return
	var p = game.player_node(game.multiplayer.get_unique_id())
	if p:
		var names := []
		for tl in Net.tools_of(p.cls):
			names.append(Net.TOOLS[tl].label)
		tools_l.text = "%s tools (keys 1-3): %s" % [Net.CLASSES[p.cls].label, ", ".join(PackedStringArray(names))]
	var inv := _inv()
	for i in slots.size():
		var b: Button = slots[i][0]
		b.tooltip_text = "" if i >= inv.size() or inv[i].is_empty() else String(inv[i].i).capitalize()
		slots[i][1].queue_redraw()

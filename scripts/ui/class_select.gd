extends PanelContainer
# Вибір класу (після вибору команди або B): 3 графічні картки (Warrior, Archer, Builder) з анімованим персонажем
# у вашому вигляді, роллю, інструментами та здібністю класу (у Builder здібностей немає).

signal chosen(cls: String)
const LookS = preload("res://scripts/look.gd")
const CraftS = preload("res://scripts/ui/craft_ui.gd")
const ORDER := ["warrior", "archer", "engineer"]
var game
var previews: Array = []
var cards: Array = []
var hint_l: Label


func _ready() -> void:
	add_theme_stylebox_override("panel", CraftS.panel_style())
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	add_child(root)
	var t := Label.new()
	t.text = "Choose your class"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 24)
	root.add_child(t)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	root.add_child(row)
	for cname in ORDER:
		var cd: Dictionary = Net.CLASSES[cname]
		var pc := PanelContainer.new()
		pc.custom_minimum_size = Vector2(220, 0)
		row.add_child(pc)
		cards.append([pc, cname])
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 4)
		pc.add_child(vb)
		var pv := Control.new()
		pv.custom_minimum_size = Vector2(200, 120)
		pv.draw.connect(_draw_preview.bind(pv, cname))
		vb.add_child(pv)
		previews.append(pv)
		var n := Label.new()
		n.text = cd.label
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		n.add_theme_font_size_override("font_size", 20)
		n.add_theme_color_override("font_color", cd.color.lightened(0.35))
		vb.add_child(n)
		var role := Label.new()
		role.text = cd.role
		role.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		role.custom_minimum_size = Vector2(200, 0)
		role.add_theme_font_size_override("font_size", 12)
		vb.add_child(role)
		var tl := []
		for tool in cd.tools:
			tl.append(Net.TOOLS[tool].label)
		var tools := Label.new()
		tools.text = "Tools: " + ", ".join(PackedStringArray(tl))
		tools.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tools.custom_minimum_size = Vector2(200, 0)
		tools.add_theme_color_override("font_color", Color(0.8, 0.62, 0.38))
		tools.add_theme_font_size_override("font_size", 12)
		vb.add_child(tools)
		var abl: Array = cd.abilities
		if abl.is_empty():
			var none := Label.new()
			none.text = "Ability: none"
			none.custom_minimum_size = Vector2(200, 0)
			none.add_theme_font_size_override("font_size", 11)
			vb.add_child(none)
		for ab in abl:
			var al := Label.new()
			var key: String = "Hold LMB %.1fs" % float(ab.get("hold_time", 2.5)) if bool(ab.get("hold", false)) else String(ab.get("key", "Q"))
			al.text = "%s  %s (%ds): %s" % [key, ab.name, int(ab.cd), ab.desc]
			al.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			al.custom_minimum_size = Vector2(200, 0)
			al.add_theme_font_size_override("font_size", 11)
			vb.add_child(al)
		var b := Button.new()
		b.text = "Play as %s" % cd.label
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 34)
		b.size_flags_vertical = Control.SIZE_SHRINK_END
		b.pressed.connect(_pick.bind(cname))
		vb.add_child(b)
	hint_l = Label.new()
	hint_l.text = "Only the Builder has a pickaxe (blocks) and an axe (trees). Change class at your base, during preparation or while dead."
	hint_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_l.add_theme_font_size_override("font_size", 12)
	root.add_child(hint_l)


func open() -> void:
	_refresh()


func _pick(cname: String) -> void:
	game.send_class(cname)
	chosen.emit(cname)


func _process(_dt: float) -> void:
	if visible:
		for pv in previews:
			pv.queue_redraw()


func _refresh() -> void:
	var mine: String = Net.players.get(game.multiplayer.get_unique_id(), {}).get("cls", "")
	for c in cards:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.1, 0.11, 0.18)
		sb.border_color = Color(0.996, 0.682, 0.204) if c[1] == mine else Color(0.3, 0.34, 0.46)
		sb.set_border_width_all(3 if c[1] == mine else 1)
		sb.set_corner_radius_all(6)
		sb.set_content_margin_all(8)
		c[0].add_theme_stylebox_override("panel", sb)


func _draw_preview(pv: Control, cname: String) -> void:
	var me: int = game.multiplayer.get_unique_id()
	var info: Dictionary = Net.players.get(me, {})
	var look := LookS.sanitize(info.get("look", Net.my_look()))
	var tm := Time.get_ticks_msec() / 1000.0
	var tool: String = Net.CLASSES[cname].tools[0]
	var sw := fmod(tm, 2.0)
	var pose := {"face": 1, "t": tm, "walk": 0.6, "tool": tool, "aim": -0.3, "scale": 3.5, "offset": Vector2(100, 66),
		"swing": sw / 0.4 if sw < 0.4 and tool != "bow" else -1.0, "draw": clampf(sw - 0.5, 0.0, 1.0) if tool == "bow" else 0.0}
	LookS.draw_char(pv, look, int(info.get("team", 0)), cname, pose)

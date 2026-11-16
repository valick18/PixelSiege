extends PanelContainer
# Редактор зовнішнього вигляду персонажа (головне меню): шкіра, зачіска, колір волосся, очі, одяг, взуття,
# головний убір, борода. Анімований перегляд з вибором класу і команди. Зберігається в user://settings.cfg
# і передається іншим гравцям при підключенні.

signal closed
const LookS = preload("res://scripts/look.gd")
const CraftS = preload("res://scripts/ui/craft_ui.gd")
const ROWS := [["skin", "Skin"], ["hair", "Hair style"], ["hair_col", "Hair color"], ["eyes", "Eyes"], ["shirt", "Shirt"], ["pants", "Pants"], ["boots", "Boots"], ["hat", "Headwear"], ["beard", "Beard"]]
const CLS := ["warrior", "archer", "engineer", "support"]
var look := {}
var prev_cls := "warrior"
var prev_team := 0
var preview: Control
var vals := {}
var swatches := {}
var classic_cb: CheckBox


func _ready() -> void:
	look = Net.my_look()
	add_theme_stylebox_override("panel", CraftS.panel_style())
	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", 16)
	add_child(root)
	var left := VBoxContainer.new()
	root.add_child(left)
	preview = Control.new()
	preview.custom_minimum_size = Vector2(240, 280)
	preview.draw.connect(_draw_preview)
	left.add_child(preview)
	var ob := OptionButton.new()
	for c in CLS:
		ob.add_item(Net.CLASSES[c].label)
	ob.item_selected.connect(func(i): prev_cls = CLS[i])
	left.add_child(ob)
	var tb := HBoxContainer.new()
	left.add_child(tb)
	for t in 2:
		var b := Button.new()
		b.text = Net.TEAM_NAMES[t]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func(): prev_team = t)
		tb.add_child(b)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	root.add_child(right)
	var title := Label.new()
	title.text = "Character appearance"
	title.add_theme_font_size_override("font_size", 22)
	right.add_child(title)
	for r in ROWS:
		var key: String = r[0]
		var h := HBoxContainer.new()
		right.add_child(h)
		var l := Label.new()
		l.text = r[1]
		l.custom_minimum_size = Vector2(110, 0)
		h.add_child(l)
		var bl := Button.new()
		bl.text = " < "
		bl.pressed.connect(_change.bind(key, -1))
		h.add_child(bl)
		var sw := ColorRect.new()
		sw.custom_minimum_size = Vector2(28, 22)
		h.add_child(sw)
		swatches[key] = sw
		var v := Label.new()
		v.custom_minimum_size = Vector2(100, 0)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		h.add_child(v)
		vals[key] = v
		var br := Button.new()
		br.text = " > "
		br.pressed.connect(_change.bind(key, 1))
		h.add_child(br)
	classic_cb = CheckBox.new()
	classic_cb.text = "Use classic class sprites instead"
	classic_cb.button_pressed = bool(look.classic)
	classic_cb.toggled.connect(func(on): look["classic"] = on)
	right.add_child(classic_cb)
	var bb := HBoxContainer.new()
	right.add_child(bb)
	for it in [["Randomize", _random], ["Save", _save], ["Cancel", func(): closed.emit()]]:
		var b2 := Button.new()
		b2.text = it[0]
		b2.custom_minimum_size = Vector2(100, 32)
		b2.pressed.connect(it[1])
		bb.add_child(b2)
	_update()


func _change(key: String, d: int) -> void:
	var n: int = LookS.option_counts()[key]
	look[key] = posmod(int(look[key]) + d, n)
	_update()


func _random() -> void:
	var c: bool = look.classic
	look = LookS.random_look()
	look["classic"] = c
	_update()


func _save() -> void:
	Net.settings.look = look.duplicate()
	Net.save_settings()
	closed.emit()


func _update() -> void:
	for key in vals:
		var v: int = look[key]
		var txt := "#%d" % (v + 1)
		var col := Color(0, 0, 0, 0)
		match key:
			"hair": txt = LookS.HAIR_STYLES[v]
			"hat": txt = LookS.HATS[v]
			"beard": txt = LookS.BEARDS[v]
			"skin": col = LookS.SKIN[v]
			"hair_col": col = LookS.HAIR_COLS[v]
			"eyes": col = LookS.EYES[v]
			_: col = LookS.CLOTH[v]
		vals[key].text = txt
		swatches[key].color = col


func _process(_dt: float) -> void:
	preview.queue_redraw()


func _draw_preview() -> void:
	preview.draw_rect(Rect2(Vector2.ZERO, preview.custom_minimum_size), Color(0.13, 0.16, 0.25))
	preview.draw_rect(Rect2(0, 236, 240, 44), Color(0.2, 0.35, 0.22))
	var tm := Time.get_ticks_msec() / 1000.0
	var tool: String = Net.CLASSES[prev_cls].tools[0]
	var sw := fmod(tm, 2.5)
	var pose := {"face": 1, "t": tm, "walk": 0.5, "tool": tool, "aim": -0.2, "scale": 7.0, "offset": Vector2(120, 138),
		"swing": sw / 0.4 if sw < 0.4 and tool != "bow" else -1.0, "draw": clampf(sw - 1.0, 0.0, 1.0) if tool == "bow" else 0.0}
	LookS.draw_char(preview, look, prev_team, prev_cls, pose)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		closed.emit()

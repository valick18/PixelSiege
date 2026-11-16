extends PanelContainer
# Панель налаштувань: гучність, екран, перепризначення клавіш руху.

signal closed
const ACTIONS := {"left": "Move left", "right": "Move right", "up": "Up / ladder", "down": "Down", "jump": "Jump", "crouch": "Crouch", "run": "Run"}
var _waiting := ""
var _btns := {}


func _ready() -> void:
	var vb := VBoxContainer.new()
	vb.custom_minimum_size = Vector2(400, 0)
	add_child(vb)
	var t := Label.new()
	t.text = "Settings"
	t.add_theme_font_size_override("font_size", 22)
	vb.add_child(t)
	_slider(vb, "Music volume", Net.settings.music, func(v): Net.settings.music = v; Net.apply_settings())
	_slider(vb, "Effects volume", Net.settings.sfx, func(v): Net.settings.sfx = v; Net.apply_settings(); Net.play("pickup"))
	var fs := CheckBox.new()
	fs.text = "Fullscreen"
	fs.button_pressed = Net.settings.fullscreen
	fs.toggled.connect(func(on): Net.settings.fullscreen = on; Net.apply_settings())
	vb.add_child(fs)
	var h := HBoxContainer.new()
	var l := Label.new()
	l.text = "Window size"
	l.custom_minimum_size = Vector2(140, 0)
	h.add_child(l)
	var ob := OptionButton.new()
	for r in Net.RES_LIST:
		ob.add_item("%dx%d" % [r.x, r.y])
	ob.selected = Net.settings.res
	ob.item_selected.connect(func(i): Net.settings.res = i; Net.apply_settings())
	h.add_child(ob)
	vb.add_child(h)
	for a in ACTIONS:
		var row := HBoxContainer.new()
		var al := Label.new()
		al.text = ACTIONS[a]
		al.custom_minimum_size = Vector2(140, 0)
		row.add_child(al)
		var b := Button.new()
		b.text = _key_name(a)
		b.pressed.connect(_start_wait.bind(a))
		_btns[a] = b
		row.add_child(b)
		vb.add_child(row)
	var c := Button.new()
	c.text = "Close"
	c.pressed.connect(func(): Net.save_settings(); closed.emit())
	vb.add_child(c)


func _slider(parent: Control, text: String, val: float, cb: Callable) -> void:
	var h := HBoxContainer.new()
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(140, 0)
	h.add_child(l)
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = val
	s.custom_minimum_size = Vector2(220, 0)
	s.value_changed.connect(cb)
	h.add_child(s)
	parent.add_child(h)


func _key_name(a: String) -> String:
	var evs := InputMap.action_get_events(a)
	if evs.size() > 0 and evs[0] is InputEventKey:
		return OS.get_keycode_string(evs[0].physical_keycode)
	return "?"


func _start_wait(a: String) -> void:
	_waiting = a
	_btns[a].text = "press a key..."


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		if _waiting != "":
			_btns[_waiting].text = _key_name(_waiting)
			_waiting = ""
		else:
			Net.save_settings()
			closed.emit()
		get_viewport().set_input_as_handled()
		return
	if _waiting != "" and event is InputEventKey and event.pressed:
		Net.bind_key(_waiting, event.physical_keycode)
		Net.settings.keys[_waiting] = event.physical_keycode
		_btns[_waiting].text = _key_name(_waiting)
		_waiting = ""
		get_viewport().set_input_as_handled()

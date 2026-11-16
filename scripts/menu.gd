extends Control

var name_edit: LineEdit
var sname_edit: LineEdit
var pass_edit: LineEdit
var seed_edit: LineEdit
var ip_edit: LineEdit
var size_opt: OptionButton
var max_spin: SpinBox
var status: Label
var list: ItemList
var _ips: Array = []
var _t := 0.0
var settings_panel: Control


func _ready() -> void:
	Net.start_listen()
	var bg := ColorRect.new()
	bg.color = Color("1b2a41")
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var vb := VBoxContainer.new()
	vb.custom_minimum_size = Vector2(460, 0)
	vb.add_theme_constant_override("separation", 5)
	center.add_child(vb)

	var title := Label.new()
	title.text = "PIXEL SIEGE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	var logo = Net.tex("res://assets/logo.png")
	if logo:
		var tr := TextureRect.new()
		tr.texture = logo
		tr.custom_minimum_size = Vector2(0, 90)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		vb.add_child(tr)
	else:
		vb.add_child(title)

	name_edit = _row(vb, "Your name", LineEdit.new())
	name_edit.text = "Player%d" % (randi() % 100)
	sname_edit = _row(vb, "Server name", LineEdit.new())
	sname_edit.text = "My server"
	pass_edit = _row(vb, "Password (optional)", LineEdit.new())
	seed_edit = _row(vb, "Seed (optional)", LineEdit.new())
	size_opt = _row(vb, "Map size", OptionButton.new())
	size_opt.add_item("Small")
	size_opt.add_item("Medium")
	max_spin = _row(vb, "Max players", SpinBox.new())
	max_spin.min_value = 2
	max_spin.max_value = 20
	max_spin.value = 20
	_btn(vb, "Host game", _host)
	vb.add_child(HSeparator.new())

	var lbl := Label.new()
	lbl.text = "LAN servers (double-click to join):"
	vb.add_child(lbl)
	list = ItemList.new()
	list.custom_minimum_size = Vector2(0, 90)
	list.item_selected.connect(func(i): ip_edit.text = _ips[i])
	list.item_activated.connect(func(i): ip_edit.text = _ips[i]; _join())
	vb.add_child(list)
	ip_edit = _row(vb, "Server IP", LineEdit.new())
	ip_edit.text = "127.0.0.1"
	_btn(vb, "Join game", _join)
	_btn(vb, "Settings", _open_settings)
	_btn(vb, "Quit", func(): get_tree().quit())
	status = Label.new()
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.text = Net.last_msg
	vb.add_child(status)
	Net.connect_failed.connect(func(): status.text = Net.last_msg)


func _btn(parent: Control, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	parent.add_child(b)


func _row(parent: Control, text: String, ctrl: Control) -> Control:
	var h := HBoxContainer.new()
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(150, 0)
	h.add_child(l)
	ctrl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(ctrl)
	parent.add_child(h)
	return ctrl


func _process(dt: float) -> void:
	_t += dt
	if _t < 0.5:
		return
	_t = 0.0
	list.clear()
	_ips.clear()
	for ip in Net.found:
		var i: Dictionary = Net.found[ip].info
		list.add_item("%s   %d/%d %s   (%s)" % [i.get("name", "?"), i.get("players", 0), i.get("max", 0), "[pw]" if i.get("pw", false) else "", ip])
		_ips.append(ip)


func _open_settings() -> void:
	if settings_panel:
		return
	settings_panel = preload("res://scripts/settings.gd").new()
	add_child(settings_panel)
	settings_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	settings_panel.closed.connect(func(): settings_panel.queue_free(); settings_panel = null)


func _host() -> void:
	Net.my_name = name_edit.text.strip_edges()
	Net.server_name = sname_edit.text
	Net.server_password = pass_edit.text
	Net.map_size = size_opt.selected
	var err := Net.host_game(int(max_spin.value), seed_edit.text)
	if err != OK:
		status.text = "Cannot start server (port %d busy?)" % Net.PORT
		return
	Net.stop_listen()
	get_tree().change_scene_to_file("res://scenes/game.tscn")


func _join() -> void:
	Net.my_name = name_edit.text.strip_edges()
	Net.join_password = pass_edit.text
	var err := Net.join_game(ip_edit.text.strip_edges())
	status.text = "Connecting..." if err == OK else "Cannot connect"

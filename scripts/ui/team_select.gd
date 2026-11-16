extends PanelContainer
# Вибір команди (при вході в матч або M): дві колонки Blue / Red зі списком гравців та балансом.
# Не можна перейти в команду, яка вже більша. Хост перевіряє баланс повторно.

signal chosen(team: int)
const CraftS = preload("res://scripts/ui/craft_ui.gd")
var game
var lists: Array = []
var heads: Array = []
var btns: Array = []
var bal_l: Label
var _t := 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(560, 360)
	add_theme_stylebox_override("panel", CraftS.panel_style())
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	add_child(root)
	var t := Label.new()
	t.text = "Choose your team"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 24)
	root.add_child(t)
	bal_l = Label.new()
	bal_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(bal_l)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 16)
	root.add_child(cols)
	for tm in 2:
		var pc := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Net.TEAM_COLORS[tm].darkened(0.7)
		sb.border_color = Net.TEAM_COLORS[tm]
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(6)
		sb.set_content_margin_all(10)
		pc.add_theme_stylebox_override("panel", sb)
		pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pc.custom_minimum_size = Vector2(250, 230)
		cols.add_child(pc)
		var vb := VBoxContainer.new()
		pc.add_child(vb)
		var h := Label.new()
		h.add_theme_font_size_override("font_size", 20)
		h.add_theme_color_override("font_color", Net.TEAM_COLORS[tm].lightened(0.3))
		vb.add_child(h)
		heads.append(h)
		var l := Label.new()
		l.size_flags_vertical = Control.SIZE_EXPAND_FILL
		vb.add_child(l)
		lists.append(l)
		var b := Button.new()
		b.text = "Join %s" % Net.TEAM_NAMES[tm]
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 36)
		b.pressed.connect(_join.bind(tm))
		vb.add_child(b)
		btns.append(b)
	var auto := Button.new()
	auto.text = "Auto-balance (join the smaller team)"
	auto.focus_mode = Control.FOCUS_NONE
	auto.pressed.connect(_auto)
	root.add_child(auto)


func open() -> void:
	_refresh()


func _me() -> int:
	return game.multiplayer.get_unique_id()


func _join(tm: int) -> void:
	if int(Net.players.get(_me(), {}).get("team", -1)) != tm:
		game.send_team(tm)
	chosen.emit(tm)


func _auto() -> void:
	var c := Net.team_counts(_me())
	_join(0 if c[0] <= c[1] else 1)


func _process(dt: float) -> void:
	if not visible:
		return
	_t += dt
	if _t >= 0.5:
		_t = 0.0
		_refresh()


func _refresh() -> void:
	if game == null or lists.is_empty():
		return
	var me := _me()
	var mine := int(Net.players.get(me, {}).get("team", -1))
	var names := [[], []]
	for pid in Net.players:
		var info = Net.players[pid]
		var line := "%s  (%s)" % [info.name, Net.CLASSES.get(info.cls, Net.CLASSES.warrior).label]
		if pid == me:
			line = "> " + line + "  [you]"
		names[int(info.team)].append(line)
	var c := Net.team_counts(me)
	for tm in 2:
		heads[tm].text = "%s team  -  %d players" % [Net.TEAM_NAMES[tm], names[tm].size()]
		lists[tm].text = "\n".join(PackedStringArray(names[tm])) if names[tm].size() > 0 else "(empty)"
		var full: bool = c[tm] > c[1 - tm] and mine != tm
		btns[tm].disabled = full
		btns[tm].text = ("Stay in %s" if mine == tm else "Join %s") % Net.TEAM_NAMES[tm]
		if full:
			btns[tm].text = "%s is full (balance)" % Net.TEAM_NAMES[tm]
	bal_l.text = "Balance: Blue %d  vs  Red %d" % [names[0].size(), names[1].size()]

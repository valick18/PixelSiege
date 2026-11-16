extends Node2D
# Гравець: власна AABB-фізика по тайлах (вода, односторонні платформи, командні двері), бій (удар по дузі,
# лук з натягом і прев'ю траєкторії), окремі слоти інструментів класу, анімація смерті.
# Власник (authority) керує своїм персонажем миттєво (локальне передбачення), інші гравці відтворюються
# через буфер знімків (net_interp.gd), позиція відправляється 20 разів на секунду.

const LookS = preload("res://scripts/look.gd")
const InterpS = preload("res://scripts/net_interp.gd")
const T := 16
const HALF := Vector2(6, 14)
const GRAVITY := 900.0
const ARROW_G := 420.0
const SEND_RATE := 0.05

var id := 0
var team := 0
var cls := "warrior"
var vel := Vector2.ZERO
var face := 1
var on_ground := false
var crouch := false
var dead := false
var selected := 0  # 0..2 - інструменти класу, 3..9 - предмети панелі (інвентар 0..6)
var aim := 0.0
var drawing := false
var draw_k := 0.0
var act_cd := 0.0
var atk_cd := 0.0
var ab_until := [0.0, 0.0, 0.0]
var blocking := false
var block_sent := false
var dodge_until := 0.0
var drop_until := 0.0
var in_water := false
var on_ladder := false
var buffs := {}
var anim_t := 0.0
var hurt_t := 0.0
var atk_t := 0.0
var atk_dur := 0.3
var dig_t := 0.0
var dodge_t := 0.0
var death_t := 0.0
var v_est := Vector2.ZERO
var _prev := Vector2.ZERO
var _send_t := 0.0
var net_pos := Vector2.ZERO
var net_flags := 2
var net_sel := 0
var net_draw := 0.0
var interp
var lt: PointLight2D
var game
var world


func setup(pid: int, t: int, c: String, g, w) -> void:
	id = pid
	team = t
	cls = c
	game = g
	world = w
	name = str(pid)
	set_multiplayer_authority(pid)


func _ready() -> void:
	interp = InterpS.new()
	lt = PointLight2D.new()
	lt.texture = world.light_texture()
	lt.texture_scale = 1.2 if is_multiplayer_authority() else 0.7
	lt.energy = 0.8 if is_multiplayer_authority() else 0.4
	add_child(lt)
	if is_multiplayer_authority():
		var cam := Camera2D.new()
		cam.zoom = Vector2(2, 2)
		cam.position_smoothing_enabled = true
		cam.position_smoothing_speed = 12.0
		add_child(cam)
		cam.make_current()


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func tool_at(i: int) -> String:
	var tl: Array = Net.tools_of(cls)
	if i >= 0 and i < tl.size():
		return tl[i]
	return ""


func cur_tool() -> String:
	return tool_at(selected) if selected < Net.TOOL_SLOTS else ""


func inv_index() -> int:
	return selected - Net.TOOL_SLOTS if selected >= Net.TOOL_SLOTS else -1


func get_item() -> String:
	var i := inv_index()
	if i < 0:
		return ""
	var inv: Array = game.cl.get(id, {}).get("inv", [])
	if i < inv.size() and inv[i].has("i"):
		return inv[i]["i"]
	return ""


func has_buff(n: String) -> bool:
	return float(buffs.get(n, 0.0)) > _now()


func add_buff(n: String, dur: float) -> void:
	buffs[n] = _now() + dur


func set_dead(d: bool) -> void:
	if d and not dead:
		death_t = 0.0
		drawing = false
		draw_k = 0.0
		buffs.clear()
	dead = d
	if not d:
		death_t = 0.0
	visible = true


func reset_to_spawn(p: Vector2) -> void:
	position = p
	net_pos = p
	_prev = p
	vel = Vector2.ZERO
	if interp:
		interp.clear()


func apply_knock(v: Vector2) -> void:
	vel += v
	on_ground = false


func _select(i: int) -> void:
	if i < Net.TOOL_SLOTS and tool_at(i) == "":
		return
	selected = i
	drawing = false
	draw_k = 0.0


func _cycle(d: int) -> void:
	for k in 10:
		selected = (selected + d + 10) % 10
		if selected >= Net.TOOL_SLOTS or tool_at(selected) != "":
			break
	drawing = false
	draw_k = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority() or game.ui_open:
		return
	if event is InputEventMouseButton and event.pressed and not dead:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cycle(-1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cycle(1)
	if event is InputEventKey and event.pressed and not event.echo:
		var k: int = event.physical_keycode
		match k:
			KEY_F1: game.send_class("warrior")
			KEY_F2: game.send_class("archer")
			KEY_F3: game.send_class("engineer")
			KEY_F4: game.send_class("support")
		if dead:
			return
		if k >= KEY_1 and k <= KEY_9:
			_select(k - KEY_1)
		elif k == KEY_0:
			_select(9)
		match k:
			KEY_Q: _use_ability(0)
			KEY_R: _use_ability(1)
			KEY_F: _use_ability(2)
			KEY_E: game.interact_local(Vector2.from_angle(aim))
			KEY_G: game.send_store(false)
			KEY_Z:
				var now := _now()
				if now >= dodge_until:
					dodge_until = now + 1.5
					game.send_dodge(face)


func _use_ability(idx: int) -> void:
	var now := _now()
	if now < float(ab_until[idx]):
		return
	ab_until[idx] = now + float(Net.CLASSES[cls]["abilities"][idx]["cd"])
	game.send_ability(idx, Vector2.from_angle(aim))


func anim(kind: int) -> void:
	match kind:
		0:
			if is_multiplayer_authority() and atk_t > 0.0:
				return
			atk_dur = 0.3
			atk_t = 0.3
		1: dodge_t = 0.35
		2: hurt_t = 0.25


func _shoulder() -> Vector2:
	return position + Vector2(0, -1 + (5 if crouch else 0))


func _frame() -> int:
	if dead:
		return 17
	if dodge_t > 0.0:
		return 21
	if blocking:
		return 16
	if hurt_t > 0.0:
		return 17
	if atk_t > 0.0:
		return 13 + clampi(int((atk_dur - atk_t) / 0.1), 0, 2)
	if on_ladder:
		return 11 + (int(anim_t * 6.0) % 2 if absf(v_est.y) > 5.0 else 0)
	if not on_ground:
		return 8 if v_est.y < 0.0 else 9
	if crouch:
		return 10
	if absf(v_est.x) > 8.0:
		var spd := 12.0 if absf(v_est.x) > 130.0 else 8.0
		return 2 + int(anim_t * spd) % 6
	return int(anim_t * 2.0) % 2


func _physics_process(dt: float) -> void:
	v_est = v_est.lerp((position - _prev) / maxf(dt, 0.0001), 0.4)
	_prev = position
	anim_t += dt
	var ug := 1.0 if floori(position.y / T) > world.surf[clampi(floori(position.x / T), 0, world.w - 1)] + 3 else 0.0
	lt.energy = clampf(maxf((0.75 - game.daylight) * 1.6, ug), 0.0, 1.0) * (0.9 if is_multiplayer_authority() else 0.45)
	hurt_t = maxf(0.0, hurt_t - dt)
	atk_t = maxf(0.0, atk_t - dt)
	dig_t = maxf(0.0, dig_t - dt)
	dodge_t = maxf(0.0, dodge_t - dt)
	if dead:
		death_t += dt
	if not is_multiplayer_authority():
		position = interp.sample(net_pos)
		crouch = (net_flags & 1) != 0
		face = 1 if (net_flags & 2) != 0 else -1
		blocking = (net_flags & 4) != 0
		in_water = (net_flags & 8) != 0
		on_ground = (net_flags & 16) != 0
		on_ladder = world.get_cell(Vector2i(floori(position.x / T), floori(position.y / T))) == world.LADDER
		selected = net_sel
		draw_k = net_draw
		drawing = draw_k > 0.0
		queue_redraw()
		return
	queue_redraw()
	aim = (get_global_mouse_position() - _shoulder()).angle()
	act_cd = maxf(0.0, act_cd - dt)
	atk_cd = maxf(0.0, atk_cd - dt)
	if dead:
		vel.x = move_toward(vel.x, 0.0, 300.0 * dt)
		vel.y = minf(vel.y + GRAVITY * dt, 500.0)
		_move(dt)
		_send(dt)
		return
	var tdef: Dictionary = Net.TOOLS.get(cur_tool(), {})
	crouch = Input.is_action_pressed("crouch") and not game.ui_open
	blocking = not game.ui_open and (Input.is_physical_key_pressed(KEY_X) or (Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and tdef.get("kind", "") == "melee"))
	if blocking != block_sent:
		block_sent = blocking
		game.send_block(blocking)
	var dir := 0.0 if game.ui_open else Input.get_axis("left", "right")
	var spd := 170.0 if Input.is_action_pressed("run") else 110.0
	if crouch:
		spd = 55.0
	if drawing:
		spd *= 0.55
	if blocking:
		spd *= 0.6
	if has_buff("haste"):
		spd *= 1.4
	var cm := Vector2i(floori(position.x / T), floori(position.y / T))
	var was_water := in_water
	in_water = world.is_water(cm.x, cm.y) or world.is_water(cm.x, floori((position.y + HALF.y - 2.0) / T))
	if in_water and not was_water and vel.y > 120.0:
		Net.play("splash")
	if in_water:
		spd *= 0.6
	vel.x = lerpf(vel.x, dir * spd, minf(1.0, dt * 12.0))
	if dir != 0.0:
		face = 1 if dir > 0.0 else -1
	if drawing or atk_t > 0.0:
		face = 1 if cos(aim) >= 0.0 else -1
	on_ladder = world.get_cell(cm) == world.LADDER
	var jump: bool = Input.is_action_just_pressed("jump") and not game.ui_open
	if on_ladder:
		vel.y = Input.get_axis("up", "down") * 80.0
		if jump:
			vel.y = -200.0
	elif in_water:
		vel.y = minf(vel.y + GRAVITY * 0.22 * dt, 70.0)
		if not game.ui_open and (Input.is_action_pressed("jump") or Input.is_action_pressed("up")):
			vel.y = maxf(vel.y - 700.0 * dt, -120.0)
			if jump and not world.is_water(cm.x, floori((position.y - HALF.y) / T)):
				vel.y = -280.0
	else:
		vel.y = minf(vel.y + GRAVITY * dt, 500.0)
		if jump and on_ground:
			if Input.is_action_pressed("down") and _on_platform():
				drop_until = _now() + 0.3
				position.y += 2.0
			else:
				vel.y = -300.0
	_move(dt)
	_actions(dt)
	_send(dt)


func _send(dt: float) -> void:
	_send_t += dt
	if _send_t < SEND_RATE:
		return
	_send_t = 0.0
	var fl := (1 if crouch else 0) | (2 if face > 0 else 0) | (4 if blocking else 0) | (8 if in_water else 0) | (16 if on_ground else 0)
	net_sync.rpc(_now(), position, v_est, fl, aim, selected, draw_k if drawing else 0.0)


func _hits(p: Vector2) -> bool:
	var x0 := floori((p.x - HALF.x) / T)
	var x1 := floori((p.x + HALF.x - 0.01) / T)
	var y0 := floori((p.y - HALF.y) / T)
	var y1 := floori((p.y + HALF.y - 0.01) / T)
	for cx in range(x0, x1 + 1):
		for cy in range(y0, y1 + 1):
			if world.blocks_for(cx, cy, team):
				return true
	return false


func _platform_row(px: float, row: int) -> bool:
	for cx in range(floori((px - HALF.x) / T), floori((px + HALF.x - 0.01) / T) + 1):
		if world.is_platform(cx, row):
			return true
	return false


func _on_platform() -> bool:
	var feet := position.y + HALF.y
	var row := floori((feet + 1.0) / T)
	return absf(feet - row * T) < 2.0 and _platform_row(position.x, row)


func _move(dt: float) -> void:
	var was_ground := on_ground
	on_ground = false
	var p := position
	p.x += vel.x * dt
	if _hits(p):
		var up := p + Vector2(0, -T)
		if was_ground and not crouch and not dead and not _hits(up):
			p = up
		else:
			p.x = position.x
			vel.x = 0.0
	var feet_prev := p.y + HALF.y
	p.y += vel.y * dt
	if _hits(p):
		if vel.y > 0.0:
			on_ground = true
			p.y = floorf((p.y + HALF.y) / T) * T - HALF.y - 0.001
		else:
			p.y = (floorf((p.y - HALF.y) / T) + 1.0) * T + HALF.y + 0.001
		vel.y = 0.0
	elif vel.y > 0.0 and _now() > drop_until:
		# односторонні платформи: тверді лише зверху, стрибок знизу проходить наскрізь
		var feet := p.y + HALF.y
		for row in range(floori((feet_prev - 0.5) / T) + 1, floori(feet / T) + 1):
			if _platform_row(p.x, row):
				p.y = row * T - HALF.y - 0.001
				vel.y = 0.0
				on_ground = true
				break
	position = p


func _in_reach(cell: Vector2i) -> bool:
	return position.distance_to(Vector2(cell) * T + Vector2(8, 8)) <= Net.REACH


func _actions(dt: float) -> void:
	if game.ui_open:
		drawing = false
		draw_k = 0.0
		return
	var mp := get_global_mouse_position()
	var cell := Vector2i(floori(mp.x / T), floori(mp.y / T))
	var lmb := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var rmb := Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	var adir := Vector2.from_angle(aim)
	var tool := cur_tool()
	if tool != "":
		var td: Dictionary = Net.TOOLS[tool]
		match String(td.kind):
			"bow":
				if rmb and drawing:
					drawing = false
					draw_k = 0.0
				elif lmb and atk_cd <= 0.0:
					drawing = true
					draw_k = minf(1.0, draw_k + dt / float(td.draw))
				elif drawing and not lmb:
					game.send_shoot(adir, draw_k)
					atk_cd = float(td.cd)
					drawing = false
					draw_k = 0.0
					Net.play("bow")
			"melee":
				if lmb and atk_cd <= 0.0 and not blocking:
					_swing(tool, td, adir)
			_:
				if lmb and act_cd <= 0.0 and _in_reach(cell):
					act_cd = float(td.dig_cd)
					dig_t = 0.25
					game.send_dig(cell, tool)
				elif rmb and atk_cd <= 0.0:
					_swing(tool, td, adir)
		return
	var item := get_item()
	if item == "" or not lmb or act_cd > 0.0:
		return
	if item == "medkit" or item == "food":
		act_cd = 0.6
		game.send_use(cell, inv_index())
		return
	var reach := 200.0 if item == "firebomb" else Net.REACH
	if position.distance_to(Vector2(cell) * T + Vector2(8, 8)) <= reach:
		act_cd = 0.15
		game.send_use(cell, inv_index())


func _swing(tool: String, td: Dictionary, adir: Vector2) -> void:
	atk_cd = float(td.cd)
	atk_dur = minf(0.3, float(td.cd) * 0.8)
	atk_t = atk_dur
	face = 1 if adir.x >= 0.0 else -1
	if on_ground:
		vel.x += face * 70.0
	Net.play("swing")
	game.send_swing(adir, tool)


@rpc("authority", "unreliable_ordered")
func net_sync(t: float, p: Vector2, v: Vector2, fl: int, a: float, sel: int, dk: float) -> void:
	net_pos = p
	net_flags = fl
	aim = a
	net_sel = sel
	net_draw = dk
	if interp:
		interp.push(t, p, v)


func _draw() -> void:
	if dead and death_t > 2.2:
		return
	var pinfo: Dictionary = Net.players.get(id, {})
	var look := LookS.sanitize(pinfo.get("look", {}))
	var tint := Color(1.0, 0.6, 0.6) if hurt_t > 0.0 else Color.WHITE
	var rot := 0.0
	var off := Vector2.ZERO
	if dead:
		var k := clampf(death_t / 0.45, 0.0, 1.0)
		rot = -face * k * PI * 0.5
		off = Vector2(0, k * 9.0)
		var dk := 1.0 - 0.35 * k
		tint = Color(tint.r * dk, tint.g * dk, tint.b * dk, clampf(2.2 - death_t, 0.0, 1.0))
	if has_buff("barrier"):
		draw_circle(Vector2.ZERO, 18.0, Color(0.4, 0.7, 1.0, 0.16))
		draw_arc(Vector2.ZERO, 18.0, 0.0, TAU, 24, Color(0.6, 0.85, 1.0, 0.6), 1.0)
	if has_buff("rage"):
		draw_circle(Vector2(0, 2), 15.0, Color(1.0, 0.25, 0.1, 0.14 + 0.06 * sin(anim_t * 10.0)))
	if has_buff("haste"):
		for i in 3:
			draw_line(Vector2(-face * (9 + i * 3), -6 + i * 6), Vector2(-face * (15 + i * 3), -6 + i * 6), Color(0.6, 1.0, 0.6, 0.5), 1.0)
	var tool := "" if dead else cur_tool()
	var sheet = Net.tex("res://assets/characters/%s_%s.png" % [cls, "blue" if team == 0 else "red"])
	if bool(look.classic) and sheet:
		draw_set_transform(off, rot, Vector2(face, 1))
		draw_texture_rect_region(sheet, Rect2(-12, -16, 24, 32), Rect2(_frame() * 24, 0, 24, 32), tint)
		if tool != "":
			var sa := aim
			if atk_t > 0.0 and tool != "bow":
				sa = aim - face * (1.4 - 2.6 * (1.0 - atk_t / atk_dur))
			draw_set_transform(Vector2(0, -1) + Vector2.from_angle(sa) * 5.0, sa, Vector2(1, 1 if cos(sa) >= 0.0 else -1))
			LookS.draw_tool_local(self, tool, draw_k, tint)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		var pose := {
			"face": face, "t": anim_t, "crouch": crouch, "tint": tint, "rot": rot, "offset": off,
			"walk": clampf(absf(v_est.x) / 110.0, 0.0, 1.4) if on_ground else 0.0,
			"air": not on_ground and not on_ladder and not in_water and not dead,
			"tool": tool, "aim": aim, "draw": draw_k, "block": blocking and not dead,
			"swing": (1.0 - atk_t / atk_dur) if atk_t > 0.0 and tool != "bow" else -1.0,
			"dig": (1.0 - dig_t / 0.25) if dig_t > 0.0 else -1.0,
		}
		if tool == "" and not dead:
			var it := get_item()
			if it != "":
				pose["item_col"] = world.COLORS.get(Net.ITEM_BLOCK.get(it, -1), Color(0.85, 0.8, 0.7))
		LookS.draw_char(self, look, team, cls, pose)
	if not dead or death_t < 1.0:
		var pname := str(pinfo.get("name", ""))
		var nc: Color = Net.TEAM_COLORS[team].lightened(0.45)
		draw_string_outline(ThemeDB.fallback_font, Vector2(-30, -21 + (5 if crouch else 0)), pname, HORIZONTAL_ALIGNMENT_CENTER, 60, 8, 2, Color(0, 0, 0, 0.7 * tint.a))
		draw_string(ThemeDB.fallback_font, Vector2(-30, -21 + (5 if crouch else 0)), pname, HORIZONTAL_ALIGNMENT_CENTER, 60, 8, Color(nc.r, nc.g, nc.b, tint.a))
	if not is_multiplayer_authority() or dead:
		return
	var mp := get_global_mouse_position()
	if tool == "pickaxe" or tool == "axe" or (tool == "" and get_item() != ""):
		var c := Vector2(floori(mp.x / T), floori(mp.y / T)) * T
		var ok := position.distance_to(c + Vector2(8, 8)) <= Net.REACH
		draw_rect(Rect2(to_local(c), Vector2(T, T)), Color(1, 1, 1, 0.9) if ok else Color(1, 0.2, 0.2, 0.6), false, 1.0)
	if tool == "bow" and drawing:
		var td: Dictionary = Net.TOOLS.bow
		var v := Vector2.from_angle(aim) * lerpf(td.speed, td.speed_max, draw_k)
		var p := _shoulder() + Vector2.from_angle(aim) * 10.0
		for i in 30:
			v.y += ARROW_G * 0.03
			v.x += game.wind * 20.0 * 0.03
			p += v * 0.03
			if world.is_solid(floori(p.x / T), floori(p.y / T)):
				break
			if i % 2 == 1:
				draw_rect(Rect2(to_local(p) - Vector2(1, 1), Vector2(2, 2)), Color(1, 1, 1, 0.6 * (1.0 - i / 30.0)))
		draw_rect(Rect2(-10, -28, 20, 3), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(-10, -28, 20.0 * draw_k, 3), Color(1.0, 0.85, 0.3) if draw_k < 1.0 else Color(1.0, 0.4, 0.2))

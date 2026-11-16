extends Node2D
# Гравець: власна AABB-фізика по тайлах. Власник (authority) керує і шле позицію.

const T := 16
const HALF := Vector2(6, 14)
const GRAVITY := 900.0
const SLOTS := ["pick", "wood", "stone", "metal", "ladder"]

var id := 0
var team := 0
var cls := "warrior"
var vel := Vector2.ZERO
var face := 1
var on_ground := false
var crouch := false
var dead := false
var selected := 0
var net_pos := Vector2.ZERO
var net_crouch := false
var net_face := 1
var act_cd := 0.0
var atk_cd := 0.0
var ab_until := 0.0
var blocking := false
var net_block := false
var dodge_until := 0.0
var block_sent := false
var anim_t := 0.0
var hurt_t := 0.0
var atk_t := 0.0
var dodge_t := 0.0
var v_est := Vector2.ZERO
var _prev := Vector2.ZERO
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
	lt = PointLight2D.new()
	lt.texture = world.light_texture()
	lt.texture_scale = 1.2 if is_multiplayer_authority() else 0.7
	lt.energy = 0.8 if is_multiplayer_authority() else 0.4
	add_child(lt)
	if is_multiplayer_authority():
		var cam := Camera2D.new()
		cam.zoom = Vector2(2, 2)
		add_child(cam)
		cam.make_current()


func set_dead(d: bool) -> void:
	dead = d
	visible = not d
	if d:
		vel = Vector2.ZERO


func reset_to_spawn(p: Vector2) -> void:
	position = p
	net_pos = p
	vel = Vector2.ZERO


func get_item() -> String:
	var inv: Array = game.cl.get(id, {}).get("inv", [])
	if selected < inv.size() and inv[selected].has("i"):
		return inv[selected]["i"]
	return ""


func apply_knock(v: Vector2) -> void:
	vel += v
	on_ground = false


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority() or game.ui_open:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_F1: game.send_class("warrior")
			KEY_F2: game.send_class("archer")
			KEY_F3: game.send_class("engineer")
			KEY_F4: game.send_class("support")
		if dead:
			return
		var k: int = event.physical_keycode
		if k >= KEY_1 and k <= KEY_9:
			selected = k - KEY_1
		elif k == KEY_0:
			selected = 9
		match k:
			KEY_Q: _use_ability()
			KEY_E: game.send_interact((get_global_mouse_position() - position).normalized(), selected)
			KEY_R: game.send_store(true)
			KEY_G: game.send_store(false)
			KEY_Z:
				var now := Time.get_ticks_msec() / 1000.0
				if now >= dodge_until:
					dodge_until = now + 1.5
					game.send_dodge(face)


func _use_ability() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now < ab_until:
		return
	ab_until = now + Net.CLASSES[cls]["ab_cd"]
	game.send_ability((get_global_mouse_position() - position).normalized())


func anim(kind: int) -> void:
	match kind:
		0: atk_t = 0.3
		1: dodge_t = 0.35
		2: hurt_t = 0.25


func _frame() -> int:
	if dodge_t > 0.0:
		return 21
	if blocking:
		return 16
	if hurt_t > 0.0:
		return 17
	if atk_t > 0.0:
		return 13 + clampi(int((0.3 - atk_t) / 0.1), 0, 2)
	if world.get_cell(Vector2i(floori(position.x / T), floori(position.y / T))) == world.LADDER:
		return 11 + (int(anim_t * 6.0) % 2 if absf(v_est.y) > 5.0 else 0)
	if not _hits(position + Vector2(0, 1.5)):
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
	dodge_t = maxf(0.0, dodge_t - dt)
	if not is_multiplayer_authority():
		position = position.lerp(net_pos, minf(1.0, dt * 20.0))
		crouch = net_crouch
		blocking = net_block
		face = net_face
		queue_redraw()
		return
	queue_redraw()
	if dead:
		return
	act_cd = maxf(0.0, act_cd - dt)
	atk_cd = maxf(0.0, atk_cd - dt)
	crouch = Input.is_action_pressed("crouch")
	blocking = Input.is_physical_key_pressed(KEY_X)
	if blocking != block_sent:
		block_sent = blocking
		game.send_block(blocking)
	var dir := Input.get_axis("left", "right")
	var spd := 170.0 if Input.is_action_pressed("run") else 110.0
	if crouch:
		spd = 55.0
	vel.x = lerpf(vel.x, dir * spd, minf(1.0, dt * 12.0))
	if dir != 0.0:
		face = 1 if dir > 0.0 else -1
	var on_ladder: bool = world.get_cell(Vector2i(floori(position.x / T), floori(position.y / T))) == world.LADDER
	if on_ladder:
		vel.y = Input.get_axis("up", "down") * 80.0
		if Input.is_action_just_pressed("jump"):
			vel.y = -200.0
	else:
		vel.y = minf(vel.y + GRAVITY * dt, 500.0)
		if Input.is_action_just_pressed("jump") and on_ground:
			vel.y = -300.0
	_move(dt)
	_actions()
	net_sync.rpc(position, crouch, face, blocking)


func _hits(p: Vector2) -> bool:
	var x0 := floori((p.x - HALF.x) / T)
	var x1 := floori((p.x + HALF.x - 0.01) / T)
	var y0 := floori((p.y - HALF.y) / T)
	var y1 := floori((p.y + HALF.y - 0.01) / T)
	for cx in range(x0, x1 + 1):
		for cy in range(y0, y1 + 1):
			if world.is_solid(cx, cy):
				return true
	return false


func _move(dt: float) -> void:
	var was_ground := on_ground
	on_ground = false
	var p := position
	p.x += vel.x * dt
	if _hits(p):
		var up := p + Vector2(0, -T)
		if was_ground and not crouch and not _hits(up):
			p = up
		else:
			p.x = position.x
			vel.x = 0.0
	p.y += vel.y * dt
	if _hits(p):
		if vel.y > 0.0:
			on_ground = true
			p.y = floorf((p.y + HALF.y) / T) * T - HALF.y - 0.001
		else:
			p.y = (floorf((p.y - HALF.y) / T) + 1.0) * T + HALF.y + 0.001
		vel.y = 0.0
	position = p


func _actions() -> void:
	if game.ui_open:
		return
	var mp := get_global_mouse_position()
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and act_cd <= 0.0:
		var cell := Vector2i(floori(mp.x / T), floori(mp.y / T))
		var reach := 200.0 if get_item() == "firebomb" else Net.REACH
		if position.distance_to(Vector2(cell) * T + Vector2(8, 8)) <= reach:
			act_cd = 0.1
			game.send_use(cell, selected)
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and atk_cd <= 0.0:
		atk_cd = 0.2
		game.send_attack((mp - position).normalized())


@rpc("authority", "unreliable_ordered")
func net_sync(p: Vector2, c: bool, f: int, bl: bool) -> void:
	net_block = bl
	net_pos = p
	net_crouch = c
	net_face = f


func _draw() -> void:
	var sheet = Net.tex("res://assets/characters/%s_%s.png" % [cls, "blue" if team == 0 else "red"])
	var off := 8.0 if crouch else 0.0
	if sheet:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1 if face >= 0 else -1, 1))
		draw_texture_rect_region(sheet, Rect2(-12, -16, 24, 32), Rect2(_frame() * 24, 0, 24, 32), Color(1.0, 0.65, 0.65) if hurt_t > 0.0 else Color.WHITE)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		draw_rect(Rect2(-6, -14 + off, 12, 28 - off), Net.CLASSES[cls]["color"])
		draw_rect(Rect2(-6, -14 + off, 12, 6), Net.TEAM_COLORS[team])
	var pname := str(Net.players.get(id, {}).get("name", ""))
	draw_string(ThemeDB.fallback_font, Vector2(-24, -20 + off), pname, HORIZONTAL_ALIGNMENT_CENTER, 48, 8)
	if is_multiplayer_authority() and not dead:
		var mp := get_global_mouse_position()
		var c := Vector2(floori(mp.x / T), floori(mp.y / T)) * T
		var ok := position.distance_to(c + Vector2(8, 8)) <= Net.REACH
		var cc: Color = Color(1, 1, 1, 0.9) if ok else Color(1, 0.2, 0.2, 0.6)
		draw_rect(Rect2(to_local(c), Vector2(T, T)), cc, false, 1.0)

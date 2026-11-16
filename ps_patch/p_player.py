"""player.gd: throwing bombs/TNT, catching (F), shop placement click, special arrows, archer rope."""

VARS = r'''
var roping := false
var hook := Vector2.ZERO
var rope_len := 0.0
var _lmb_prev := false
const ROPE_MAX := 200.0
const SPECIAL_LMB := ["bomb", "rope", "shop_kit", "fire_arrow", "bomb_arrow", "poison_arrow"]
'''

KEY_E = r'''
KEY_E:
    if not game.try_open_shop(position):
        game.interact_local(Vector2.from_angle(aim))
KEY_F: _catch_or_throw()
'''

DRAW_ROPE = r'''
if roping:
    draw_line(Vector2(0, -6), to_local(hook), Color(0.76, 0.6, 0.38), 1.5)
    draw_rect(Rect2(to_local(hook) - Vector2(2, 2), Vector2(4, 4)), Color(0.62, 0.64, 0.7))
'''

CODE = r'''
# ------------------------------------------------------------ throwing / catching / rope
func _throw_power(mp: Vector2) -> float:
	return clampf(position.distance_to(mp) / 220.0, 0.3, 1.0)

# ЛКМ для "особливих" предметів: кидок бомби/TNT, канат, магазин, завантаження стріл.
func _special_lmb(mp: Vector2) -> bool:
	var lmb := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var edge := lmb and not _lmb_prev
	_lmb_prev = lmb
	var it := get_item()
	var holding: bool = game.held_proj_id() != 0
	if not (holding or it in SPECIAL_LMB or (it == "tnt" and not crouch)):
		return false
	if not edge:
		return true
	var dir := (mp - position).normalized()
	if holding:
		game.send_catch(dir, _throw_power(mp))
	elif it == "rope":
		if cls != "archer":
			return true
		if roping:
			_rope_release()
		else:
			_rope_fire(dir)
	elif it == "bomb" or it == "tnt":
		game.send_throw(dir, _throw_power(mp), inv_index())
	elif it == "shop_kit":
		game.open_shop_picker(Vector2i(floori(mp.x / T), floori(mp.y / T)), inv_index())
	else:
		game.send_use(Vector2i(floori(mp.x / T), floori(mp.y / T)), inv_index())
	return true

func _catch_or_throw() -> void:
	var mp := get_global_mouse_position()
	game.send_catch((mp - position).normalized(), _throw_power(mp))

func _rope_fire(dir: Vector2) -> void:
	var p := position + Vector2(0, -6)
	var d := 0.0
	while d < ROPE_MAX:
		d += 4.0
		var q := p + dir * d
		if world.is_solid(floori(q.x / T), floori(q.y / T)):
			roping = true
			hook = q
			rope_len = d * 0.9
			net_rope.rpc(true, hook)
			Net.play("place")
			return
	Net.play("dig")

func _rope_release() -> void:
	if roping:
		roping = false
		net_rope.rpc(false, hook)

func _rope_update(dt: float) -> void:
	if not roping:
		return
	if not world.is_solid(floori(hook.x / T), floori(hook.y / T)):
		_rope_release()
		return
	if Input.is_action_just_pressed("jump"):
		_rope_release()
		vel.y = -240.0
		return
	var climb := Input.get_axis("up", "down")
	if climb < 0.0:
		rope_len -= 170.0 * dt
	elif climb > 0.0:
		rope_len += 110.0 * dt
	rope_len = clampf(rope_len, 12.0, ROPE_MAX)
	var to := hook - position
	var dist := to.length()
	if dist > rope_len and dist > 0.01:
		var n := to / dist
		var radial := vel.dot(n)
		if radial < 0.0:
			vel -= n * radial
		vel += n * minf((dist - rope_len) * 14.0, 400.0)
	on_ground = false

@rpc("authority", "reliable")
func net_rope(on: bool, h: Vector2) -> void:
	roping = on
	hook = h
'''


def apply(pl):
    pl.after("^var world", VARS)
    pl.after("^dead = d", "if d:\n    roping = false")
    pl.replace("^KEY_E: game.interact_local(Vector2.from_angle(aim))", KEY_E)
    pl.before("^_move(dt)", "_rope_update(dt)")
    pl.after("^var mp := get_global_mouse_position()", "if _special_lmb(mp):\n    return")
    pl.before("^if not dead or death_t < 1.0:", DRAW_ROPE)
    pl.append(CODE)

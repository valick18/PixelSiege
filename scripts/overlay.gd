extends Control
# Екранні ефекти: спалах, віньєтка. Промені сонця прибрано.
# Дощ і туман прибрано з гри повністю.

var game


func _process(_dt: float) -> void:
	queue_redraw()


func _draw() -> void:
	if game == null:
		return
	var vs := get_viewport_rect().size
	var k: float = game.rain_k
	if game.flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, vs), Color(1, 1, 1, game.flash * 0.7 * (0.25 + 0.75 * k)))
	var vg = Net.tex("res://assets/vignette.png")
	if vg:
		draw_texture_rect(vg, Rect2(Vector2.ZERO, vs), false, Color(1, 1, 1, 0.9))

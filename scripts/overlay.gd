extends Control
# Екранні ефекти: дощ, туман, блискавка, промені світла, віньєтка. Під землею дощу немає (rain_k -> 0).

var game


func _process(_dt: float) -> void:
	queue_redraw()


func _draw() -> void:
	if game == null:
		return
	var vs := get_viewport_rect().size
	var t := Time.get_ticks_msec() / 1000.0
	var k: float = game.rain_k
	if game.weather == "clear" and game.daylight > 0.8 and k > 0.5:
		for i in 5:
			var x0 := vs.x * (0.1 + i * 0.2) + sin(t * 0.3 + i) * 40.0
			var a := 0.05 + 0.025 * sin(t * 0.7 + i * 2.0)
			draw_colored_polygon(PackedVector2Array([Vector2(x0, 0), Vector2(x0 + 90, 0), Vector2(x0 + 90 - vs.y * 0.55, vs.y), Vector2(x0 - vs.y * 0.55, vs.y)]), Color(1.0, 0.95, 0.75, a))
	if (game.weather == "rain" or game.weather == "storm") and k > 0.02:
		var n := 220 if game.weather == "storm" else 130
		for i in n:
			var x := fposmod(i * 97.0 + t * game.wind * 260.0, vs.x)
			var y := fposmod(i * 53.0 + t * 700.0 + i * 13.0, vs.y)
			draw_line(Vector2(x, y), Vector2(x + game.wind * 10.0, y + 16.0), Color(0.7, 0.8, 1.0, 0.55 * k), 1.0)
	if game.weather == "fog":
		draw_rect(Rect2(Vector2.ZERO, vs), Color(0.85, 0.88, 0.9, 0.5 * (0.3 + 0.7 * k)))
	elif game.weather == "storm":
		draw_rect(Rect2(Vector2.ZERO, vs), Color(0.1, 0.1, 0.15, 0.25 * k))
	if game.flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, vs), Color(1, 1, 1, game.flash * 0.7 * (0.25 + 0.75 * k)))
	var vg = Net.tex("res://assets/vignette.png")
	if vg:
		draw_texture_rect(vg, Rect2(Vector2.ZERO, vs), false, Color(1, 1, 1, 0.9))

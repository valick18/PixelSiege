extends RefCounted
# Snapshot interpolation для інших гравців: буфер знімків з часом відправника, відтворення з затримкою DELAY,
# лінійна інтерполяція між двома знімками та коротка екстраполяція за швидкістю, якщо пакети запізнюються.
# Зсув годинників (offset) оцінюється автоматично, тому синхронізація часу між ПК не потрібна.

const DELAY := 0.1
const MAX_EXTRA := 0.15
const SNAP_DIST := 220.0

var buf: Array = []  # [t_sender, pos, vel]
var offset := 0.0
var _has_offset := false


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func push(t_sender: float, pos: Vector2, vel: Vector2) -> void:
	var o := _now() - t_sender
	if not _has_offset or o < offset:
		offset = o
		_has_offset = true
	else:
		offset = lerpf(offset, o, 0.01)
	if not buf.is_empty():
		var last = buf[buf.size() - 1]
		if t_sender <= float(last[0]):
			return
		if pos.distance_to(last[1]) > SNAP_DIST:
			buf.clear()
	buf.append([t_sender, pos, vel])
	while buf.size() > 40:
		buf.pop_front()


func clear() -> void:
	buf.clear()


func sample(fallback: Vector2) -> Vector2:
	if buf.is_empty():
		return fallback
	var rt := _now() - offset - DELAY
	while buf.size() > 2 and float(buf[1][0]) <= rt:
		buf.pop_front()
	var a = buf[0]
	if rt <= float(a[0]):
		return a[1]
	if buf.size() == 1:
		return a[1] + a[2] * minf(rt - float(a[0]), MAX_EXTRA)
	var b = buf[1]
	if rt >= float(b[0]):
		return b[1] + b[2] * minf(rt - float(b[0]), MAX_EXTRA)
	var k := (rt - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.0001)
	return (a[1] as Vector2).lerp(b[1], k)

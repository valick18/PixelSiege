extends RefCounted
# Інвентар: 0..6 - панель предметів (клавіші 4-0), 7..20 - рюкзак (Tab).
# Інструменти (меч, лук, кирка...) не займають інвентар: вони в окремих слотах класу.

const SIZE := 21
const HOTBAR := 7


static func empty() -> Array:
	var inv := []
	for i in SIZE:
		inv.append({})
	return inv


static func max_stack(item: String) -> int:
	return 99 if item in ["wood", "stone", "metal", "arrow"] else 20


static func count(inv: Array, item: String) -> int:
	var n := 0
	for e in inv:
		if e.get("i", "") == item:
			n += int(e.n)
	return n


static func add(inv: Array, item: String, n: int) -> int:
	var mx := max_stack(item)
	for e in inv:
		if n <= 0:
			break
		if e.get("i", "") == item and int(e.n) < mx:
			var k := mini(n, mx - int(e.n))
			e.n = int(e.n) + k
			n -= k
	for i in inv.size():
		if n <= 0:
			break
		if inv[i].is_empty():
			var k2 := mini(n, mx)
			inv[i] = {"i": item, "n": k2}
			n -= k2
	return n


static func take(inv: Array, item: String, n: int) -> int:
	var left := n
	for i in inv.size():
		if left <= 0:
			break
		if inv[i].get("i", "") == item:
			var k := mini(left, int(inv[i].n))
			inv[i].n = int(inv[i].n) - k
			left -= k
			if int(inv[i].n) <= 0:
				inv[i] = {}
	return n - left


static func consume(inv: Array, slot: int) -> void:
	inv[slot].n = int(inv[slot].n) - 1
	if int(inv[slot].n) <= 0:
		inv[slot] = {}


static func swap(inv: Array, a: int, b: int) -> void:
	if a < 0 or b < 0 or a >= inv.size() or b >= inv.size() or a == b:
		return
	var ea: Dictionary = inv[a]
	var eb: Dictionary = inv[b]
	if not ea.is_empty() and not eb.is_empty() and ea.i == eb.i:
		var mx := max_stack(ea.i)
		var k := mini(int(ea.n), mx - int(eb.n))
		if k > 0:
			eb.n = int(eb.n) + k
			ea.n = int(ea.n) - k
			if int(ea.n) <= 0:
				inv[a] = {}
			return
	inv[a] = eb
	inv[b] = ea


static func _rank(item: String) -> String:
	return ("0" if item in ["wood", "stone", "metal"] else "1") + item


# Сортує та об'єднує стопки в рюкзаку (панель предметів не чіпає).
static func sort_backpack(inv: Array) -> void:
	var totals := {}
	var order: Array = []
	for i in range(HOTBAR, inv.size()):
		if inv[i].is_empty():
			continue
		var it: String = inv[i].i
		if not totals.has(it):
			totals[it] = 0
			order.append(it)
		totals[it] = int(totals[it]) + int(inv[i].n)
		inv[i] = {}
	for i in range(1, order.size()):
		var j := i
		while j > 0 and _rank(order[j - 1]) > _rank(order[j]):
			var tmp = order[j - 1]
			order[j - 1] = order[j]
			order[j] = tmp
			j -= 1
	var k := HOTBAR
	for it in order:
		var left: int = totals[it]
		while left > 0 and k < inv.size():
			var m := mini(left, max_stack(it))
			inv[k] = {"i": it, "n": m}
			left -= m
			k += 1

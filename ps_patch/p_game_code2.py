"""game.gd new code, part 2: shops (Builder only, inside player-built houses)."""

CODE = r'''
# ============================================================ PixelSiege patch: shops
@rpc("authority", "call_local", "reliable")
func c_shops(d: Dictionary) -> void:
	shops = d
	world.shop_info = d

func send_place_shop(cell: Vector2i, slot: int, kind: String) -> void:
	if multiplayer.is_server():
		req_place_shop(cell, slot, kind)
	else:
		req_place_shop.rpc_id(1, cell, slot, kind)

func _cost_text(cost: Dictionary) -> String:
	var parts := PackedStringArray()
	for k in cost:
		parts.append("%d %s" % [int(cost[k]), k])
	return ", ".join(parts)

func _can_pay_shop(s, team: int, cost: Dictionary, near: bool) -> bool:
	for k in cost:
		var have := InvS.count(s.inv, k)
		if near and k in Net.RESOURCES:
			have += int(store[team][k])
		if have < int(cost[k]):
			return false
	return true

func _pay_shop(s, team: int, cost: Dictionary, near: bool) -> void:
	for k in cost:
		var need: int = int(cost[k])
		need -= InvS.take(s.inv, k, need)
		if need > 0 and near:
			store[team][k] -= need

# Блок, який поставив гравець (дерево / камінь / метал)
func _is_built(c: Vector2i) -> bool:
	if not edits.has(c):
		return false
	var b: int = int(edits[c][0])
	return (b == world.WOOD or b == world.STONE or b == world.METAL) and world.get_cell(c) == b

# "Будинок": твердa підлога, побудований дах до 7 клітинок вгору, стіни зліва і справа до 9 клітинок
func _in_house(cell: Vector2i) -> bool:
	if not world.is_solid(cell.x, cell.y + 1):
		return false
	var roof := false
	for dy in range(1, 8):
		if world.is_solid(cell.x, cell.y - dy):
			roof = _is_built(cell + Vector2i(0, -dy))
			break
	var lw := false
	var rw := false
	for dx in range(1, 10):
		for dy in range(0, 3):
			if not lw and _is_built(cell + Vector2i(-dx, -dy)):
				lw = true
			if not rw and _is_built(cell + Vector2i(dx, -dy)):
				rw = true
	return roof and lw and rw

func _near_shop(p, team: int, kind: String) -> bool:
	for c in shops:
		var sh: Array = shops[c]
		if sh[0] == kind and int(sh[1]) == team and p.position.distance_to(Vector2(c) * T + Vector2(8, 8)) < 64.0:
			return true
	return false

@rpc("any_peer", "reliable")
func req_place_shop(cell: Vector2i, slot: int, kind: String) -> void:
	if not multiplayer.is_server() or not Net.SHOPS.has(kind):
		return
	var id := _sid()
	var a = actor(id)
	if a == null:
		return
	var s = a[0]
	var p = a[1]
	if Net.players[id].cls != "engineer":
		note_to(id, "Only the Builder can place shops")
		return
	slot = clampi(slot, 0, InvS.HOTBAR - 1)
	if s.inv[slot].get("i", "") != "shop_kit":
		return
	if p.position.distance_to(Vector2(cell) * T + Vector2(8, 8)) > Net.REACH:
		note_to(id, "Too far away")
		return
	if world.get_cell(cell) != world.AIR:
		note_to(id, "Pick an empty cell inside the house")
		return
	if not _in_house(cell):
		note_to(id, "Shops go inside a player-built house: floor, walls and a roof")
		return
	for c in shops:
		if Vector2(c).distance_to(Vector2(cell)) < 4.0:
			note_to(id, "Too close to another shop")
			return
	var team: int = Net.players[id].team
	var cost: Dictionary = Net.SHOPS[kind].cost
	var near: bool = bool(building.near_store(id, p))
	if not _can_pay_shop(s, team, cost, near):
		note_to(id, "%s needs %s" % [Net.SHOPS[kind].label, _cost_text(cost)])
		return
	_pay_shop(s, team, cost, near)
	InvS.consume(s.inv, slot)
	structs[cell] = {"type": "shop", "team": team, "ready_at": now(), "cd": 0.0, "shop": kind}
	shops[cell] = [kind, team]
	send_edits([[cell, world.SHOP, team]])
	c_shops.rpc(shops)
	push_state(id)
	push_store()
	note_to(0, "%s team opened a %s" % [Net.TEAM_NAMES[team], Net.SHOPS[kind].label])
	c_sfx.rpc("craft")

# E біля магазину своєї команди відкриває меню крафту на вкладці цього магазину
func try_open_shop(pos: Vector2) -> bool:
	var me := multiplayer.get_unique_id()
	if not Net.players.has(me):
		return false
	var team: int = Net.players[me].team
	for c in shops:
		var sh: Array = shops[c]
		if int(sh[1]) == team and pos.distance_to(Vector2(c) * T + Vector2(8, 8)) < 64.0:
			var shop_kind: String = str(sh[0])
			var cat_name: String = Net.SHOPS.get(shop_kind, {}).get("label", "Builder shop")
			_show(craft_ui)
			if craft_ui != null:
				craft_ui._set_cat(cat_name)
			return true
	return false

func open_shop_picker(cell: Vector2i, slot: int) -> void:
	var me := multiplayer.get_unique_id()
	if str(Net.players.get(me, {}).get("cls", "")) != "engineer":
		note = "Only the Builder can place shops"
		note_t = 3.0
		return
	shop_pick_cell = cell
	shop_pick_slot = slot
	if shop_menu == null:
		shop_menu = PanelContainer.new()
		var v := VBoxContainer.new()
		v.custom_minimum_size = Vector2(360, 0)
		shop_menu.add_child(v)
		var t := Label.new()
		t.text = "Choose a shop for this house"
		v.add_child(t)
		for k in Net.SHOPS:
			var b := Button.new()
			b.text = "%s  [%s]" % [Net.SHOPS[k].label, _cost_text(Net.SHOPS[k].cost)]
			b.pressed.connect(_pick_shop.bind(k))
			v.add_child(b)
		var cb := Button.new()
		cb.text = "Cancel"
		cb.pressed.connect(func(): shop_menu.visible = false; _refresh_ui_flag())
		v.add_child(cb)
		hud_layer.add_child(shop_menu)
	_show(shop_menu)

func _pick_shop(kind: String) -> void:
	if shop_menu != null:
		shop_menu.visible = false
	_refresh_ui_flag()
	send_place_shop(shop_pick_cell, shop_pick_slot, kind)
'''


def apply(g):
    g.append(CODE)

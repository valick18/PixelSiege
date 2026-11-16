"""game.gd, CombatManager.gd, BuildingManager.gd hooks."""

GAME_VARS = r'''
var proj := {} # host: id -> {k, pos, vel, owner, team, fuse, holder, b, life}
var proj_id := 1
var proj_sync := 0.0
var proj_live := false
var proj_view: Array = [] # all: [id, pos, kind, holder, block, fuse]
var shops := {} # all: cell -> [shop type, team]
var status_t := 0.0
var shop_menu: PanelContainer
var shop_pick_cell := Vector2i.ZERO
var shop_pick_slot := 0
'''

BUILDING_USE = r'''
if item in Net.ARROWS:
    s["arrow"] = item
    g.note_to(id, "%s loaded: shoot with bow" % item.replace("_", " ").capitalize())
    return
if item == "shop_kit" or item == "bomb" or item == "rope":
    return
'''

BUILDING_CRAFT = r'''
var need_cls: String = rec.get("cls", "")
if need_cls != "" and Net.players[id].cls != need_cls:
    hint(id, "Only %s can craft this" % Net.CLASSES[need_cls].label)
    return
var need_shop: String = rec.get("shop", "")
if need_shop != "" and not g._near_shop(p, team, need_shop):
    hint(id, "Go to your team's %s (press E next to it)" % Net.SHOPS[need_shop].label)
    return
'''

COMBAT_SPECIAL_ARROW = r'''
var special: String = s.get("arrow", "")
var akind := 0
if special != "":
    match special:
        "fire_arrow": akind = 1
        "bomb_arrow": akind = 4
        "poison_arrow": akind = 5
    s["arrow"] = ""
'''

COMBAT_HIT_PLAYER = r'''
if int(a.k) == 4:
    g._explode_square(Vector2i(floori(pt.x / T), floori(pt.y / T)), 1, 8.0, src, false)
elif int(a.k) == 5:
    if g.st.has(oid):
        g.st[oid]["poison_until"] = g.now() + 5.0
        g.st[oid]["poison_src"] = src
        g.note_to(oid, "You are poisoned!")
'''


def apply(g, combat, bld):
    # game.gd
    g.after("^var drop_id := 1", GAME_VARS)
    g.after("^falling.clear()", "proj.clear()\nproj_view = []\nshops.clear()\nworld.shop_info = shops")
    g.after("^physics.sim_falling(dt)", "if multiplayer.is_server():\n    _proj_tick(dt)\n    _status_tick(dt)")
    g.after("^func _draw_fx() -> void:", "    _draw_proj(fx_layer)")
    g.after("^c_full.rpc_id(_sid(), d)", "c_shops.rpc_id(_sid(), shops)")
    g.after("^structs.erase(c)", "if shops.has(c):\n    shops.erase(c)\n    c_shops.rpc(shops)")
    g.replace("^var any := settings_ui != null", "var any := settings_ui != null or (shop_menu != null and shop_menu.visible)")

    # BuildingManager.gd
    bld.before('^if item == "medkit" or item == "food":', BUILDING_USE)
    bld.before("^var near := near_store(id, p)", BUILDING_CRAFT)
    bld.replace("^if InvS.add(test, rname, int(rec.n)) > 0:",
                'var out_item: String = rec.get("item", rname)\nif InvS.add(test, out_item, int(rec.n)) > 0:')
    bld.replace("^InvS.add(s.inv, rname, int(rec.n))", "InvS.add(s.inv, out_item, int(rec.n))")

    # CombatManager.gd
    combat.after("^g.c_fx.rpc(origin, origin + dir * rng, 0)", "g._deflect_proj(id, origin, dir, rng)")
    combat.before("^spawn_arrow(_bow_origin(p, dir), dir * spd, 0, _team(id), id, dmg)", COMBAT_SPECIAL_ARROW)
    combat.replace("^spawn_arrow(_bow_origin(p, dir), dir * spd, 0, _team(id), id, dmg)",
                   "spawn_arrow(_bow_origin(p, dir), dir * spd, akind, _team(id), id, dmg)")
    combat.after("^g.fire_sys.ignite_area(Vector2i(floori(pt.x / T), floori(pt.y / T)), 1, false)", COMBAT_HIT_PLAYER)
    combat.after("^3: g.building.damage_block(cell, 4)", "4: g._explode_square(cell, 1, 8.0, int(meta.src), false)")

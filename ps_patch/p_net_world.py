"""net.gd (classes, recipes, shops), world.gd (shop block), look.gd (icons for new items and shop block)."""

SHOPS_CONST = r'''
# Магазини: ставить лише Builder (engineer) з shop_kit у будинок гравця; cost списується при встановленні
const SHOPS := {
    "builder": {"label": "Builder shop", "cost": {"wood": 12, "stone": 6}, "color": Color("f39c12")},
    "warrior": {"label": "Warrior shop", "cost": {"wood": 8, "stone": 6, "metal": 4}, "color": Color("c0392b")},
    "archer": {"label": "Archer shop", "cost": {"wood": 14, "metal": 3}, "color": Color("27ae60")},
    "siege": {"label": "Siege workshop", "cost": {"wood": 16, "stone": 10, "metal": 8}, "color": Color("8d6e63")},
}
const CRAFT_TABS := {"basic": "Basic", "builder": "Builder shop", "warrior": "Warrior shop", "archer": "Archer shop", "siege": "Siege workshop"}
const ARROWS := ["fire_arrow", "bomb_arrow", "poison_arrow"]
'''

NEW_RECIPES = r'''
    "shop_kit": {"cost": {"wood": 10, "stone": 6, "metal": 2}, "n": 1, "station": "hand", "cat": "Stations", "cls": "engineer", "desc": "LMB inside a player-built house, then choose the shop"},
    "bomb": {"cost": {"stone": 1, "metal": 1}, "n": 2, "station": "hand", "cat": "Warrior Shop", "shop": "warrior", "desc": "LMB throw, explodes 3x3"},
    "rope": {"cost": {"wood": 3}, "n": 1, "station": "hand", "cat": "Archer Shop", "cls": "archer", "desc": "LMB throw, W pull up, S lower, Space let go"},
    "fire_arrow": {"cost": {"wood": 2, "metal": 1}, "n": 5, "station": "hand", "cat": "Archer Shop", "shop": "archer", "desc": "Sets blocks and enemies on fire"},
    "bomb_arrow": {"cost": {"wood": 2, "stone": 2, "metal": 2}, "n": 3, "station": "hand", "cat": "Archer Shop", "shop": "archer", "desc": "Explodes 3x3 on hit"},
    "poison_arrow": {"cost": {"wood": 2, "stone": 1}, "n": 5, "station": "hand", "cat": "Archer Shop", "shop": "archer", "desc": "Poison: damage over 5 s"},
    "rope_spare": {"item": "rope", "cost": {"wood": 2}, "n": 1, "station": "hand", "cat": "Archer Shop", "shop": "archer"},
    "ladder_pack": {"item": "ladder", "cost": {"wood": 6}, "n": 8, "station": "hand", "cat": "Builder Shop", "shop": "builder"},
    "torch_pack": {"item": "torch", "cost": {"wood": 2, "stone": 1}, "n": 10, "station": "hand", "cat": "Builder Shop", "shop": "builder"},
    "medkit_pack": {"item": "medkit", "cost": {"wood": 3, "metal": 2}, "n": 3, "station": "hand", "cat": "Warrior Shop", "shop": "warrior"},
    "tnt_crate": {"item": "tnt", "cost": {"stone": 5, "metal": 5}, "n": 3, "station": "hand", "cat": "Siege Workshop", "shop": "siege"},
    "bomb_crate": {"item": "bomb", "cost": {"stone": 3, "metal": 3}, "n": 6, "station": "hand", "cat": "Siege Workshop", "shop": "siege"},
    "firebomb_crate": {"item": "firebomb", "cost": {"wood": 5, "stone": 2}, "n": 3, "station": "hand", "cat": "Siege Workshop", "shop": "siege"},
'''

WORLD_DRAW_SHOP = r'''
func _draw_shop(x: int, y: int, r: Rect2) -> void:
    var info = shop_info.get(Vector2i(x, y))
    var kind: String = info[0] if info != null else "builder"
    var col: Color = Net.SHOPS.get(kind, {}).get("color", Color("d4a017"))
    draw_rect(Rect2(r.position + Vector2(1, 8), Vector2(14, 8)), Color("6d4c41"))
    draw_rect(Rect2(r.position + Vector2(0, 2), Vector2(16, 4)), col)
    for i in 4:
        draw_rect(Rect2(r.position + Vector2(i * 4, 2), Vector2(2, 4)), col.lightened(0.4))
    draw_rect(Rect2(r.position + Vector2(1, 6), Vector2(1, 2)), Color("4e342e"))
    draw_rect(Rect2(r.position + Vector2(14, 6), Vector2(1, 2)), Color("4e342e"))
    draw_string(ThemeDB.fallback_font, r.position + Vector2(4, 15), kind.substr(0, 1).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color.WHITE)
'''

LOOK_ICONS = r'''
if item == "bomb":
    var s := r.size.x / 16.0
    var cp := r.get_center()
    ci.draw_circle(cp, 5.0 * s, Color(0.18, 0.18, 0.22))
    ci.draw_rect(Rect2(cp.x - 1.5 * s, cp.y - 7.5 * s, 3.0 * s, 3.0 * s), Color(0.55, 0.45, 0.3))
    ci.draw_circle(cp + Vector2(0, -8.0 * s), 2.0 * s, Color(1.0, 0.8, 0.2))
    return
if item == "rope":
    var s := r.size.x / 16.0
    var cp := r.get_center()
    ci.draw_arc(cp, 5.0 * s, 0.0, TAU, 12, Color(0.76, 0.6, 0.38), 2.5 * s)
    ci.draw_line(cp + Vector2(-3, 0) * s, cp + Vector2(5, 4) * s, Color(0.65, 0.5, 0.3), 2.0 * s)
    return
if item == "shop_kit":
    var s := r.size.x / 16.0
    ci.draw_rect(Rect2(r.position.x + 2 * s, r.position.y + 6 * s, 12 * s, 8 * s), Color("6d4c41"))
    ci.draw_rect(Rect2(r.position.x + 1 * s, r.position.y + 2 * s, 14 * s, 4 * s), Color("d4a017"))
    return
if item in ["fire_arrow", "bomb_arrow", "poison_arrow"]:
    var tip_col: Color = Color("ff5722") if item == "fire_arrow" else (Color("424242") if item == "bomb_arrow" else Color("7cb342"))
    var sd := r.size.x / 16.0
    var aa := r.position + Vector2(r.size.x * 0.2, r.size.y * 0.8)
    var bb := r.position + Vector2(r.size.x * 0.8, r.size.y * 0.2)
    var dv := (bb - aa).normalized()
    ci.draw_line(aa, bb, WOOD.lightened(0.2), maxf(1.0, sd * 1.2))
    ci.draw_colored_polygon(PackedVector2Array([bb + dv * 4.0 * sd, bb + dv.orthogonal() * 2.5 * sd, bb - dv.orthogonal() * 2.5 * sd]), tip_col)
    ci.draw_line(aa, aa + (dv + dv.orthogonal()) * 3.0 * sd, STRING, 1.0)
    ci.draw_line(aa, aa + (dv - dv.orthogonal()) * 3.0 * sd, STRING, 1.0)
    return
'''

LOOK_BLOCK_SHOP = r'''
29:
    var col: Color = Color("d4a017")
    ci.draw_rect(_q(r, 1, 8, 14, 8), Color("6d4c41") * md)
    ci.draw_rect(_q(r, 0, 2, 16, 4), col * md)
    for i in 4:
        ci.draw_rect(_q(r, i * 4, 2, 2, 4), col.lightened(0.4) * md)
    ci.draw_rect(_q(r, 1, 6, 1, 2), Color("4e342e") * md)
    ci.draw_rect(_q(r, 14, 6, 1, 2), Color("4e342e") * md)
'''


def apply(net, world, look):
    # net.gd: starter kits, shops, categories, recipes, ITEM_BLOCK, STRUCT_ITEMS
    net.replace('^"warrior": [["medkit", 1], ["food", 2]],',
                '"warrior": [["medkit", 1], ["food", 2], ["bomb", 2]],')
    net.replace('^"archer": [["arrow", ARROW_REFILL], ["food", 2], ["torch", 2]],',
                '"archer": [["arrow", ARROW_REFILL], ["food", 2], ["torch", 2], ["rope", 1]],')
    net.replace('^"engineer": [["wood", 20], ["stone", 10], ["platform", 6], ["wall", 10], ["torch", 2]],',
                '"engineer": [["wood", 20], ["stone", 10], ["platform", 6], ["wall", 10], ["torch", 2], ["shop_kit", 1]],')
    net.before('^const CATEGORIES :=', SHOPS_CONST)
    net.replace('^const CATEGORIES :=',
                'const CATEGORIES := ["All", "Building", "Defense", "Siege", "Light", "Consumables", "Stations", "Builder Shop", "Warrior Shop", "Archer Shop", "Siege Workshop"]')
    net.before('^"workbench": {"cost": {"wood": 10}', NEW_RECIPES)
    net.replace('^const ITEM_BLOCK :=',
                'const ITEM_BLOCK := {"wood": 3, "stone": 2, "metal": 4, "ladder": 9, "torch": 10, "spikes": 11, "tnt": 12, "spawn": 13, "catapult": 14, "storage": 15, "platform": 17, "door": 18, "workbench": 19, "siege_workshop": 20, "ballista": 21, "campfire": 22, "lantern": 23, "hatch": 24, "arrow_trap": 26, "shop": 29}')
    net.replace('^const STRUCT_ITEMS :=',
                'const STRUCT_ITEMS := ["spikes", "spawn", "catapult", "storage", "door", "workbench", "siege_workshop", "ballista", "hatch", "arrow_trap", "campfire", "lantern", "shop"]')

    # world.gd: SHOP block (29), not solid, drops a shop kit when dug
    world.after("^const RUIN_CHEST := 28", "const SHOP := 29")
    world.replace("^const HP := {",
                  "const HP := {1: 2, 2: 4, 3: 2, 4: 8, 5: 4, 6: 2, 8: 1, 9: 1, 10: 1, 11: 3, 12: 3, 13: 10, 14: 20, 15: 15, 17: 1, 18: 6, 19: 6, 20: 12, 21: 14, 22: 3, 23: 3, 24: 5, 25: 5, 26: 8, 27: 6, 28: 2, 29: 25}")
    world.replace("^const DROPS := {",
                  'const DROPS := {2: "stone", 3: "wood", 4: "metal", 5: "metal", 6: "wood", 9: "ladder", 10: "torch", 11: "spikes", 13: "spawn", 14: "catapult", 15: "storage", 17: "platform", 18: "door", 19: "workbench", 20: "siege_workshop", 21: "ballista", 22: "campfire", 23: "lantern", 24: "hatch", 25: "hatch", 26: "arrow_trap", 27: "stone", 29: "shop_kit"}')
    world.replace('^26: Color("8a93a3")', '26: Color("8a93a3"), 27: Color("9c8f7a"), 28: Color("e8b33a"), 29: Color("d4a017"),')
    world.after("^var lights := {}", "var shop_info := {}  # cell -> [shop type, team], sets game.gd")
    world.before("^var ot = owner_team.get(Vector2i(x, y))", "if b == SHOP:\n    _draw_shop(x, y, r)\n    continue")
    world.append(WORLD_DRAW_SHOP)

    # look.gd: icons and block shape
    look.before("^var idx := ITEM_ORDER.find(item)", LOOK_ICONS)
    look.before("^_:", LOOK_BLOCK_SHOP)

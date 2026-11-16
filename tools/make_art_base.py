# Генерує весь піксель-арт у assets/. Запуск: python tools/make_art.py (потрібен Pillow)
import math, random, os
from PIL import Image, ImageFont, ImageDraw

A = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets")
os.makedirs(A + "/characters", exist_ok=True)

def C(h):
    h = h.lstrip("#"); return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), 255)
def sh(c, f): return (max(0, min(255, int(c[0]*f))), max(0, min(255, int(c[1]*f))), max(0, min(255, int(c[2]*f))), c[3] if len(c) > 3 else 255)
def px(im, x, y, c):
    if 0 <= x < im.width and 0 <= y < im.height: im.putpixel((int(x), int(y)), c)
def rect(im, x0, y0, x1, y1, c):
    for y in range(int(y0), int(y1)+1):
        for x in range(int(x0), int(x1)+1): px(im, x, y, c)
def line(im, x0, y0, x1, y1, c, th=1):
    x0, y0, x1, y1 = int(round(x0)), int(round(y0)), int(round(x1)), int(round(y1))
    dx, dy = abs(x1-x0), -abs(y1-y0); sx = 1 if x0 < x1 else -1; sy = 1 if y0 < y1 else -1; e = dx+dy
    while True:
        rect(im, x0, y0, x0+th-1, y0+th-1, c)
        if x0 == x1 and y0 == y1: break
        e2 = 2*e
        if e2 >= dy: e += dy; x0 += sx
        if e2 <= dx: e += dx; y0 += sy

def outline(im, col=(26, 18, 30, 255)):
    out = im.copy(); w, h = im.size
    for y in range(h):
        for x in range(w):
            if im.getpixel((x, y))[3] == 0:
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x+dx, y+dy
                    if 0 <= nx < w and 0 <= ny < h and im.getpixel((nx, ny))[3] > 200:
                        out.putpixel((x, y), col); break
    return out

def bevel(im):
    for x in range(16):
        for y, f in ((0, 1.12), (15, 0.82)):
            p = im.getpixel((x, y))
            if p[3]: im.putpixel((x, y), sh(p, f))
    for y in range(1, 15):
        p = im.getpixel((0, y)); q = im.getpixel((15, y))
        if p[3]: im.putpixel((0, y), sh(p, 1.06))
        if q[3]: im.putpixel((15, y), sh(q, 0.9))
    return im

# ------------------------------------------------------------------ blocks (16x16, 3 variants per id)
def new(w=16, h=16): return Image.new("RGBA", (w, h), (0, 0, 0, 0))
def noise_fill(im, base, r, amt=0.12):
    for y in range(im.height):
        for x in range(im.width): px(im, x, y, sh(base, 1+r.uniform(-amt, amt)))

def t_dirt(v, grass=False):
    r = random.Random(100+v); im = new(); noise_fill(im, C("7a5230"), r)
    for _ in range(8): px(im, r.randrange(16), r.randrange(16), C("5a3a20"))
    for _ in range(5): x, y = r.randrange(15), r.randrange(15); px(im, x, y, C("9a7248")); px(im, x+1, y, C("8a6238"))
    if grass:
        for x in range(16):
            h = 3 + r.choice([0, 1, 1, 2])
            for y in range(h): px(im, x, y, sh(C("3fa34d"), 1+r.uniform(-.15, .15)))
            px(im, x, h-1, C("2b7a3a")); px(im, x, 0, C("6fcf6a"))
    return im
def t_stone(v):
    r = random.Random(200+v); im = new(); noise_fill(im, C("7f8c8d"), r, .1)
    for _ in range(2):
        x, y = r.randrange(16), r.randrange(16)
        for _ in range(7): px(im, x, y, C("56626a")); x = (x+r.choice([-1, 0, 1])) % 16; y = (y+1) % 16
    for _ in range(6): px(im, r.randrange(16), r.randrange(16), C("a5b1b2"))
    rect(im, 0, 0, 15, 0, C("94a1a2")); rect(im, 0, 15, 15, 15, C("5e6a6c"))
    return im
def t_wood(v):
    r = random.Random(300+v); im = new(); noise_fill(im, C("b9854a"), r, .07)
    for yy in (0, 8): rect(im, 0, yy+7, 15, yy+7, C("6d4a22")); rect(im, 0, yy, 15, yy, C("d0a066"))
    for yy in (0, 8):
        for _ in range(4): x = r.randrange(16); px(im, x, yy+r.randrange(1, 6), C("9a6c36"))
    for x, y in ((1, 2), (14, 2), (1, 10), (14, 10)): px(im, x, y, C("3e2a14"))
    return im
def t_metal(v):
    r = random.Random(400+v); im = new(); noise_fill(im, C("aab7c4"), r, .04)
    rect(im, 0, 0, 15, 0, C("e4ecf3")); rect(im, 0, 0, 0, 15, C("d3dde6"))
    rect(im, 0, 15, 15, 15, C("5e6a76")); rect(im, 15, 0, 15, 15, C("6b7885"))
    for x, y in ((2, 2), (13, 2), (2, 13), (13, 13)): px(im, x, y, C("48535e")); px(im, x-1, y-1, C("f2f6f9")) if False else None
    for i in range(3, 13): px(im, i, 15-i, C("c4d0db"))
    return im
def t_ore(v):
    r = random.Random(500+v); im = t_stone(v)
    for cx, cy in ((4, 4), (11, 9), (5, 12)):
        for dx, dy in ((0, 0), (1, 0), (0, 1), (1, 1), (-1, 0)):
            px(im, cx+dx, cy+dy, C("e6b800"))
        px(im, cx, cy, C("fff3a0")); px(im, cx+1, cy+1, C("b8860b"))
    return im
def t_trunk(v):
    r = random.Random(600+v); im = new()
    for x in range(4, 12):
        for y in range(16): px(im, x, y, sh(C("6d4c41"), 1+r.uniform(-.1, .1)))
    for y in range(16):
        px(im, 4, y, C("4e342e")); px(im, 11, y, C("4e342e")); px(im, 6, y, C("5d4037")) if y % 3 else None; px(im, 8, y, C("8d6e63")) if y % 4 == 1 else None
    if v == 1: rect(im, 7, 6, 8, 7, C("3e2723"))
    return im
def t_base(v):
    im = new(); rect(im, 0, 0, 15, 15, C("2c3e50"))
    for y in (0, 5, 10): rect(im, 0, y, 15, y, C("1b2836"))
    for x in (3, 11): rect(im, x, 0, x, 4, C("1b2836")); rect(im, x+(-2 if x == 3 else 2) % 16, 5, x, 9, C("1b2836")) if False else None
    for x in (7,): rect(im, x, 5, x, 9, C("1b2836"))
    for x in (3, 11): rect(im, x, 10, x, 15, C("1b2836"))
    rect(im, 0, 15, 15, 15, C("1b2836")); rect(im, 0, 0, 15, 0, C("3d566e"))
    px(im, 7, 7, C("4fd1e5")); px(im, 8, 8, C("4fd1e5")); px(im, 7, 8, C("1b8aa0"))
    return im
def t_leaf(v):
    r = random.Random(800+v); im = new()
    for y in range(16):
        for x in range(16):
            d = math.hypot(x-7.5, y-7.5)
            if d < 8.5 and r.random() > 0.14 + max(0, d-6)*0.12:
                px(im, x, y, sh(C("2ecc71"), 1+r.uniform(-.25, .1)))
    for _ in range(10):
        x, y = r.randrange(16), r.randrange(16)
        if im.getpixel((x, y))[3]: px(im, x, y, C("1e8449"))
    for _ in range(6):
        x, y = r.randrange(16), r.randrange(8)
        if im.getpixel((x, y))[3]: px(im, x, y, C("7dffa0"))
    return im
def t_ladder(v):
    im = new()
    for y in range(16): px(im, 3, y, C("8d6e63")); px(im, 4, y, C("6d4c41")); px(im, 11, y, C("8d6e63")); px(im, 12, y, C("6d4c41"))
    for y in (2, 7, 12): rect(im, 5, y, 10, y+1, C("a1887f")); rect(im, 5, y+1, 10, y+1, C("795548"))
    return im
def t_torch(v):
    im = new(); rect(im, 7, 7, 8, 15, C("6d4c41")); rect(im, 7, 7, 7, 15, C("8d6e63"))
    rect(im, 6, 4, 9, 7, C("ff9800")); rect(im, 7, 2, 8, 5, C("ffc107")); rect(im, 7, 3, 8, 4, C("fff59d")); px(im, 7, 1, C("ff9800"))
    return im
def t_spikes(v):
    im = new(); rect(im, 0, 13, 15, 15, C("455a64")); rect(im, 0, 13, 15, 13, C("78909c"))
    for k in range(4):
        x = k*4
        for i in range(8):
            w = (8-i)//3
            rect(im, x+1-w+1, 13-i-1, x+2+w-1, 13-i-1, C("cfd8dc"))
        px(im, x+1, 8, C("ffffff"))
    return im
def glyph(im, ch, x, y, c):
    G = {"T": ["111", "010", "010", "010", "010"], "N": ["101", "111", "111", "101", "101"]}
    for j, row in enumerate(G[ch]):
        for i, b in enumerate(row):
            if b == "1": px(im, x+i, y+j, c)
def t_tnt(v):
    im = new(); rect(im, 1, 1, 14, 15, C("c0392b")); rect(im, 1, 1, 14, 1, C("e74c3c")); rect(im, 1, 15, 14, 15, C("922b21"))
    for x in (4, 9): rect(im, x, 1, x, 15, C("a93226"))
    rect(im, 1, 5, 14, 11, C("f5f0e1")); glyph(im, "T", 2, 6, C("222222")); glyph(im, "N", 6, 6, C("222222")); glyph(im, "T", 10, 6, C("222222"))
    rect(im, 7, 0, 8, 0, C("5d4037")); px(im, 8, 0, C("ffb300"))
    return im
def t_spawn(v):
    im = new(); rect(im, 0, 12, 15, 15, C("546e7a")); rect(im, 0, 12, 15, 12, C("90a4ae")); rect(im, 0, 15, 15, 15, C("37474f"))
    for x in range(3, 13): px(im, x, 11, C("26c6da"))
    for x in range(4, 12): px(im, x, 10, C("80deea"))
    for x in range(5, 11): px(im, x, 9, (38, 198, 218, 150))
    for x in range(6, 10): px(im, x, 8, (38, 198, 218, 90))
    return im
def t_catapult(v):
    im = new(); rect(im, 0, 10, 15, 12, C("8d6e63")); rect(im, 0, 10, 15, 10, C("a1887f"))
    for cx in (4, 12):
        for dx in range(-2, 3):
            for dy in range(-2, 3):
                if dx*dx+dy*dy <= 5: px(im, cx+dx, 13+dy-1, C("3e2723"))
        px(im, cx, 12, C("8d6e63"))
    rect(im, 6, 5, 7, 10, C("6d4c41"))
    line(im, 4, 10, 13, 2, C("5d4037"), 2); rect(im, 12, 0, 15, 2, C("4e342e")); px(im, 13, 1, C("9e9e9e"))
    return im
def t_storage(v):
    im = new(); rect(im, 1, 5, 14, 15, C("8d6e43")); rect(im, 1, 5, 14, 8, C("a1824f")); rect(im, 1, 5, 14, 5, C("c9a25f"))
    rect(im, 1, 15, 14, 15, C("5d4a2a"))
    for x in (3, 12): rect(im, x, 5, x, 15, C("5d4a2a"))
    rect(im, 1, 8, 14, 8, C("5d4a2a")); rect(im, 7, 7, 8, 10, C("ffd54f")); px(im, 7, 9, C("8a6d00"))
    return im
def t_cave(v):
    r = random.Random(900+v); im = new(); noise_fill(im, C("3b2a22"), r, .15)
    for _ in range(5): px(im, r.randrange(16), r.randrange(16), C("2a1c16"))
    return im

TILES = {1: t_dirt, 2: t_stone, 3: t_wood, 4: t_metal, 5: t_ore, 6: t_trunk, 7: t_base, 8: t_leaf, 9: t_ladder, 10: t_torch, 11: t_spikes, 12: t_tnt, 13: t_spawn, 14: t_catapult, 15: t_storage}
atlas = new(256, 64)
for bid, fn in TILES.items():
    for v in range(3):
        t = fn(v)
        if bid in (1, 5, 7): t = bevel(t)
        atlas.paste(t, (bid*16, v*16))
atlas.paste(t_cave(0), (0, 48)); atlas.paste(t_dirt(0, True), (16, 48))
atlas.save(A + "/blocks.png")

# ------------------------------------------------------------------ item icons (16x16)
def icon_wood():
    im = new(); line(im, 2, 12, 12, 4, C("8d6e43"), 3); line(im, 3, 12, 13, 5, C("6d4c41"), 1); rect(im, 11, 3, 13, 5, C("d7b27a")); px(im, 12, 4, C("8d6e43")); return im
def icon_stone():
    im = new()
    for y in range(16):
        for x in range(16):
            if math.hypot(x-7.5, y-9) < 6 + (x % 3)*0.3: px(im, x, y, C("95a5a6"))
    for x, y in ((5, 8), (9, 6), (8, 11)): px(im, x, y, C("c5d0d1"))
    for x, y in ((6, 13), (10, 12), (11, 9)): px(im, x, y, C("5f6d6e"))
    return im
def icon_metal():
    im = new(); rect(im, 3, 6, 12, 11, C("b0bec5")); rect(im, 3, 6, 12, 7, C("eceff1")); rect(im, 3, 11, 12, 11, C("607d8b")); rect(im, 12, 7, 12, 11, C("78909c"))
    rect(im, 5, 4, 10, 5, C("cfd8dc")); return im
def icon_ladder():
    im = new(); line(im, 4, 14, 8, 1, C("8d6e63"), 2); line(im, 9, 14, 13, 1, C("8d6e63"), 2)
    for k in range(4): line(im, 5+k*0.9, 12-k*3.4, 11+k*0.9, 12-k*3.4, C("a1887f"), 1)
    return im
def icon_torch():
    return t_torch(0)
def icon_spikes():
    im = new(); rect(im, 1, 12, 14, 14, C("455a64"))
    for k in range(3): line(im, 2+k*5, 12, 4+k*5, 3, C("cfd8dc"), 1); line(im, 4+k*5, 3, 6+k*5, 12, C("90a4ae"), 1)
    return im
def icon_firebomb():
    im = new()
    for y in range(16):
        for x in range(16):
            if math.hypot(x-7.5, y-9.5) < 5: px(im, x, y, C("37474f"))
    rect(im, 6, 3, 9, 5, C("90a4ae")); line(im, 8, 3, 11, 0, C("8d6e63")); px(im, 12, 0, C("ffb300")); px(im, 11, 1, C("ff7043"))
    px(im, 6, 8, C("78909c")); px(im, 6, 9, C("78909c")); return im
def icon_medkit():
    im = new(); rect(im, 2, 4, 13, 13, C("eceff1")); rect(im, 2, 4, 13, 4, C("ffffff")); rect(im, 2, 13, 13, 13, C("b0bec5"))
    rect(im, 7, 6, 8, 11, C("e53935")); rect(im, 5, 8, 10, 9, C("e53935")); rect(im, 6, 2, 9, 3, C("90a4ae")); return im
def icon_food():
    im = new()
    for y in range(16):
        for x in range(16):
            if ((x-7.5)/6.5)**2 + ((y-9)/4.5)**2 < 1: px(im, x, y, C("d9a066"))
    for x, y in ((5, 8), (8, 7), (10, 9)): px(im, x, y, C("f0c987"))
    for x, y in ((6, 11), (9, 12)): px(im, x, y, C("a8743c"))
    return im
ICONS = [icon_wood, icon_stone, icon_metal, icon_ladder, icon_torch, icon_spikes, lambda: t_tnt(0), icon_firebomb, lambda: t_spawn(0), lambda: t_storage(0), lambda: t_catapult(0), icon_medkit, icon_food]
ic = new(16*len(ICONS), 16)
for i, f in enumerate(ICONS): ic.paste(outline(f()), (i*16, 0))
ic.save(A + "/items.png")

# ------------------------------------------------------------------ characters (24x32 frames, 22 frames)
SKIN = C("f1c27d"); SKIN_D = C("d19a5a"); PANTS = C("3b3f58"); BOOT = C("3e2a1a"); OUT = C("20161a")
CLS = {
    "warrior": {"tunic": C("b03a2e"), "dark": C("7e2a20")},
    "archer": {"tunic": C("27ae60"), "dark": C("1b7a44")},
    "engineer": {"tunic": C("ca6f1e"), "dark": C("964f12")},
    "support": {"tunic": C("8e44ad"), "dark": C("633078")},
}
TEAM = {"blue": C("2e86de"), "red": C("e74c3c")}

def tool(im, cls, hx, hy, dx, dy, pull=0):
    n = math.hypot(dx, dy) or 1; dx, dy = dx/n, dy/n
    if cls == "warrior":
        ex, ey = hx+dx*10, hy+dy*10
        line(im, hx, hy, ex, ey, C("e0e6ea"), 1); line(im, hx+(-dy), hy+dx, ex+(-dy), ey+dx, C("9aa7b0"), 1) if False else None
        px(im, ex, ey, C("ffffff"))
        gx, gy = hx+dx*2, hy+dy*2; line(im, gx-dy*2, gy+dx*2, gx+dy*2, gy-dx*2, C("c9a227"), 1); rect(im, hx-1, hy-1, hx, hy, C("5d4037"))
    elif cls == "archer":
        line(im, hx+1, hy-7, hx+3, hy, C("6d4c41"), 1); line(im, hx+3, hy, hx+1, hy+7, C("6d4c41"), 1); line(im, hx+3, hy-6, hx+4, hy-3, C("8d6e63"), 1); line(im, hx+4, hy+3, hx+3, hy+6, C("8d6e63"), 1)
        sx = hx-pull; line(im, hx+1, hy-7, sx, hy, C("e8e8e8"), 1); line(im, sx, hy, hx+1, hy+7, C("e8e8e8"), 1)
        if pull: line(im, sx, hy, hx+9, hy, C("cfd8dc"), 1); px(im, hx+10, hy, C("90a4ae"))
    elif cls == "engineer":
        ex, ey = hx+dx*8, hy+dy*8; line(im, hx, hy, ex, ey, C("8d6e63"), 1)
        pxx, pyy = -dy, dx; rect(im, ex-2+int(pxx*0), ey-2, ex+2, ey+1, C("90a4ae")); rect(im, ex-2, ey-2, ex+2, ey-2, C("cfd8dc"))
    else:
        ex, ey = hx+dx*13, hy+dy*13; line(im, hx-dx*3, hy-dy*3, ex, ey, C("8d6e43"), 1)
        rect(im, ex-1, ey-1, ex+1, ey+1, C("4dd0e1")); px(im, ex, ey, C("e0f7fa")); px(im, ex-2, ey, (77, 208, 225, 120)); px(im, ex+2, ey, (77, 208, 225, 120))

def character(cls, team, bob=0, legA=(0, 0), legB=(0, 0), armF=(3, 6), armB=(-3, 6), crouch=0, lean=0, tdir=(0.6, -0.8), show_tool=True, shield=False, hurt=False, eyes_closed=False, pull=0, cape=0):
    im = new(24, 32); k = CLS[cls]; tc = TEAM[team]; tcd = sh(tc, .7)
    bx = 12 + lean; hipy = 20 + crouch + bob*0; top = bob
    # cape (behind)
    for y in range(13+crouch, 23+crouch):
        w = 3 + (1 if y > 17+crouch else 0)
        rect(im, bx-4-w+cape*((y-13)//4), y+top, bx-4, y+top, tc if y % 2 else tcd)
    # back arm
    ax, ay = bx+armB[0], 13+crouch+top+armB[1]; line(im, bx-1, 13+crouch+top, ax, ay, sh(k["dark"], 1), 2); rect(im, ax, ay, ax+1, ay+1, SKIN_D)
    # legs
    for (dx, lift), hx in ((legA, bx-3), (legB, bx+1)):
        fy = 29 - lift; fx = hx + dx
        line(im, hx+1, hipy+top, fx+1, fy-1, PANTS, 3); rect(im, fx, fy-1, fx+3, fy, BOOT)
    # torso
    rect(im, bx-4, 12+crouch+top, bx+3, 19+crouch+top, k["tunic"]); rect(im, bx-4, 12+crouch+top, bx+3, 12+crouch+top, sh(k["tunic"], 1.25))
    rect(im, bx-4, 18+crouch+top, bx+3, 18+crouch+top, tc); rect(im, bx-4, 19+crouch+top, bx+3, 19+crouch+top, sh(k["tunic"], .7))
    rect(im, bx-4, 12+crouch+top, bx-2, 13+crouch+top, tc)  # shoulder team pad
    # head
    hy = 3 + crouch + top; rect(im, bx-4, hy, bx+3, hy+7, SKIN); rect(im, bx-4, hy+7, bx+3, hy+7, SKIN_D)
    px(im, bx+2, hy+4, OUT if not eyes_closed else SKIN_D); px(im, bx+1, hy+4, C("ffffff")) if not eyes_closed else None; px(im, bx+2, hy+6, SKIN_D)
    if cls == "warrior":
        rect(im, bx-5, hy-1, bx+3, hy+2, C("aab4bd")); rect(im, bx-5, hy-1, bx+3, hy-1, C("e0e6ea")); rect(im, bx+2, hy+3, bx+3, hy+5, C("aab4bd"))
        rect(im, bx-2, hy-3, bx+1, hy-2, C("c0392b"))
    elif cls == "archer":
        rect(im, bx-5, hy-1, bx+3, hy+2, C("1b7a44")); rect(im, bx-6, hy+1, bx-5, hy+4, C("1b7a44")); rect(im, bx-4, hy-1, bx+2, hy-1, C("27ae60"))
        line(im, bx+1, hy-1, bx-1, hy-4, C("ecf0f1"), 1)
    elif cls == "engineer":
        rect(im, bx-5, hy-1, bx+4, hy+1, C("f1c40f")); rect(im, bx-4, hy-2, bx+2, hy-2, C("f1c40f")); rect(im, bx-5, hy+1, bx+4, hy+1, C("c9a000")); px(im, bx, hy-2, C("fff59d"))
    else:
        rect(im, bx-5, hy-1, bx+3, hy+3, C("ece6d6")); rect(im, bx-6, hy+1, bx-5, hy+5, C("ece6d6")); px(im, bx+1, hy-1, C("4dd0e1")); rect(im, bx-4, hy-2, bx+1, hy-2, C("ece6d6"))
    # front arm + tool
    fx, fy = bx+armF[0], 13+crouch+top+armF[1]
    if shield:
        rect(im, bx+4, 11+crouch+top, bx+7, 22+crouch+top, C("90a4ae")); rect(im, bx+4, 11+crouch+top, bx+4, 22+crouch+top, C("cfd8dc")); rect(im, bx+5, 14+crouch+top, bx+6, 18+crouch+top, tc)
        fx, fy = bx+4, 15+crouch+top
    if show_tool: tool(im, cls, fx, fy, tdir[0], tdir[1], pull)
    line(im, bx+2, 13+crouch+top, fx, fy, k["tunic"], 2); rect(im, fx, fy, fx+1, fy+1, SKIN)
    if hurt:
        for y in range(32):
            for x in range(24):
                p = im.getpixel((x, y))
                if p[3]: im.putpixel((x, y), (min(255, p[0]+70), min(255, p[1]+30), min(255, p[2]+30), 255))
    return im

def frames(cls, team):
    F = []
    F.append(character(cls, team, 0, tdir=(0.5, -0.85), armF=(3, 5))); F.append(character(cls, team, 1, tdir=(0.5, -0.85), armF=(3, 6), armB=(-3, 7)))
    for i in range(6):
        ph = i/6*2*math.pi; s = math.sin(ph); lift = 2 if math.cos(ph) > .4 else 0
        F.append(character(cls, team, 1 if i % 3 == 0 else 0, legA=(round(3*s), lift), legB=(round(-3*s), 2 if math.cos(ph) < -.4 else 0), armF=(round(-3*s)+2, 6), armB=(round(3*s)-2, 6), tdir=(0.5, -0.85), cape=1 if i % 2 else 0))
    F.append(character(cls, team, 0, legA=(-2, 4), legB=(2, 2), armF=(4, -3), armB=(-4, -2), tdir=(0.3, -1), cape=-1))
    F.append(character(cls, team, 0, legA=(-3, 1), legB=(3, 0), armF=(5, 1), armB=(-5, 1), tdir=(0.9, -0.3), cape=2))
    F.append(character(cls, team, 0, crouch=7, legA=(-2, 0), legB=(2, 0), armF=(4, 4), armB=(-3, 5), tdir=(0.8, -0.5)))
    F.append(character(cls, team, 0, legA=(-1, 2), legB=(1, 0), armF=(2, -5), armB=(-2, -3), show_tool=False))
    F.append(character(cls, team, 0, legA=(1, 0), legB=(-1, 2), armF=(-2, -3), armB=(2, -5), show_tool=False))
    pulls = (0, 3, 0)
    for i, (arm, td) in enumerate((((2, -6), (-0.3, -1)), ((7, 0), (1, 0)), ((5, 5), (0.7, 0.7)))):
        a = (5, -1) if cls == "archer" else arm
        F.append(character(cls, team, 0, armF=a, armB=(-4, 3), tdir=td, lean=(1 if i == 1 else 0), pull=(5 if (cls == "archer" and i == 0) else 0), legA=(-2, 0), legB=(2, 0)))
    F.append(character(cls, team, 0, shield=True, armF=(4, 4), armB=(-3, 6), show_tool=False))
    F.append(character(cls, team, 0, lean=-2, armF=(1, -4), armB=(-5, -3), hurt=True, eyes_closed=True, show_tool=False, legA=(-2, 0), legB=(2, 1)))
    base = character(cls, team, 0, tdir=(0.5, -0.85))
    for ang in (-35, -65, -90):
        rot = base.rotate(ang, resample=Image.NEAREST, center=(12, 29))
        F.append(rot)
    F.append(character(cls, team, 0, crouch=5, lean=3, legA=(-4, 0), legB=(-2, 0), armF=(5, 3), armB=(-1, 3), tdir=(1, 0), cape=3))
    return F

for cls in CLS:
    for team in TEAM:
        F = frames(cls, team); assert len(F) == 22, len(F)
        sheet = new(24*22, 32)
        for i, f in enumerate(F): sheet.paste(outline(f), (i*24, 0))
        sheet.save(f"{A}/characters/{cls}_{team}.png")

# ------------------------------------------------------------------ flags (3 frames of 18x30 per team)
for team, col in TEAM.items():
    sheet = new(54, 30)
    for f in range(3):
        im = new(18, 30); rect(im, 2, 0, 3, 29, C("6d4c41")); rect(im, 2, 0, 2, 29, C("8d6e63")); rect(im, 1, 0, 4, 1, C("ffd54f"))
        for x in range(4, 18):
            wave = round(math.sin((x*0.6)+f*2.1)*1.5)
            for y in range(3, 13):
                px(im, x, y+wave, col if (y+x) % 5 else sh(col, .85))
            px(im, x, 3+wave, sh(col, 1.2)); px(im, x, 12+wave, sh(col, .6))
        rect(im, 8, 6, 10, 9, (255, 255, 255, 230))  # emblem
        sheet.paste(im, (f*18, 0))
    sheet.save(f"{A}/flag_{team}.png")

# ------------------------------------------------------------------ backgrounds
sky = new(1, 128)
for y in range(128):
    t = y/127; sky.putpixel((0, y), (int(88+(185-88)*t), int(160+(225-160)*t), int(228+(245-228)*t), 255))
sky.save(A + "/sky.png")

def mountains(w, h, seed, col, snow, amp, per):
    im = new(w, h); r = random.Random(seed); ph = [r.uniform(0, 6.28) for _ in per]
    for x in range(w):
        y = h - 8 - sum(amp[i]*(0.5+0.5*math.sin(2*math.pi*per[i]*x/w + ph[i])) for i in range(len(per)))
        y = int(y)
        for yy in range(y, h):
            c = sh(col, 1.0 - (yy-y)*0.004)
            if snow and yy - y < 3 and y < h*0.4: c = (240, 245, 250, 255)
            px(im, x, yy, c)
    return im
mountains(256, 96, 3, C("7d93b8"), True, [34, 22, 10], [2, 5, 11]).save(A + "/mountains_far.png")
mountains(256, 64, 9, C("5a7fa0"), False, [22, 12, 6], [3, 7, 13]).save(A + "/mountains_near.png")
cl = new(144, 20)
for i, (cx, w) in enumerate(((24, 20), (72, 28), (120, 16))):
    for dx in range(-w, w+1):
        hh = int(7*math.sqrt(max(0, 1-(dx/w)**2)))
        for dy in range(-hh, 3): px(cl, cx+dx, 12+dy, (255, 255, 255, 235) if dy < 1 else (215, 230, 245, 235))
cl.save(A + "/clouds.png")

# ------------------------------------------------------------------ logo + icon
try:
    font = ImageFont.load_default()
except Exception:
    font = None
def pixel_text(text, scale, col, shadow):
    tmp = Image.new("L", (len(text)*8, 12), 0); ImageDraw.Draw(tmp).text((0, 0), text, fill=255, font=font)
    bb = tmp.getbbox() or (0, 0, 1, 1); tmp = tmp.crop(bb).resize(((bb[2]-bb[0])*scale, (bb[3]-bb[1])*scale), Image.NEAREST)
    out = Image.new("RGBA", (tmp.width+scale*2, tmp.height+scale*2), (0, 0, 0, 0))
    for (ox, oy, c) in ((scale, scale, shadow), (0, 0, col)):
        for y in range(tmp.height):
            for x in range(tmp.width):
                if tmp.getpixel((x, y)) > 100: out.putpixel((x+ox, y+oy), c)
    return out
pixel_text("PIXEL SIEGE", 5, C("ffd54f"), C("5d3a00")).save(A + "/logo.png")
icon = new(64, 64)
for y in range(64):
    for x in range(64): icon.putpixel((x, y), (88, 160, 228, 255) if y < 40 else (122, 82, 48, 255))
for x in range(64):
    for y in range(40, 46): icon.putpixel((x, y), (63, 163, 77, 255))
rect(icon, 30, 8, 33, 44, C("6d4c41")); rect(icon, 34, 8, 54, 22, C("e74c3c")); rect(icon, 36, 12, 40, 16, C("ffffff"))
rect(icon, 8, 30, 24, 44, C("7f8c8d")); rect(icon, 8, 30, 24, 31, C("b0bec5"))
icon.save(A + "/icon.png")

# ------------------------------------------------------------------ fire (4 frames 16x16)
fire = new(64, 16)
for f in range(4):
    r = random.Random(1000+f)
    for x in range(2, 14):
        hgt = int(12 - abs(x-7.5)*1.5 + r.uniform(-2, 2) + (1 if (x+f) % 3 == 0 else 0))
        for y in range(15, 15-max(hgt, 2), -1):
            rel = (15-y)/max(hgt, 2)
            c = (255, 232, 90, 255) if rel < .4 else (255, 140, 30, 255) if rel < .75 else (222, 62, 20, 235)
            px(fire, f*16+x, y, c)
    for _ in range(3): px(fire, f*16+r.randrange(3, 13), r.randrange(0, 5), (255, 200, 80, 200))
fire.save(A + "/fire.png")

# ------------------------------------------------------------------ explosion (6 frames 64x64)
boom = new(64*6, 64)
for f in range(6):
    r = random.Random(2000+f)
    rad = 8 + f*4.6; wob = [r.uniform(0.85, 1.15) for _ in range(12)]
    for y in range(64):
        for x in range(64):
            dx, dy = x-31.5, y-31.5; d = math.hypot(dx, dy)
            ang = math.atan2(dy, dx); idx = int((ang+math.pi)/(2*math.pi)*12) % 12
            re = rad*wob[idx]
            if d < re:
                q = d/re
                if f >= 4: c = (90, 90, 95, int(200-(f-4)*70)); 
                elif q < .35: c = (255, 250, 200, 255)
                elif q < .65: c = (255, 170, 40, 255)
                else: c = (200, 60, 25, 240)
                if f < 4 and r.random() < 0.08: c = (60, 40, 35, 255)
                px(boom, f*64+x, y, c)
boom.save(A + "/boom.png")

# ------------------------------------------------------------------ sun / moon (32x32)
sun = new(32, 32)
for y in range(32):
    for x in range(32):
        d = math.hypot(x-15.5, y-15.5)
        if d < 8.5: px(sun, x, y, (255, 236, 110, 255) if d < 6.5 else (255, 190, 50, 255))
        elif d < 15: px(sun, x, y, (255, 230, 120, int(70*(1-(d-8.5)/6.5))))
for ang in range(0, 360, 45):
    a = math.radians(ang)
    for k in range(10, 14): px(sun, round(15.5+math.cos(a)*k), round(15.5+math.sin(a)*k), (255, 215, 80, 255))
sun.save(A + "/sun.png")
moon = new(32, 32)
for y in range(32):
    for x in range(32):
        d = math.hypot(x-15.5, y-15.5)
        if d < 8: px(moon, x, y, (232, 236, 246, 255) if math.hypot(x-13, y-14) < 7 else (190, 198, 220, 255))
        elif d < 14: px(moon, x, y, (190, 205, 255, int(60*(1-(d-8)/6))))
for cx, cy, r_ in ((12, 12, 2), (18, 17, 2), (13, 19, 1)):
    for dx in range(-r_, r_+1):
        for dy in range(-r_, r_+1):
            if dx*dx+dy*dy <= r_*r_: px(moon, cx+dx, cy+dy, (165, 172, 198, 255))
moon.save(A + "/moon.png")

# ------------------------------------------------------------------ far forest (256x64, tileable)
trees = new(256, 64); r = random.Random(77)
def wpx(im, x, y, c): px(im, x % 256, y, c)
for i in range(19):
    cx = i*13 + r.randrange(0, 5); hgt = r.randrange(26, 44); base = 63
    for tier in range(3):
        top = base-hgt+tier*(hgt//4); bot = top+hgt//2
        for y in range(top, min(bot, 63)+1):
            wdt = int((y-top)/max(1, (bot-top))*(5+tier*2))+1
            for x in range(cx-wdt, cx+wdt+1): wpx(trees, x, y, (38, 84, 66, 255) if x < cx+wdt-1 else (52, 108, 82, 255))
    for y in range(base-6, base+1): wpx(trees, cx, y, (58, 42, 30, 255))
trees.save(A + "/trees_far.png")

# ------------------------------------------------------------------ surface decor (8 frames 16x16)
dec = new(128, 16); r = random.Random(55)
def blade(im, ox, x, h, c):
    for k in range(h): px(im, ox+x+(1 if k > h*0.6 else 0), 15-k, c)
for f in range(3):
    for x, h in ((4, 4+f), (7, 6+f), (10, 3+f), (12, 4)):
        blade(dec, f*16, x, h, (60, 170, 80, 255)); px(dec, f*16+x, 15-h, (110, 220, 120, 255))
for f, pc in ((3, (225, 60, 70, 255)), (4, (250, 215, 60, 255))):
    ox = f*16; rect(dec, ox+7, 10, ox+7, 15, (50, 140, 60, 255)); px(dec, ox+6, 13, (60, 170, 80, 255)); px(dec, ox+8, 12, (60, 170, 80, 255))
    for dx, dy in ((0, 0), (-1, 0), (1, 0), (0, -1), (0, 1)): px(dec, ox+7+dx, 8+dy, pc)
    px(dec, ox+7, 8, (255, 245, 200, 255))
ox = 5*16; rect(dec, ox+7, 12, ox+8, 15, (235, 225, 205, 255)); rect(dec, ox+5, 9, ox+10, 11, (200, 50, 50, 255)); px(dec, ox+6, 10, (255, 255, 255, 255)); px(dec, ox+9, 10, (255, 255, 255, 255))
ox = 6*16
for x, y in ((4, 14), (6, 14), (9, 14), (7, 13), (11, 14)): px(dec, ox+x, y, (140, 150, 155, 255)); px(dec, ox+x+1, y, (110, 120, 125, 255))
ox = 7*16
for x in range(3, 13):
    for y in range(9, 16):
        if math.hypot(x-7.5, (y-14)*1.4) < 4.5: px(dec, ox+x, y, (46, 150, 80, 255) if (x+y) % 3 else (80, 190, 105, 255))
dec.save(A + "/decor.png")
print("art ok")

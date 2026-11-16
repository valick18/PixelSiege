# Генератор арту v2 (запускає базовий скрипт, потім перемальовує персонажів, блоки, фони, UI, ефекти).
import os
_base = os.path.join(os.path.dirname(os.path.abspath(__file__)), "make_art_base.py")
exec(compile(open(_base).read().replace('print("art ok")', ''), _base, "exec"))

PAL = {"hair": C("5a3a22")}
def lerpc(a, b, t): return tuple(int(a[i]+(b[i]-a[i])*t) for i in range(3)) + (255,)
def ramp(c): return [sh(c, 1.3), sh(c, 1.0), sh(c, .78), sh(c, .58)]
def vgrad(im, x0, y0, x1, y1, rp):
    n = y1-y0+1
    for i in range(n): rect(im, x0, y0+i, x1, y0+i, rp[min(len(rp)-1, i*len(rp)//n)])
METAL = ramp(C("a9b4bf")); GOLD = C("e0b020")
SK = [C("ffe0bd"), C("f0b88c"), C("cd8c64")]
PANTS_R = ramp(C("3b4260")); BOOT_R = ramp(C("5a3a22"))
GR = ramp(C("2a8a52")); YR = ramp(C("f1c40f")); CR = ramp(C("ece6d6")); RR = ramp(C("c0392b"))

def shade_pass(im):
    src = im.copy()
    for y in range(im.height):
        for x in range(im.width):
            p = src.getpixel((x, y))
            if p[3] == 0: continue
            ul = src.getpixel((x-1, y-1))[3] if x > 0 and y > 0 else 0
            lr = src.getpixel((x+1, y+1))[3] if x < im.width-1 and y < im.height-1 else 0
            if ul == 0: im.putpixel((x, y), sh(p, 1.15))
            elif lr == 0: im.putpixel((x, y), sh(p, .85))
    return im

def character(cls, team, bob=0, legA=(0, 0), legB=(0, 0), armF=(3, 6), armB=(-3, 6), crouch=0, lean=0, tdir=(.6, -.8), show_tool=True, shield=False, hurt=False, eyes_closed=False, pull=0, cape=0):
    im = new(24, 32); k = CLS[cls]; tc = TEAM[team]; trp = ramp(tc); krp = ramp(k["tunic"])
    bx = 12+lean; c = crouch; t = bob; top = 12+c+t; hy = 3+c+t
    for y in range(top+1, top+11):  # cape
        w = 3 + (1 if y > top+5 else 0); sway = cape*((y-top)//4)
        for x in range(bx-4-w+sway, bx-3): px(im, x, y, trp[0] if x == bx-4-w+sway else trp[1] if (y-top) < 5 else trp[2])
    if cls == "archer":
        rect(im, bx-6, top-1, bx-4, top+8, C("6d4c33")); rect(im, bx-6, top-1, bx-6, top+8, C("8a6240"))
        for i, xx in enumerate((bx-6, bx-5, bx-4)): px(im, xx, top-2-(i % 2), C("e8e8e8")); px(im, xx, top-1, (210, 60, 60, 255))
    if cls == "engineer":
        rect(im, bx-7, top+1, bx-4, top+8, C("7a5a2e")); rect(im, bx-7, top+1, bx-4, top+2, C("a07a40")); px(im, bx-6, top+4, GOLD); rect(im, bx-6, top+6, bx-5, top+7, C("445566"))
    ax, ay = bx+armB[0], top+1+armB[1]
    line(im, bx-2, top+1, ax, ay, krp[2], 2); rect(im, ax, ay, ax+1, ay+1, SK[2])
    hip = 20+c+t
    for (dx, lift), hx in ((legA, bx-3), (legB, bx)):
        fy = 29-lift; fx = hx+dx
        line(im, hx+1, hip, fx+1, fy-1, PANTS_R[1], 3)
        rect(im, fx, fy-1, fx+3, fy, BOOT_R[1]); rect(im, fx, fy, fx+3, fy, BOOT_R[3]); px(im, fx+3, fy-1, BOOT_R[0])
    vgrad(im, bx-4, top, bx+3, top+7, krp)
    if cls == "support": vgrad(im, bx-4, top+8, bx+3, top+11-min(c, 2), krp); rect(im, bx-1, top, bx, top+10-min(c, 2), CR[1])
    rect(im, bx-4, top+6, bx+3, top+6, trp[1]); px(im, bx, top+6, GOLD); px(im, bx+1, top+6, GOLD)
    if cls == "warrior":
        rect(im, bx-3, top+1, bx+2, top+4, METAL[1]); rect(im, bx-3, top+1, bx+2, top+1, METAL[0]); rect(im, bx, top+1, bx, top+4, METAL[2])
        rect(im, bx-5, top-1, bx-2, top+2, METAL[1]); rect(im, bx-5, top-1, bx-2, top-1, METAL[0])
    if cls == "archer": line(im, bx-3, top+1, bx+2, top+6, C("6d4c33"), 1)
    if cls == "engineer": rect(im, bx-4, top+4, bx+3, top+5, C("6d4c33")); px(im, bx-2, top+4, GOLD); rect(im, bx+1, top+4, bx+2, top+5, C("90a4ae"))
    rect(im, bx-4, top, bx-3, top+1, trp[0])
    rect(im, bx-3, hy, bx+3, hy+7, SK[0]); rect(im, bx-3, hy+6, bx+3, hy+7, SK[1]); rect(im, bx+3, hy+2, bx+3, hy+6, SK[1]); px(im, bx+4, hy+4, SK[1])
    if eyes_closed: rect(im, bx+1, hy+4, bx+2, hy+4, SK[2])
    else:
        rect(im, bx+1, hy+3, bx+2, hy+4, C("ffffff")); px(im, bx+2, hy+3, C("1a1a2e")); px(im, bx+2, hy+4, C("1a1a2e"))
    rect(im, bx+1, hy+2, bx+3, hy+2, PAL["hair"]); px(im, bx+2, hy+6, SK[2])
    rect(im, bx-4, hy, bx-3, hy+5, PAL["hair"])
    if cls == "warrior":
        rect(im, bx-4, hy-1, bx+3, hy+2, METAL[1]); rect(im, bx-4, hy-1, bx+3, hy-1, METAL[0]); rect(im, bx-4, hy+2, bx+3, hy+2, METAL[2])
        rect(im, bx+3, hy+2, bx+3, hy+5, METAL[2]); rect(im, bx-4, hy+2, bx-3, hy+6, METAL[2])
        rect(im, bx-3, hy-3, bx+1, hy-2, RR[1]); rect(im, bx-3, hy-3, bx+1, hy-3, RR[0]); rect(im, bx-6, hy-2, bx-4, hy, RR[2])
    elif cls == "archer":
        rect(im, bx-4, hy-1, bx+3, hy+1, GR[1]); rect(im, bx-4, hy-1, bx+3, hy-1, GR[0]); rect(im, bx-5, hy+1, bx-4, hy+6, GR[2]); rect(im, bx-4, hy+2, bx+3, hy+2, GR[2]) 
        line(im, bx+1, hy-1, bx-2, hy-5, C("ecf0f1"), 1); px(im, bx-2, hy-5, (210, 60, 60, 255))
    elif cls == "engineer":
        rect(im, bx-4, hy-1, bx+4, hy+1, YR[1]); rect(im, bx-3, hy-2, bx+2, hy-2, YR[0]); rect(im, bx-4, hy+1, bx+4, hy+1, YR[2]); rect(im, bx+2, hy-1, bx+3, hy, C("fff59d"))
    else:
        rect(im, bx-4, hy-1, bx+3, hy+2, CR[1]); rect(im, bx-3, hy-2, bx+1, hy-2, CR[0]); rect(im, bx-5, hy+1, bx-4, hy+6, CR[2]); rect(im, bx-4, hy+2, bx+3, hy+2, CR[2])
        px(im, bx, hy-1, C("4dd0e1")); px(im, bx, hy, C("e0f7fa"))
    fx, fy = bx+armF[0], top+1+armF[1]
    if shield:
        rect(im, bx+4, top-1, bx+7, top+10, METAL[1]); rect(im, bx+4, top-1, bx+4, top+10, METAL[0]); rect(im, bx+7, top-1, bx+7, top+10, METAL[3]); rect(im, bx+5, top+2, bx+6, top+6, trp[1]); px(im, bx+5, top+3, trp[0])
        fx, fy = bx+4, top+3
    if show_tool: tool(im, cls, fx, fy, tdir[0], tdir[1], pull)
    line(im, bx+2, top+1, fx, fy, krp[1], 2); rect(im, fx, fy, fx+1, fy+1, SK[0])
    if hurt:
        for y in range(32):
            for x in range(24):
                p = im.getpixel((x, y))
                if p[3]: im.putpixel((x, y), (min(255, p[0]+80), min(255, p[1]+30), min(255, p[2]+30), 255))
    return shade_pass(im)

for cls_ in CLS:
    for team_ in TEAM:
        F = frames(cls_, team_); assert len(F) == 22
        sheet = new(24*22, 32)
        for i, f in enumerate(F): sheet.paste(outline(f), (i*24, 0))
        sheet.save(f"{A}/characters/{cls_}_{team_}.png")

# ---------------------------------------------------------------- blocks v2
def vor_tile(seed, base, n, tones, crack, crack_f, hl=1.14):
    r = random.Random(seed); pts = [(r.uniform(0, 16), r.uniform(0, 16), r.choice(tones)) for _ in range(n)]; im = new()
    for y in range(16):
        for x in range(16):
            ds = []
            for (cx, cy, tn) in pts:
                dx = min(abs(x-cx), 16-abs(x-cx)); dy = min(abs(y-cy), 16-abs(y-cy)); ds.append((math.hypot(dx, dy), cx, cy, tn))
            ds.sort(); d1, cx, cy, tn = ds[0]; d2 = ds[1][0]; f = tn
            if x < cx and y < cy: f *= hl
            if crack and d2-d1 < 1.0: f *= crack_f
            px(im, x, y, sh(base, f*(1+r.uniform(-.03, .03))))
    return im
def t_stone(v): 
    im = vor_tile(200+v, C("8795a0"), 6, [.9, 1.0, 1.08], True, .66)
    r = random.Random(210+v)
    for _ in range(3): px(im, r.randrange(16), r.randrange(16), C("b6c3cc"))
    if v == 2:
        for _ in range(8): px(im, r.randrange(16), r.randrange(0, 4), C("4a8f4a"))
    return im
def t_dirt(v, grass=False):
    im = vor_tile(100+v, C("84582f"), 9, [.86, 1.0, 1.1], True, .82, 1.1); r = random.Random(120+v)
    for _ in range(4):
        x, y = r.randrange(1, 14), r.randrange(1, 14); px(im, x, y, C("b08a5c")); px(im, x+1, y, C("8c6a40")); px(im, x, y+1, C("5c3a1c"))
    if grass:
        for x in range(16):
            h = 3 + r.choice([0, 1, 1, 2])
            for y in range(h): px(im, x, y, sh(C("48b85a") if y < 2 else C("2f8f48"), 1+r.uniform(-.08, .08)))
            px(im, x, 0, C("8ff07a") if x % 3 else C("6fdc6a")); px(im, x, h, C("1f6a34"))
    return im
def t_leaf(v):
    r = random.Random(800+v); im = new(); cs = [(r.uniform(1, 15), r.uniform(1, 15), r.uniform(3.4, 5.2)) for _ in range(7)]
    tones = [C("1f6b3c"), C("2c8f4e"), C("45b866"), C("8be08a")]
    for y in range(16):
        for x in range(16):
            best = None
            for cx, cy, cr in cs:
                dx = min(abs(x-cx), 16-abs(x-cx)); dy = min(abs(y-cy), 16-abs(y-cy)); d = math.hypot(dx, dy)
                if d < cr:
                    l = 1.5 - d/cr*0.9 + (cy-y)*0.06 + (cx-x)*0.05
                    if best is None or l > best: best = l
            if best is None:
                if r.random() < .8: px(im, x, y, tones[0])
            else: px(im, x, y, tones[max(0, min(3, int(best*1.9-0.6)))])
    return im
TILES[1] = t_dirt; TILES[2] = t_stone; TILES[8] = t_leaf
atlas = new(256, 64)
for bid, fn in TILES.items():
    for v in range(3):
        t_ = fn(v)
        if bid in (1, 5, 7): t_ = bevel(t_)
        atlas.paste(t_, (bid*16, v*16))
atlas.paste(t_cave(0), (0, 48)); atlas.paste(t_dirt(0, True), (16, 48)); atlas.save(A + "/blocks.png")

# ---------------------------------------------------------------- backdrops v2
def mountain_layer(w, h, seed, top, bottom, snow, amp, per):
    im = new(w, h); r = random.Random(seed); ph = [r.uniform(0, 6.28) for _ in per]; ys = []
    for x in range(w):
        v = sum(amp[i]*(0.5+0.5*math.sin(2*math.pi*per[i]*x/w+ph[i])) for i in range(len(per))); ys.append(int(h-8-v))
    for x in range(w):
        y0 = ys[x]; slope = ys[(x+1) % w]-ys[(x-1) % w]
        for y in range(y0, h):
            tt = y/h; c = lerpc(top, bottom, tt); lit = 1.14 if slope > 1 else 0.84 if slope < -1 else 1.0
            if (x+y) % 2 == 0 and (y-y0) < 6: lit *= 1.04
            col = sh(c, lit)
            if snow and y-y0 < 5+(x*7 % 4) and y0 < h*0.5: col = (244, 248, 252, 255) if slope >= -1 else (206, 218, 236, 255)
            px(im, x, y, col)
    return im
mountain_layer(512, 150, 3, C("8aa3cc"), C("c4d6ee"), True, [70, 38, 16], [2, 5, 11]).save(A + "/mountains_far.png")
mountain_layer(512, 110, 9, C("5f86ad"), C("a8c4dc"), False, [46, 22, 9], [3, 7, 14]).save(A + "/mountains_near.png")
cl = new(64*6, 28)
for i in range(6):
    r = random.Random(40+i); blobs = [(r.uniform(14, 50), r.uniform(12, 18), r.uniform(6, 12)) for _ in range(5)]
    for y in range(28):
        for x in range(64):
            for cx, cy, cr in blobs:
                if math.hypot(x-cx, (y-cy)*1.3) < cr:
                    rel = (y-(cy-cr))/(2*cr); col = (255, 255, 255, 235) if rel < .4 else (234, 242, 255, 235) if rel < .72 else (196, 212, 238, 230)
                    px(cl, i*64+x, y, col); break
cl.save(A + "/clouds.png")

# ---------------------------------------------------------------- fx + ui
sl = new(120, 40)
for f in range(3):
    lo, hi = [(-75, -20), (-50, 25), (-15, 62)][f]
    for y in range(40):
        for x in range(40):
            dx, dy = x-0, y-20; d = math.hypot(dx, dy); a = math.degrees(math.atan2(dy, dx)); d2 = math.hypot(x+12, y-20)
            if d < 36 and d2 > 36 and lo < a < hi:
                al = 255 if f < 2 else 150; core = d > 31
                px(sl, f*40+x, y, (255, 255, 255, al) if core else (255, 236, 150, al))
sl.save(A + "/slash.png")
vg = new(128, 128)
for y in range(128):
    for x in range(128):
        d = math.hypot(x-63.5, y-63.5)/(64*1.2); a = int(max(0, min(1, d**2.4))*170); vg.putpixel((x, y), (8, 10, 24, a))
vg.save(A + "/vignette.png")
def ui_box(size, fill, border, hi, rad=3):
    im = new(size, size)
    for y in range(size):
        for x in range(size):
            cut = (x < rad and y < rad and x+y < rad) or (x >= size-rad and y < rad and (size-1-x)+y < rad) or (x < rad and y >= size-rad and x+(size-1-y) < rad) or (x >= size-rad and y >= size-rad and (size-1-x)+(size-1-y) < rad)
            if cut: continue
            e = min(x, y, size-1-x, size-1-y)
            im.putpixel((x, y), (16, 20, 34, 255) if e == 0 else border if e == 1 else hi if (e == 2 and y == 2) else fill)
    return im
ui_box(24, (14, 18, 34, 215), (84, 98, 140, 255), (50, 60, 96, 255), 4).save(A + "/ui_panel.png")
ui_box(26, (12, 16, 30, 200), (70, 82, 120, 255), (34, 42, 70, 255), 3).save(A + "/ui_slot.png")
ui_box(26, (40, 46, 74, 225), (255, 213, 79, 255), (255, 240, 170, 255), 3).save(A + "/ui_slot_sel.png")
hr = new(12, 12)
for y in range(12):
    for x in range(12):
        if ((x-3)**2+(y-4)**2 <= 7) or ((x-8)**2+(y-4)**2 <= 7) or (y >= 5 and abs(x-5.5) < (11-y)*0.9+0.6 and y < 11): hr.putpixel((x, y), (231, 60, 70, 255))
for x, y in ((2, 2), (3, 2), (2, 3)): px(hr, x, y, (255, 170, 170, 255))
outline(hr).save(A + "/ui_heart.png")
print("art v2 ok")

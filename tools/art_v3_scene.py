# Арт v3, частина 2: дерева-спрайти, кора, декор, небо, шари гір/лісу, хмари, сонце/місяць.
import random, math, os
from PIL import Image
A = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets")
def C(h): h = h.lstrip("#"); return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), 255)
BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]
def bay(x, y): return BAYER[y % 4][x % 4] / 16.0 - 0.47
def clamp(v, a, b): return max(a, min(b, v))
def outline(im, col):
    src = im.copy(); W, H = im.size
    for y in range(H):
        for x in range(W):
            if src.getpixel((x, y))[3] == 0:
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x+dx, y+dy
                    if 0 <= nx < W and 0 <= ny < H and src.getpixel((nx, ny))[3] > 200: im.putpixel((x, y), col); break
    return im

BARK = [C(c) for c in ("21141a", "3e2731", "5d3a35", "7a4c3c", "9a6a4f")]
LEAF = [C(c) for c in ("102a20", "1b4a32", "2a6e3c", "45974a", "74c05a", "b0e07a")]
PINE = [C(c) for c in ("0c2420", "123a30", "1b5a3e", "2c7a48", "4b9a58", "84c46e")]

def branch(im, x0, y0, x1, y1, w):
    n = int(max(abs(x1-x0), abs(y1-y0)))+1
    for i in range(n):
        x = x0+(x1-x0)*i/n; y = y0+(y1-y0)*i/n
        for k in range(w): im.putpixel((int(x)+k-w//2, int(y)), BARK[3] if k == 0 else BARK[2])

def broadleaf(seed):
    im = Image.new("RGBA", (64, 80), (0, 0, 0, 0)); r = random.Random(seed)
    branch(im, 32, 66, 32, 40, 4); branch(im, 31, 50, 20, 34, 2); branch(im, 33, 47, 45, 32, 2)
    cx, cy, rad = 32, 32, 25; cl = []
    for i in range(16):
        a = r.uniform(0, 2*math.pi); d = r.uniform(0, rad*0.72)
        cl.append((cx+math.cos(a)*d*1.15, cy+math.sin(a)*d*0.8, r.uniform(8, 12)))
    cl.sort(key=lambda c: -c[1])
    for (x0, y0, cr) in cl:
        for y in range(int(y0-cr)-1, int(y0+cr)+2):
            for x in range(int(x0-cr)-1, int(x0+cr)+2):
                if not (0 <= x < 64 and 0 <= y < 80): continue
                dx, dy = x-x0, y-y0; d = math.hypot(dx, dy*1.12)
                if d > cr: continue
                l = 0.55 + (-(dx*0.62+dy*0.78)/cr)*0.42 - (d/cr)**4*0.3 - (y-cy)/(rad*2.2)*0.55
                if d > cr-1.3 and (dx+dy) > 0: l -= 0.25
                idx = int(clamp(l*4.2 + bay(x, y)*0.7, 0, 3.99)) + 1
                im.putpixel((x, y), LEAF[idx])
    for _ in range(26):
        x, y = r.randrange(64), r.randrange(10, 50)
        if im.getpixel((x, y))[3] and im.getpixel((x, y)) in (LEAF[4],): im.putpixel((x, y), LEAF[5])
    for _ in range(5):
        x, y = r.randrange(14, 50), r.randrange(20, 52)
        if im.getpixel((x, y))[3]: im.putpixel((x, y), C("e43b44") if seed % 2 else C("fee761"))
    return outline(im, LEAF[0])

def pine(seed):
    im = Image.new("RGBA", (64, 80), (0, 0, 0, 0)); r = random.Random(seed)
    branch(im, 32, 68, 32, 8, 3)
    for k in range(6):
        top = 4 + k*9; hgt = 17; hw = 7 + k*3.2
        for y in range(top, top+hgt):
            if y >= 80: break
            t = (y-top)/hgt; half = hw*t**0.85 + 1
            droop = (t > 0.8)
            for x in range(int(32-half), int(32+half)+1):
                if not (0 <= x < 64): continue
                edge_wave = math.sin(x*1.3+k)*1.2
                if droop and abs(x-32) > half-2 and y > top+hgt-2+edge_wave: continue
                rel = (x-32)/max(half, 1)
                l = 0.62 - rel*0.42 - t*0.35 + (0.15 if (x+y+k) % 7 == 0 else 0)
                idx = int(clamp(l*4.3 + bay(x, y)*0.7, 0, 3.99)) + 1
                im.putpixel((x, y), PINE[idx])
    for _ in range(4):
        x, y = r.randrange(20, 44), r.randrange(10, 58)
        if im.getpixel((x, y))[3]: im.putpixel((x, y), C("ffffff") if False else PINE[5])
    return outline(im, PINE[0])

trees = Image.new("RGBA", (256, 80), (0, 0, 0, 0))
for k, im in enumerate((broadleaf(1), broadleaf(4), broadleaf(9), pine(3))): trees.paste(im, (k*64, 0))
trees.save(A + "/trees.png")

blocks = Image.open(A + "/blocks.png").convert("RGBA")
for v in range(3):
    t = Image.new("RGBA", (16, 16), (0, 0, 0, 0)); r = random.Random(500+v)
    cols = [BARK[0], BARK[4], BARK[3], BARK[3], BARK[2], BARK[2], BARK[1], BARK[0]]
    for y in range(16):
        for i, x in enumerate(range(4, 12)): t.putpixel((x, y), cols[i])
    for _ in range(5):
        x = r.randrange(6, 10); y = r.randrange(0, 13)
        for k in range(3): t.putpixel((x, y+k), BARK[1])
    if v == 1:
        for x, y in ((7, 7), (8, 7), (7, 8), (8, 8)): t.putpixel((x, y), BARK[0])
        t.putpixel((7, 6), BARK[4])
    blocks.paste(t, (6*16, v*16))
blocks.save(A + "/blocks.png")

G = [C(c) for c in ("12301f", "1f5a35", "2f7d3c", "4ba046", "7cc657", "b6e27a")]
dec = Image.new("RGBA", (128, 16), (0, 0, 0, 0))
def blade(ox, x, hgt, lean):
    for k in range(hgt):
        xx = ox+x+int(lean*k/hgt)
        dec.putpixel((xx, 15-k), G[4] if k > hgt-3 else G[3] if k > hgt//2 else G[2])
for f in range(3):
    r = random.Random(f)
    for x in range(1, 15, 2):
        if r.random() < 0.75: blade(f*16, x, r.randrange(3, 8), r.choice([-1, 0, 1]))
def flower(ox, petal, center):
    for k in range(6): dec.putpixel((ox+8, 15-k), G[2])
    dec.putpixel((ox+7, 13), G[3]); dec.putpixel((ox+9, 12), G[3])
    for dx, dy in ((0, -1), (-1, 0), (1, 0), (0, 1)): dec.putpixel((ox+8+dx, 8+dy), petal)
    dec.putpixel((ox+8, 8), center)
    for x in (3, 5, 11, 13): blade(ox, x, 3, 0)
flower(48, C("e43b44"), C("fee761")); flower(64, C("fee761"), C("f77622"))
for x, y in ((7, 12), (8, 12), (7, 13), (8, 13), (7, 14), (8, 14), (7, 15), (8, 15)): dec.putpixel((80+x, y), C("ead4aa"))
for x in range(5, 11):
    for y in range(8, 12):
        if not (y == 8 and x in (5, 10)): dec.putpixel((80+x, y), C("e43b44") if y < 11 else C("a22633"))
dec.putpixel((86, 9), C("ffffff")); dec.putpixel((89, 10), C("ffffff"))
for x, y, c in ((4, 14, "8b9bb4"), (5, 14, "5a6988"), (5, 13, "c0cbdc"), (9, 14, "8b9bb4"), (10, 14, "5a6988"), (10, 13, "c0cbdc"), (12, 15, "5a6988")): dec.putpixel((96+x, y), C(c))
for y in range(8, 16):
    for x in range(2, 14):
        d = math.hypot(x-7.5, (y-14.5)*1.3)
        if d < 6: dec.putpixel((112+x, y), G[4] if (y < 11 and x < 8) else G[3] if d < 4.5 else G[2])
dec = outline(dec, G[0]); dec.save(A + "/decor.png")

SKY = [C(c) for c in ("2f63b8", "3b78cc", "4b8ddb", "62a5e6", "80bdef", "a3d3f5", "c8e6f9")]
sky = Image.new("RGBA", (4, 400))
for y in range(400):
    for x in range(4):
        v = (y/399)**1.15*len(SKY) + bay(x, y)*0.9
        sky.putpixel((x, y), SKY[int(clamp(v, 0, len(SKY)-1))])
sky.save(A + "/sky.png")

def wrapd(a, b, W): d = (a-b) % W; return d-W if d > W/2 else d
def mountains(W, H, seed, n, hmin, hmax, ramp, snow=None, haze=None):
    r = random.Random(seed); peaks = []
    for i in range(n):
        peaks.append((i*W/n + r.uniform(-W/n*0.3, W/n*0.3), H - r.uniform(hmin, hmax), r.uniform(0.7, 1.4), r.uniform(0.7, 1.4)))
    jag = [r.uniform(-1, 1) for _ in range(W)]
    js = [sum(jag[(x+k) % W] for k in range(-2, 3))/5*3 for x in range(W)]
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    for x in range(W):
        best = None
        for pi, (px_, py, sl, sr) in enumerate(peaks):
            dx = wrapd(x, px_, W); y = py + abs(dx)*(sl if dx < 0 else sr) + js[x]
            if best is None or y < best[0]: best = (y, pi, dx)
        top, pi, dx = best
        for y in range(max(0, int(top)), H):
            lit = dx < (math.sin(y*0.4+pi)*1.5)
            depth = y-top; py = peaks[pi][1]
            idx = 2 if lit else 1
            if depth < 2: idx += 1
            if (y-py) > (H-py)*0.55: idx = 1 if lit else 0
            c = ramp[idx]
            if snow and (y-py) < 10+js[x]*2 and (y-py) < (H-py)*0.3: c = snow[1] if lit else snow[0]
            if haze:
                t = clamp((y-(H*0.45))/(H*0.55), 0, 1)
                if t+bay(x, y)*0.35 > 0.6: c = haze
            im.putpixel((x, y), c)
    return im
mountains(512, 190, 3, 5, 120, 180, [C(c) for c in ("8697c0", "9aabd0", "b2c2e2", "c6d4ec")], snow=(C("d6e0f0"), C("f4f8fd")), haze=C("b8cbe8")).save(A + "/mountains_far.png")
mountains(512, 140, 9, 7, 70, 120, [C(c) for c in ("5c6f9e", "6f84b2", "8499c4", "98acd2")], snow=(C("b9c6e0"), C("e2eaf6")), haze=C("8fa6cf")).save(A + "/mountains_near.png")

def treeline(W, H, seed, cols, base, amp, tree_h, density):
    r = random.Random(seed); im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    hill = [base + amp*(0.5+0.5*math.sin(2*math.pi*2*x/W+1.3))*0.6 + amp*0.4*(0.5+0.5*math.sin(2*math.pi*5*x/W)) for x in range(W)]
    for x in range(W):
        for y in range(int(H-hill[x]), H): im.putpixel((x, y), cols[1])
    for i in range(int(W*density)):
        cx = r.uniform(0, W); th = r.uniform(tree_h*0.6, tree_h); gy = H-hill[int(cx) % W]+2
        for y in range(int(gy-th), int(gy)+1):
            t = (y-(gy-th))/th; half = 1 + t*th*0.28
            for x in range(int(cx-half), int(cx+half)+1):
                c = cols[2] if (x-cx) < -half*0.3 and t < 0.85 else cols[1]
                if (y+int(cx)) % 5 == 0 and abs(x-cx) > half-1.5: c = cols[0]
                im.putpixel((x % W, clamp(y, 0, H-1)), c)
    return im
treeline(512, 110, 5, [C(c) for c in ("3e6a78", "4c7d8a", "5f92a0")], 28, 34, 22, 0.09).save(A + "/trees_far.png")
treeline(512, 90, 6, [C(c) for c in ("1c3f3a", "25504a", "33665a")], 22, 20, 30, 0.12).save(A + "/forest_near.png")

CL = [C(c) for c in ("8b9bc4", "b7c6e2", "dfe9f6", "ffffff")]
clouds = Image.new("RGBA", (288, 44), (0, 0, 0, 0))
for i in range(3):
    r = random.Random(60+i); blobs = [(r.uniform(18, 78), r.uniform(20, 30), r.uniform(8, 15)) for _ in range(6)]
    for y in range(44):
        for x in range(96):
            hit = [(cx, cy, cr) for cx, cy, cr in blobs if math.hypot(x-cx, (y-cy)*1.25) < cr]
            if not hit or y > 36: continue
            top = min(cy-cr/1.25 for cx, cy, cr in hit)
            rel = (y-top)/(36-top+0.01); l = 1-rel + bay(x, y)*0.35
            clouds.putpixel((i*96+x, y), CL[int(clamp(l*3.6, 0, 3.99))])
clouds.save(A + "/clouds.png")

sun = Image.new("RGBA", (48, 48), (0, 0, 0, 0))
for y in range(48):
    for x in range(48):
        d = math.hypot(x-23.5, y-23.5)
        if d < 9: sun.putpixel((x, y), C("fff6c8") if d < 6 else C("ffe27a"))
        elif d < 10: sun.putpixel((x, y), C("feae34"))
        elif d < 23 and bay(x, y)+0.5 > d/23*1.6: sun.putpixel((x, y), (255, 236, 160, 90))
sun.save(A + "/sun.png")
moon = Image.new("RGBA", (48, 48), (0, 0, 0, 0))
for y in range(48):
    for x in range(48):
        d = math.hypot(x-23.5, y-23.5)
        if d < 8.5 and math.hypot(x-27, y-21) > 7.5: moon.putpixel((x, y), C("eef2fb") if d < 7 else C("c0cbdc"))
        elif d < 20 and bay(x, y)+0.5 > d/20*1.7: moon.putpixel((x, y), (200, 215, 255, 60))
moon.save(A + "/moon.png")
print("scene ok")

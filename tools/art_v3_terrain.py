# Арт v3, частина 1: безшовні текстури ландшафту + автотайли (16 масок відкритих сторін).
import random, math, os
from PIL import Image
A = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets")
def C(h): h = h.lstrip("#"); return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), 255)
BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]
def bay(x, y): return BAYER[y % 4][x % 4] / 16.0 - 0.47

def tnoise(size, period, seed):
    r = random.Random(seed); g = [[r.random() for _ in range(period)] for _ in range(period)]
    out = [[0.0]*size for _ in range(size)]
    for y in range(size):
        for x in range(size):
            fx = x*period/size; fy = y*period/size; x0 = int(fx); y0 = int(fy)
            tx = fx-x0; ty = fy-y0; tx = tx*tx*(3-2*tx); ty = ty*ty*(3-2*ty)
            a = g[y0 % period][x0 % period]; b = g[y0 % period][(x0+1) % period]
            c = g[(y0+1) % period][x0 % period]; d = g[(y0+1) % period][(x0+1) % period]
            out[y][x] = (a*(1-tx)+b*tx)*(1-ty)+(c*(1-tx)+d*tx)*ty
    return out
def fbm(size, seed, periods=(4, 8, 16), weights=(0.55, 0.3, 0.15)):
    L = [tnoise(size, p, seed+i*31) for i, p in enumerate(periods)]
    return [[sum(L[i][y][x]*weights[i] for i in range(len(L))) for x in range(size)] for y in range(size)]
def quant(v, ramp, x, y, spread=0.8):
    n = len(ramp); t = v*n + bay(x, y)*spread
    return ramp[max(0, min(n-1, int(t)))]
def norm(v, lo, hi): return max(0.0, min(0.999, (v-lo)/(hi-lo)))

DIRT = [C(c) for c in ("2a1b24", "4a2c2c", "6b3f31", "8a5638", "a87046", "c99460")]
STONE = [C(c) for c in ("17162a", "2b2d42", "414660", "586178", "77829a", "a2adc0")]
WALL = [C(c) for c in ("150f18", "211722", "2e1f28", "3b2a30", "4a3739")]
GRASS = [C(c) for c in ("12301f", "1f5a35", "2f7d3c", "4ba046", "7cc657", "b6e27a")]

def dirt_tex(seed):
    n = fbm(64, seed); im = Image.new("RGBA", (64, 64)); r = random.Random(seed)
    for y in range(64):
        for x in range(64): im.putpixel((x, y), quant(norm(n[y][x], 0.28, 0.72), DIRT[2:5], x, y))
    for _ in range(16):
        x, y = r.randrange(64), r.randrange(64); s = r.choice([1, 2, 2])
        for dy in range(s):
            for dx in range(s+1): im.putpixel(((x+dx) % 64, (y+dy) % 64), DIRT[4])
        im.putpixel((x % 64, y % 64), DIRT[5])
        for dx in range(s+1): im.putpixel(((x+dx) % 64, (y+s) % 64), DIRT[1])
    for _ in range(26): im.putpixel((r.randrange(64), r.randrange(64)), DIRT[1])
    return im

def stone_tex(seed):
    r = random.Random(seed); pts = [(r.uniform(0, 64), r.uniform(0, 64), r.choice([2, 3, 3, 4])) for _ in range(20)]
    im = Image.new("RGBA", (64, 64))
    for y in range(64):
        for x in range(64):
            best = []
            for (px, py, tn) in pts:
                dx = (x-px+32) % 64-32; dy = (y-py+32) % 64-32; best.append((math.hypot(dx, dy), dx, dy, tn))
            best.sort(); d1, dx, dy, tn = best[0]; edge = best[1][0]-d1
            if edge < 1.0: c = STONE[1]
            else:
                idx = tn
                if edge < 2.4: idx = tn+1 if (dx+dy) < 0 else tn-1
                elif bay(x, y) + (-(dx*0.6+dy*0.8))/14.0 > 0.42: idx = tn+1
                c = STONE[max(1, min(5, idx))]
            im.putpixel((x, y), c)
    for _ in range(10): im.putpixel((r.randrange(64), r.randrange(64)), STONE[5])
    return im

def wall_tex(seed):
    n = fbm(64, seed, (4, 8, 32), (0.5, 0.3, 0.2)); im = Image.new("RGBA", (64, 64)); r = random.Random(seed)
    for y in range(64):
        for x in range(64): im.putpixel((x, y), quant(norm(n[y][x], 0.3, 0.7), WALL[1:5], x, y, 1.0))
    for _ in range(12):
        x, y = r.randrange(64), r.randrange(64)
        for k in range(r.randrange(3, 7)): im.putpixel(((x+k) % 64, y), WALL[0])
    return im

def shade(c, f): return (max(0, min(255, int(c[0]*f))), max(0, min(255, int(c[1]*f))), max(0, min(255, int(c[2]*f))), 255)

def masked(tex, outline, grass=False, seed=0):
    out = Image.new("RGBA", (1024, 64), (0, 0, 0, 0)); gr = random.Random(seed)
    gd = [4 + gr.choice([0, 0, 1, 1, 2]) for _ in range(64)]
    def cut(m, x, y):
        if x < 0 or x > 15 or y < 0 or y > 15: return False
        return ((m & 1 and m & 8 and x+y < 3) or (m & 1 and m & 2 and (15-x)+y < 3) or
                (m & 4 and m & 8 and x+(15-y) < 3) or (m & 4 and m & 2 and (15-x)+(15-y) < 3))
    for m in range(16):
        for ty in range(4):
            for tx in range(4):
                for y in range(16):
                    for x in range(16):
                        if cut(m, x, y): continue
                        gx, gy = tx*16+x, ty*16+y; c = tex.getpixel((gx, gy))
                        if m & 1 and y in (1, 2): c = shade(c, 1.18)
                        if m & 8 and x == 1: c = shade(c, 1.1)
                        if m & 4 and y in (13, 14): c = shade(c, 0.78)
                        if m & 2 and x == 14: c = shade(c, 0.85)
                        ol = outline; g = gd[gx]
                        if grass and m & 1:
                            if y < g:
                                ol = GRASS[0]
                                if y == 1: c = GRASS[5] if (gx % 3) else GRASS[4]
                                elif y == g-1: c = GRASS[1]
                                else: c = GRASS[3] if bay(gx, y) + (0.25 if y < 3 else -0.1) > 0 else GRASS[2]
                            elif y == g: c = DIRT[1]
                        edge = ((m & 1 and y == 0) or (m & 4 and y == 15) or (m & 8 and x == 0) or (m & 2 and x == 15) or
                                cut(m, x-1, y) or cut(m, x+1, y) or cut(m, x, y-1) or cut(m, x, y+1))
                        if edge: c = ol
                        out.putpixel((m*64+gx, gy), c)
    return out

d = dirt_tex(11); s = stone_tex(22)
dirt_set = Image.new("RGBA", (1024, 128), (0, 0, 0, 0))
dirt_set.paste(masked(d, DIRT[0], True, 5), (0, 0)); dirt_set.paste(masked(d, DIRT[0], False), (0, 64))
dirt_set.save(A + "/terrain_dirt.png")
masked(s, STONE[0]).save(A + "/terrain_stone.png")
wall_tex(33).save(A + "/wall.png")

ORE = [C(c) for c in ("3a2410", "9a6a12", "d9a21c", "f7d64a", "fff6c0")]
ore = Image.new("RGBA", (48, 16), (0, 0, 0, 0))
for v in range(3):
    r = random.Random(70+v)
    for _ in range(4):
        cx, cy = r.randrange(2, 13), r.randrange(2, 13); w_, h_ = r.choice([(2, 2), (3, 2), (2, 3)])
        for yy in range(cy-1, cy+h_+1):
            for xx in range(cx-1, cx+w_+1):
                if 0 <= xx < 16 and 0 <= yy < 16 and ore.getpixel((v*16+xx, yy))[3] == 0: ore.putpixel((v*16+xx, yy), ORE[0])
        for yy in range(cy, cy+h_):
            for xx in range(cx, cx+w_):
                if 0 <= xx < 16 and 0 <= yy < 16: ore.putpixel((v*16+xx, yy), ORE[2] if (xx+yy) % 2 else ORE[3])
        if cx < 16 and cy < 16: ore.putpixel((v*16+cx, cy), ORE[4])
        if cx+w_-1 < 16 and cy+h_-1 < 16: ore.putpixel((v*16+cx+w_-1, cy+h_-1), ORE[1])
ore.save(A + "/ore.png")
print("terrain ok")

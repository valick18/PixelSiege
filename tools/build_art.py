# Генерує весь арт гри: python tools/build_art.py  (потрібен Pillow: pip install pillow)
import os, runpy
d = os.path.dirname(os.path.abspath(__file__))
for f in ("make_art.py", "art_v3_terrain.py", "art_v3_scene.py"):
    runpy.run_path(os.path.join(d, f), run_name="__main__")

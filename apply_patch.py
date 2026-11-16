"""Apply the PixelSiege gameplay patch.

Usage (from the repository root, next to project.godot):
    python apply_patch.py

Backups of every changed file are written next to it as *.gd.bak.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from ps_patch.engine import FilePatch  # noqa: E402
from ps_patch import p_net_world, p_player, p_game_edits, p_game_code1, p_game_code2  # noqa: E402


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else os.getcwd()
    if not os.path.exists(os.path.join(root, "project.godot")) and os.environ.get("PS_TEST") != "1":
        raise SystemExit("Run this from the PixelSiege folder (where project.godot is) or pass its path.")
    targets = [
        "net.gd",
        "world.gd",
        "look.gd",
        "player.gd",
        "game.gd",
        "managers/CombatManager.gd",
        "managers/BuildingManager.gd",
    ]
    files = {n: FilePatch(root, n) for n in targets}
    if any(f.already_patched() for f in files.values()):
        raise SystemExit("Patch is already applied (restore the .bak files to re-apply).")
    p_net_world.apply(files["net.gd"], files["world.gd"], files["look.gd"])
    p_player.apply(files["player.gd"])
    p_game_edits.apply(files["game.gd"], files["managers/CombatManager.gd"], files["managers/BuildingManager.gd"])
    p_game_code1.apply(files["game.gd"])
    p_game_code2.apply(files["game.gd"])
    for f in files.values():
        f.save()
    print("Done. Open the project in Godot 4.3+ and press F5.")


if __name__ == "__main__":
    main()

# Pixel Siege (prototype) - Godot 4.3+

2D multiplayer sandbox & siege game: build a base, mine, craft siege engines and capture the enemy flag.
See **CHANGES.md** for the latest update (combat rework, class tool slots, crafting, workbenches, water, ruins,
platforms, team doors, abilities, team/class screens, inventory, character customization, snapshot interpolation).

## EXE
1. Install Godot 4.3+ (standard) and its Export Templates (Editor > Manage Export Templates > Download).
2. Run `build_exe.bat` (set GODOT=path\to\godot.exe if godot is not in PATH), or put Godot into `_tools`.
3. Result: `build\PixelSiege.exe`. Or just run `run_game.bat` / open the folder in Godot and press F5.

## Multiplayer
- Host: Host game. LAN servers appear automatically in the list. The host tries UPnP to open UDP 24565.
  If the router blocks UPnP, forward UDP 24565 manually.
- Optional Steam P2P: add the GodotSteam plugin, then "Host via Steam" appears; join with `steam:<lobby id>`.
- Test on one PC: Debug > Customize Run Instances > Enable Multiple Instances.

## Classes
| Class | Tools (keys 1-3) | Abilities Q / R / F |
|---|---|---|
| Warrior | Sword, Spear | Charge, Whirlwind, War Cry |
| Archer | Bow, Dagger | Backflip, Volley, Fire Arrow |
| Builder | Pickaxe (blocks), Axe (trees), Hammer | Bridge, Stone Wall, Repair |
| Support | Mace | Heal Aura, Haste, Barrier |

Only the Builder can mine blocks (pickaxe) and chop trees (axe).

## Controls
WASD move, Space jump, S+Space drop through platform, Shift run, Ctrl crouch.
1-3 tool slots, 4-0 item slots, mouse wheel switch.
LMB: attack / hold to draw the bow / dig / place / use medkit. RMB: block (weapons) or swing (pickaxe, axe).
X block (tap right before a hit = parry), Z dodge, Q R F class abilities.
E use: workbench (crafting), catapult, ballista, hatch, ruin chest, deposit to storage. G take from storage.
C crafting, Tab / I inventory, B class, M team, F1-F4 quick class change, H help, Esc menu.

## Music
Put .ogg/.mp3/.wav files into assets/music - the first one loops automatically.

## Art
`python tools/build_art.py` (needs Pillow) regenerates all art. New blocks (water, platforms, doors, workbenches,
ballista, campfire, lantern, hatch, arrow trap, ruins) and the customizable characters are drawn in code (`scripts/look.gd`).

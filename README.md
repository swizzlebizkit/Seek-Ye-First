# Seek Ye First

A top-down 2D New Testament action-adventure RPG (Godot 4, GDScript). You play an unnamed villager in first-century Galilee who witnesses the baptism of Jesus and spends the story seeking answers. Scripture is the King James Version (public domain). Villagers, places and side quests are invented and tagged `origin: fiction` in the data.

Status: **Milestone 2A "Sword, Equipment & Interaction"** on top of Milestone 1. The overworld, Jordan road and baptism are intentionally not built yet.

## Run

Godot 4.7.2 is required.

```
Godot_v4.7.2-stable_win64.exe --path .
```

First time (or after adding scripts/art), import once so class names and textures register:

```
Godot_v4.7.2-stable_win64_console.exe --headless --path . --import
```

## Controls

| Key | Action |
|---|---|
| WASD / arrows | Move |
| E / Space / Enter | Interact, advance dialogue, confirm |
| Up/Down (or 1-9) | Choose a dialogue option |
| J / Tab | Journal, quests, satchel (Left/Right switch tabs, PgUp/PgDn scroll) |
| Esc | Pause menu (save, load, quit) / close screens |
| K / X | Swing the sword (needs a sword equipped) |
| Shift / L | Dodge step (brief protection, 0.8 s cooldown) |
| I / Q | Equipment screen (Up/Down, Enter to select/equip, Left/Right switch list) |
| F5 / F9 | Quick save / quick load (slot 1) |

## Layout

- `scripts/autoload/` the three world systems plus services: `canonical_timeline` (A), `world_sim` (B), `player_knowledge` (C), `journal`, `quests`, `dialogue_runner`, `save_manager`, `scripture`, `game_state`.
- `scripts/entities/`, `scripts/world/`, `scripts/ui/`, `scripts/core/` entities, region loader, screens, shared helpers.
- `data/` all content as JSON: dialogue, journal entries, quests, canon events, KJV verses, items, region.
- `tools/procgen/` deterministic procedural art (pure Python, no dependencies). `tools/mapgen/` builds the village layout.
- `tests/` headless suite.

## Regenerating generated content

```
python -I tools/procgen/generate_all.py     # tiles, props, characters, UI art (then re-run --import)
python -I tools/mapgen/kefar_zayit.py       # data/regions/kefar_zayit.json
```

## Tests

```
Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/test_runner.tscn
```

Add `-- --verbose` to list every check. Uses a throwaway save directory.

## Dev helpers

`scripts/dev/dev_hooks.gd` reads user args for scripted screenshots, e.g.
`-- --autostart=new --skipintro --at=20.5,14.8 --talk=yosef --shot=out.png`.

## Combat training yard (dev only)

Debug builds show **Combat Training Yard (dev)** on the main menu: a fresh protagonist with Ezra's Sword in a test area with a talkable toll-taker, a highwayman you can outrun, a cutthroat who flees, a guard who reacts only to what he sees, and two bystanders. Crates hold placeholder gear. The ledger board lists how each encounter ended.

Behaviour profiles are data: `data/combat/profiles.json` (hostile / noncombatant / contextual). Equipment: `data/items.json` + `data/equipment/slots.json`. Regenerate the yard with `python -I tools/mapgen/training_yard.py`.

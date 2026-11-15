# Seek Ye First

A top-down 2D New Testament action-adventure RPG (Godot 4, GDScript). You play an unnamed villager in first-century Galilee who witnesses the baptism of Jesus and spends the story seeking answers. Scripture is the King James Version (public domain). Villagers, places and side quests are invented and tagged `origin: fiction` in the data.

Status: **Milestone 1 "Walk, Talk, Remember"**. The Jordan baptism is intentionally not built yet.

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

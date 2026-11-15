# Seek Ye First

A top-down 2D New Testament action-adventure RPG (Godot 4, GDScript). You play an unnamed villager in first-century Galilee who witnesses the baptism of Jesus and spends the story seeking answers. Scripture is the King James Version (public domain). Villagers, places and side quests are invented and tagged `origin: fiction` in the data.

Status: **Milestone 2A.1 (2A plus scripture links, scrolls and health options)** on top of Milestone 1. The overworld, Jordan road and baptism are intentionally not built yet.

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
| J / Tab | Journal, quests, satchel, map (Left/Right switch tabs, PgUp/PgDn scroll; on the Map tab 1 2 3 choose level, + / - zoom) |
| Esc | Pause menu (save, load, quit) / close screens |
| K / X / R | Swing the sword (needs a sword equipped) |
| H | Eat food from the satchel (restores health) |
| Shift / L | Dodge step (brief protection, 0.8 s cooldown) |
| I / Q | Equipment screen (Up/Down, Enter to select/equip, Left/Right switch list) |
| F5 / F9 | Quick save / quick load (slot 1) |

## Layout

- `scripts/autoload/` the three world systems plus services: `canonical_timeline` (A), `world_sim` (B), `player_knowledge` (C), `journal`, `quests`, `dialogue_runner`, `save_manager`, `scripture`, `game_state`.
- `scripts/entities/`, `scripts/world/`, `scripts/ui/`, `scripts/core/` entities, region loader, screens, shared helpers.
- `data/` all content as JSON: dialogue, journal entries, quests, canon events, KJV verses, items, regions, world (calendar, geography, travel).
- `tools/procgen/` deterministic procedural art (pure Python, no dependencies). `tools/mapgen/` builds the village layout.
- `tests/` headless suite.

## Regenerating generated content

```
python -I tools/procgen/generate_all.py     # tiles, props, characters, UI art (then re-run --import)
python -I tools/mapgen/kefar_zayit.py       # data/regions/kefar_zayit.json
python -I tools/mapgen/galilee.py           # galilee_hills, magdala_shore, road_camp, outskirts
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

## Scripture links, scrolls and health (2A.1)

- **Journal links:** `data/journal/links.json` joins a journal entry to Old Testament passages. Links stay hidden until a teacher or scroll reveals them; once found they are permanent. Each link has a relationship (prophecy, typology, theme, parallel), says whether the New Testament states it outright, can carry a teacher's disagreement, and has a separate "understood" step (reserved for later). New Testament references are player-side. Add KJV text to `data/scripture/kjv.json` for anything a link cites.
- **Scrolls:** scroll items (`category: scroll`, `reveals: [link ids]`) are found in the world. Elder Ezra reads one you bring him (effect `read_scroll`). After the sword gift he has a new conversation teaching the protagonist to look back at what was written before.
- **Health:** resting heals slowly up to half of full health (`data/combat/player.json`, can be turned off); food (`heal`) restores more with H. Bread and fig cakes are in the yard crates and the village.
- **Planned, not built:** the Sabbath and calendar, see `docs/sabbath_calendar_plan.md`.

## Calendar (S1.1)

`Calendar` (`data/world/calendar.json`, `data/world/festivals.json`) is a simplified lunisolar Jewish calendar worked out from `WorldSim`. It is a gameplay approximation, not a historical reconstruction; see `docs/calendar.md`. Months are 29 or 30 days from a fixed mean lunation, a year is 12 or 13 months (Adar I and II in leap years, by a configurable 19-year pattern plus per-year overrides), and the date starts from a configurable start date. The seven-day week never resets and the Sabbath runs sunset on the sixth day to sunset on the seventh. Saves are unchanged (only the clock is stored). The HUD reads `The first day | 1 Nisan | 7:00`. Conditions in data: `weekday` (0 to 6, a list means any of), `sabbath` (bool), `day_phase`. Festival dates are looked up only; schedules, closed stalls and festival gameplay are planned, not built.

## The living world (W1)

Three levels: **local** (a village such as Kefar Zayit), **regional** (walkable country: `galilee_hills`, `magdala_shore`, and the shared template regions `road_camp` and `outskirts`) and **strategic** (a map of places and routes, `data/world/geography.json`). Read `docs/world_architecture.md` for the design and `docs/geography.md` for what is documented, uncertain and invented (Kefar Zayit is invented).

- **Walking:** regions connect through data-driven `exits` and `entries`, no per-map code. Leaving Kefar Zayit by the east road enters the hills, which lead on to the lake shore.
- **Travel:** a road marker, landing or camp opens the strategic map (`Travel`, `data/world/travel.json`). The traveller walks (4 km/h, dawn to sunset, resting overnight) or sails (6 km/h, day and night). The clock advances in steps that always stop at sunset and midnight, so nothing is skipped. A journey can be stopped at a waypoint, paused, resumed or abandoned (you stay on the road and may go on to either end).
- **Sabbath:** the only authority is `Calendar`. Overland travel stops at sunset on the sixth day at the exact progress reached and you are put in a camp; no overland start or resume during the Sabbath, and nothing resumes by itself. A boat already at sea keeps sailing; no boat departs on the Sabbath.
- **Journal map:** the Map tab shows what has been discovered (unknown, rumored, discovered, visited, investigated), with fog over country not yet walked. It cannot move you.
- **Saves:** version 3 adds `geo` and `travel` blocks; older saves load with defaults. See `docs/w1_playtest.md` for what has and has not been played by a person.
- **Dev:** `-- --autostart=new --autoplay=w1` plays the whole demonstration through the live game. Other hooks: `--region`, `--loc`, `--clock`, `--journey`, `--ui=strategic|map`, `--travel=<route>`.

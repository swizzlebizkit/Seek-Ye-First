# World architecture (W1.0)

Status: design for Milestone W1. Beads epic `seek-ye-first-6o3`. Geography decisions live in `docs/geography.md`.

## 1. What exists today (inspected)

| Piece | Interface | W1 use |
| --- | --- | --- |
| `Region` (scripts/world/region.gd) | `load_region(id)` builds tiles, props, NPCs, interactables from `data/regions/<id>.json`; `size_px()`, `spawn_position()` | Extended with `exits`, `entries`, `landmarks`, `waymarks`, `encounter_spots`; existing keys unchanged |
| `Game` (scripts/game/game.gd) | One scene; builds Region, Player, camera (limits from region size), Hud; save/load by reloading the scene | Region change = set autoload state, reload scene. No per-scene state leaks |
| `GameState` | flags, inventory, `region_id`, `player_pos`, `has_saved_position`, `check()` conditions | New fields `entry_id`; new condition keys for places and journeys |
| `SaveManager` | JSON, `VERSION = 2`, one block per subsystem, missing blocks load defaults | `VERSION = 3`; new blocks `geo` and `travel`; absent blocks mean defaults |
| `WorldSim` | `day`, `minute_of_day`, advances in `_process` only while exploring | New `advance(minutes)` for travel and rests |
| `Calendar` | stateless; `is_sabbath(day, minute)`, `sunset_for`, `calendar_day`, `date()` | Only source of Sabbath. Add `minutes_until(...)` helpers, no second clock |
| `PlayerKnowledge` | canon-event knowledge levels | Map discovery is separate state in `World`; places can be revealed by knowing an event (data link) |
| `Journal` view | tabs enum, rows + detail pane | New Map tab |
| `Combat`/`Npc` | encounter profiles, outcomes, actor status | Reused for the regional encounter |
| tests | `tests/test_runner.gd` plus section files | New `tests/world_tests.gd` |

## 2. Three levels

| Level | Unit | Where it lives | Coordinates |
| --- | --- | --- | --- |
| Strategic | a map (`galilee_judea`) with locations, routes, features | `data/world/geography.json` | lon/lat degrees (approximate), projected for display |
| Regional | a walkable region scene | `data/regions/<id>.json`, `kind: "regional"` | tiles (32 px), origin top-left, y down |
| Local | an enterable place (village, later building) | same file format, `kind: "local"` | tiles |

A **location** is a strategic point (id like `magdala`). A **region** is a playable scene (id like `galilee_hills`). A region may name `anchor`, the location it is "at". A location may name `region`, the scene used when the player is *at* it. Many locations have no scene yet; those use the shared `outskirts` template.

The journal map is inspect-only. Travel exists only through (a) walking exits between regions, (b) a waymark in a region that opens the strategic map.

## 3. Identifiers

- Lowercase snake_case, globally unique within kind. Locations: `nazareth`, `kefar_zayit`. Regions: `galilee_hills`. Routes: `<a>__<b>__<mode>` with a < b alphabetically. Features: `sea_of_galilee`.
- Region exits and entries are unique within their region; a destination names `{region, entry}`.
- Anything persisted stores ids only, never indices.

## 4. Transition contract

Region data:

```json
"entries": { "from_village": { "tile": [4.5, 20], "facing": "right" } },
"exits":   [ { "id": "to_village", "rect": [0, 18, 1, 5], "to": { "region": "kefar_zayit", "entry": "from_hills" }, "facing": "left" } ]
```

`RegionExit` (an `Area2D`) is built from each exit. On the player entering it: `World.transition(region, entry)` stores the destination, sets `GameState.region_id`, clears the saved position, and reloads the scene. Player state (health, items, flags, clock, journey) lives in autoloads, so nothing is lost. Position is preserved *relative* to the edge (the entry tile is offset along the exit by the player's position along it). Validation at load: every `to` resolves to a real region entry; two-way links are reported if only one-way (warning, not error).

Templates: regions with `"template": true` take their name from `World.context` (a location or a route position). They are used for journey stops and arrivals where no hand-built scene exists.

## 5. Journeys

A journey is data in `Travel` (autoload):

```
{ route_id, from, to, direction (+1/-1), mode (land|water),
  progress_km, state: underway | paused | arrived | abandoned,
  pause_reason: sabbath | player | stop | encounter | blocked | night,
  stop: {region, entry} or null, started_day, seed }
```

Time never jumps. `Travel.advance(minutes)` runs in chunks; each chunk ends at the earliest of: next sunset, next midnight, next stop point, arrival, end of the daily travel window, requested minutes. After each chunk it re-checks the Sabbath, stops and encounters. `WorldSim.advance` itself steps day rollovers one at a time and emits `day_rolled`, `sunset_passed` so dependents cannot be skipped.

Rules (all configurable in `data/world/travel.json`):
- Land: moves between `window_start` (06:00) and sunset. At sunset it rests overnight automatically and continues next dawn, **except** at Sabbath start, where it pauses at the stop for the exact progress.
- Land cannot start or resume while `Calendar.is_sabbath`. Resume is never automatic.
- Water: moves continuously; may depart only outside the Sabbath (`depart_on_sabbath: false`); a vessel under way continues (`continue_on_sabbath: true`).
- Speeds are gameplay values (km/h by mode), not historical claims.

Stops: each route lists `stops` (id, distance along route, optional region). The traveler is placed in the stop region (default `road_camp`). Progress is untouched.

## 6. Discovery

`World` keeps `place_level[location_id]` in `unknown < rumored < discovered < visited < investigated` and a set of discovered route ids. Rumors reveal an approximate marker (offset circle), not entrances or routes. Data hooks: a location may list `reveal_on` (canon event + level) and `scripture_refs`; nothing consumes them yet.

## 7. Saves

`VERSION = 3`. New blocks: `geo` (`place_level`, `routes`, `landmarks`), `travel` (journey or null). `GameState` serializes `entry_id`. Absent blocks load defaults; unknown ids are dropped; a journey whose route no longer exists is abandoned safely. Loading a paused-for-Sabbath journey restores `paused`, never `underway`.

## 8. Risks

| Risk | Mitigation |
| --- | --- |
| Large time jumps skip calendar transitions | Chunked `advance`, boundary signals, tests across sunset, midnight, month and year |
| Scene reload loses state | All state in autoloads; reload already used by load-game |
| Many stops with no hand-built scene | Template regions parameterised by location/route |
| Save migration | Optional blocks with defaults; fixture of a pre-W1 save in tests |
| False historical precision | `category` and `certainty` per location; fictional flagged; docs say so |
| Scope creep into cities, Paul, naval play | Strategic maps are separate files; only Galilee-Judea shipped |
| Region size vs camera | Camera limits already come from `size_px()` |
| Sabbath logic duplicated | `Travel` only calls `Calendar` |

## 9. Acceptance criteria (summary)

See each Beads task. Overall: the 17-step demonstration plays; every item in the brief's test list has a check; existing 1,396 checks still pass; six screenshots reviewed; unplayed features reported.

## 10. As built (changes from the design above)

- **Autoloads:** `World` (geography, regions, discovery, fog) and `Travel` (journeys). `WorldSim.advance()` steps to sunset and
  midnight and emits `sunset_passed` and `day_rolled`.
- **Transitions:** `World.go()` stores the destination and emits `transition_requested`; `Game` answers by reloading the scene with
  `start_request = {"mode": "resume"}` (it ignores the signal when it is not the live scene, which keeps tests safe). Exits keep the player's
  place along an edge through `entry.span` and `World.entry_offset`.
- **Budget:** `Travel.run(n)` spends `n` minutes of walking or sailing; overnight rests advance the clock but cost nothing from the
  budget, so the animated map does not sit through a night. `estimate()` and `estimate_option()` run the same loop on a copy.
- **Abandon:** the destination is dropped but the protagonist stays at the same place on the road (`World.context = {route, km}`); either end can then be chosen. No distance is gained.
- **Notices:** `Travel.notice` ("sabbath", "stop", "arrived") is read once by the next scene. Not saved.
- **Discovery:** `visit()` also makes neighbours "discovered" and learns the roads out of the place. `reveal(place, level, source)` records who told you. A canon event
  can put a place on the map through `reveal_on` in `geography.json`; canon itself is never touched.
- **Fog:** `World.explored` holds 4x4-tile blocks the protagonist has seen (sight radius 7 tiles), saved per region. The regional and local map views draw only those.
- **Saves:** version 3. A real version-1 save from the first milestone is kept as `tests/fixtures/pre_w1_v1_slot.json` and loads.
- **Dev:** `scripts/dev/autoplay_w1.gd` plays the demonstration through the live game, scene reloads included.


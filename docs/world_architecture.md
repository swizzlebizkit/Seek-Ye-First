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

## 11. W1.6: the continuous physical world

W1 chained regions together with hand-set exits, which let a map's exit side disagree with the real direction to its destination.
W1.6 replaces that with one shared world.

- **Two scales of play, three map views.** Villages, countryside, camps and interiors are all the same 32 px tiles and the same collision. The
  strategic map is an optional shortcut, not a place you have to go to reach something you can see.
- **World tiles.** `data/world/physical.json`: 50 m per tile, Kefar Zayit's centre is (0, 0), x grows east, y grows south. Every map has a `world`
  entry: the world tile of its top-left corner. Strategic longitude and latitude convert to world tiles with the same scale
  (`World.expected_world_tile`), and `World.validate()` fails if a settlement is more than 16 tiles from where its coordinates put it or lies in the
  wrong compass direction from another. Cana is 112 tiles west and 66 south of Kefar Zayit; Magdala 186 east and 112 north.
- **Edges are found, not wired.** Walking off the edge of a regional map looks up the map that contains the next world tile (`World.edge_crossing`).
  Different map sizes just work, the position along the boundary is kept to the pixel, facing is kept, and the player is placed 24 px inside the next map so
  they are never standing on its edge. `Game` does this each physics frame. An edge with nothing beyond it is solid cliff (the validator rejects an open edge, and rock, water or wall
  must show it).
- **Gates.** A village or town is a *local* map whose `world` rectangle is its exact footprint inside a regional map. The regional map draws the footprint (low wall,
  gateposts, rooftops), and the gate tiles are exits into the local map; the local map has exits back. A gate has the same world coordinates on both sides.
- **One raster.** `tools/mapgen/world.py` generates the whole countryside as a single raster and cuts it into maps, so roads, the river, outcrops and the lake
  continue across seams by construction. `World.validate()` still checks it: walkable ground meets walkable ground, roads and the river continue across every seam.
- **Clock.** A regional map runs the world clock four times faster (`regional_clock_multiplier`), so walking the 130 tiles from Kefar Zayit to Cana takes about
  the 1.5 game hours the strategic map gives. Villages and camps run at the ordinary rate.
- **Optional strategic travel.** Road markers carry the place (or point on a road) they stand at, so `E` offers the strategic map from exactly there. Nothing opens it by itself.
  An arrival by strategic travel puts the protagonist inside the settlement's own map at its `arrival` entry.
- **Reachability.** `WorldGraph.path` plans a walk across maps, edges and gates from the data alone. The tests use it to prove routes marked `"physical": true` in
  `geography.json` can be walked, and `scripts/dev/autoplay_w16.gd` walks one with real key presses.
- **Not yet physical.** Routes without `"physical": true` (Nazareth, Tiberias, Capernaum, Bethsaida and everything farther) can still only be reached through the strategic map until their maps are built. This is a
  recorded gap (see `docs/w16_playtest.md`), not a design intent.


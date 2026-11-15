# Geography (W1.1)

**The map is a gameplay approximation. Positions are rounded to about a kilometre and are not surveyed; roads
are plausible corridors, not reconstructions of Roman or Herodian highways; no travel time claims to be a
first-century measurement.** Data: `data/world/geography.json`, `data/world/travel.json`. Code: `scripts/autoload/world.gd`.

## 1. Scope of the first strategic map

`galilee_judea` covers Galilee, Samaria, Judea, the Jordan Valley, Perea, the Decapolis and the Mediterranean coast from
Ptolemais to Joppa: longitude 34.35 to 36.10 east, latitude 31.35 to 33.35 north. Features drawn: the Great Sea (the
Mediterranean), the Sea of Galilee, the Jordan, the Dead Sea (clipped by the southern edge) and five hills.

Positions are `[longitude, latitude]` in degrees. The screen projection scales longitude by the cosine of the middle
latitude so the land is not stretched. Playable regions use tile coordinates (32 px tiles, origin top-left).

## 2. Three kinds of place, kept apart

Every location has a `category` and a plain-language `certainty` note.

| Category | Meaning | Examples |
| --- | --- | --- |
| `documented` | A settlement whose general site is not in serious doubt | Nazareth, Capernaum, Magdala, Tiberias, Jerusalem, Bethlehem, Bethany, Jericho, Scythopolis, Gerasa, Caesarea |
| `uncertain` | A biblical place whose exact site is debated. The marker is a general area, drawn with an outer ring | Cana (Kafr Kanna or Khirbet Qana), Bethsaida (et-Tell or el-Araj), Sychar (Askar or Balata), the Jordan fords, Bethany beyond Jordan |
| `fictional` | Invented for the game | Kefar Zayit |

No exact archaeological coordinates are claimed for uncertain places. Even documented places are placed to the nearest
kilometre or so.

### Kefar Zayit (invented)

Kefar Zayit ("village of the olives") is placed at about 32.78 N, 35.40 E: in the hills of lower Galilee, west of the lake
and east of Cana, on the way down to Magdala. This is an **invented position** chosen to fit the village's established
geography (hills, olives, a road east down to the lake) and to give it roads to Cana, Nazareth and Magdala. Nothing in
any source places a village there. No canonical event happens at Kefar Zayit.

The playable countryside between the village and the lake (`galilee_hills`) is likewise invented; `magdala_shore` is the
approach to a real town but only the shore road and landing are modelled.

## 3. Routes

Routes are straight or lightly bent corridors between two places, with intermediate waypoints that are guesses at
terrain-following roads (the Jezreel valley, the central Samaritan ridge, the Jordan valley, the Jericho road, the coast).
They are not claimed to be the Roman road network. Water routes cross the Sea of Galilee. Every route has at least one
**stopping point** (land) so a halted journey has a valid place to be. Distances are computed from the waypoints.

Route ids are `a__b__mode` with the two place ids in alphabetical order. Two places may have both a land and a water
route.

## 4. Travel speeds

`travel.json` sets 4 km/h on foot (walking between dawn and sunset, resting overnight) and 6 km/h by boat (sailing
through the night). These are game values chosen so a trip across Galilee takes a day and Galilee to Jerusalem about
three, not measurements of ancient journeys. Observant travellers stop for the Sabbath; see `docs/world_architecture.md`.

## 5. Adding more

Everything is data. A new strategic map (Damascus and Syria, Asia Minor, Greece, Rome) is a new entry under `maps` with its
own bounds, and locations and routes that belong to it. Nothing in the first map assumes it is the only one. The three
levels stay the same: strategic places lead into a regional scene, or into the shared `outskirts` template until a real
scene exists. Paul's journeys, Antioch and Cyprus are not built.

## 6. Known simplifications

- The Mediterranean coast is a rough polyline; the Dead Sea is cut off by the map's southern edge.
- Boundaries between Galilee, Samaria, Judea and the Decapolis are labels, not borders.
- Positions of rumored places on the map are deliberately offset by a few pixels so a rumor never reveals an exact spot.

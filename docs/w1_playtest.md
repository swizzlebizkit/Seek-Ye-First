# W1 human playtest checklist

Nothing in W1 has been played by a person yet. The automated suite (`tests/world_tests.gd`, `tests/map_tests.gd`) and a
scripted run through the live game (`--autoplay=w1`) pass, and six screenshots were reviewed, but the feel of
walking, the map's readability, and the pacing of travel are untested by a human. Please work through this list and note
anything that feels wrong.

Run: `Godot_v4.7.2-stable_win64.exe --path .` and choose New Game.

## Leaving home
1. Walk east along the village road to the open gap in the cliffs. **Expect** the screen to change to the hills without a
   jump: you appear at the west edge at the same height you left.
2. Walk back west. **Expect** the village, at the east road.

## The countryside (`galilee_hills`)
3. Follow the main road east. **Expect** a stream with a stone ford, outcrops of rock to walk around, olive trees, a branching
   path north and another south. Nothing blocks the road itself.
4. Take the north path to the shepherds' cairn and press E. **Expect** a landmark message; Tiberias and Capernaum then appear on the map.
5. Take the south path toward the spring. By day a highwayman waits there. He is optional: avoid him, talk, or fight (K).
   **Expect** a red threat line before he attacks. At night (after 18:00) he is not there.
6. Reach the east end of the hills. **Expect** the lake shore at Magdala.

## The road marker, the strategic map and travel
7. At the road marker (hills junction), the one on the shore, or the camp's "The road", press E. **Expect** the map. Choose
   a road with Up/Down; read the distance and arrival time; press Enter.
8. **Expect** a small walker moving along the route, the clock running, the date in the header. Space speeds it up.
   Mouse wheel / + / - zooms; drag pans.
9. While walking press "Stop at the next camp" (or Esc). **Expect** the walker to halt at the next waypoint and you to be put in a
   roadside camp. Open the map there (the road at the top of the clearing): the journey is shown as paused. Resume, or Abandon.
10. At the landing on the shore (the pier) press E. **Expect** only boat routes. A boat has a sail icon, runs day and night, and
    cannot be stopped at sea.

## The Sabbath
11. Wait until it is the sixth day afternoon (the HUD reads "the sixth day"). From Nazareth (reach it via Kefar Zayit) start the long
    road to Sychar. **Expect** the map to warn that the Sabbath will begin on the way.
12. **Expect** at sunset, "The Sabbath has begun"; you are put in a camp, free to explore. The HUD turns gold.
    Open the map: Resume is greyed with a reason. Nothing moves by itself.
13. After sunset the next day (HUD no longer gold), open the map. **Expect** Resume to work, and only when you press it.
14. Try a boat on the Sabbath: it should refuse to leave, but a boat already under way keeps sailing.

## Journal map
15. Press J, go to the Map tab. **Expect** three levels (keys 1, 2, 3): Lands (the strategic map, places you know), Roads (country
    you have walked, fogged where you have not), Village (Kefar Zayit with its places named). Places you only heard of show as dashed
    circles with a "?"; their position is approximate. The map has no travel buttons.

## Saving
16. F5 anywhere (including in a camp, mid-journey), quit, load. **Expect** the same region, position, time, journey, discovered
    places and explored country. A journey paused for the Sabbath is still paused.

## Things to look at critically
- Is the speed of the walker (about 4 km/h) and the day length right for how long you want travel to take?
- Is the map readable at your window size? (1280x720 and 1920x1080 were checked by screenshot only.)
- Does the Sabbath message arrive clearly, without feeling like a punishment?
- Do the roadside camp and the "outskirts" scene feel too empty? (They are shared templates; towns are not built yet.)

## Known not built
Town and city interiors, Magdala's streets, Jerusalem, festivals, scripture investigation from the map, Damascus and beyond.

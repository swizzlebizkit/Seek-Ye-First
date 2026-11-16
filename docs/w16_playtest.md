# W1.6 human playtest checklist: the continuous world

Automated: the full headless suite, plus a scripted walk through the live game with real key presses (`--autoplay=w16`, also on the Sabbath).
Not yet done by a person: everything below, especially the feel of the crossings and the gates.

Run: `Godot_v4.7.2-stable_win64.exe --path .`, New Game.

## Leaving and re-entering the village
1. Walk to either end of the main village road. **Expect** a gap with a stone post on each side. Step into it: the screen changes to the countryside, with a wall
   and the matching gate behind you, at the height you left. Nothing asks you to press E.
2. Turn around and walk back into the gate. **Expect** the village at the same gate, facing inward, and no bouncing back out.

## Walking to Cana (the village's west gate, then south-west)
3. From the west gate follow the road west, then bending south. **Expect** the countryside to continue across two screen changes (to "The Cana road", then
   "The approach to Cana") with the road meeting itself at each boundary and no jump in where you stand along it.
4. The map named by the HUD/journal changes as you cross. **Expect** the clock to move noticeably faster in the open country than in the village (about 4x).
5. At the end of the road is a wall with a gate. Walk in. **Expect** a small placeholder settlement ("Cana of Galilee (placeholder)").
6. Leave by the same gate and walk the road back to Kefar Zayit. **Expect** to arrive at the west gate.
   Road markers (a signpost, press E) are optional: ignoring them never stops you.

## Magdala (the east gate, then north-east)
7. From the east gate follow the road east, then north-east, across two boundaries and a stone ford over the stream. **Expect** a wall and gate at Magdala (a placeholder), and past it a pier into the lake.
8. A side path leads north-west to the shepherds' cairn; another leads south to a spring where a highwayman waits by day (optional).

## Edges
9. Walk into the cliffs at the world's edge in several places. **Expect** a solid rock band, never an invisible wall and never open ground that leads nowhere.

## Strategic map (optional)
10. At a road marker press E: the strategic map for that place. **Expect** Cana and Magdala to be offered from Kefar Zayit, and that choosing them walks the same
    roads (but fast). Close it and carry on walking. During the Sabbath the map should refuse to set out overland, but walking must still work.
11. Travel by boat: the landing (end of the pier) offers the ferry. Unchanged from before.

## Journal
12. J, Map, Roads: the first entry is "The whole countryside": every map you have walked, where it lies, with Kefar Zayit, Cana and Magdala as named blocks.
    Fog should cover what you have not seen. Percentages should be low after a short walk, never 100% unless you walked it all. A strategic journey should not fill in the ground it crosses.

## Save
13. F5 anywhere (also in the middle of a long road), quit, load. **Expect** the same map, position, facing, discovery and fog.

## Known gaps to judge
- Nazareth, Tiberias, Capernaum, Bethsaida and everything farther are not yet physically connected: only the strategic map reaches them. Cana and Magdala are placeholders.
- No roadside hazards, inns or caravan stops yet (eating and health are therefore only testable in the training yard).
- The countryside is sparse and the settlement exteriors are simple walls and rooftops.
- Scale is compressed (50 m per tile, clock x4 in the open); say if the walking pace feels wrong.

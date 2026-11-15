class_name Effects
extends RefCounted
## Data-driven effects ({"set_flag": "x"}) used by dialogue, pickups, quests and examine text.
## Every change that content can make to the world goes through here. There is deliberately
## no effect that touches the CanonicalTimeline: scripted biblical events are not player-alterable.


static func run_all(effects: Array) -> void:
	for e in effects:
		run(e)


static func run(e: Dictionary) -> void:
	if e.has("when") and not GameState.check(e["when"]):
		return
	if e.has("set_flag"):
		GameState.set_flag(e["set_flag"], true)
	if e.has("clear_flag"):
		GameState.set_flag(e["clear_flag"], false)
	if e.has("journal"):
		Journal.discover(e["journal"])
	if e.has("annotate"):
		var a: Dictionary = e["annotate"]
		Journal.annotate(a["entry"], a.get("text", ""), a.get("refs", []), a.get("source", ""), a.get("id", ""))
	if e.has("set_status"):
		var s: Dictionary = e["set_status"]
		Journal.set_status(s["entry"], s["status"])
	if e.has("scripture_link"):
		var l: Dictionary = e["scripture_link"]
		Journal.discover_link(l["id"], l.get("source", ""))
	if e.has("read_scroll"):
		read_scroll(e["read_scroll"])
	if e.has("quest_start"):
		Quests.start(e["quest_start"])
	if e.has("quest_objective"):
		var q: Dictionary = e["quest_objective"]
		Quests.complete_objective(q["quest"], q["objective"])
	if e.has("give_item"):
		var g: Dictionary = e["give_item"]
		GameState.add_item(g["item"], int(g.get("count", 1)))
	if e.has("take_item"):
		var t: Dictionary = e["take_item"]
		GameState.remove_item(t["item"], int(t.get("count", 1)))
	if e.has("equip"):
		Equipment.equip(e["equip"])
	if e.has("encounter"):
		var enc: Dictionary = e["encounter"]
		Combat.resolve_encounter(enc["id"], enc["outcome"])
	if e.has("actor"):
		var a: Dictionary = e["actor"]
		Combat.command_actor(a["id"], a["command"])
	if e.has("knowledge"):
		var k: Dictionary = e["knowledge"]
		PlayerKnowledge.learn(k["event"], k["level"], k.get("source", ""))


## A teacher reads a scroll the protagonist is carrying. Every link it holds is found (and so becomes
## permanent in the journal). The scroll stays in the satchel; reading it twice does nothing new.
static func read_scroll(item_id: String) -> void:
	var def: Dictionary = GameState.items.get(item_id, {})
	if def.get("category", "") != "scroll" or GameState.item_count(item_id) < 1:
		push_warning("read_scroll: '%s' is not a scroll in the satchel" % item_id)
		return
	for lid in def.get("reveals", []):
		Journal.discover_link(lid, def.get("teacher", ""))
	GameState.set_flag("scroll_read_" + item_id, true)

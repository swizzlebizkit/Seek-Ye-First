extends Node
## Global game state: mode, flags, inventory, player placement. Content reads and writes it through
## Effects/check(); subsystems (journal, quests, knowledge, canon, world) keep their own state.

signal mode_changed(mode: int)
signal flag_changed(flag: String, value: bool)
signal inventory_changed
signal toast(text: String)
## A waymark or landing asks for the strategic map; `modes` limits which routes it offers.
signal map_requested(modes: Array)

enum Mode { MENU, EXPLORE, DIALOGUE, JOURNAL, PAUSED, EQUIPMENT, DEFEAT, MAP }

var mode: int = Mode.MENU:
	set(value):
		if mode != value:
			mode = value
			mode_changed.emit(mode)

var flags: Dictionary = {}
var inventory: Dictionary = {}
var region_id := "kefar_zayit"
var player_pos := Vector2.ZERO
var player_facing := "down"
var has_saved_position := false
var play_seconds := 0.0

## Set by the menu before the game scene loads: {"mode": "new"}, {"mode": "load", "slot": 1}
## or {"mode": "training"} (the dev-only combat training yard).
var start_request: Dictionary = {"mode": "new"}

var items: Dictionary = {}


func _ready() -> void:
	var data = DataFiles.load_json("res://data/items.json")
	if data is Dictionary:
		items = data


func _process(delta: float) -> void:
	if mode != Mode.MENU:
		play_seconds += delta


func new_game() -> void:
	flags.clear()
	inventory.clear()
	region_id = "kefar_zayit"
	player_pos = Vector2.ZERO
	player_facing = "down"
	has_saved_position = false
	play_seconds = 0.0
	Journal.reset()
	Scripture.reset()  # the player's own bookmarks; not protagonist knowledge
	Quests.reset()
	PlayerKnowledge.reset()
	CanonicalTimeline.reset()
	WorldSim.reset()
	World.reset()
	Travel.reset()
	Combat.reset()
	Equipment.reset()
	# The Baptist's ministry is already under way when the prologue opens.
	CanonicalTimeline.story_advance("john_preaching")


# -- flags -------------------------------------------------------------------------------------
func set_flag(flag: String, value: bool = true) -> void:
	if value:
		if flags.get(flag, false):
			return
		flags[flag] = true
	else:
		if not flags.erase(flag):
			return
	flag_changed.emit(flag, value)


func has_flag(flag: String) -> bool:
	return flags.get(flag, false)


# -- inventory ---------------------------------------------------------------------------------
## Unique items (e.g. a gift that carries meaning) can only be received once. Returns false if refused.
func add_item(id: String, count: int = 1, quiet: bool = false) -> bool:
	if items.get(id, {}).get("unique", false):
		if item_count(id) > 0:
			return false
		count = 1
	inventory[id] = int(inventory.get(id, 0)) + count
	inventory_changed.emit()
	if not quiet:
		toast.emit("Received: %s%s" % [item_name(id), " x%d" % count if count > 1 else ""])
	return true


func remove_item(id: String, count: int = 1) -> bool:
	var have := item_count(id)
	if have < count:
		return false
	if have == count:
		inventory.erase(id)
	else:
		inventory[id] = have - count
	inventory_changed.emit()
	return true


func item_count(id: String) -> int:
	return int(inventory.get(id, 0))


func place_name() -> String:
	if region_id == "training_yard":
		return "Training Yard (dev)"
	return World.region_name(region_id)


func item_name(id: String) -> String:
	return items.get(id, {}).get("name", id)


# -- conditions --------------------------------------------------------------------------------
## All keys must hold. Supported: flag, not_flag, has_item, equipped, quest_active, quest_done, knows,
## encounter ({"id", "outcome"}; outcome "any" or a specific one), actor ({"id", "status"}).
func check(cond: Dictionary) -> bool:
	for key in cond:
		var v = cond[key]
		match key:
			"flag":
				for f in _as_array(v):
					if not has_flag(f):
						return false
			"not_flag":
				for f in _as_array(v):
					if has_flag(f):
						return false
			"has_item":
				for i in _as_array(v):
					if item_count(i) < 1:
						return false
			"equipped":
				for i in _as_array(v):
					if not Equipment.is_equipped(i):
						return false
			"encounter":
				var got := Combat.outcome_of(v["id"])
				var want: String = v.get("outcome", "any")
				if got == "" or (want != "any" and got != want):
					return false
			"actor":
				if Combat.actor_status(v["id"]) != v["status"]:
					return false
			"weekday":
				var today := Calendar.weekday(Calendar.current_day())
				if not _as_array(v).any(func(w): return int(w) == today):  # a list means "any of these days"
					return false
			"sabbath":
				if Calendar.is_sabbath(WorldSim.day, WorldSim.minute_of_day) != bool(v):
					return false
			"day_phase":
				if Calendar.current_phase() != str(v):
					return false
			"time_of_day":
				# {"from": minute, "to": minute}; a window that crosses midnight is fine
				var now := WorldSim.minute_of_day
				var a := float(v["from"])
				var b := float(v["to"])
				if not ((now >= a and now < b) if a <= b else (now >= a or now < b)):
					return false
			"place_known":
				if not World.knows_place(v["place"], v.get("level", "rumored")):
					return false
			"landmark":
				for l in _as_array(v):
					if not World.landmarks_found.get(l, false):
						return false
			"quest_active":
				if not Quests.is_active(v):
					return false
			"quest_done":
				if not Quests.is_done(v):
					return false
			"knows":
				if not PlayerKnowledge.knows(v["event"], v.get("level", "rumor")):
					return false
			_:
				push_warning("Unknown condition key: %s" % key)
				return false
	return true


func _as_array(v) -> Array:
	return v if v is Array else [v]


# -- persistence -------------------------------------------------------------------------------
func serialize() -> Dictionary:
	return {
		"flags": flags.duplicate(),
		"inventory": inventory.duplicate(),
		"region": region_id,
		"player": {"x": player_pos.x, "y": player_pos.y, "facing": player_facing},
		"play_seconds": play_seconds,
	}


func deserialize(d: Dictionary) -> void:
	flags = d.get("flags", {}).duplicate()
	inventory = {}
	for k in d.get("inventory", {}):
		inventory[k] = int(d["inventory"][k])
	region_id = d.get("region", "kefar_zayit")
	var p: Dictionary = d.get("player", {})
	player_pos = Vector2(float(p.get("x", 0.0)), float(p.get("y", 0.0)))
	player_facing = p.get("facing", "down")
	has_saved_position = p.has("x")
	play_seconds = float(d.get("play_seconds", 0.0))

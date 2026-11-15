extends Node
## Combat bookkeeping that must outlive any scene: the protagonist's health, how each
## encounter was resolved, what became of individual characters, and a few consequence counters
## for future journal and quest use. Behaviour profiles and encounter definitions are data
## (data/combat/*.json). Nothing here touches the CanonicalTimeline.

signal player_hp_changed(hp: int, max_hp: int)
signal player_defeated
signal encounter_resolved(encounter_id: String, outcome: String)
signal actor_command(actor_id: String, command: String)
signal player_swung(origin: Vector2)
signal assault_reported(victim_id: String, position: Vector2)

const BASE_MAX_HP := 12  # drawn as hearts of 2 points each

## Statuses that are remembered across saves; everything else is momentary behaviour.
const LASTING_STATUSES := ["dead", "fled", "routed", "surrendered", "stood_down"]

var player_hp := BASE_MAX_HP
var outcomes: Dictionary = {}  # encounter id -> {"outcome": String, "day": int}
var consequences: Dictionary = {}
var actors: Dictionary = {}  # actor id -> {"status": String, "hp": int}

var profiles: Dictionary = {}
var profile_defaults: Dictionary = {}
var encounters: Dictionary = {}
var outcome_labels: Dictionary = {}


func _ready() -> void:
	var p = DataFiles.load_json("res://data/combat/profiles.json")
	if p is Dictionary:
		profiles = p.get("profiles", {})
		profile_defaults = p.get("defaults", {})
	var e = DataFiles.load_json("res://data/combat/encounters.json")
	if e is Dictionary:
		encounters = e.get("encounters", {})
		outcome_labels = e.get("outcomes", {})
	reset()


func reset() -> void:
	player_hp = BASE_MAX_HP
	outcomes.clear()
	actors.clear()
	consequences = {
		"defeated": 0,  # opponents killed
		"routed": 0,  # opponents who ran
		"yielded": 0,  # opponents who surrendered
		"noncombatants_struck": 0,
		"times_overcome": 0,  # times the protagonist was beaten down
	}
	player_hp_changed.emit(player_hp, max_hp())


# -- profiles ----------------------------------------------------------------------------------
func has_profile(id: String) -> bool:
	return profiles.has(id)


## A profile with the file defaults filled in. Unknown ids fall back to a harmless noncombatant.
func profile(id: String) -> Dictionary:
	var p: Dictionary = profile_defaults.duplicate(true)
	p.merge(profiles.get(id, profiles.get("villager", {})).duplicate(true), true)
	return p


# -- player health -----------------------------------------------------------------------------
func max_hp() -> int:
	return BASE_MAX_HP


func is_player_down() -> bool:
	return player_hp <= 0


## Damage after armor and, for hits from the front, the shield. Never below 1.
func damage_after_armor(raw: int, from_front: bool) -> int:
	var reduced := float(raw) - Equipment.stat("defense")
	if from_front:
		reduced -= Equipment.stat("block")
	return maxi(1, int(reduced))


## Applies already-reduced damage. Returns the damage dealt.
func hurt_player(amount: int) -> int:
	if player_hp <= 0 or amount <= 0:
		return 0
	player_hp = maxi(0, player_hp - amount)
	player_hp_changed.emit(player_hp, max_hp())
	if player_hp == 0:
		consequences["times_overcome"] = int(consequences.get("times_overcome", 0)) + 1
		player_defeated.emit()
	return amount


func heal_player(amount: int = BASE_MAX_HP) -> void:
	player_hp = clampi(player_hp + amount, 0, max_hp())
	player_hp_changed.emit(player_hp, max_hp())


# -- encounters --------------------------------------------------------------------------------
func has_encounter(id: String) -> bool:
	return encounters.has(id)


func outcome_of(id: String) -> String:
	return outcomes.get(id, {}).get("outcome", "")


func is_valid_outcome(encounter_id: String, outcome: String) -> bool:
	return encounters.has(encounter_id) and encounters[encounter_id].get("valid", []).has(outcome) \
		and outcome_labels.has(outcome)


## Records how an encounter ended. The first resolution stands. Returns true if it was recorded.
func resolve_encounter(encounter_id: String, outcome: String) -> bool:
	if not is_valid_outcome(encounter_id, outcome):
		push_warning("Invalid encounter outcome '%s' for '%s'" % [outcome, encounter_id])
		return false
	if outcomes.has(encounter_id):
		return false
	outcomes[encounter_id] = {"outcome": outcome, "day": WorldSim.day}
	GameState.set_flag("encounter_%s" % encounter_id)
	match outcome:
		"combat_victory":
			consequences["defeated"] = int(consequences["defeated"]) + 1
		"combat_routed":
			consequences["routed"] = int(consequences["routed"]) + 1
		"combat_surrender":
			consequences["yielded"] = int(consequences["yielded"]) + 1
	encounter_resolved.emit(encounter_id, outcome)
	return true


## Human-readable summary of every encounter, for the training-yard ledger.
func ledger_lines() -> Array:
	var lines: Array = []
	for id in encounters:
		var o := outcome_of(id)
		lines.append("%s: %s" % [encounters[id]["title"], outcome_labels[o] if o != "" else "not yet resolved"])
	return lines


# -- individual characters ---------------------------------------------------------------------
func actor_status(id: String) -> String:
	return actors.get(id, {}).get("status", "")


func actor_hp(id: String, fallback: int) -> int:
	return int(actors.get(id, {}).get("hp", fallback))


func set_actor(id: String, status: String, hp: int) -> void:
	actors[id] = {"status": status, "hp": hp}


## Lets data (dialogue effects) steer a character: "stand_down", "provoke", "release".
func command_actor(id: String, command: String) -> void:
	actor_command.emit(id, command)


func swung(origin: Vector2) -> void:
	player_swung.emit(origin)


func report_assault(victim_id: String, pos: Vector2) -> void:
	consequences["noncombatants_struck"] = int(consequences.get("noncombatants_struck", 0)) + 1
	assault_reported.emit(victim_id, pos)


# -- persistence -------------------------------------------------------------------------------
func serialize() -> Dictionary:
	var lasting := {}
	for id in actors:
		if LASTING_STATUSES.has(actors[id]["status"]):
			lasting[id] = actors[id].duplicate()
	return {
		"hp": player_hp,
		"outcomes": outcomes.duplicate(true),
		"consequences": consequences.duplicate(),
		"actors": lasting,
	}


func deserialize(d: Dictionary) -> void:
	reset()
	player_hp = clampi(int(d.get("hp", BASE_MAX_HP)), 0, max_hp())
	if player_hp == 0:
		player_hp = max_hp()  # a save is never loaded into a defeat screen
	for id in d.get("outcomes", {}):
		var o: Dictionary = d["outcomes"][id]
		outcomes[id] = {"outcome": String(o.get("outcome", "")), "day": int(o.get("day", 1))}
	for k in d.get("consequences", {}):
		consequences[k] = int(d["consequences"][k])
	for id in d.get("actors", {}):
		var a: Dictionary = d["actors"][id]
		actors[id] = {"status": String(a.get("status", "")), "hp": int(a.get("hp", 0))}
	player_hp_changed.emit(player_hp, max_hp())

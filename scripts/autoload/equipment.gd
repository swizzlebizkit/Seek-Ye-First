extends Node
## What the protagonist is wearing and carrying in hand: six ordinary physical slots
## (data/equipment/slots.json). Items are defined in data/items.json (category "equipment" with a
## `slot` and numeric `stats`). Equipped items stay in the satchel; a slot only remembers the item id.
##
## Wearing something grants its physical stats and nothing else. Adding gear means adding data: any
## new stat key is summed automatically, and only the systems that read that key care about it.

signal equipment_changed

const SPEED_MIN := 0.6
const SPEED_MAX := 1.25

var slot_defs: Array = []
var stat_labels: Dictionary = {}
var worn: Dictionary = {}  # slot id -> item id


func _ready() -> void:
	var data = DataFiles.load_json("res://data/equipment/slots.json")
	if data is Dictionary:
		slot_defs = data.get("slots", [])
		stat_labels = data.get("stat_labels", {})
	GameState.inventory_changed.connect(_on_inventory_changed)
	_clear()


# -- definitions -------------------------------------------------------------------------------
func slot_ids() -> Array:
	return slot_defs.map(func(s): return s["id"])


func has_slot(slot: String) -> bool:
	return slot_ids().has(slot)


func slot_label(slot: String) -> String:
	for s in slot_defs:
		if s["id"] == slot:
			return s["label"]
	return slot


func is_equipment(item_id: String) -> bool:
	return GameState.items.get(item_id, {}).get("category", "") == "equipment"


func slot_of(item_id: String) -> String:
	return GameState.items.get(item_id, {}).get("slot", "")


func stats_of(item_id: String) -> Dictionary:
	return GameState.items.get(item_id, {}).get("stats", {})


func stat_label(key: String) -> String:
	return stat_labels.get(key, key.capitalize())


# -- state -------------------------------------------------------------------------------------
func equipped(slot: String) -> String:
	return worn.get(slot, "")


func is_equipped(item_id: String) -> bool:
	return worn.values().has(item_id)


func has_sword() -> bool:
	return equipped("sword") != ""


## Empty string if the item can be equipped right now, otherwise why not.
func equip_problem(item_id: String) -> String:
	if not is_equipment(item_id):
		return "That cannot be worn."
	if not has_slot(slot_of(item_id)):
		return "There is nowhere to wear that."
	if GameState.item_count(item_id) < 1:
		return "You do not have that."
	return ""


func equip(item_id: String) -> bool:
	if equip_problem(item_id) != "":
		return false
	var slot := slot_of(item_id)
	if worn.get(slot, "") == item_id:
		return true
	worn[slot] = item_id
	equipment_changed.emit()
	GameState.toast.emit("Equipped: %s" % GameState.item_name(item_id))
	return true


func unequip(slot: String) -> bool:
	if not worn.has(slot):
		return false
	worn.erase(slot)
	equipment_changed.emit()
	return true


## Items in the satchel that fit a slot.
func candidates_for(slot: String) -> Array:
	var out: Array = []
	for id in GameState.inventory:
		if is_equipment(id) and slot_of(id) == slot:
			out.append(id)
	return out


# -- derived stats -----------------------------------------------------------------------------
## Sum of every equipped item's stats. Sword stats (attack, reach, cooldown) come only from the sword.
func totals() -> Dictionary:
	var t := {}
	for slot in worn:
		var stats := stats_of(worn[slot])
		for k in stats:
			t[k] = float(t.get(k, 0.0)) + float(stats[k])
	return t


func stat(key: String) -> float:
	return float(totals().get(key, 0.0))


func speed_multiplier() -> float:
	return clampf(1.0 + stat("mobility"), SPEED_MIN, SPEED_MAX)


## Null-ish dictionary when no sword is held; otherwise {attack, reach, cooldown}.
func weapon() -> Dictionary:
	var sword := equipped("sword")
	if sword == "":
		return {}
	var s := stats_of(sword)
	return {
		"item": sword,
		"attack": int(s.get("attack", 1)),
		"reach": float(s.get("reach", 24.0)),
		"cooldown": float(s.get("cooldown", 0.5)),
	}


# -- lifecycle ---------------------------------------------------------------------------------
func _clear() -> void:
	worn.clear()


## New game: nothing but the plain starting clothes.
func reset() -> void:
	_clear()
	for s in slot_defs:
		var d: String = s.get("default", "")
		if d != "":
			GameState.add_item(d, 1, true)
			worn[s["id"]] = d
	equipment_changed.emit()


## Drops anything that is no longer valid (item gone, wrong slot, unknown slot).
func validate() -> void:
	var changed := false
	for slot in worn.keys():
		var id: String = worn[slot]
		if not has_slot(slot) or not is_equipment(id) or slot_of(id) != slot or GameState.item_count(id) < 1:
			worn.erase(slot)
			changed = true
	if changed:
		equipment_changed.emit()


func _on_inventory_changed() -> void:
	validate()


func serialize() -> Dictionary:
	return {"worn": worn.duplicate()}


func deserialize(d: Dictionary) -> void:
	_clear()
	if not d.has("worn"):
		# a save from before equipment existed: wear the starting clothes
		for s in slot_defs:
			var def: String = s.get("default", "")
			if def != "":
				GameState.add_item(def, 1, true)
				worn[s["id"]] = def
	else:
		for slot in d["worn"]:
			worn[slot] = String(d["worn"][slot])
	validate()
	equipment_changed.emit()

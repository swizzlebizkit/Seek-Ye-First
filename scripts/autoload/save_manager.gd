extends Node
## JSON save files in user://saves (slot_1..slot_3). Every subsystem serializes itself; this
## node only assembles and applies the pieces. Writes go to a temp file first so a crash
## mid-save cannot corrupt an existing slot.

const SLOTS := 3
const VERSION := 1

## Overridden by tests so they never touch real saves.
var save_dir := "user://saves"


func slot_path(slot: int) -> String:
	return "%s/slot_%d.json" % [save_dir, slot]


func has_save(slot: int) -> bool:
	return FileAccess.file_exists(slot_path(slot))


func has_any_save() -> bool:
	for s in range(1, SLOTS + 1):
		if has_save(s):
			return true
	return false


## Slot with the most recent save, or 0.
func latest_slot() -> int:
	var best := 0
	var best_time := -1.0
	for s in range(1, SLOTS + 1):
		var info := slot_info(s)
		if info.get("exists", false) and float(info.get("saved_unix", 0)) > best_time:
			best_time = float(info["saved_unix"])
			best = s
	return best


func slot_info(slot: int) -> Dictionary:
	var data := read_slot(slot)
	if data.is_empty():
		return {"exists": false}
	var meta: Dictionary = data.get("meta", {})
	return {
		"exists": true,
		"saved_unix": data.get("saved_unix", 0),
		"saved_at": data.get("saved_at", ""),
		"place": meta.get("place", "Unknown"),
		"play_seconds": meta.get("play_seconds", 0),
		"journal_entries": meta.get("journal_entries", 0),
	}


func read_slot(slot: int) -> Dictionary:
	if not has_save(slot):
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(slot_path(slot))) != OK or not json.data is Dictionary:
		push_warning("Save slot %d is unreadable" % slot)
		return {}
	return json.data


func save_slot(slot: int) -> bool:
	DirAccess.make_dir_recursive_absolute(save_dir)
	var data := {
		"version": VERSION,
		"saved_unix": Time.get_unix_time_from_system(),
		"saved_at": Time.get_datetime_string_from_system(false, true),
		"meta": {
			"place": "Kefar Zayit",
			"play_seconds": GameState.play_seconds,
			"journal_entries": Journal.count(),
		},
		"game": GameState.serialize(),
		"journal": Journal.serialize(),
		"quests": Quests.serialize(),
		"knowledge": PlayerKnowledge.serialize(),
		"canon": CanonicalTimeline.serialize(),
		"world": WorldSim.serialize(),
	}
	var path := slot_path(slot)
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("Cannot write save: %s" % error_string(FileAccess.get_open_error()))
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	if DirAccess.rename_absolute(tmp, path) != OK:
		push_error("Cannot finalize save file")
		return false
	return true


## Restores every subsystem from a slot. Returns false (touching nothing) if unreadable or too new.
func load_slot(slot: int) -> bool:
	var data := read_slot(slot)
	if data.is_empty():
		return false
	if int(data.get("version", 0)) > VERSION:
		push_error("Save slot %d was written by a newer version" % slot)
		return false
	GameState.deserialize(data.get("game", {}))
	Journal.deserialize(data.get("journal", {}))
	Quests.deserialize(data.get("quests", {}))
	PlayerKnowledge.deserialize(data.get("knowledge", {}))
	CanonicalTimeline.deserialize(data.get("canon", {}))
	WorldSim.deserialize(data.get("world", {}))
	return true


func delete_slot(slot: int) -> void:
	if has_save(slot):
		DirAccess.remove_absolute(slot_path(slot))

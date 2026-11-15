extends Node
## System B: World Simulation. Ordinary life: the clock, and (later) NPC schedules, travel and
## fictional events. Milestone 1 keeps this lightweight: a day/time clock only. NPC wandering
## lives in the Npc entity for now and will move under this system as schedules arrive.

const GAME_MINUTES_PER_REAL_SECOND := 0.5

var day := 1
var minute_of_day := 7.0 * 60.0


func _process(delta: float) -> void:
	if GameState.mode != GameState.Mode.EXPLORE:
		return
	minute_of_day += delta * GAME_MINUTES_PER_REAL_SECOND
	while minute_of_day >= 1440.0:
		minute_of_day -= 1440.0
		day += 1


func time_string() -> String:
	var m := int(minute_of_day)
	return "%d:%02d" % [m / 60, m % 60]


func reset() -> void:
	day = 1
	minute_of_day = 7.0 * 60.0


func serialize() -> Dictionary:
	return {"day": day, "minute": minute_of_day}


func deserialize(d: Dictionary) -> void:
	day = int(d.get("day", 1))
	minute_of_day = float(d.get("minute", 7.0 * 60.0))

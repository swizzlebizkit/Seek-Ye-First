extends Node
## System B: World Simulation. Ordinary life: the clock, and (later) NPC schedules, travel and
## fictional events. Milestone 1 keeps this lightweight: a day/time clock only. NPC wandering
## lives in the Npc entity for now and will move under this system as schedules arrive.

signal sunset_passed(day: int)
signal day_rolled(day: int)

const GAME_MINUTES_PER_REAL_SECOND := 0.5

## Walking the countryside is a compressed scale: the clock runs this much faster there (set by the game scene).
var clock_multiplier := 1.0
var day := 1
var minute_of_day := 7.0 * 60.0


func _process(delta: float) -> void:
	if GameState.mode != GameState.Mode.EXPLORE:
		return
	advance(delta * GAME_MINUTES_PER_REAL_SECOND * clock_multiplier)


## Moves the clock forward without ever stepping over a boundary: each step stops exactly at sunset
## and at midnight, and announces it. Travel, rests and the real-time clock all go through here, so a
## big jump cannot skip the start of a Sabbath, a new day, or a new month or year.
func advance(minutes: float) -> void:
	var left := minutes
	while left > 0.0:
		var sunset := float(Calendar.sunset_for(day))
		var step := minf(left, 1440.0 - minute_of_day)
		var hits_sunset := minute_of_day < sunset and minute_of_day + step >= sunset
		if hits_sunset:
			step = sunset - minute_of_day
		# The clock also stops exactly at the start or end of every canonical event, so a long rest
		# or journey cannot step over one; the timeline announces each in order.
		var day_start := float(day - 1) * 1440.0
		var to_canon := CanonicalTimeline.next_boundary(day_start + minute_of_day) - (day_start + minute_of_day)
		var hits_canon := to_canon < step
		if hits_canon:
			step = to_canon
			hits_sunset = false
		if hits_canon:
			minute_of_day += step
		else:
			minute_of_day = sunset if hits_sunset else minute_of_day + step
		left -= step
		if hits_sunset:
			sunset_passed.emit(day)
		if minute_of_day >= 1440.0:
			minute_of_day -= 1440.0
			day += 1
			day_rolled.emit(day)
		CanonicalTimeline.sync_to(Calendar.world_minutes(day, minute_of_day))


## Minutes from now until the next sunset (the day number and the Sabbath both turn over there).
func minutes_to_sunset() -> float:
	var sunset := float(Calendar.sunset_for(day))
	if minute_of_day < sunset:
		return sunset - minute_of_day
	return 1440.0 - minute_of_day + float(Calendar.sunset_for(day + 1))


func time_string() -> String:
	var m := int(minute_of_day)
	return "%d:%02d" % [m / 60, m % 60]


func reset() -> void:
	day = 1
	minute_of_day = float(Calendar.start_minute)


func serialize() -> Dictionary:
	return {"day": day, "minute": minute_of_day}


func deserialize(d: Dictionary) -> void:
	day = int(d.get("day", 1))
	minute_of_day = float(d.get("minute", Calendar.start_minute))
	CanonicalTimeline.sync_to(Calendar.world_minutes(day, minute_of_day))  # canon is a function of time

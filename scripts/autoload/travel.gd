extends Node
## Strategic journeys. A journey follows one route between two locations, advancing the real world
## clock (WorldSim) in steps that always end at sunset and midnight, so no calendar transition is
## ever skipped. All Sabbath questions go to Calendar; there is no second Sabbath clock.
##
## Rules come from data/world/travel.json. Land travel walks between dawn and sunset, rests
## overnight and stops for the Sabbath at exactly the progress it had reached. Boats keep moving.
## A journey never resumes by itself.

signal journey_changed
signal paused(reason: String)
signal arrived(location: String)
signal event_fired(event: Dictionary)

enum Phase { IDLE, UNDERWAY, PAUSED }

const REASONS := ["sabbath", "player", "stop", "encounter", "blocked", "load"]
const EPS := 0.0001

## The saved journey: {} when none. Keys: route, from, to, dir, mode, pos (km from the route's a end),
## start_pos, state ("underway"/"paused"), pause, stop, fired, started_day, stop_requested.
var journey: Dictionary = {}
var last_arrival := ""
## What the next region should tell the player ("sabbath", "stop", "arrived"); not saved.
var notice := ""


func reset() -> void:
	journey = {}
	last_arrival = ""
	journey_changed.emit()


# -- rules -------------------------------------------------------------------------------------
func rules(mode: String) -> Dictionary:
	return World.travel_rules.get(mode, {})


func speed_kmh(mode: String) -> float:
	return float(rules(mode).get("speed_kmh", 4.0))


func window_start(mode: String) -> float:
	return float(rules(mode).get("window_start", 0))


## Minute of the day the daily travel window closes (sunset for land).
func window_end(mode: String, day: int) -> float:
	var e = rules(mode).get("window_end", 1440)
	return float(Calendar.sunset_for(day)) if str(e) == "sunset" else float(e)


func active() -> bool:
	return not journey.is_empty()


func phase() -> int:
	if journey.is_empty():
		return Phase.IDLE
	return Phase.PAUSED if journey["state"] == "paused" else Phase.UNDERWAY


func progress_fraction() -> float:
	if journey.is_empty():
		return 0.0
	var span := absf(_target() - float(journey["start_pos"]))
	return 1.0 if span <= 0.0 else clampf(absf(float(journey["pos"]) - float(journey["start_pos"])) / span, 0.0, 1.0)


func remaining_km() -> float:
	return 0.0 if journey.is_empty() else absf(_target() - float(journey["pos"]))


func _target() -> float:
	return float(World.route(journey["route"]).get("length_km", 0.0)) if int(journey["dir"]) > 0 else 0.0


## Strategic position of the traveller as [lon, lat].
func traveller_point() -> Vector2:
	return World.point_on_route(journey["route"], float(journey["pos"])) if not journey.is_empty() else Vector2.ZERO


# -- starting ----------------------------------------------------------------------------------
## Where the protagonist stands on the strategic network: {"location": id} or {"route": id, "km": x}.
func position() -> Dictionary:
	if not journey.is_empty():
		return {"route": journey["route"], "km": journey["pos"]}
	if World.context.has("route"):
		return {"route": World.context["route"], "km": float(World.context.get("km", 0.0))}
	var loc := World.current_location()
	return {"location": loc} if loc != "" else {}


## Routes the protagonist can begin from here, as [{route, to, dir, mode, from_km}].
func options() -> Array:
	var out: Array = []
	if not journey.is_empty():
		return out
	var p := position()
	if p.has("location"):
		for id in World.usable_routes_from(str(p["location"])):
			var r := World.route(id)
			var forward: bool = r["a"] == p["location"]
			out.append({"route": id, "to": World.other_end(id, str(p["location"])), "dir": 1 if forward else -1,
				"mode": r["mode"], "from_km": 0.0 if forward else float(r["length_km"])})
	elif p.has("route"):
		var r2 := World.route(str(p["route"]))
		if not r2.is_empty() and r2["mode"] == "land":
			out.append({"route": p["route"], "to": r2["b"], "dir": 1, "mode": "land", "from_km": float(p["km"])})
			out.append({"route": p["route"], "to": r2["a"], "dir": -1, "mode": "land", "from_km": float(p["km"])})
	return out


## {"ok": bool, "reason": text}. Departure rules: no overland departure on the Sabbath, and none by
## boat either (boats already at sea are a different matter).
func can_start(opt: Dictionary) -> Dictionary:
	if not journey.is_empty():
		return {"ok": false, "reason": "A journey is already under way."}
	var rule := rules(str(opt["mode"]))
	if not bool(rule.get("start_on_sabbath", false)) and Calendar.is_sabbath(WorldSim.day, WorldSim.minute_of_day):
		return {"ok": false, "reason": "It is the Sabbath. The road is closed to travel until sunset."}
	return {"ok": true, "reason": ""}


func start(opt: Dictionary) -> bool:
	if not can_start(opt)["ok"]:
		return false
	journey = _new_journey(opt)
	World.context = {"route": opt["route"], "km": float(opt["from_km"])}
	journey_changed.emit()
	return true


func _new_journey(opt: Dictionary) -> Dictionary:
	var r := World.route(str(opt["route"]))
	var from_loc := World.current_location()
	var from_id: String = from_loc if from_loc != "" else str(r["a"] if int(opt["dir"]) > 0 else r["b"])
	return {
		"route": opt["route"], "from": from_id, "to": opt["to"], "dir": int(opt["dir"]), "mode": opt["mode"],
		"pos": float(opt["from_km"]), "start_pos": float(opt["from_km"]), "state": "underway", "pause": "",
		"stop": "", "fired": [], "started_day": WorldSim.day, "stop_requested": false,
	}


func can_resume() -> Dictionary:
	if journey.is_empty() or journey["state"] != "paused":
		return {"ok": false, "reason": "There is no journey to resume."}
	var rule := rules(str(journey["mode"]))
	if not bool(rule.get("continue_on_sabbath", false)) and Calendar.is_sabbath(WorldSim.day, WorldSim.minute_of_day):
		return {"ok": false, "reason": "It is the Sabbath. You may travel again after sunset."}
	return {"ok": true, "reason": ""}


## Resumption is always the player's choice.
func resume() -> bool:
	if not can_resume()["ok"]:
		return false
	journey["state"] = "underway"
	journey["pause"] = ""
	journey["stop"] = ""
	journey["stop_requested"] = false
	journey_changed.emit()
	return true


## Drops the destination. The protagonist stays on the road at the same place and may go on to
## either end later; no distance is gained by abandoning.
func abandon() -> void:
	if journey.is_empty():
		return
	World.context = {"route": journey["route"], "km": float(journey["pos"])}
	journey = {}
	journey_changed.emit()


## The player asks to halt: a walker stops at the next waypoint; a boat cannot stop at sea.
func request_stop() -> bool:
	if journey.is_empty() or journey["mode"] != "land" or journey["state"] != "underway":
		return false
	journey["stop_requested"] = true
	return true


# -- the simulation ----------------------------------------------------------------------------
## Runs the journey for up to `moving_minutes` of walking or sailing. Overnight rests cost nothing
## from that budget (they still advance the clock), so a caller animating the journey sees a night
## pass at once. Stops early for an arrival, a Sabbath pause, a requested or scripted stop, or an event.
## Returns {"elapsed" (clock minutes, rests included), "moving", "rest", "event", "text"}.
func run(moving_minutes: float) -> Dictionary:
	return _simulate(journey, moving_minutes, true)


## What the journey would take from now, without touching the world: the same fields as run(), plus
## "arrives" (false if the Sabbath stops it first) and the "day" and "minute" it ends at.
func estimate() -> Dictionary:
	return _estimate(journey.duplicate(true))


## The same, for a journey that has not been started yet (an entry from options()).
func estimate_option(opt: Dictionary) -> Dictionary:
	return _estimate(_new_journey(opt))


func _estimate(j: Dictionary) -> Dictionary:
	if j.is_empty() or j["state"] != "underway":
		return {"elapsed": 0.0, "moving": 0.0, "rest": 0.0, "event": "", "text": "", "arrives": false, "day": WorldSim.day, "minute": WorldSim.minute_of_day}
	var out := _simulate(j, 1.0e9, false)
	out["arrives"] = out["event"] == "arrived"
	return out


func _simulate(j: Dictionary, budget: float, real: bool) -> Dictionary:
	var out := {"elapsed": 0.0, "event": "", "text": "", "moving": 0.0, "rest": 0.0, "day": WorldSim.day, "minute": WorldSim.minute_of_day}
	if j.is_empty() or j["state"] != "underway":
		return out
	var mode: String = j["mode"]
	var rule := rules(mode)
	var speed := speed_kmh(mode)
	var clock := {"day": WorldSim.day, "minute": WorldSim.minute_of_day}
	var safety := 0
	while float(out["moving"]) < budget - EPS and safety < 4000:
		safety += 1
		var day: int = clock["day"]
		var minute: float = clock["minute"]
		# the Sabbath ends a land journey for the day, wherever the traveller has got to
		if not bool(rule.get("continue_on_sabbath", false)) and Calendar.is_sabbath(day, minute):
			if real:
				_pause("sabbath")
			out["event"] = "sabbath"
			break
		# outside the daily window the walker rests; nothing moves until dawn
		var w0 := window_start(mode)
		var w1 := window_end(mode, day)
		if minute < w0 or minute >= w1:
			var wake := (w0 - minute) if minute < w0 else (1440.0 - minute + w0)
			_advance(clock, wake, real)
			out["elapsed"] += wake
			out["rest"] += wake
			continue
		# one leg: to the earliest of the budget, window end, a waypoint, an event or the destination
		var to_target := absf(_target_of(j) - float(j["pos"]))
		var leg := minf(budget - float(out["moving"]), float(World.travel_rules.get("chunk_max_minutes", 120)))
		leg = minf(leg, w1 - minute)
		leg = minf(leg, to_target / speed * 60.0)
		var milestone := _next_milestone(j)
		if not milestone.is_empty():
			leg = minf(leg, absf(float(milestone["km"]) - float(j["pos"])) / speed * 60.0)
		leg = maxf(leg, 0.0)
		_advance(clock, leg, real)
		out["elapsed"] += leg
		out["moving"] += leg
		j["pos"] = float(j["pos"]) + float(j["dir"]) * speed * leg / 60.0
		if real:
			World.context = {"route": j["route"], "km": float(j["pos"])}
		if absf(_target_of(j) - float(j["pos"])) <= EPS:
			j["pos"] = _target_of(j)
			out["event"] = "arrived"
			break
		if not milestone.is_empty() and absf(float(milestone["km"]) - float(j["pos"])) <= EPS:
			if milestone["kind"] == "stop":
				j["stop_requested"] = false
				if real:
					_pause("player", str(milestone["id"]))
				out["event"] = "stop"
				break
			var ev: Dictionary = milestone["event"]
			(j["fired"] as Array).append(ev["id"])
			if not real and not bool(ev.get("pause", false)):
				continue  # an estimate sails on past a harmless event
			out["text"] = str(ev.get("text", ""))
			out["event"] = "scripted"
			out["scripted"] = ev
			if bool(ev.get("pause", false)) and real:
				_pause("encounter", "", ev)
			break
	out["day"] = clock["day"]
	out["minute"] = clock["minute"]
	if real:
		if out["event"] == "arrived":
			_arrive()
		elif out["event"] == "scripted" and out.has("scripted"):
			event_fired.emit(out["scripted"])
		journey_changed.emit()
	return out


func _target_of(j: Dictionary) -> float:
	return float(World.route(j["route"]).get("length_km", 0.0)) if int(j["dir"]) > 0 else 0.0


## The nearest thing ahead on the road that interrupts a leg: a requested stop or an unfired event.
func _next_milestone(j: Dictionary) -> Dictionary:
	var r := World.route(j["route"])
	var length := float(r["length_km"])
	var pos := float(j["pos"])
	var dir := int(j["dir"])
	var best := {}
	var best_d := INF
	if bool(j.get("stop_requested", false)):
		for s in r["stop_list"]:
			var d := (float(s["km"]) - pos) * dir
			if d > EPS and d < best_d:
				best_d = d
				best = {"kind": "stop", "km": float(s["km"]), "id": s["id"]}
	for ev in r.get("events", []):
		if (j["fired"] as Array).has(ev["id"]):
			continue
		var km := float(ev["at"]) * length
		var d2 := (km - pos) * dir
		if d2 > EPS and d2 < best_d:
			best_d = d2
			best = {"kind": "event", "km": km, "event": ev}
	return best


func _advance(clock: Dictionary, minutes: float, real: bool) -> void:
	if minutes <= 0.0:
		return
	if real:
		WorldSim.advance(minutes)
		clock["day"] = WorldSim.day
		clock["minute"] = WorldSim.minute_of_day
		return
	var left := minutes
	while left > 0.0:
		var sunset := float(Calendar.sunset_for(clock["day"]))
		var step := minf(left, 1440.0 - float(clock["minute"]))
		if float(clock["minute"]) < sunset and float(clock["minute"]) + step >= sunset:
			step = sunset - float(clock["minute"])
			clock["minute"] = sunset
		else:
			clock["minute"] = float(clock["minute"]) + step
		left -= step
		if float(clock["minute"]) >= 1440.0:
			clock["minute"] = float(clock["minute"]) - 1440.0
			clock["day"] = int(clock["day"]) + 1


func _pause(reason: String, stop_id: String = "", ev: Dictionary = {}) -> void:
	journey["state"] = "paused"
	journey["pause"] = reason
	if stop_id == "":
		stop_id = _nearest_stop(journey)
	journey["stop"] = stop_id
	journey["pause_region"] = ev.get("region", "") if not ev.is_empty() else ""
	journey["pause_entry"] = ev.get("entry", "") if not ev.is_empty() else ""
	World.context = {"route": journey["route"], "km": float(journey["pos"])}
	paused.emit(reason)


func _nearest_stop(j: Dictionary) -> String:
	var best := ""
	var best_d := INF
	for s in World.route(j["route"])["stop_list"]:
		var d := absf(float(s["km"]) - float(j["pos"]))
		if d < best_d:
			best_d = d
			best = s["id"]
	return best


## The playable place a paused traveller is put in: {"region", "entry"}.
func pause_destination() -> Dictionary:
	if journey.is_empty():
		return {}
	if str(journey.get("pause_region", "")) != "":
		return {"region": journey["pause_region"], "entry": str(journey.get("pause_entry", "camp"))}
	for s in World.route(journey["route"])["stop_list"]:
		if s["id"] == journey.get("stop", "") and str(s["region"]) != "":
			return {"region": s["region"], "entry": "camp"}
	return {"region": str(rules(journey["mode"]).get("stop_region", "road_camp")), "entry": "camp"}


## Where an arrival is put: the location's own scene, or the shared outskirts template.
func arrival_destination(loc: String) -> Dictionary:
	var own = World.location(loc).get("region")
	if own != null and str(own) != "":
		return {"region": str(own), "entry": "arrival"}
	return {"region": str(World.travel_rules.get("arrival_region", "outskirts")), "entry": "arrival"}


func _arrive() -> void:
	var dest: String = journey["to"]
	var rid: String = journey["route"]
	last_arrival = dest
	journey = {}
	World.context = {"location": dest}
	World.discover_route(rid)
	World.visit(dest)
	arrived.emit(dest)


## Enters the playable place a paused or arrived journey calls for (reloads the scene at runtime).
func enter_paused_region() -> void:
	var d := pause_destination()
	if not d.is_empty():
		World.go(str(d["region"]), str(d["entry"]))


func enter_arrival_region() -> void:
	var d := arrival_destination(last_arrival)
	World.go(str(d["region"]), str(d["entry"]))


# -- persistence -------------------------------------------------------------------------------
func serialize() -> Dictionary:
	return {"v": 1, "journey": journey.duplicate(true), "last_arrival": last_arrival}


## A journey is always restored paused: loading never moves anyone, and during the Sabbath it is
## marked as a Sabbath pause so nothing can resume until the Sabbath has passed.
func deserialize(d: Dictionary) -> void:
	journey = {}
	last_arrival = str(d.get("last_arrival", ""))
	var j = d.get("journey", {})
	if j is Dictionary and not j.is_empty() and World.routes.has(j.get("route", "")):
		for k in ["pos", "start_pos"]:
			j[k] = float(j.get(k, 0.0))
		j["dir"] = int(j.get("dir", 1))
		j["fired"] = j.get("fired", []) if j.get("fired", []) is Array else []
		j["stop_requested"] = false
		if j.get("state", "paused") != "paused":
			j["state"] = "paused"
			j["pause"] = "load"
		if j["mode"] == "land" and Calendar.is_sabbath(WorldSim.day, WorldSim.minute_of_day):
			j["pause"] = "sabbath"
		journey = j
	journey_changed.emit()

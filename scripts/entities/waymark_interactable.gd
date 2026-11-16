class_name WaymarkInteractable
extends Interactable
## A milestone, landing or camp fire where the long road can be taken. Examining it reads a few
## lines, then opens the strategic map for the routes of the listed modes that start here.

var text: Array = []
var modes: Array = ["land", "water"]
var landmark := ""
## What this marker stands at: a strategic place, or a point part-way along a route (0 to 1).
var place := ""
var route := ""
var at := 0.5


func _init() -> void:
	super._init()
	verb = "Take the road"


func _on_interact(_by: Node) -> void:
	if landmark != "":
		World.find_landmark(landmark)
	if text.is_empty():
		GameState.map_requested.emit(modes)
	else:
		DialogueRunner.start_text(text, [])
		DialogueRunner.finished.connect(_open_map, CONNECT_ONE_SHOT)


func _open_map(_id = "") -> void:
	if not Travel.active():  # a journey already knows where it is
		if route != "":
			var length := float(World.route(route).get("length_km", 0.0))
			World.context = {"route": route, "km": clampf(at, 0.0, 1.0) * length, "via_waymark": true}
		elif place != "":
			World.context = {"location": place, "via_waymark": true}
	GameState.map_requested.emit(modes)

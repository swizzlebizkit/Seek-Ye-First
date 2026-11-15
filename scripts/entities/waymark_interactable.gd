class_name WaymarkInteractable
extends Interactable
## A milestone, landing or camp fire where the long road can be taken. Examining it reads a few
## lines, then opens the strategic map for the routes of the listed modes that start here.

var text: Array = []
var modes: Array = ["land", "water"]
var landmark := ""


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
	GameState.map_requested.emit(modes)

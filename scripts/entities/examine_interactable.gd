class_name ExamineInteractable
extends Interactable
## Shows a few lines of text. `variants` lets the text change with game state; the first whose
## `when` passes wins. `once_flag` records that the player has seen it.

var variants: Array = []  # [{"when": {...}, "text": [...], "effects": [...]}]
var once_flag := ""


func _on_interact(_by: Node) -> void:
	for v in variants:
		if not v.has("when") or GameState.check(v["when"]):
			DialogueRunner.start_text(v["text"], v.get("effects", []))
			if once_flag != "":
				GameState.set_flag(once_flag)
			return

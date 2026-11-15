class_name LedgerInteractable
extends Interactable
## Training-yard board that reads out how each encounter has been resolved so far.


func _ready() -> void:
	super._ready()
	verb = "Read"


func _on_interact(_by: Node) -> void:
	var lines: Array = ["TRAINING YARD LEDGER. Every way an encounter can end is valid; none is required."]
	lines.append("\n".join(Combat.ledger_lines()))
	lines.append("Defeated: %d   Driven off: %d   Yielded: %d   Times overcome: %d" % [
		Combat.consequences.get("defeated", 0), Combat.consequences.get("routed", 0),
		Combat.consequences.get("yielded", 0), Combat.consequences.get("times_overcome", 0)])
	DialogueRunner.start_text(lines)

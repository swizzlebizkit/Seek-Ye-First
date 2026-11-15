extends Node
## KJV lookup. The canonical source for every quotation the game shows.

const DATA_PATH := "res://data/scripture/kjv.json"

var translation := "KJV"
var _books: Dictionary = {}


func _ready() -> void:
	var data = DataFiles.load_json(DATA_PATH)
	if data is Dictionary:
		translation = data.get("translation", "KJV")
		_books = data.get("books", {})


## "Matthew 3:13-17" -> {book, chapter, start, end}; empty if unparseable.
func parse_ref(ref: String) -> Dictionary:
	var sp := ref.rfind(" ")
	if sp < 0:
		return {}
	var cv := ref.substr(sp + 1).split(":")
	if cv.size() != 2:
		return {}
	var vs := cv[1].split("-")
	var v1 := int(vs[0])
	var v2 := int(vs[1]) if vs.size() > 1 else v1
	return {"book": ref.substr(0, sp), "chapter": int(cv[0]), "start": v1, "end": v2}


## Verses for a reference as [{n, text}]. Verses missing from the data file are skipped.
func get_verses(ref: String) -> Array:
	var out: Array = []
	var p := parse_ref(ref)
	if p.is_empty():
		return out
	var book: Dictionary = _books.get(p["book"], {})
	var chapter: Dictionary = book.get(str(p["chapter"]), {})
	for n in range(p["start"], p["end"] + 1):
		if chapter.has(str(n)):
			out.append({"n": n, "text": chapter[str(n)]})
	return out


func get_passage(ref: String) -> String:
	var parts: PackedStringArray = []
	for v in get_verses(ref):
		parts.append(v["text"])
	return " ".join(parts)


## True when every verse in the reference is present in the data file.
func is_complete(ref: String) -> bool:
	var p := parse_ref(ref)
	return not p.is_empty() and get_verses(ref).size() == p["end"] - p["start"] + 1

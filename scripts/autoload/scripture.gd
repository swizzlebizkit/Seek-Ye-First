extends Node
## KJV lookup. The canonical source for every quotation the game shows, and the data behind the player's
## Scripture reader. Reader state (bookmarks, last place read) lives here and nowhere in the protagonist's
## systems: the human player reading Acts says nothing about what the protagonist knows.

const DATA_PATH := "res://data/scripture/kjv.json"

## Canonical order of the 66 books (the data file's own order is checked against this in tests).
const BOOK_ORDER: Array = ["Genesis", "Exodus", "Leviticus", "Numbers", "Deuteronomy", "Joshua", "Judges", "Ruth",
	"1 Samuel", "2 Samuel", "1 Kings", "2 Kings", "1 Chronicles", "2 Chronicles", "Ezra", "Nehemiah", "Esther", "Job",
	"Psalms", "Proverbs", "Ecclesiastes", "Song of Solomon", "Isaiah", "Jeremiah", "Lamentations", "Ezekiel", "Daniel",
	"Hosea", "Joel", "Amos", "Obadiah", "Jonah", "Micah", "Nahum", "Habakkuk", "Zephaniah", "Haggai", "Zechariah",
	"Malachi", "Matthew", "Mark", "Luke", "John", "Acts", "Romans", "1 Corinthians", "2 Corinthians", "Galatians",
	"Ephesians", "Philippians", "Colossians", "1 Thessalonians", "2 Thessalonians", "1 Timothy", "2 Timothy", "Titus",
	"Philemon", "Hebrews", "James", "1 Peter", "2 Peter", "1 John", "2 John", "3 John", "Jude", "Revelation"]
const OLD_TESTAMENT_BOOKS := 39

var translation := "KJV"
var _books: Dictionary = {}
var _index: Array = []  # lazily built search index: [{book, chapter, verse, text, low}]

## The player's own reader state. Optional in saves (absent in older ones).
var _bookmarks: Array = []  # single-verse refs "Book c:v", in the order added
var _last_ref := ""


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


# -- Reader navigation -------------------------------------------------------------------------
func book_names() -> Array:
	return BOOK_ORDER.duplicate()


func has_book(book: String) -> bool:
	return _books.has(book)


func testament_of(book: String) -> String:
	var i := BOOK_ORDER.find(book)
	return "" if i < 0 else ("old" if i < OLD_TESTAMENT_BOOKS else "new")


func chapter_count(book: String) -> int:
	return _books.get(book, {}).size()


func verse_count(book: String, chapter: int) -> int:
	return _books.get(book, {}).get(str(chapter), {}).size()


## Whole chapter as [{n, text}] in verse order; empty if there is no such chapter.
func get_chapter(book: String, chapter: int) -> Array:
	var out: Array = []
	var ch: Dictionary = _books.get(book, {}).get(str(chapter), {})
	for n in range(1, ch.size() + 1):
		if ch.has(str(n)):
			out.append({"n": n, "text": ch[str(n)]})
	return out


func make_ref(book: String, chapter: int, verse: int) -> String:
	return "%s %d:%d" % [book, chapter, verse]


# -- Search ------------------------------------------------------------------------------------
func _build_index() -> void:
	if not _index.is_empty():
		return
	for book in BOOK_ORDER:
		for c in range(1, chapter_count(book) + 1):
			for v in get_chapter(book, c):
				_index.append({"book": book, "chapter": c, "verse": v["n"], "text": v["text"], "low": String(v["text"]).to_lower()})


## Case-insensitive full-text search: every word typed must appear in the verse. Results in canonical
## order as [{ref, book, chapter, verse, text}], at most `limit`. Blank queries find nothing.
func search(query: String, limit: int = 200) -> Array:
	var words: PackedStringArray = []
	for w in query.to_lower().split(" ", false):
		var t := w.strip_edges()
		if t != "":
			words.append(t)
	var out: Array = []
	if words.is_empty():
		return out
	_build_index()
	for rec in _index:
		var ok := true
		for w in words:
			if not String(rec["low"]).contains(w):
				ok = false
				break
		if ok:
			out.append({"ref": make_ref(rec["book"], rec["chapter"], rec["verse"]), "book": rec["book"],
					"chapter": rec["chapter"], "verse": rec["verse"], "text": rec["text"]})
			if out.size() >= limit:
				break
	return out


# -- Bookmarks and reader position -------------------------------------------------------------
func is_single_verse(ref: String) -> bool:
	var p := parse_ref(ref)
	return not p.is_empty() and p["start"] == p["end"] and is_complete(ref)


func bookmarks() -> Array:
	return _bookmarks.duplicate()


func is_bookmarked(ref: String) -> bool:
	return _bookmarks.has(ref)


func add_bookmark(ref: String) -> bool:
	if not is_single_verse(ref) or _bookmarks.has(ref):
		return false
	_bookmarks.append(ref)
	return true


func remove_bookmark(ref: String) -> bool:
	if not _bookmarks.has(ref):
		return false
	_bookmarks.erase(ref)
	return true


## Adds the bookmark if absent, removes it if present. Returns true when it ends up bookmarked.
func toggle_bookmark(ref: String) -> bool:
	if _bookmarks.has(ref):
		remove_bookmark(ref)
		return false
	return add_bookmark(ref)


func last_ref() -> String:
	return _last_ref


func set_last_ref(ref: String) -> void:
	if is_single_verse(ref):
		_last_ref = ref


## New game: the reader starts clean. Only new-game and load call this; the reader never does.
func reset() -> void:
	_bookmarks.clear()
	_last_ref = ""


func serialize() -> Dictionary:
	return {"bookmarks": _bookmarks.duplicate(), "last": _last_ref}


## Absent or malformed data gives defaults; bookmarks that no longer resolve are dropped.
func deserialize(d: Dictionary) -> void:
	reset()
	var saved = d.get("bookmarks", [])
	if saved is Array:
		for ref in saved:
			if ref is String:
				add_bookmark(ref)
	var last = d.get("last", "")
	if last is String:
		set_last_ref(last)

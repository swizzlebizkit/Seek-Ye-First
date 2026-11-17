extends RefCounted
## GC-B checks: the Scripture reader (66 books, search, bookmarks, links), its independence from the
## protagonist's knowledge, and the journal's append-only annotations and citation lint.

var t: Node
var _source: Dictionary = {}  # kjv.json parsed independently of the Scripture autoload


func run(runner: Node) -> void:
	t = runner
	_source = JSON.parse_string(FileAccess.get_file_as_string("res://data/scripture/kjv.json"))["books"]
	test_all_books_and_verses()
	test_search()
	test_bookmarks()
	test_links_resolve()
	test_journal_annotations()
	test_citation_lint()
	await test_reader_ui()
	await test_independence()


func _fresh() -> void:
	t._fresh()


func _key(code: int) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	return e


func _snapshot() -> String:
	# The wall clock and play timer tick while frames pass (awaits); that is time, not knowledge.
	var game := GameState.serialize()
	game["play_seconds"] = 0.0
	var world := WorldSim.serialize()
	world["minute"] = 0.0
	var snap := {
		"game": game, "journal": Journal.serialize(), "quests": Quests.serialize(),
		"knowledge": PlayerKnowledge.serialize(), "canon": CanonicalTimeline.serialize(), "world": world,
		"equipment": Equipment.serialize(), "combat": Combat.serialize(), "geo": World.serialize(), "travel": Travel.serialize(),
		"flags": GameState.flags.duplicate(true), "inventory": GameState.inventory.duplicate(true),
	}
	return JSON.stringify(snap, "", true)


# -- GC-B.1 books, chapters, verses --------------------------------------------------------------
func test_all_books_and_verses() -> void:
	var names: Array = Scripture.book_names()
	t.check(names.size() == 66, "the reader lists 66 books")
	t.check(_source.size() == 66 and names == _source.keys(), "the book order matches the KJV file exactly")
	var ot := 0
	var nt := 0
	var verses := 0
	var mismatches := 0
	var unreachable := 0
	for b in names:
		match Scripture.testament_of(b):
			"old": ot += 1
			"new": nt += 1
		var src_ch: Dictionary = _source[b]
		if Scripture.chapter_count(b) != src_ch.size():
			mismatches += 1
		for c in range(1, src_ch.size() + 1):
			if not src_ch.has(str(c)):
				unreachable += 1
				continue
			var sv: Dictionary = src_ch[str(c)]
			var chapter: Array = Scripture.get_chapter(b, c)
			if chapter.size() != sv.size() or Scripture.verse_count(b, c) != sv.size():
				mismatches += 1
			for n in range(1, sv.size() + 1):
				verses += 1
				var ref := Scripture.make_ref(b, c, n)
				if not sv.has(str(n)):
					unreachable += 1
				elif Scripture.get_passage(ref) != sv[str(n)] or chapter[n - 1]["text"] != sv[str(n)] or chapter[n - 1]["n"] != n:
					mismatches += 1
	t.check(ot == 39 and nt == 27, "39 Old Testament and 27 New Testament books")
	t.check(unreachable == 0, "every chapter and verse is numbered contiguously and reachable")
	t.check(mismatches == 0, "every verse the reader serves equals the source text (%d verses)" % verses)
	t.check(verses == 31102, "the full KJV verse count is present")
	t.check(Scripture.testament_of("Acts") == "new" and Scripture.testament_of("Malachi") == "old" and Scripture.testament_of("Nope") == "", "testament lookup")
	t.check(Scripture.get_chapter("Genesis", 999).is_empty() and Scripture.get_chapter("Nope", 1).is_empty(), "missing chapters give nothing")


# -- GC-B.2 search -------------------------------------------------------------------------------
func test_search() -> void:
	var r: Array = Scripture.search("seek ye first the kingdom of God")
	t.check(not r.is_empty() and r[0]["ref"] == "Matthew 6:33", "search finds Matthew 6:33")
	t.check(Scripture.search("JESUS WEPT").any(func(x): return x["ref"] == "John 11:35"), "search ignores case and finds John 11:35")
	t.check(Scripture.search("In the beginning God created")[0]["ref"] == "Genesis 1:1", "Genesis 1:1 comes first, in canonical order")
	t.check(Scripture.search("beginning created heaven")[0]["ref"] == "Genesis 1:1", "every word must appear, in any order")
	t.check(Scripture.search("").is_empty() and Scripture.search("   ").is_empty(), "empty and blank queries find nothing")
	t.check(Scripture.search("zzqxv nothing here").is_empty(), "a no-match query finds nothing")
	t.check(Scripture.search("the", 5).size() == 5, "the result limit is honoured")
	var all_hit := true
	for x in Scripture.search("love", 50):
		all_hit = all_hit and Scripture.get_passage(x["ref"]) == x["text"] and String(x["text"]).to_lower().contains("love")
	t.check(all_hit, "every result is the real verse text and contains the word")


# -- GC-B.2 bookmarks ----------------------------------------------------------------------------
func test_bookmarks() -> void:
	_fresh()
	t.check(Scripture.bookmarks().is_empty(), "a new game has no bookmarks")
	t.check(Scripture.add_bookmark("John 3:16") and Scripture.is_bookmarked("John 3:16"), "a bookmark adds")
	t.check(not Scripture.add_bookmark("John 3:16"), "no duplicates")
	t.check(not Scripture.add_bookmark("John 3:16-17") and not Scripture.add_bookmark("Nope 1:1") and not Scripture.add_bookmark("John 99:1"), "ranges and unknown verses are refused")
	Scripture.add_bookmark("Acts 2:1")
	Scripture.set_last_ref("Acts 2:1")
	t.check(Scripture.bookmarks() == ["John 3:16", "Acts 2:1"], "bookmarks keep the order added")
	t.check(SaveManager.save_slot(2), "saves with bookmarks")
	var raw := SaveManager.read_slot(2)
	t.check(raw["version"] == SaveManager.VERSION and raw.has("scripture"), "bookmarks ride in an optional save block")
	t.check(Scripture.remove_bookmark("John 3:16") and not Scripture.is_bookmarked("John 3:16") and not Scripture.remove_bookmark("John 3:16"), "a bookmark removes")
	t.check(SaveManager.save_slot(3), "saves again after removal")
	GameState.new_game()
	t.check(Scripture.bookmarks().is_empty() and Scripture.last_ref() == "", "new game clears the reader")
	t.check(SaveManager.load_slot(2), "loads the first save")
	t.check(Scripture.bookmarks() == ["John 3:16", "Acts 2:1"] and Scripture.last_ref() == "Acts 2:1", "bookmarks and place persist through save and load")
	t.check(SaveManager.load_slot(3) and Scripture.bookmarks() == ["Acts 2:1"], "a removal persists too")
	# an old save has no block at all: defaults apply and everything else is untouched
	raw = SaveManager.read_slot(3)
	raw.erase("scripture")
	var f := FileAccess.open(SaveManager.slot_path(3), FileAccess.WRITE)
	f.store_string(JSON.stringify(raw))
	f.close()
	Scripture.add_bookmark("Mark 1:1")
	t.check(SaveManager.load_slot(3) and Scripture.bookmarks().is_empty() and Scripture.last_ref() == "", "a save with no scripture block loads with defaults")
	Scripture.deserialize({"bookmarks": ["Nope 9:9", 5, "Luke 1:1-3", "Luke 1:3"], "last": 7})
	t.check(Scripture.bookmarks() == ["Luke 1:3"] and Scripture.last_ref() == "", "malformed or unresolvable saved data is dropped")
	SaveManager.delete_slot(2)
	SaveManager.delete_slot(3)
	Scripture.reset()


# -- GC-B.3 links resolve ------------------------------------------------------------------------
func test_links_resolve() -> void:
	_fresh()
	var refs: Array = ScriptureLinks.all_data_refs()
	t.check(refs.size() > 30, "cross-references and journal links are present (%d refs)" % refs.size())
	var bad: Array = []
	for r in refs:
		if not Scripture.is_complete(r) or Scripture.get_passage(r) == "":
			bad.append(r)
	t.check(bad.is_empty(), "every cross-reference and link resolves to complete KJV text %s" % str(bad))
	var groups: Dictionary = ScriptureLinks.groups()
	var small: Array = []
	for g in groups:
		if groups[g]["refs"].size() < 2:
			small.append(g)
	t.check(groups.size() >= 10 and small.is_empty(), "each cross-reference group relates at least two passages")
	t.check(ScriptureLinks.overlaps("Matthew 3:13-17", "Matthew 3:16") and not ScriptureLinks.overlaps("Matthew 3:13-17", "Matthew 4:1") and not ScriptureLinks.overlaps("Mark 3:16", "Matthew 3:16"), "passage overlap")
	var rel: Array = ScriptureLinks.related("Matthew 3:16")
	t.check(rel.any(func(g): return g["id"] == "baptism_of_jesus" and g["others"].has("John 1:32-34")), "the baptism relates to the other gospel accounts")
	t.check(ScriptureLinks.related("Genesis 50:26").is_empty(), "an unrelated verse has no cross-references")
	# journal links only show what the protagonist has already written or found
	t.check(ScriptureLinks.journal_for("Matthew 3:2").is_empty(), "nothing is linked before the protagonist has the entries")
	Journal.discover("testimony_ezra")
	t.check(ScriptureLinks.journal_for("Isaiah 40:3").size() == 1 and ScriptureLinks.journal_for("Isaiah 40:3")[0]["kind"] == "entry", "a written entry links to its passage")
	t.check(ScriptureLinks.journal_for("Matthew 3:3").is_empty(), "an undiscovered connection (and its New Testament side) stays hidden")
	var before := _snapshot()
	Journal.discover_link("isaiah_40_3", "Ezra")
	t.check(ScriptureLinks.journal_for("Matthew 3:3").size() == 1, "once found, the connection shows from the New Testament side")
	t.check(ScriptureLinks.refs_for_entry("testimony_ezra") == ["Isaiah 40:3", "Matthew 3:3"], "an entry leads to its passages and found comparisons")
	t.check(before != _snapshot(), "(sanity) discovering a link is a state change the reader never does)")


# -- GC-B.5 journal annotations ------------------------------------------------------------------
func test_journal_annotations() -> void:
	_fresh()
	Journal.discover("rumor_yosef")
	var orig := Journal.get_entry("rumor_yosef").duplicate(true)
	t.check(Journal.annotate("rumor_yosef", "Ezra read me Isaiah, and I wonder.", ["Isaiah 40:3"], "Ezra", "a1"), "later understanding appends a note")
	t.check(Journal.annotate("rumor_yosef", "Hannah described the same man.", [], "Hannah", "a2"), "a second note appends")
	var rec := Journal.get_entry("rumor_yosef")
	t.check(rec["text"] == orig["text"] and rec["title"] == orig["title"] and rec["source"] == orig["source"] and rec["refs"] == orig["refs"] and int(rec["day"]) == int(orig["day"]), "annotating leaves the original entry unchanged")
	t.check(rec["notes"].size() == 2 and rec["notes"][0]["id"] == "a1" and rec["notes"][1]["id"] == "a2", "notes append in order")
	t.check(rec["notes"][0].has("day") and int(rec["notes"][0]["day"]) == Calendar.current_day(), "each note is dated")
	t.check(not Journal.annotate("rumor_yosef", "   ", [], "", "blank") and Journal.get_entry("rumor_yosef")["notes"].size() == 2, "a blank note is refused")
	Journal.set_status("rumor_yosef", "corroborated")
	t.check(not Journal.discover("rumor_yosef") and Journal.get_entry("rumor_yosef")["text"] == orig["text"], "discovering again never rewrites an entry")
	# round trip through a save, and a very old record with no notes list at all
	t.check(SaveManager.save_slot(1), "saves")
	GameState.new_game()
	t.check(SaveManager.load_slot(1), "loads")
	rec = Journal.get_entry("rumor_yosef")
	t.check(rec["text"] == orig["text"] and rec["notes"].size() == 2 and rec["notes"][1]["text"] == "Hannah described the same man.", "original and notes survive save and load")
	var old := Journal.serialize()
	old["entries"]["rumor_yosef"].erase("notes")
	Journal.deserialize(old)
	t.check(Journal.get_entry("rumor_yosef")["notes"] == [] and Journal.get_entry("rumor_yosef")["text"] == orig["text"], "an old record without notes loads with an empty list")
	t.check(Journal.annotate("rumor_yosef", "Now I can add one.", [], "", "late"), "and can still be annotated")
	SaveManager.delete_slot(1)


# -- GC-B.5 lint: no modern chapter-and-verse citations in protagonist text ---------------------
const CITATION_PATTERN := "\\b\\d{1,3}\\s*:\\s*\\d{1,3}\\b|(?i)\\bchapters?\\s+\\d+|(?i)\\bverses?\\s+\\d+"
const STRUCTURED_KEYS := ["refs", "reference", "nt_ref", "id", "entry"]  # structured data for the reader, not prose


func _lint(node, path: String, rx: RegEx, offenders: Array) -> void:
	if node is Dictionary:
		for k in node:
			if not STRUCTURED_KEYS.has(k):
				_lint(node[k], path + "/" + str(k), rx, offenders)
	elif node is Array:
		for i in range(node.size()):
			_lint(node[i], path + "/" + str(i), rx, offenders)
	elif node is String and rx.search(node) != null:
		offenders.append("%s: %s" % [path, node.substr(0, 60)])


func _annotation_texts(node, out: Array) -> void:
	if node is Dictionary:
		if node.has("annotate") and node["annotate"] is Dictionary:
			out.append(node["annotate"].get("text", ""))
		for k in node:
			_annotation_texts(node[k], out)
	elif node is Array:
		for x in node:
			_annotation_texts(x, out)


func test_citation_lint() -> void:
	var rx := RegEx.create_from_string(CITATION_PATTERN)
	t.check(rx.search("see John 3:16") != null and rx.search("in chapter 3") != null and rx.search("verse 12") != null, "the lint catches chapter:verse and chapter/verse wording")
	t.check(rx.search("Isaiah wrote of a voice in the wilderness, at the ninth hour") == null and rx.search("the 14th of Iyar") == null, "the lint passes named writings and ordinary prose")
	var offenders: Array = []
	for path in ["res://data/journal/entries.json", "res://data/journal/links.json"]:
		_lint(JSON.parse_string(FileAccess.get_file_as_string(path)), path.get_file(), rx, offenders)
	t.check(offenders.is_empty(), "journal data prose has no chapter:verse citations %s" % str(offenders))
	var dir := DirAccess.open("res://data/dialogue")
	var texts: Array = []
	for f in dir.get_files():
		if f.ends_with(".json"):
			_annotation_texts(JSON.parse_string(FileAccess.get_file_as_string("res://data/dialogue/" + f)), texts)
	var bad: Array = []
	for s in texts:
		if rx.search(String(s)) != null:
			bad.append(String(s).substr(0, 60))
	t.check(texts.size() > 0 and bad.is_empty(), "dialogue-written journal notes (%d) have no citations %s" % [texts.size(), str(bad)])


# -- GC-B.1 / B.2 / B.3 the reader screen, driven through the journal shell ---------------------
func test_reader_ui() -> void:
	_fresh()
	Journal.discover("testimony_ezra")
	var view := JournalView.new()
	t.add_child(view)
	await t.get_tree().process_frame
	view.open()
	var tab_names: Array = JournalView.TAB_NAMES
	t.check(tab_names.has("Scripture") and JournalView.Tab.SCRIPTURE == tab_names.find("Scripture"), "the journal shell has a Scripture tab")
	view._set_tab(JournalView.Tab.SCRIPTURE)
	var sv: ScriptureView = view._scripture
	t.check(sv.visible and sv.mode == ScriptureView.Mode.BOOKS, "the Scripture tab opens on the list of books")
	var books := sv.rows.filter(func(r): return r["kind"] == "book")
	t.check(books.size() == 66 and sv.rows.size() == 68, "the list holds 66 books under two testament headings")
	t.check(not view._list.visible and not view._map.visible, "the journal list and map are hidden behind it")
	view._input(_key(KEY_ENTER))
	t.check(sv.mode == ScriptureView.Mode.CHAPTERS and sv.book == "Genesis", "Enter opens the selected book")
	view._input(_key(KEY_ENTER))
	t.check(sv.mode == ScriptureView.Mode.READING and sv.current_ref() == "Genesis 1:1", "Enter opens the chapter at verse 1")
	t.check(sv.details_text().contains("In the beginning God created the heaven and the earth."), "the chapter text is shown")
	view._input(_key(KEY_BRACKETRIGHT))
	t.check(sv.chapter == 2 and sv.rows.size() == Scripture.verse_count("Genesis", 2), "] steps to the next chapter")
	view._input(_key(KEY_B))
	t.check(Scripture.is_bookmarked("Genesis 2:1"), "B bookmarks the selected verse")
	view._input(_key(KEY_BACKSPACE))
	view._input(_key(KEY_BACKSPACE))
	t.check(sv.mode == ScriptureView.Mode.BOOKS, "Backspace climbs back to the books")
	sv.goto("Revelation 22:21")
	t.check(sv.mode == ScriptureView.Mode.READING and sv.rows.size() == 21 and sv.current_ref() == "Revelation 22:21", "the last verse of the last book is reachable")
	view._input(_key(KEY_SLASH))
	t.check(sv.typing(), "/ starts typing a search")
	view._input(_key(KEY_ESCAPE))
	t.check(not sv.typing() and view.visible, "Esc leaves the search box without closing the journal")
	sv.run_search("seek ye first")
	t.check(sv.mode == ScriptureView.Mode.SEARCH and sv.rows.any(func(r): return r["ref"] == "Matthew 6:33"), "searching lists the matching verses")
	sv.run_search("qqzzxx")
	t.check(sv.rows.is_empty() and sv.details_text().contains("No verse contains"), "a no-match search says so")
	sv.run_search("")
	t.check(sv.rows.is_empty() and sv.details_text().contains("Type a word"), "an empty search prompts instead of listing everything")
	sv.run_search("seek ye first")
	view._input(_key(KEY_ENTER))
	t.check(sv.mode == ScriptureView.Mode.READING and sv.current_ref() == "Matthew 6:33", "Enter on a result reads it in context")
	view._input(_key(KEY_M))
	t.check(sv.mode == ScriptureView.Mode.MARKS and sv.rows.size() == 1 and sv.rows[0]["ref"] == "Genesis 2:1", "M lists bookmarks")
	view._input(_key(KEY_B))
	t.check(Scripture.bookmarks().is_empty() and sv.rows.is_empty(), "B in the bookmark list removes it")
	view._input(_key(KEY_BACKSPACE))
	# journal <-> scripture navigation
	view._set_tab(JournalView.Tab.JOURNAL)
	view._input(_key(KEY_S))
	t.check(view._tab == JournalView.Tab.SCRIPTURE and sv.book == "Isaiah" and sv.chapter == 40 and sv.verse == 3, "S on a journal entry opens its passage in Scripture")
	view._input(_key(KEY_X))
	t.check(sv.mode == ScriptureView.Mode.RELATED and sv.rows.any(func(r): return r["kind"] == "entry" and r["entry"] == "testimony_ezra"), "X lists related passages and the journal entry")
	var idx := sv.rows.find_custom(func(r): return r["kind"] == "entry")
	sv._list.select(idx)
	view._input(_key(KEY_ENTER))
	t.check(view._tab == JournalView.Tab.JOURNAL and view._row_ids[view._list.get_selected_items()[0]] == "testimony_ezra", "Enter on a journal row goes back to that entry")
	view._input(_key(KEY_ESCAPE))
	t.check(not view.visible, "Esc still closes the journal")
	view.queue_free()
	GameState.mode = GameState.Mode.EXPLORE
	_fresh()


# -- GC-B.4 independence -------------------------------------------------------------------------
func test_independence() -> void:
	_fresh()
	# a protagonist who knows a little: one entry, one found link, one fact, a flag, a quest
	Journal.discover("testimony_ezra")
	Journal.discover_link("isaiah_40_3", "Ezra")
	PlayerKnowledge.learn("john_preaching", "rumor", "Yosef")
	GameState.set_flag("yosef_rumor_told")
	Quests.start("word_jordan")
	var before := _snapshot()
	var knowledge_before := JSON.stringify(PlayerKnowledge.serialize(), "", true)

	# the human player reads far ahead of the protagonist: the Gospels, Acts, Revelation
	for ref in ["Matthew 28:1-10", "John 20:1-10", "Acts 2:1-4", "Revelation 22:21", "Isaiah 40:3", "Matthew 3:3"]:
		Scripture.get_verses(ref)
		Scripture.get_passage(ref)
		Scripture.add_bookmark(ref) if Scripture.is_single_verse(ref) else null
	Scripture.search("resurrection")
	Scripture.search("risen")
	Scripture.get_chapter("Acts", 2)
	Scripture.set_last_ref("Acts 2:1")
	for ref in ["Matthew 3:16", "Isaiah 40:3", "Matthew 28:6"]:
		ScriptureLinks.related(ref)
		ScriptureLinks.journal_for(ref)
	ScriptureLinks.refs_for_entry("testimony_ezra")
	t.check(_snapshot() == before, "the Scripture API (read, search, bookmark, cross-reference) changes no protagonist state")

	# the screen itself, standalone and inside the journal shell
	var sv := ScriptureView.new()
	t.add_child(sv)
	await t.get_tree().process_frame
	sv.open()
	sv.goto("Acts 1:1")
	sv.step_chapter(1)
	sv.toggle_bookmark()
	sv.show_related()
	sv.back()
	sv.run_search("risen")
	sv.show_marks()
	sv.goto("Isaiah 40:3")
	sv.show_related()
	sv.activate()  # follow whatever the first related row is, a passage or a journal request
	sv.free()
	t.check(_snapshot() == before, "the Scripture screen changes no protagonist state")

	var view := JournalView.new()
	t.add_child(view)
	await t.get_tree().process_frame
	view.open()
	view._set_tab(JournalView.Tab.SCRIPTURE)
	view._scripture.goto("John 1:1")
	view._input(_key(KEY_X))
	view._input(_key(KEY_B))
	view._set_tab(JournalView.Tab.JOURNAL)
	view._input(_key(KEY_S))
	view._scripture.run_search("Jesus")
	view._input(_key(KEY_ENTER))
	view._input(_key(KEY_ESCAPE))
	view.queue_free()
	GameState.mode = GameState.Mode.EXPLORE
	t.check(_snapshot() == before, "opening, searching, bookmarking and following links through the journal shell changes no protagonist state")
	t.check(JSON.stringify(PlayerKnowledge.serialize(), "", true) == knowledge_before and PlayerKnowledge.level_of("resurrection") == "unknown", "PlayerKnowledge is byte-identical after reading ahead")
	t.check(not Journal.has_entry("q_who_is_john") and Journal.count() == 1 and Journal.links_for("testimony_ezra").size() == 1, "no journal entry or link was discovered by reading")
	t.check(not Scripture.bookmarks().is_empty(), "(sanity) the reader's own state did change, so the test exercised it")
	# and the reader's state does not leak into what the protagonist's saves hold
	SaveManager.save_slot(1)
	var raw := SaveManager.read_slot(1)
	var json_protagonist := JSON.stringify([raw["journal"], raw["knowledge"], raw["quests"], raw["canon"]], "", true)
	t.check(not json_protagonist.contains("Acts 2:1") and not json_protagonist.contains("Revelation 22:21"), "bookmarks are not stored in protagonist save data")
	SaveManager.delete_slot(1)
	Scripture.reset()

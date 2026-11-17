class_name ScriptureView
extends HBoxContainer
## The player's Scripture reader: the full KJV, all 66 books. This is the HUMAN PLAYER's reader, not the
## protagonist's journal. It owns its own state, only reads KJV text and game data, and never writes to
## PlayerKnowledge, Journal, Quests, flags or discovery state. (Bookmarks and the last place read are the
## reader's own, kept in the Scripture autoload.) Hosted as a tab of the journal screen.

signal journal_requested(entry_id: String)

enum Mode { BOOKS, CHAPTERS, READING, SEARCH, MARKS, RELATED }

const GOLD := "#e8d29a"
const MUTED := "#b3a27c"
const DIM := "#7d705a"
const HINTS := {
	Mode.BOOKS: "Up/Down: book    Enter: open    /: search    M: bookmarks",
	Mode.CHAPTERS: "Up/Down: chapter    Enter: read    Backspace: books    /: search    M: bookmarks",
	Mode.READING: "Up/Down: verse    [ ]: chapter    B: bookmark    X: related    Backspace: chapters    /: search",
	Mode.SEARCH: "Up/Down: result    Enter: read it    /: new search    Backspace: back",
	Mode.MARKS: "Up/Down: bookmark    Enter: read    B: remove    Backspace: back",
	Mode.RELATED: "Up/Down: choose    Enter: go there    Backspace: back to reading",
}

var mode: int = Mode.BOOKS
var book := ""
var chapter := 0
var verse := 0
var query := ""
var results: Array = []
var rows: Array = []  # what the list currently shows: [{kind, ...}]

var _list: ItemList
var _details: RichTextLabel
var _edit: LineEdit
var _crumb: Label
var _hint: Label
var _return_mode: int = Mode.BOOKS


func _ready() -> void:
	add_theme_constant_override("separation", 16)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(400, 0)
	left.add_theme_constant_override("separation", 6)
	add_child(left)
	_crumb = UiTheme.label("", 18, UiTheme.GOLD)
	left.add_child(_crumb)
	_edit = LineEdit.new()
	_edit.placeholder_text = "Search the Scriptures"
	_edit.visible = false
	_edit.add_theme_font_size_override("font_size", 18)
	_edit.text_submitted.connect(_on_search_submitted)
	left.add_child(_edit)
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.select_mode = ItemList.SELECT_SINGLE
	_list.auto_height = false
	_list.add_theme_font_size_override("font_size", 18)
	_list.add_theme_color_override("font_color", UiTheme.TEXT)
	_list.add_theme_color_override("font_selected_color", UiTheme.GOLD)
	_list.add_theme_color_override("font_hovered_color", UiTheme.GOLD)
	_list.add_theme_stylebox_override("panel", UiTheme._button_box(Color("1f1812"), 1))
	_list.add_theme_stylebox_override("selected", UiTheme._button_box(UiTheme.PARCHMENT_LIGHT, 2))
	_list.add_theme_stylebox_override("selected_focus", UiTheme._button_box(UiTheme.PARCHMENT_LIGHT, 2))
	_list.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_list.item_selected.connect(_on_row_selected)
	_list.item_activated.connect(func(_i): activate())
	left.add_child(_list)
	_hint = UiTheme.label("", 14, UiTheme.MUTED)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(_hint)
	_details = RichTextLabel.new()
	_details.bbcode_enabled = true
	_details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_details.focus_mode = Control.FOCUS_NONE
	_details.add_theme_font_size_override("normal_font_size", 20)
	_details.add_theme_font_size_override("bold_font_size", 20)
	_details.add_theme_font_size_override("italics_font_size", 20)
	_details.add_theme_color_override("default_color", UiTheme.TEXT)
	add_child(_details)


# -- Public interface (also what the tests drive) ----------------------------------------------
func hint() -> String:
	return HINTS[mode]


func typing() -> bool:
	return _edit != null and _edit.visible and _edit.has_focus()


func focus_list() -> void:
	_list.grab_focus()


func details_text() -> String:
	return _details.text


func current_ref() -> String:
	return Scripture.make_ref(book, chapter, verse) if book != "" and chapter > 0 and verse > 0 else ""


## Opens where the player left off, or at the list of books the first time.
func open() -> void:
	var last := Scripture.last_ref()
	if last != "":
		goto(last)
	elif mode == Mode.BOOKS or book == "":
		show_books()
	else:
		_refresh()


func show_books() -> void:
	mode = Mode.BOOKS
	_refresh()


func open_book(name: String) -> void:
	if not Scripture.has_book(name):
		return
	book = name
	mode = Mode.CHAPTERS
	_refresh()


func open_chapter(name: String, c: int, v: int = 1) -> void:
	if not Scripture.has_book(name) or c < 1 or c > Scripture.chapter_count(name):
		return
	book = name
	chapter = c
	verse = clampi(v, 1, maxi(1, Scripture.verse_count(name, c)))
	mode = Mode.READING
	Scripture.set_last_ref(current_ref())
	_refresh()


## Jumps to any reference ("John 3:16" or a range); a range lands on its first verse.
func goto(ref: String) -> bool:
	var p: Dictionary = Scripture.parse_ref(ref)
	if p.is_empty() or not Scripture.is_complete(ref):
		return false
	open_chapter(p["book"], p["chapter"], p["start"])
	return true


func run_search(q: String) -> void:
	query = q
	results = Scripture.search(q)
	if mode != Mode.SEARCH:
		_return_mode = mode
	mode = Mode.SEARCH
	_refresh()


func show_marks() -> void:
	if mode != Mode.MARKS:
		_return_mode = mode
	mode = Mode.MARKS
	_refresh()


func show_related() -> void:
	if mode != Mode.READING:
		return
	_return_mode = Mode.READING
	mode = Mode.RELATED
	_refresh()


func toggle_bookmark() -> void:
	var ref := ""
	match mode:
		Mode.READING:
			ref = current_ref()
		Mode.MARKS:
			ref = _selected_ref()
		Mode.SEARCH:
			ref = _selected_ref()
	if ref == "":
		return
	var keep := _selected_index()
	Scripture.toggle_bookmark(ref)
	_refresh()
	if mode == Mode.MARKS:
		keep = mini(keep, rows.size() - 1)
	if keep >= 0 and keep < rows.size():
		_list.select(keep)
		_on_row_selected(keep)


func activate() -> void:
	var i := _selected_index()
	if i < 0:
		return
	var r: Dictionary = rows[i]
	match r["kind"]:
		"book":
			open_book(r["book"])
		"chapter":
			open_chapter(book, r["chapter"])
		"verse", "ref":
			goto(r["ref"] if r["kind"] == "ref" else current_ref())
		"entry":
			journal_requested.emit(r["entry"])


func back() -> void:
	match mode:
		Mode.READING:
			mode = Mode.CHAPTERS
		Mode.CHAPTERS:
			mode = Mode.BOOKS
		Mode.SEARCH, Mode.MARKS, Mode.RELATED:
			mode = _return_mode if _return_mode != mode else Mode.BOOKS
			if mode == Mode.READING and book == "":
				mode = Mode.BOOKS
		_:
			return
	_refresh()


func step_chapter(delta: int) -> void:
	if mode != Mode.READING:
		return
	var c := chapter + delta
	if c >= 1 and c <= Scripture.chapter_count(book):
		open_chapter(book, c)


func begin_typing() -> void:
	_edit.visible = true
	_edit.text = query
	_edit.grab_focus()
	_edit.select_all()


func end_typing() -> void:
	_edit.release_focus()
	_edit.visible = mode == Mode.SEARCH
	_list.grab_focus()


## Keys the journal shell hands us first. Returns true when consumed. Left/Right, Up/Down, PgUp/PgDn and
## Esc keep their journal meanings; the rest are reader keys.
func handle_key(event: InputEvent) -> bool:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return false
	match event.keycode:
		KEY_ENTER, KEY_KP_ENTER:
			activate()
		KEY_BACKSPACE:
			back()
		KEY_SLASH, KEY_F:
			begin_typing()
		KEY_B:
			toggle_bookmark()
		KEY_M:
			show_marks()
		KEY_X:
			show_related()
		KEY_BRACKETLEFT:
			step_chapter(-1)
		KEY_BRACKETRIGHT:
			step_chapter(1)
		_:
			return false
	return true


# -- Rendering ---------------------------------------------------------------------------------
func _selected_index() -> int:
	var sel := _list.get_selected_items()
	return sel[0] if not sel.is_empty() and sel[0] < rows.size() else -1


func _selected_ref() -> String:
	var i := _selected_index()
	return rows[i].get("ref", "") if i >= 0 else ""


func _refresh() -> void:
	if _list == null:
		return
	_list.clear()
	rows.clear()
	_hint.text = hint()
	_edit.visible = mode == Mode.SEARCH
	var select := 0
	match mode:
		Mode.BOOKS:
			_crumb.text = "Scripture (KJV)"
			for name in Scripture.book_names():
				if name == Scripture.BOOK_ORDER[0]:
					_add_header("Old Testament")
				elif name == Scripture.BOOK_ORDER[Scripture.OLD_TESTAMENT_BOOKS]:
					_add_header("New Testament")
				_add_row("%s  (%d)" % [name, Scripture.chapter_count(name)], {"kind": "book", "book": name})
				if name == book:
					select = rows.size() - 1
		Mode.CHAPTERS:
			_crumb.text = book
			for c in range(1, Scripture.chapter_count(book) + 1):
				_add_row("Chapter %d" % c, {"kind": "chapter", "chapter": c})
			select = maxi(0, chapter - 1) if chapter > 0 else 0
		Mode.READING:
			_crumb.text = "%s %d" % [book, chapter]
			for v in Scripture.get_chapter(book, chapter):
				var mark := "* " if Scripture.is_bookmarked(Scripture.make_ref(book, chapter, v["n"])) else ""
				_add_row("%s%d  %s" % [mark, v["n"], _snippet(v["text"])], {"kind": "verse", "verse": v["n"]})
			select = verse - 1
		Mode.SEARCH:
			_crumb.text = "Search: %s" % query
			for r in results:
				_add_row("%s  %s" % [r["ref"], _snippet(r["text"], 24)], {"kind": "ref", "ref": r["ref"]})
		Mode.MARKS:
			_crumb.text = "Bookmarks"
			for ref in Scripture.bookmarks():
				_add_row(ref, {"kind": "ref", "ref": ref})
		Mode.RELATED:
			_crumb.text = "Related: %s" % current_ref()
			for e in _related_rows(current_ref()):
				_add_row(e["text"], e["row"])
	if rows.is_empty():
		_details.text = _empty_text()
		return
	select = clampi(select, 0, rows.size() - 1)
	while rows[select].get("kind", "") == "header" and select < rows.size() - 1:
		select += 1
	_list.select(select)
	_list.ensure_current_is_visible()
	_on_row_selected(select)


func _add_header(text: String) -> void:
	var idx := _list.add_item("-- %s --" % text, null, false)
	_list.set_item_custom_fg_color(idx, UiTheme.MUTED)
	rows.append({"kind": "header"})


func _add_row(text: String, row: Dictionary) -> void:
	_list.add_item(text)
	rows.append(row)


func _snippet(text: String, n: int = 30) -> String:
	return text if text.length() <= n else text.substr(0, n).strip_edges() + "..."


func _related_rows(ref: String) -> Array:
	var out: Array = []
	for g in ScriptureLinks.related(ref):
		for r in g["others"]:
			out.append({"text": "%s: %s" % [r, g["title"]], "row": {"kind": "ref", "ref": r}})
	for j in ScriptureLinks.journal_for(ref):
		out.append({"text": j["label"], "row": {"kind": "entry", "entry": j["entry"]}})
	return out


func _on_row_selected(index: int) -> void:
	if index < 0 or index >= rows.size():
		return
	var r: Dictionary = rows[index]
	match mode:
		Mode.BOOKS:
			if r["kind"] == "book":
				var b: String = r["book"]
				_details.text = "[b][color=%s]%s[/color][/b]\n[color=%s]%s Testament, %d chapters[/color]\n\n[i][color=%s]Enter to read. The whole King James Version is here for you to read freely; reading it does not change what the journal records.[/color][/i]" % [GOLD, b, MUTED, "Old" if Scripture.testament_of(b) == "old" else "New", Scripture.chapter_count(b), DIM]
		Mode.CHAPTERS:
			chapter = r["chapter"]
			_details.text = _chapter_bbcode(book, chapter, -1, 6)
		Mode.READING:
			verse = r["verse"]
			Scripture.set_last_ref(current_ref())
			_details.text = _reading_bbcode()
			_scroll_to_verse.call_deferred(verse)
		Mode.SEARCH, Mode.MARKS:
			_details.text = _ref_bbcode(r["ref"])
		Mode.RELATED:
			_details.text = _ref_bbcode(r["ref"]) if r["kind"] == "ref" else _entry_bbcode(r["entry"])


func _scroll_to_verse(n: int) -> void:
	if not is_inside_tree():
		return
	await get_tree().process_frame  # the new text must be laid out before offsets mean anything
	if mode == Mode.READING and n == verse and is_inside_tree():
		_details.get_v_scroll_bar().value = maxf(0.0, _details.get_paragraph_offset(n) - 40.0)


func _empty_text() -> String:
	match mode:
		Mode.SEARCH:
			if query.strip_edges() == "":
				return "[i][color=%s]Type a word or phrase and press Enter. Every word you type must appear in the verse.[/color][/i]" % MUTED
			return "[i][color=%s]No verse contains \"%s\".[/color][/i]" % [MUTED, _esc(query)]
		Mode.MARKS:
			return "[i][color=%s]No bookmarks yet. Press B while reading to keep your place in a verse.[/color][/i]" % MUTED
		Mode.RELATED:
			return "[i][color=%s]Nothing related is recorded for this verse.[/color][/i]" % MUTED
	return ""


## A chapter with up to `limit` verses (all when -1); `mark` highlights a verse number.
func _chapter_bbcode(b: String, c: int, mark: int, limit: int = -1) -> String:
	var s := "[b][color=%s]%s %d[/color][/b]\n" % [GOLD, b, c]
	var shown := 0
	for v in Scripture.get_chapter(b, c):
		if limit >= 0 and shown >= limit:
			s += "[color=%s]...[/color]" % DIM
			break
		shown += 1
		var star := " [color=%s]*[/color]" % GOLD if Scripture.is_bookmarked(Scripture.make_ref(b, c, v["n"])) else ""
		if v["n"] == mark:
			s += "[color=%s]%d[/color] [b][color=%s]%s[/color][/b]%s\n" % [GOLD, v["n"], GOLD, _esc(v["text"]), star]
		else:
			s += "[color=%s]%d[/color] %s%s\n" % [MUTED, v["n"], _esc(v["text"]), star]
	return s.strip_edges(false, true)


func _reading_bbcode() -> String:
	var s := _chapter_bbcode(book, chapter, verse)
	var ref := current_ref()
	var rel := _related_rows(ref)
	if not rel.is_empty():
		s += "\n\n[color=%s]%d related passage%s or journal link%s for %s. Press X.[/color]" % [DIM, rel.size(), "" if rel.size() == 1 else "s", "" if rel.size() == 1 else "s", ref]
	return s


func _ref_bbcode(ref: String) -> String:
	var s := "[b][color=%s]%s[/color][/b]%s\n" % [GOLD, ref, "  [color=%s](bookmarked)[/color]" % MUTED if Scripture.is_bookmarked(ref) else ""]
	for v in Scripture.get_verses(ref):
		s += "[color=%s]%d[/color] %s\n" % [MUTED, v["n"], _esc(v["text"])]
	return s.strip_edges(false, true)


func _entry_bbcode(entry_id: String) -> String:
	var rec: Dictionary = Journal.get_entry(entry_id)
	return "[b][color=%s]Journal: %s[/color][/b]\n[color=%s]Enter opens this entry in the journal.[/color]" % [GOLD, _esc(rec.get("title", "")), MUTED]


func _on_search_submitted(text: String) -> void:
	run_search(text)
	_list.grab_focus()


## Keeps text from being parsed as BBCode tags.
func _esc(t: String) -> String:
	return t.replace("[", "[lb]")

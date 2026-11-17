class_name ScriptureLinks
extends RefCounted
## Read-only lookups that join the Scripture reader to the journal and to cross-referenced events.
## Everything here only READS journal state (and only what the protagonist has already discovered, so the
## reader never spoils an undiscovered entry). Nothing here, or anything that calls it, may write to the
## protagonist's systems; the independence test enforces that.

const CROSSREFS_PATH := "res://data/scripture/crossrefs.json"

static var _groups: Dictionary = {}
static var _loaded := false


static func groups() -> Dictionary:
	if not _loaded:
		_loaded = true
		var data = DataFiles.load_json(CROSSREFS_PATH)
		if data is Dictionary:
			_groups = data.get("groups", {})
	return _groups


## True when two references share at least one verse in the same chapter of the same book.
static func overlaps(a: String, b: String) -> bool:
	var pa: Dictionary = Scripture.parse_ref(a)
	var pb: Dictionary = Scripture.parse_ref(b)
	if pa.is_empty() or pb.is_empty():
		return false
	return pa["book"] == pb["book"] and pa["chapter"] == pb["chapter"] and pa["start"] <= pb["end"] and pb["start"] <= pa["end"]


## Event groups that mention this verse or passage: [{id, title, others: [ref]}], `others` excluding the
## overlapping reference(s) themselves.
static func related(ref: String) -> Array:
	var out: Array = []
	var g := groups()
	for id in g:
		var hit := false
		var others: Array = []
		for r in g[id]["refs"]:
			if overlaps(ref, r):
				hit = true
			else:
				others.append(r)
		if hit and not others.is_empty():
			out.append({"id": id, "title": g[id]["title"], "others": others})
	return out


## Journal entries the protagonist has ALREADY written that cite this passage, plus connections already
## found: [{kind: "entry"|"link", entry, title, label}].
static func journal_for(ref: String) -> Array:
	var out: Array = []
	for rec in Journal.list():
		for r in rec["refs"]:
			if overlaps(ref, r):
				out.append({"kind": "entry", "entry": rec["id"], "title": rec["title"], "label": "Journal: %s" % rec["title"]})
				break
	for lid in Journal.link_ids():
		if not Journal.has_link(lid):
			continue
		var d: Dictionary = Journal.link_def(lid)
		if not Journal.has_entry(d["entry"]):
			continue
		if overlaps(ref, d["reference"]) or (d.get("nt_ref", "") != "" and overlaps(ref, d["nt_ref"])):
			var title: String = Journal.get_entry(d["entry"])["title"]
			out.append({"kind": "link", "entry": d["entry"], "title": title, "label": "Connection found in: %s" % title})
	return out


## Passages worth reading for a journal entry: its own references, then connections already found and the
## player-side New Testament comparisons that came with them. Order preserved, no duplicates.
static func refs_for_entry(entry_id: String) -> Array:
	var out: Array = []
	var rec: Dictionary = Journal.get_entry(entry_id)
	for r in rec.get("refs", []):
		if not out.has(r):
			out.append(r)
	for l in Journal.links_for(entry_id):
		for r in [l.get("reference", ""), l.get("nt_ref", "")]:
			if r != "" and not out.has(r):
				out.append(r)
	return out


## Every reference the reader can be pointed at by game data (for completeness tests).
static func all_data_refs() -> Array:
	var out: Array = []
	for id in groups():
		out.append_array(groups()[id]["refs"])
	for lid in Journal.link_ids():
		var d: Dictionary = Journal.link_def(lid)
		out.append(d["reference"])
		if d.get("nt_ref", "") != "":
			out.append(d["nt_ref"])
	return out

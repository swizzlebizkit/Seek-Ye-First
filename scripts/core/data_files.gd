class_name DataFiles
extends RefCounted
## Loads JSON content from res://data. Missing or malformed files are reported loudly, never silently.


static func load_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		push_error("Missing data file: %s" % path)
		return null
	var text := FileAccess.get_file_as_string(path)
	var json := JSON.new()
	if json.parse(text) != OK:
		push_error("Invalid JSON in %s (line %d): %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data

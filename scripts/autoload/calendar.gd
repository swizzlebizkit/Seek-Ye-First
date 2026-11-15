extends Node
## The game calendar: a simplified lunisolar Jewish calendar worked out from WorldSim's day count and
## clock. It keeps no state of its own that is saved, so saves are unchanged.
##
## Three independent things, all derived from the same day count:
##   - the seven-day week: a continuous count that never resets (every seventh day is the Sabbath);
##   - the date: months of 29 or 30 days from a fixed mean lunation, years of 12 or 13 months;
##   - the day boundary: days run sunset to sunset, so the number turns over at sunset, not midnight.
##
## Everything about the date is a gameplay approximation. The real months began when the new moon was
## first seen, and first-century leap years were declared by observation, not by a formula.
## See docs/calendar.md.

const DATA_PATH := "res://data/world/calendar.json"
const FESTIVALS_PATH := "res://data/world/festivals.json"

var config: Dictionary = {}
var festival_config: Dictionary = {}

var sunset_minute := 18 * 60
var preparation_minute := 15 * 60
var start_minute := 7 * 60
var week_length := 7
var start_weekday := 0
var sabbath_index := 6
var weekday_names: Array = []
var month_names: Array = []
var leap_adar_names: Array = ["Adar I", "Adar II"]
var mean_lunation := 29.530589
var lunation_phase := 0.0
var year_label := "Year"

var _first_year := 1
var _start_in_year := 0  # days from Nisan 1 of the first year to Day 1
var _year_start: Array = [0]  # day offset at the start of each year (index 0 = the first year)
var _lun_start: Array = [0]  # lunation counter at the start of each year
var _months: Dictionary = {}  # year index -> [{name, length}]


func _ready() -> void:
	var d = DataFiles.load_json(DATA_PATH)
	if d is Dictionary:
		load_config(d)
	var f = DataFiles.load_json(FESTIVALS_PATH)
	if f is Dictionary:
		festival_config = f


## Applies a calendar configuration (the contents of calendar.json). Tests use this to try other set-ups.
func load_config(d: Dictionary) -> void:
	config = d.duplicate(true)
	sunset_minute = int(d.get("sunset_minute", 18 * 60))
	preparation_minute = int(d.get("preparation_minute", 15 * 60))
	start_minute = int(d.get("start_minute", 7 * 60))
	var w: Dictionary = d.get("week", {})
	week_length = int(w.get("length", 7))
	start_weekday = posmod(int(w.get("start_weekday", 0)), week_length)
	sabbath_index = int(w.get("sabbath_index", week_length - 1))
	weekday_names = w.get("names", [])
	var m: Dictionary = d.get("months", {})
	month_names = m.get("names", [])
	leap_adar_names = m.get("leap_adar_names", leap_adar_names)
	var l: Dictionary = d.get("lunation", {})
	mean_lunation = float(l.get("mean_length", 29.530589))
	lunation_phase = float(l.get("phase", 0.0))
	year_label = d.get("year_label", "Year")
	_year_start = [0]
	_lun_start = [0]
	_months.clear()
	var s: Dictionary = d.get("start_date", {})
	_first_year = int(s.get("year", 1))
	_start_in_year = 0
	var pos := _month_position(0, s.get("month", 1))
	var ms := months_in_year(0)
	for i in range(pos - 1):
		_start_in_year += int(ms[i]["length"])
	_start_in_year += int(s.get("day", 1)) - 1


# -- leap years and months ---------------------------------------------------------------------
## Whether a year (by its year number) has a thirteenth month. Explicit overrides always win.
func is_leap_year(year: int) -> bool:
	var ic: Dictionary = config.get("intercalation", {})
	var ov: Dictionary = ic.get("overrides", {})
	if ov.has(str(year)):
		return bool(ov[str(year)])
	match ic.get("policy", "metonic"):
		"never":
			return false
		_:
			var cycle := int(ic.get("cycle", 19))
			var pos := posmod(year - 1 + int(ic.get("cycle_offset", 0)), cycle) + 1
			return ic.get("leap_positions", []).any(func(p): return int(p) == pos)  # JSON numbers load as floats


## Months of a year by index from the first year: [{name, length}], in Nisan-based order.
func months_in_year(index: int) -> Array:
	if _months.has(index):
		return _months[index]
	while _lun_start.size() <= index:
		var i := _lun_start.size() - 1
		var ms := _build_months(i)
		_year_start.append(int(_year_start[i]) + _sum_lengths(ms))
		_lun_start.append(int(_lun_start[i]) + ms.size())
	var out := _build_months(index)
	_months[index] = out
	return out


func _build_months(index: int) -> Array:
	if _months.has(index):
		return _months[index]
	var year := _first_year + index
	var names: Array = month_names.duplicate()
	if is_leap_year(year) and not names.is_empty():
		names.pop_back()
		names.append_array(leap_adar_names)
	var out: Array = []
	var lun: int = int(_lun_start[index]) if index < _lun_start.size() else 0
	for i in range(names.size()):
		out.append({"name": names[i], "length": _lunation_length(lun + i, year, i + 1)})
	return out


## A month is 29 or 30 days: the difference between successive lunation boundaries on a fixed mean month.
func _lunation_length(lunation: int, year: int, position: int) -> int:
	for o in config.get("month_length_overrides", []):
		if int(o.get("year", 0)) == year and _month_position_in(year, o.get("month", 0)) == position:
			return int(o.get("length", 30))
	return int(floor((lunation + 1) * mean_lunation + lunation_phase) - floor(lunation * mean_lunation + lunation_phase))


func _month_position_in(year: int, month) -> int:
	return _month_position(year - _first_year, month)


## 1-based position of a month (given as a name or a number) within a year.
func _month_position(index: int, month) -> int:
	if month is String:
		var names: Array = month_names.duplicate()
		if is_leap_year(_first_year + index) and not names.is_empty():
			names.pop_back()
			names.append_array(leap_adar_names)
		return names.find(month) + 1
	return int(month)


func _sum_lengths(ms: Array) -> int:
	var n := 0
	for m in ms:
		n += int(m["length"])
	return n


func year_length(year: int) -> int:
	var ms := months_in_year(year - _first_year)
	return _sum_lengths(ms)


func month_count(year: int) -> int:
	return months_in_year(year - _first_year).size()


## The moment the day turns over. A function of the day so seasonal sunsets can replace the fixed value.
func sunset_for(_day: int) -> int:
	return sunset_minute


# -- the day count -----------------------------------------------------------------------------
## The calendar day for a clock reading (WorldSim.day turns over at midnight; this turns over at sunset).
func calendar_day(day: int, minute: float) -> int:
	return day + (1 if minute >= float(sunset_for(day)) else 0)


func current_day() -> int:
	return calendar_day(WorldSim.day, WorldSim.minute_of_day)


## 0 is the first day of the week; sabbath_index is the Sabbath. Independent of months and years.
func weekday(cal_day: int) -> int:
	return posmod(cal_day - 1 + start_weekday, week_length)


func weekday_name(cal_day: int) -> String:
	var i := weekday(cal_day)
	return weekday_names[i] if i < weekday_names.size() else "Day %d" % (i + 1)


func is_sabbath(day: int, minute: float) -> bool:
	return weekday(calendar_day(day, minute)) == sabbath_index


## "sabbath", "preparation" (the afternoon of the sixth day) or "ordinary".
func phase(day: int, minute: float) -> String:
	var wd := weekday(calendar_day(day, minute))
	if wd == sabbath_index:
		return "sabbath"
	if wd == posmod(sabbath_index - 1, week_length) and minute >= float(preparation_minute) and minute < float(sunset_for(day)):
		return "preparation"
	return "ordinary"


func current_phase() -> String:
	return phase(WorldSim.day, WorldSim.minute_of_day)


# -- dates -------------------------------------------------------------------------------------
## {year, month (position in the year, 1-based), name, day, months_in_year, leap}.
func date(cal_day: int) -> Dictionary:
	var t := cal_day - 1 + _start_in_year
	var idx := maxi(0, t / 385 - 1)  # a year is never longer than 385 days, so this is a safe lower bound
	months_in_year(idx)
	while true:
		months_in_year(idx + 1)  # makes sure the next year's start is known
		if t < int(_year_start[idx + 1]):
			break
		idx += 1
	var d := t - int(_year_start[idx])
	var ms := months_in_year(idx)
	var pos := 0
	while pos < ms.size() - 1 and d >= int(ms[pos]["length"]):
		d -= int(ms[pos]["length"])
		pos += 1
	return {"year": _first_year + idx, "month": pos + 1, "name": ms[pos]["name"], "day": d + 1,
			"months_in_year": ms.size(), "leap": ms.size() > month_names.size()}


## "14 Nisan". The year is left out of the HUD; see full_date_string.
func date_string(cal_day: int) -> String:
	var d := date(cal_day)
	return "%d %s" % [d["day"], d["name"]]


func full_date_string(cal_day: int) -> String:
	var d := date(cal_day)
	return "%d %s, %s %d" % [d["day"], d["name"], year_label, d["year"]]


## The calendar day number of a date, or 0 if it does not exist. The inverse of date().
func day_of(year: int, month, day: int) -> int:
	var idx := year - _first_year
	if idx < 0:
		return 0
	var ms := months_in_year(idx)
	var pos := _month_position(idx, month)
	if pos < 1 or pos > ms.size() or day < 1 or day > int(ms[pos - 1]["length"]):
		return 0
	var t := int(_year_start[idx])
	for i in range(pos - 1):
		t += int(ms[i]["length"])
	return t + day - 1 - _start_in_year + 1


## A day configured in data for a story event (calendar.json "anchors"): {"year", "month", "day"}.
func anchor_day(anchor_id: String) -> int:
	var a: Dictionary = config.get("anchors", {}).get(anchor_id, {})
	if a.is_empty():
		return 0
	return day_of(int(a["year"]), a["month"], int(a["day"]))


## The three-part HUD line: weekday (and preparation), Jewish date. The time is added by the HUD.
func weekday_label(day: int, minute: float) -> String:
	var s := weekday_name(calendar_day(day, minute))
	if phase(day, minute) == "preparation":
		s += ", preparation"
	return s


func hud_text(day: int, minute: float, time_text: String) -> String:
	return "%s | %s | %s" % [weekday_label(day, minute), date_string(calendar_day(day, minute)), time_text]


# -- festivals (lookup only; nothing uses them yet) ----------------------------------------------
## Festival id -> {start, length, name} (calendar day numbers) for one year. Dates may precede Day 1.
func festivals_in_year(year: int) -> Dictionary:
	var out: Dictionary = {}
	for id in festival_config.get("festivals", {}):
		var f: Dictionary = festival_config["festivals"][id]
		var start := 0
		if f.get("rule", "") == "pentecost":
			start = pentecost_day(year)
		else:
			start = _raw_day_of(year, f["month"], int(f["day"]))
		if start != -999999:
			out[id] = {"start": start, "length": int(f.get("length", 1)), "name": f.get("name", id)}
	return out


## Ids of the festivals running on a calendar day.
func festivals_on(cal_day: int) -> Array:
	var out: Array = []
	var fs := festivals_in_year(int(date(cal_day)["year"]))
	for id in fs:
		var f: Dictionary = fs[id]
		if cal_day >= int(f["start"]) and cal_day < int(f["start"]) + int(f["length"]):
			out.append(id)
	return out


## The day of Pentecost under the selected counting method (or the one named).
func pentecost_day(year: int, method: String = "") -> int:
	var cfg: Dictionary = festival_config.get("pentecost", {})
	var m: Dictionary = cfg.get("methods", {}).get(method if method != "" else cfg.get("selected", "pharisaic"), {})
	if m.is_empty():
		return -999999
	var count_from := -999999
	match m.get("count_from", "fixed"):
		"fixed":
			count_from = _raw_day_of(year, m["month"], int(m["day"]))
		"weekday_after_sabbath":
			var w0 := _raw_day_of(year, m["window_month"], int(m["window_start"]))
			for i in range(int(m["window_days"])):
				if weekday(w0 + i) == sabbath_index:
					count_from = w0 + i + 1
					break
	return count_from + 49 if count_from != -999999 else -999999


## Like day_of but also valid for days before Day 1 (so festival lookups never fail in early years).
func _raw_day_of(year: int, month, day: int) -> int:
	var idx := year - _first_year
	if idx < 0:
		return -999999
	var ms := months_in_year(idx)
	var pos := _month_position(idx, month)
	if pos < 1 or pos > ms.size():
		return -999999
	var t := int(_year_start[idx])
	for i in range(pos - 1):
		t += int(ms[i]["length"])
	return t + day - _start_in_year

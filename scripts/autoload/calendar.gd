extends Node
## The game calendar, worked out from WorldSim's day count and clock. It keeps no state of its own, so
## it needs no save data. Days run sunset to sunset: the day number turns over at sunset, not midnight.
## The week is a continuous count (every seventh day is the Sabbath) and never depends on the year.
## Dates (month and day) are separate and only matter for names and, later, the feasts.

const DATA_PATH := "res://data/world/calendar.json"

var sunset_minute := 18 * 60
var preparation_minute := 15 * 60
var week_length := 7
var sabbath_index := 6
var weekday_names: Array = []
var month_length := 30
var months: Array = []
var extra_days := 5
var extra_name := "Year's end"
var start_offset := 0  # days into the year that Day 1 falls on


func _ready() -> void:
	var d = DataFiles.load_json(DATA_PATH)
	if not d is Dictionary:
		return
	sunset_minute = int(d.get("sunset_minute", sunset_minute))
	preparation_minute = int(d.get("preparation_minute", preparation_minute))
	var w: Dictionary = d.get("week", {})
	week_length = int(w.get("length", 7))
	sabbath_index = int(w.get("sabbath_index", week_length - 1))
	weekday_names = w.get("names", [])
	var y: Dictionary = d.get("year", {})
	month_length = int(y.get("month_length", 30))
	months = y.get("months", [])
	extra_days = int(y.get("extra_days", 5))
	extra_name = y.get("extra_name", extra_name)
	var s: Dictionary = d.get("start_date", {})
	start_offset = (int(s.get("month", 1)) - 1) * month_length + (int(s.get("day", 1)) - 1)


func year_length() -> int:
	return months.size() * month_length + extra_days


## The moment the day turns over. A function of the day so seasonal sunsets can replace the fixed value.
func sunset_for(_day: int) -> int:
	return sunset_minute


# -- the day count -----------------------------------------------------------------------------
## The calendar day for a clock reading (WorldSim.day turns over at midnight; this turns over at sunset).
func calendar_day(day: int, minute: float) -> int:
	return day + (1 if minute >= float(sunset_for(day)) else 0)


func current_day() -> int:
	return calendar_day(WorldSim.day, WorldSim.minute_of_day)


## 0 is the first day of the week; sabbath_index is the Sabbath.
func weekday(cal_day: int) -> int:
	return posmod(cal_day - 1, week_length)


func weekday_name(cal_day: int) -> String:
	var i := weekday(cal_day)
	return weekday_names[i] if i < weekday_names.size() else "Day %d" % (i + 1)


func is_sabbath(day: int, minute: float) -> bool:
	return weekday(calendar_day(day, minute)) == sabbath_index


## "sabbath", "preparation" (the afternoon of the day before it) or "ordinary".
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
## {year, month (1-12, or 0 for the extra days), day, extra (1-5 on the extra days, else 0)}.
func date(cal_day: int) -> Dictionary:
	var n := cal_day - 1 + start_offset
	var year_len := year_length()
	var in_year := posmod(n, year_len)
	var out := {"year": n / year_len + 1, "month": 0, "day": 0, "extra": 0}
	var regular := months.size() * month_length
	if in_year < regular:
		out["month"] = in_year / month_length + 1
		out["day"] = in_year % month_length + 1
	else:
		out["extra"] = in_year - regular + 1
		out["day"] = out["extra"]
	return out


func date_string(cal_day: int) -> String:
	var d := date(cal_day)
	if d["month"] == 0:
		return "%s, day %d" % [extra_name, d["extra"]]
	return "%s %d" % [months[d["month"] - 1], d["day"]]


## Two short lines for the HUD: the weekday (and phase) and the day count.
func weekday_label(day: int, minute: float) -> String:
	var cd := calendar_day(day, minute)
	var s := weekday_name(cd)
	if phase(day, minute) == "preparation":
		s += ", preparation"
	return s

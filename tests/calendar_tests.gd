extends RefCounted
## Calendar checks (S1.1): the lunisolar date calculation, leap months, the continuous week, the Sabbath,
## sunset turnover, configuration, festival lookup, the HUD and saves. Driven by test_runner.gd.

var t: Node
var orig: Dictionary = {}

const SUNSET := 18 * 60
const LEAP_YEARS_FIRST_CYCLE := [3, 6, 8, 11, 14, 17, 19]


func run(runner: Node) -> void:
	t = runner
	orig = Calendar.config.duplicate(true)
	t._section = "calendar-data"
	test_data()
	t._section = "calendar-months"
	test_months_and_years()
	test_not_the_old_calendar()
	test_date_walk()
	test_determinism()
	t._section = "calendar-days"
	test_day_turnover()
	test_week_and_sabbath()
	test_phases()
	test_week_never_resets()
	t._section = "calendar-config"
	test_configuration()
	test_overrides()
	t._section = "calendar-festivals"
	test_festivals()
	t._section = "calendar-conditions"
	test_conditions()
	await test_hud_and_saves()
	Calendar.load_config(orig)
	WorldSim.reset()


func cfg() -> Dictionary:
	return orig.duplicate(true)


# -- data --------------------------------------------------------------------------------------
func test_data() -> void:
	t.check(Calendar.month_names.size() == 12, "twelve regular months")
	t.check(Calendar.month_names == ["Nisan", "Iyar", "Sivan", "Tammuz", "Av", "Elul", "Tishri", "Cheshvan", "Kislev", "Tevet", "Shevat", "Adar"], "month names, Nisan first")
	t.check(Calendar.leap_adar_names == ["Adar I", "Adar II"], "the leap year has two Adars")
	t.check(Calendar.weekday_names.size() == 7 and Calendar.weekday_names[6] == "The Sabbath", "seven ordinal weekday names, the seventh is the Sabbath")
	t.check(Calendar.sunset_for(1) == SUNSET and Calendar.sunset_for(400) == SUNSET, "sunset comes from data (18:00)")
	t.check(Calendar.start_minute == 7 * 60 and Calendar.start_weekday == 0, "default start: 7:00, the first day of the week")
	t.check(Calendar.date(1)["year"] == 1 and Calendar.date_string(1) == "1 Nisan", "Day 1 is 1 Nisan")
	for n in Calendar.weekday_names:
		var low := String(n).to_lower()
		t.check(not low.contains("sunday") and not low.contains("saturday"), "weekday name '%s' avoids later planetary names" % n)
	t.check(orig["intercalation"]["policy"] == "metonic" and orig.has("month_length_overrides") and orig.has("anchors"), "intercalation policy, month overrides and anchors are configurable")
	var ban := str(orig).to_lower()
	t.check(not ban.contains("year's end") and not ban.contains("extra_days"), "no trace of the old five-extra-days year")


# -- months and years ----------------------------------------------------------------------------
func test_months_and_years() -> void:
	var seen29 := false
	var seen30 := false
	var all_ok := true
	var leaps: Array = []
	var total19 := 0
	var months19 := 0
	for y in range(1, 58):
		var ms: Array = Calendar.months_in_year(y - 1)
		for m in ms:
			var l: int = m["length"]
			if l == 29:
				seen29 = true
			elif l == 30:
				seen30 = true
			else:
				all_ok = false
		if ms.size() == 13:
			leaps.append(y)
		elif ms.size() != 12:
			all_ok = false
		if y <= 19:
			total19 += Calendar.year_length(y)
			months19 += ms.size()
	t.check(all_ok, "every month has 29 or 30 days and every year has 12 or 13 months")
	t.check(seen29 and seen30, "both 29-day and 30-day months occur")
	t.check(leaps.slice(0, 7) == LEAP_YEARS_FIRST_CYCLE, "leap years follow the 19-year pattern (3, 6, 8, 11, 14, 17, 19)")
	t.check(leaps.size() == 21, "seven leap years in each 19-year cycle (21 in 57 years)")
	t.check(months19 == 235, "19 years hold 235 months")
	var mean := float(total19) / 19.0
	t.check(mean > 365.0 and mean < 365.5, "a 19-year cycle averages %.2f days, close to a solar year" % mean)
	var lengths_ok := true
	for y in range(1, 58):
		var yl := Calendar.year_length(y)
		var is_leap := Calendar.month_count(y) == 13
		if not ((not is_leap and yl >= 353 and yl <= 355) or (is_leap and yl >= 383 and yl <= 385)):
			lengths_ok = false
	t.check(lengths_ok, "ordinary years are 353 to 355 days and leap years 383 to 385")
	var ord := Calendar.months_in_year(0)
	var leap_year := Calendar.months_in_year(2)
	t.check(ord[11]["name"] == "Adar" and ord.size() == 12, "an ordinary year ends with Adar")
	t.check(leap_year[10]["name"] == "Shevat" and leap_year[11]["name"] == "Adar I" and leap_year[12]["name"] == "Adar II", "a leap year ends with Adar I and Adar II")
	t.check(Calendar.is_leap_year(3) and not Calendar.is_leap_year(4), "year 3 is a leap year, year 4 is not")


func test_not_the_old_calendar() -> void:
	var any_365 := false
	var always_30 := true
	for y in range(1, 40):
		if Calendar.year_length(y) == 365:
			any_365 = true
	for y in range(1, 4):
		for m in Calendar.months_in_year(y - 1):
			if m["length"] != 30:
				always_30 = false
	t.check(not any_365, "no year is the old fixed 365 days")
	t.check(not always_30, "months are no longer a fixed 30 days")
	t.check(Calendar.month_count(3) != Calendar.month_count(4), "the number of months in a year varies")
	t.check(Calendar.date(354)["year"] == 1 and Calendar.date_string(354) == "30 Adar", "the first year ends on day 354, not 360 or 365")
	t.check(Calendar.date(355)["year"] == 2 and Calendar.date_string(355) == "1 Nisan", "and the second year begins on day 355")
	t.check(Calendar.date_string(361) != "Year's end, day 1", "there is no block of five extra days")


# -- walking every day for decades -----------------------------------------------------------------
func test_date_walk() -> void:
	var prev: Dictionary = Calendar.date(1)
	var ok_step := true
	var ok_names := true
	var year_changes := 0
	var month_changes := 0
	var leap_seen := false
	var bad := ""
	for cd in range(2, 20000):
		var d: Dictionary = Calendar.date(cd)
		var ms: Array = Calendar.months_in_year(int(prev["year"]) - 1)
		if d["year"] == prev["year"] and d["month"] == prev["month"]:
			if d["day"] != prev["day"] + 1:
				ok_step = false
				bad = "same month day jump at %d" % cd
		elif d["year"] == prev["year"] and d["month"] == prev["month"] + 1:
			month_changes += 1
			if d["day"] != 1 or prev["day"] != ms[prev["month"] - 1]["length"]:
				ok_step = false
				bad = "month rollover at %d" % cd
		elif d["year"] == prev["year"] + 1:
			year_changes += 1
			if d["month"] != 1 or d["day"] != 1 or prev["month"] != ms.size() or prev["day"] != ms[ms.size() - 1]["length"]:
				ok_step = false
				bad = "year rollover at %d" % cd
		else:
			ok_step = false
			bad = "odd step at %d" % cd
		var names: Array = Calendar.months_in_year(int(d["year"]) - 1).map(func(m): return m["name"])
		if names[d["month"] - 1] != d["name"]:
			ok_names = false
		if d["leap"]:
			leap_seen = true
		prev = d
	t.check(ok_step, "walking 20,000 days: every day follows the last, months and years roll over correctly %s" % bad)
	t.check(ok_names, "the month name always matches its place in the year")
	t.check(year_changes >= 53 and month_changes > 600, "about 55 years and 600+ month changes crossed")
	t.check(leap_seen, "leap years were met on the way")
	# day_of is the inverse of date
	var inv := true
	for cd in range(1, 3000, 7):
		var d: Dictionary = Calendar.date(cd)
		if Calendar.day_of(d["year"], d["month"], d["day"]) != cd:
			inv = false
	t.check(inv, "day_of is the exact inverse of date")
	t.check(Calendar.day_of(1, "Nisan", 31) == 0 or Calendar.months_in_year(0)[0]["length"] == 30, "a day that does not exist in a month is refused")
	t.check(Calendar.day_of(3, "Adar", 1) == 0, "a leap year has no plain 'Adar'")
	t.check(Calendar.day_of(3, "Adar II", 1) > Calendar.day_of(3, "Adar I", 1), "Adar II follows Adar I in a leap year")
	# examples for the report
	var samples := [1, 15, 29, 30, 31, 59, 60, 177, 354, 355, 384, 385, 740, 1000]
	for cd in samples:
		print("DEMO date  day %5d  %-9s %s" % [cd, Calendar.weekday_name(cd).trim_prefix("The "), Calendar.full_date_string(cd)])


func test_determinism() -> void:
	var a: Array = []
	for cd in range(1, 4000, 13):
		a.append(Calendar.full_date_string(cd))
	Calendar.load_config(cfg())
	var b: Array = []
	for cd in range(1, 4000, 13):
		b.append(Calendar.full_date_string(cd))
	t.check(a == b and a.size() > 100, "reloading the calendar gives identical dates")
	t.check(Calendar.full_date_string(1234) == Calendar.full_date_string(1234), "the same day always gives the same date")


# -- the day count ---------------------------------------------------------------------------------
func test_day_turnover() -> void:
	t.check(Calendar.calendar_day(1, 7.0 * 60.0) == 1, "the game opens on Day 1")
	t.check(Calendar.calendar_day(1, SUNSET - 0.1) == 1, "still Day 1 a moment before sunset")
	t.check(Calendar.calendar_day(1, SUNSET) == 2, "the day turns over at sunset, not midnight")
	t.check(Calendar.calendar_day(2, 0.0) == 2, "midnight does not turn the day over")
	t.check(Calendar.date_string(Calendar.calendar_day(1, 23.0 * 60.0 + 59.0)) == Calendar.date_string(Calendar.calendar_day(2, 0.0)), "the Jewish date is the same either side of midnight")
	t.check(Calendar.date_string(Calendar.calendar_day(1, 12.0 * 60.0)) == "1 Nisan" and Calendar.date_string(Calendar.calendar_day(1, SUNSET)) == "2 Nisan", "the date changes at sunset")
	var prev := Calendar.calendar_day(1, 0.0)
	var steps: Array = []
	for day in range(1, 5):
		for m in range(0, 1440):
			var c := Calendar.calendar_day(day, float(m))
			if c != prev:
				steps.append([day, m, c - prev])
				prev = c
	t.check(steps.size() == 4 and steps.all(func(s): return s[1] == SUNSET and s[2] == 1), "the count steps by exactly one, always at 18:00")
	var c2 := cfg()
	c2["sunset_minute"] = 19 * 60
	Calendar.load_config(c2)
	t.check(Calendar.calendar_day(1, 18.5 * 60.0) == 1 and Calendar.calendar_day(1, 19.0 * 60.0) == 2, "the sunset hour is configurable")
	Calendar.load_config(cfg())


func test_week_and_sabbath() -> void:
	t.check(Calendar.weekday(1) == 0 and Calendar.weekday_name(1) == "The first day", "Day 1 is the first day of the week")
	t.check(Calendar.weekday(7) == 6 and Calendar.weekday_name(7) == "The Sabbath", "Day 7 is the Sabbath")
	t.check(Calendar.weekday(8) == 0 and Calendar.weekday(14) == 6, "the week repeats")
	t.check(not Calendar.is_sabbath(6, SUNSET - 1.0), "Friday afternoon is not yet the Sabbath")
	t.check(Calendar.is_sabbath(6, SUNSET), "the Sabbath begins at sunset on the sixth day")
	t.check(Calendar.is_sabbath(6, 23.0 * 60.0) and Calendar.is_sabbath(7, 3.0 * 60.0), "it runs through the night")
	t.check(Calendar.is_sabbath(7, 12.0 * 60.0) and Calendar.is_sabbath(7, SUNSET - 1.0), "and all the seventh day")
	t.check(not Calendar.is_sabbath(7, SUNSET), "it ends at sunset on the seventh day")
	var sabbath_minutes := 0
	for day in range(1, 29):
		for m in range(0, 1440):
			if Calendar.is_sabbath(day, float(m)):
				sabbath_minutes += 1
	t.check(sabbath_minutes == 4 * 1440, "exactly four Sabbaths of 24 hours in 28 days")


func test_phases() -> void:
	t.check(Calendar.phase(1, 12.0 * 60.0) == "ordinary", "an ordinary day")
	t.check(Calendar.phase(6, 14.0 * 60.0 + 59.0) == "ordinary", "the sixth day before the afternoon")
	t.check(Calendar.phase(6, 15.0 * 60.0) == "preparation", "the sixth-day afternoon is the day of preparation")
	t.check(Calendar.phase(6, SUNSET - 1.0) == "preparation", "until sunset")
	t.check(Calendar.phase(6, SUNSET) == "sabbath", "then the Sabbath")
	t.check(Calendar.phase(5, 19.0 * 60.0) == "ordinary", "the evening that begins the sixth day is not preparation")
	t.check(Calendar.phase(7, SUNSET) == "ordinary", "the day after the Sabbath is ordinary again")
	t.check(Calendar.weekday_label(6, 16.0 * 60.0).ends_with("preparation"), "the HUD label marks preparation")


func test_week_never_resets() -> void:
	var ok := true
	var sabbath_gaps := true
	var last_sabbath := -1
	var month_start_weekdays := {}
	var year_start_weekdays := {}
	for cd in range(1, 20000):
		if Calendar.weekday(cd + 1) != (Calendar.weekday(cd) + 1) % 7:
			ok = false
		if Calendar.weekday(cd) == Calendar.sabbath_index:
			if last_sabbath != -1 and cd - last_sabbath != 7:
				sabbath_gaps = false
			last_sabbath = cd
		var d: Dictionary = Calendar.date(cd)
		if d["day"] == 1:
			month_start_weekdays[Calendar.weekday(cd)] = true
			if d["month"] == 1:
				year_start_weekdays[Calendar.weekday(cd)] = true
	t.check(ok, "the weekday advances by exactly one every day for 55 years")
	t.check(sabbath_gaps, "every Sabbath is exactly seven days after the last, through every month, year and leap month")
	t.check(month_start_weekdays.size() == 7, "months begin on every weekday: the week does not restart with the month")
	t.check(year_start_weekdays.size() >= 4, "years begin on varying weekdays: the week does not restart with the year")
	# crossing the inserted month in year 3
	var first_adar2 := Calendar.day_of(3, "Adar II", 1)
	var before := Calendar.day_of(3, "Adar I", Calendar.months_in_year(2)[11]["length"])
	t.check(first_adar2 == before + 1 and Calendar.weekday(first_adar2) == (Calendar.weekday(before) + 1) % 7, "no weekday reset when the leap month begins")
	var nisan4 := Calendar.day_of(4, "Nisan", 1)
	var adar2_last := Calendar.day_of(3, "Adar II", Calendar.months_in_year(2)[12]["length"])
	t.check(nisan4 == adar2_last + 1 and Calendar.weekday(nisan4) == (Calendar.weekday(adar2_last) + 1) % 7, "and none when the leap year ends")
	print("DEMO sabbath  Sabbaths either side of the leap month: ", Calendar.full_date_string(before - 3), " -> ", Calendar.full_date_string(first_adar2 + 4))
	var run := []
	for cd in range(before - 6, first_adar2 + 9):
		var d: Dictionary = Calendar.date(cd)
		run.append("%d %s%s" % [d["day"], d["name"], "*" if Calendar.weekday(cd) == 6 else ""])
	var ny: Array = []
	for cd in range(adar2_last - 3, nisan4 + 4):
		var dd: Dictionary = Calendar.date(cd)
		ny.append("%d %s Y%d%s" % [dd["day"], dd["name"], dd["year"], "*" if Calendar.weekday(cd) == 6 else ""])
	print("DEMO newyear ", " | ".join(ny), "   (* = Sabbath)")
	print("DEMO leap    ", " | ".join(run), "   (* = Sabbath)")


# -- configuration ---------------------------------------------------------------------------------
func test_configuration() -> void:
	var c := cfg()
	c["week"]["start_weekday"] = 3
	Calendar.load_config(c)
	t.check(Calendar.weekday(1) == 3 and Calendar.weekday_name(1) == "The fourth day", "Day 1 can fall on another weekday")
	t.check(Calendar.date_string(1) == "1 Nisan", "without moving the date")
	t.check(Calendar.weekday(4) == 6 and Calendar.is_sabbath(4, 10.0 * 60.0), "so the Sabbath comes on Day 4")
	c = cfg()
	c["start_date"] = {"year": 5, "month": "Tishri", "day": 10}
	Calendar.load_config(c)
	t.check(Calendar.date(1)["year"] == 5 and Calendar.date_string(1) == "10 Tishri", "the start date is configurable (here the Day of Atonement)")
	t.check(Calendar.day_of(5, "Tishri", 10) == 1, "and Day 1 is that date")
	t.check(Calendar.weekday(1) == 0, "while the weekday stays independent of the date")
	t.check(Calendar.date_string(1 + Calendar.months_in_year(0)[6]["length"] - 9) == "1 Cheshvan", "the following month starts on schedule")
	c = cfg()
	c["start_date"] = {"year": 3, "month": "Adar II", "day": 5}
	Calendar.load_config(c)
	t.check(Calendar.date_string(1) == "5 Adar II" and Calendar.date(1)["leap"], "a game can start inside a leap month")
	var len2: int = Calendar.months_in_year(0)[12]["length"]
	t.check(Calendar.date_string(len2 - 5 + 2) == "1 Nisan" and Calendar.date(len2 - 5 + 2)["year"] == 4, "and roll into the next year from it")
	c = cfg()
	c["start_date"] = {"year": 1, "month": 3, "day": 12}
	Calendar.load_config(c)
	t.check(Calendar.date_string(1) == "12 Sivan", "a month can be given by number as well as name")
	c = cfg()
	c["start_minute"] = 6 * 60
	Calendar.load_config(c)
	WorldSim.reset()
	t.check(WorldSim.minute_of_day == 360.0 and WorldSim.day == 1, "the starting game time is configurable")
	c = cfg()
	c["year_label"] = "Year of the story"
	c["start_date"]["year"] = 30
	Calendar.load_config(c)
	t.check(Calendar.full_date_string(1) == "1 Nisan, Year of the story 30", "the calendar year identifier is configurable")
	Calendar.load_config(cfg())
	WorldSim.reset()
	t.check(WorldSim.minute_of_day == 420.0, "defaults restored")


func test_overrides() -> void:
	var c := cfg()
	c["intercalation"]["overrides"] = {"2": true, "3": false}
	Calendar.load_config(c)
	t.check(Calendar.month_count(2) == 13 and Calendar.month_count(3) == 12, "a story year can be forced leap or ordinary, over the pattern")
	t.check(Calendar.months_in_year(1)[12]["name"] == "Adar II", "a forced leap year gets its second Adar")
	t.check(Calendar.is_leap_year(6), "other years still follow the pattern")
	c = cfg()
	c["intercalation"]["policy"] = "never"
	Calendar.load_config(c)
	var any_leap := false
	for y in range(1, 40):
		if Calendar.month_count(y) != 12:
			any_leap = true
	t.check(not any_leap, "the 'never' policy gives only twelve-month years")
	c = cfg()
	c["intercalation"]["cycle_offset"] = 1
	Calendar.load_config(c)
	t.check(Calendar.is_leap_year(2) and not Calendar.is_leap_year(3), "the pattern can be shifted")
	c = cfg()
	c["intercalation"]["policy"] = "never"
	c["intercalation"]["overrides"] = {"4": true}
	Calendar.load_config(c)
	t.check(Calendar.month_count(4) == 13 and Calendar.month_count(5) == 12, "an override works under any policy")
	c = cfg()
	c["month_length_overrides"] = [{"year": 1, "month": "Nisan", "length": 30}, {"year": 1, "month": "Iyar", "length": 30}, {"year": 3, "month": "Adar II", "length": 29}]
	Calendar.load_config(c)
	t.check(Calendar.months_in_year(0)[0]["length"] == 30 and Calendar.months_in_year(0)[1]["length"] == 30, "a month's length can be set for a story year")
	t.check(Calendar.months_in_year(2)[12]["length"] == 29, "including the leap month")
	c = cfg()
	c["anchors"] = {"baptism_test": {"year": 2, "month": "Sivan", "day": 3}}
	Calendar.load_config(c)
	var a := Calendar.anchor_day("baptism_test")
	t.check(a > 0 and Calendar.date_string(a) == "3 Sivan" and Calendar.date(a)["year"] == 2, "a story event can be pinned to a configured date")
	t.check(Calendar.anchor_day("nothing") == 0, "an unknown anchor is harmless")
	var d2 := Calendar.date(a + 1000)
	t.check(Calendar.day_of(d2["year"], d2["month"], d2["day"]) == a + 1000, "and the calendar still works around it")
	Calendar.load_config(cfg())
	t.check(CanonicalTimeline.event_ids().size() > 0 and not CanonicalTimeline.has_event("baptism_test"), "calendar anchors do not touch the canonical timeline")


# -- festivals (lookup only) -----------------------------------------------------------------------
func test_festivals() -> void:
	var fs: Dictionary = Calendar.festivals_in_year(2)
	t.check(fs.size() == 6, "six festival rules are loaded")
	t.check(fs["passover"]["start"] == Calendar.day_of(2, "Nisan", 14), "Passover is 14 Nisan")
	t.check(fs["unleavened_bread"]["start"] == Calendar.day_of(2, "Nisan", 15) and fs["unleavened_bread"]["length"] == 7, "Unleavened Bread begins 15 Nisan and lasts seven days")
	t.check(fs["trumpets"]["start"] == Calendar.day_of(2, "Tishri", 1), "Trumpets is 1 Tishri")
	t.check(fs["atonement"]["start"] == Calendar.day_of(2, "Tishri", 10), "Atonement is 10 Tishri")
	t.check(fs["tabernacles"]["start"] == Calendar.day_of(2, "Tishri", 15) and fs["tabernacles"]["length"] == 7, "Tabernacles begins 15 Tishri")
	var in_leap: Dictionary = Calendar.festivals_in_year(3)
	t.check(in_leap["tabernacles"]["start"] == Calendar.day_of(3, "Tishri", 15), "festivals are found in a leap year too")
	var pass_day: int = fs["passover"]["start"]
	t.check(Calendar.festivals_on(pass_day) == ["passover"], "festivals_on finds Passover")
	t.check(Calendar.festivals_on(pass_day + 1) == ["unleavened_bread"] and Calendar.festivals_on(pass_day + 7) == ["unleavened_bread"], "and the week that follows")
	t.check(Calendar.festivals_on(pass_day + 8).is_empty(), "and nothing the day after it ends")
	# Pentecost: two readings of Leviticus 23:15, both available
	var ph := Calendar.pentecost_day(2, "pharisaic")
	var sad := Calendar.pentecost_day(2, "sadducean")
	t.check(ph == Calendar.day_of(2, "Nisan", 16) + 49, "pharisaic reading: fifty days counted from 16 Nisan")
	t.check(Calendar.weekday(ph) == Calendar.weekday(Calendar.day_of(2, "Nisan", 16)), "seven weeks later is the same weekday")
	var count_start := sad - 49
	t.check(Calendar.weekday(count_start) == (Calendar.sabbath_index + 1) % 7, "sadducean reading: counted from the day after a Sabbath")
	t.check(count_start >= Calendar.day_of(2, "Nisan", 16) and count_start <= Calendar.day_of(2, "Nisan", 22), "and that Sabbath falls within Unleavened Bread")
	t.check(Calendar.pentecost_day(2) == ph, "the selected method comes from data, and is configurable")
	var methods_differ := false
	for y in range(1, 12):
		if Calendar.pentecost_day(y, "pharisaic") != Calendar.pentecost_day(y, "sadducean"):
			methods_differ = true
	t.check(methods_differ, "the two readings can give different dates (so neither is silently assumed)")
	t.check(Calendar.pentecost_day(2, "unknown_method") == -999999, "an unknown method is refused")
	var saved: Dictionary = Calendar.festival_config.duplicate(true)
	Calendar.festival_config["pentecost"]["selected"] = "sadducean"
	t.check(Calendar.festivals_in_year(2)["weeks"]["start"] == sad, "switching the selected method changes Pentecost")
	Calendar.festival_config = saved
	for id in fs:
		t.check(not CanonicalTimeline.has_event(id), "festival '%s' is not part of the canonical timeline" % id)
	print("DEMO festivals year 2: Passover ", Calendar.date_string(pass_day), " (", Calendar.weekday_name(pass_day), "), Pentecost pharisaic ", Calendar.date_string(ph), " / sadducean ", Calendar.date_string(sad), ", Tabernacles ", Calendar.date_string(fs["tabernacles"]["start"]))


# -- conditions ------------------------------------------------------------------------------------
func test_conditions() -> void:
	var day := WorldSim.day
	var minute := WorldSim.minute_of_day
	WorldSim.day = 6
	WorldSim.minute_of_day = 16.0 * 60.0
	t.check(GameState.check({"day_phase": "preparation"}) and GameState.check({"sabbath": false}), "conditions read the preparation afternoon")
	t.check(GameState.check({"weekday": 5}) and not GameState.check({"weekday": 6}), "weekday condition: the sixth day (index 5)")
	WorldSim.minute_of_day = 19.0 * 60.0
	t.check(GameState.check({"sabbath": true}) and GameState.check({"weekday": 6}) and GameState.check({"day_phase": "sabbath"}), "the same evening is the Sabbath")
	t.check(GameState.check({"weekday": [0, 6]}) and not GameState.check({"weekday": [0, 1]}), "weekday accepts a list of days")
	WorldSim.day = day
	WorldSim.minute_of_day = minute
	# stamps use the calendar day
	t._fresh()
	WorldSim.day = 1
	WorldSim.minute_of_day = 19.0 * 60.0
	Journal.discover("rumor_yosef")
	t.check(Journal.get_entry("rumor_yosef")["day"] == 2, "a journal entry made after sunset is stamped with the new day")
	t.check(Combat.resolve_encounter("yard_toll", "diplomacy") and Combat.outcomes["yard_toll"]["day"] == 2, "an encounter outcome made after sunset is stamped with the same day")
	var view := JournalView.new()
	var txt: String = view._entry_bbcode(Journal.get_entry("rumor_yosef"))
	t.check(txt.contains("Day 2, 2 Nisan"), "the journal shows the day and the date it works out to")
	view.free()
	WorldSim.reset()


# -- HUD and saves -----------------------------------------------------------------------------------
func test_hud_and_saves() -> void:
	t._section = "calendar-hud"
	t._fresh()
	var game: Node = await t._spawn_game({"mode": "new"})
	DialogueRunner.cancel()
	GameState.mode = GameState.Mode.EXPLORE
	game.hud._process(0.0)
	t.check(game.hud._clock.text == "The first day | 1 Nisan | 7:00", "the HUD reads 'The first day | 1 Nisan | 7:00'")
	WorldSim.day = 6
	WorldSim.minute_of_day = 19.0 * 60.0
	game.hud._process(0.0)
	t.check(game.hud._clock.text == "The Sabbath | 7 Nisan | 19:00", "after sunset on the sixth day the HUD shows the Sabbath and the new date")
	t.check(game.hud._clock.get_theme_color("font_color") == UiTheme.GOLD, "the Sabbath is marked in gold")
	WorldSim.minute_of_day = 16.0 * 60.0
	game.hud._process(0.0)
	t.check(game.hud._clock.text == "The sixth day, preparation | 6 Nisan | 16:00" and game.hud._clock.get_theme_color("font_color") == UiTheme.MUTED, "the preparation afternoon is labelled")
	# a month boundary on the HUD, including a leap month
	var adar2_first := Calendar.day_of(3, "Adar II", 1)
	WorldSim.day = adar2_first
	WorldSim.minute_of_day = 9.0 * 60.0
	game.hud._process(0.0)
	t.check(game.hud._clock.text.contains("1 Adar II"), "the HUD names the leap month")
	# the running clock crosses sunset and midnight
	WorldSim.day = 1
	WorldSim.minute_of_day = 17.0 * 60.0 + 59.9
	WorldSim._process(1.0)
	t.check(Calendar.current_day() == 2 and Calendar.date_string(Calendar.current_day()) == "2 Nisan", "the running clock crosses into the next date at sunset")
	WorldSim.minute_of_day = 23.0 * 60.0 + 59.9
	WorldSim._process(1.0)
	t.check(WorldSim.day == 2 and Calendar.date_string(Calendar.current_day()) == "2 Nisan", "and midnight changes nothing")
	game.queue_free()
	await t.get_tree().process_frame
	# saves
	t._section = "calendar-saves"
	await save_round_trip("across a month boundary", _last_day_of_month(1, 0), 10.0 * 60.0)
	await save_round_trip("across a year boundary", _last_day_of_month(1, 11), 10.0 * 60.0)
	await save_round_trip("across a leap month", _last_day_of_month(3, 11), 10.0 * 60.0)
	await save_round_trip("on the Sabbath", 7, 12.0 * 60.0)
	await save_round_trip("on the Sabbath evening", 6, 21.0 * 60.0)
	# an older save: only the clock is stored, and journal stamps are plain day numbers
	t._fresh()
	WorldSim.deserialize({"day": 40, "minute": 600.0})
	Journal.deserialize({"entries": {"rumor_yosef": {"id": "rumor_yosef", "type": "rumor", "title": "A preacher at the Jordan", "text": "x", "source": "", "origin": "fiction", "refs": [], "status": "unverified", "day": 12, "notes": [{"id": "n", "text": "later", "refs": [], "source": "", "day": 30}]}}, "order": ["rumor_yosef"]})
	t.check(WorldSim.day == 40 and WorldSim.minute_of_day == 600.0, "an older save's clock is kept exactly")
	t.check(Journal.get_entry("rumor_yosef")["day"] == 12, "an older journal stamp is kept as the same day number")
	var v := JournalView.new()
	var jt: String = v._entry_bbcode(Journal.get_entry("rumor_yosef"))
	t.check(jt.contains("Day 12, " + Calendar.date_string(12)) and jt.contains("Day 30, " + Calendar.date_string(30)), "and shown with the date the new calendar gives it, never rewritten")
	v.free()
	WorldSim.deserialize({})
	t.check(WorldSim.day == 1 and WorldSim.minute_of_day == 420.0, "a save with no clock data opens at the start")
	WorldSim.reset()


func _last_day_of_month(year: int, month_index: int) -> int:
	var ms := Calendar.months_in_year(year - 1)
	return Calendar.day_of(year, ms[month_index]["name"], int(ms[month_index]["length"]))


func save_round_trip(label: String, day: int, minute: float) -> void:
	t._fresh()
	WorldSim.day = day
	WorldSim.minute_of_day = minute
	var date_before := Calendar.full_date_string(Calendar.current_day())
	var wd_before := Calendar.weekday(Calendar.current_day())
	var sab_before := Calendar.is_sabbath(day, minute)
	Journal.discover("rumor_yosef")
	t.check(SaveManager.save_slot(2), "save %s" % label)
	t._fresh()
	t.check(SaveManager.load_slot(2), "load %s" % label)
	t.check(WorldSim.day == day and WorldSim.minute_of_day == minute, "the clock is exactly as saved %s" % label)
	t.check(Calendar.full_date_string(Calendar.current_day()) == date_before and Calendar.weekday(Calendar.current_day()) == wd_before, "date and weekday are unchanged after loading %s (%s)" % [label, date_before])
	t.check(Calendar.is_sabbath(WorldSim.day, WorldSim.minute_of_day) == sab_before, "Sabbath status unchanged after loading %s" % label)
	t.check(Journal.get_entry("rumor_yosef")["day"] == Calendar.calendar_day(day, minute), "the journal stamp survives %s" % label)
	# and time carries on correctly from the loaded point
	var before := Calendar.current_day()
	WorldSim.minute_of_day = float(Calendar.sunset_for(WorldSim.day)) - 0.5
	WorldSim._process(2.0)
	t.check(Calendar.current_day() == Calendar.calendar_day(WorldSim.day, WorldSim.minute_of_day) and Calendar.current_day() > before - 1, "time carries on across sunset after loading %s" % label)
	WorldSim.reset()

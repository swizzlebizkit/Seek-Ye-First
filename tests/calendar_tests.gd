extends RefCounted
## Calendar core (S1) checks: the sunset-to-sunset day count, the continuous week, the Sabbath, dates with
## the five extra days, condition keys, the HUD and saves. Driven by test_runner.gd.

var t: Node

const SUNSET := 18 * 60


func run(runner: Node) -> void:
	t = runner
	t._section = "calendar-data"
	test_data()
	t._section = "calendar-days"
	test_day_turnover()
	test_week_and_sabbath()
	test_phases()
	t._section = "calendar-dates"
	test_dates()
	test_week_never_resets()
	t._section = "calendar-conditions"
	test_conditions()
	await test_hud_and_saves()


func test_data() -> void:
	t.check(Calendar.year_length() == 365, "a year is twelve 30-day months plus five extra days")
	t.check(Calendar.months.size() == 12 and Calendar.months[0] == "Nisan", "months run from Nisan")
	t.check(Calendar.weekday_names.size() == 7 and Calendar.weekday_names[6] == "The Sabbath", "seven ordinal weekday names, the seventh is the Sabbath")
	t.check(Calendar.sunset_for(1) == SUNSET and Calendar.sunset_for(200) == SUNSET, "sunset is a fixed 18:00 for now")
	t.check(Calendar.start_offset == 0, "Day 1 is the first day of the first month by default")
	for n in Calendar.weekday_names:
		var low := String(n).to_lower()
		t.check(not low.contains("sunday") and not low.contains("saturday"), "weekday name '%s' avoids later planetary names" % n)


func test_day_turnover() -> void:
	t.check(Calendar.calendar_day(1, 7.0 * 60.0) == 1, "the game opens on Day 1")
	t.check(Calendar.calendar_day(1, SUNSET - 0.1) == 1, "still Day 1 a moment before sunset")
	t.check(Calendar.calendar_day(1, SUNSET) == 2, "the day turns over at sunset, not midnight")
	t.check(Calendar.calendar_day(1, 23.0 * 60.0) == 2, "the evening belongs to the next day")
	t.check(Calendar.calendar_day(2, 0.0) == 2, "midnight does not turn the day over")
	t.check(Calendar.calendar_day(2, SUNSET - 0.1) == 2 and Calendar.calendar_day(2, SUNSET) == 3, "and so on every day")
	# every minute across a few days: the count only ever steps up by one, exactly at sunset
	var prev := Calendar.calendar_day(1, 0.0)
	var steps: Array = []
	for day in range(1, 5):
		for m in range(0, 1440):
			var c := Calendar.calendar_day(day, float(m))
			if c != prev:
				steps.append([day, m, c - prev])
				prev = c
	t.check(steps.size() == 4 and steps.all(func(s): return s[1] == SUNSET and s[2] == 1), "the count steps by exactly one, always at 18:00")


func test_week_and_sabbath() -> void:
	t.check(Calendar.weekday(1) == 0 and Calendar.weekday_name(1) == "The first day", "Day 1 is the first day of the week")
	t.check(Calendar.weekday(7) == 6 and Calendar.weekday_name(7) == "The Sabbath", "Day 7 is the Sabbath")
	t.check(Calendar.weekday(8) == 0 and Calendar.weekday(14) == 6, "the week repeats")
	# Sabbath: sunset on the sixth day to sunset on the seventh
	t.check(not Calendar.is_sabbath(6, SUNSET - 1.0), "Friday afternoon is not yet the Sabbath")
	t.check(Calendar.is_sabbath(6, SUNSET), "the Sabbath begins at sunset on the sixth day")
	t.check(Calendar.is_sabbath(6, 23.0 * 60.0) and Calendar.is_sabbath(7, 3.0 * 60.0), "it runs through the night")
	t.check(Calendar.is_sabbath(7, 12.0 * 60.0) and Calendar.is_sabbath(7, SUNSET - 1.0), "and all the seventh day")
	t.check(not Calendar.is_sabbath(7, SUNSET), "it ends at sunset on the seventh day")
	t.check(not Calendar.is_sabbath(1, 12.0 * 60.0) and not Calendar.is_sabbath(3, 12.0 * 60.0), "ordinary days are not the Sabbath")
	# exactly one Sabbath per seven days, 24 hours long, over a long stretch
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
	t.check(Calendar.phase(5, 16.0 * 60.0) == "ordinary", "nor is the afternoon before it")
	t.check(Calendar.phase(7, SUNSET) == "ordinary", "the day after the Sabbath is ordinary again")
	t.check(Calendar.weekday_label(6, 16.0 * 60.0).ends_with("preparation"), "the HUD label marks preparation")
	t.check(Calendar.weekday_label(2, 9.0 * 60.0) == "The second day", "and names ordinary days plainly")


func test_dates() -> void:
	var d1 := Calendar.date(1)
	t.check(d1["year"] == 1 and d1["month"] == 1 and d1["day"] == 1, "Day 1 is 1 Nisan")
	t.check(Calendar.date_string(1) == "Nisan 1" and Calendar.date_string(30) == "Nisan 30", "days run 1 to 30 in a month")
	t.check(Calendar.date_string(31) == "Iyyar 1", "then the next month")
	t.check(Calendar.date_string(360) == "Adar 30", "the twelfth month ends at day 360")
	for i in range(5):
		var d := Calendar.date(361 + i)
		t.check(d["month"] == 0 and d["extra"] == i + 1 and d["year"] == 1, "extra day %d comes after the twelfth month" % (i + 1))
	t.check(Calendar.date_string(361) == "Year's end, day 1" and Calendar.date_string(365) == "Year's end, day 5", "the five extra days have a name")
	var ny := Calendar.date(366)
	t.check(ny["year"] == 2 and ny["month"] == 1 and ny["day"] == 1, "the next year begins after the five extra days")
	t.check(Calendar.date(731)["year"] == 3, "and the one after")
	# Day 1 need not be the first of the year
	var saved := Calendar.start_offset
	Calendar.start_offset = 13
	t.check(Calendar.date_string(1) == "Nisan 14", "the start date is one data value")
	Calendar.start_offset = 358
	t.check(Calendar.date_string(1) == "Adar 29" and Calendar.date_string(3) == "Year's end, day 1" and Calendar.date(8)["year"] == 2, "a start near the year's end rolls over correctly")
	Calendar.start_offset = saved


func test_week_never_resets() -> void:
	var ok := true
	for cd in range(1, 3000):
		if Calendar.weekday(cd + 1) != (Calendar.weekday(cd) + 1) % 7:
			ok = false
	t.check(ok, "the weekday advances by exactly one every day for over eight years")
	var year_ok := true
	for cd in [30, 31, 359, 360, 361, 365, 366, 730, 731]:
		if Calendar.weekday(cd + 1) != (Calendar.weekday(cd) + 1) % 7:
			year_ok = false
	t.check(year_ok, "including across month ends, the five extra days and the new year")
	var sabbaths := 0
	for cd in range(1, 366):
		if Calendar.weekday(cd) == Calendar.sabbath_index:
			sabbaths += 1
	t.check(sabbaths == 52, "a 365-day year holds 52 Sabbaths")
	t.check(Calendar.weekday(366) == (Calendar.weekday(1) + 1) % 7, "the weekday of New Year moves on by one each year")
	t.check(Calendar.weekday(361) == (Calendar.weekday(360) + 1) % 7 and Calendar.weekday(365) == (Calendar.weekday(360) + 5) % 7, "the extra days do not disturb the week")


func test_conditions() -> void:
	var day := WorldSim.day
	var minute := WorldSim.minute_of_day
	WorldSim.day = 6
	WorldSim.minute_of_day = 16.0 * 60.0
	t.check(GameState.check({"day_phase": "preparation"}) and GameState.check({"sabbath": false}), "conditions read the preparation afternoon")
	t.check(GameState.check({"weekday": 5}) and not GameState.check({"weekday": 6}), "weekday condition: the sixth day (index 5)")
	WorldSim.minute_of_day = 19.0 * 60.0
	t.check(GameState.check({"sabbath": true}) and GameState.check({"weekday": 6}) and GameState.check({"day_phase": "sabbath"}), "the same evening is the Sabbath")
	t.check(GameState.check({"weekday": [0, 6]}) and not GameState.check({"weekday": [0, 1]}), "weekday accepts a list")
	t.check(GameState.check({"sabbath": true, "not_flag": "nope"}), "it combines with other conditions")
	WorldSim.day = day
	WorldSim.minute_of_day = minute
	# the journal and encounter ledger stamp the calendar day, so they agree with the HUD
	t._fresh()
	WorldSim.day = 1
	WorldSim.minute_of_day = 19.0 * 60.0
	Journal.discover("rumor_yosef")
	t.check(Journal.get_entry("rumor_yosef")["day"] == 2, "a journal entry made after sunset is stamped with the new day")
	WorldSim.reset()


func test_hud_and_saves() -> void:
	t._section = "calendar-hud"
	t._fresh()
	var game: Node = await t._spawn_game({"mode": "new"})
	DialogueRunner.cancel()
	GameState.mode = GameState.Mode.EXPLORE
	game.hud._process(0.0)
	var txt: String = game.hud._clock.text
	t.check(txt.contains("The first day") and txt.contains("Day 1") and txt.contains("7:00"), "the HUD shows the weekday, day count and time")
	WorldSim.day = 6
	WorldSim.minute_of_day = 19.0 * 60.0
	game.hud._process(0.0)
	t.check(game.hud._clock.text.contains("The Sabbath") and game.hud._clock.text.contains("Day 7"), "after sunset on the sixth day the HUD shows the Sabbath")
	t.check(game.hud._clock.get_theme_color("font_color") == UiTheme.GOLD, "the Sabbath is marked in gold")
	WorldSim.minute_of_day = 16.0 * 60.0
	game.hud._process(0.0)
	t.check(game.hud._clock.text.contains("preparation") and game.hud._clock.get_theme_color("font_color") == UiTheme.MUTED, "the preparation afternoon is labelled")
	# the real clock: let it run across sunset
	WorldSim.day = 1
	WorldSim.minute_of_day = 17.0 * 60.0 + 59.9
	var before := Calendar.current_day()
	WorldSim._process(1.0)
	t.check(before == 1 and Calendar.current_day() == 2, "the running clock crosses into the next day at sunset")
	WorldSim.minute_of_day = 23.0 * 60.0 + 59.9
	WorldSim._process(1.0)
	t.check(WorldSim.day == 2 and Calendar.current_day() == 2, "and midnight changes nothing")
	# saves: only WorldSim's day and minute are stored, and the calendar follows
	WorldSim.day = 6
	WorldSim.minute_of_day = 20.0 * 60.0
	t.check(SaveManager.save_slot(2), "save on the Sabbath")
	game.queue_free()
	await t.get_tree().process_frame
	t._fresh()
	t.check(Calendar.current_day() == 1, "a new game is Day 1 again")
	t.check(SaveManager.load_slot(2), "load")
	t.check(Calendar.current_day() == 7 and Calendar.is_sabbath(WorldSim.day, WorldSim.minute_of_day), "the Sabbath is still the Sabbath after loading")
	WorldSim.deserialize({})
	t.check(Calendar.current_day() == 1, "a save with no clock data opens on Day 1")
	WorldSim.reset()

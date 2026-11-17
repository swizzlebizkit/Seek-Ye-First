# The game calendar (S1.1)

**This is a gameplay approximation of the Jewish lunisolar calendar. It is not a reconstruction of
first-century practice, and no date it produces should be read as astronomically or historically verified.**

Code: `scripts/autoload/calendar.gd`. Data: `data/world/calendar.json`, `data/world/festivals.json`.
Tests: `tests/calendar_tests.gd`.

## 1. Three separate things, one source

Every system reads the calendar from `Calendar`; nothing else works out dates.

| Thing | What it is | Where it comes from |
| --- | --- | --- |
| The clock | Continuous game time (`WorldSim.day`, `minute_of_day`) | Saved with the game |
| The day count | Days counted 1, 2, 3 ..., turning over at **sunset** (18:00, from data) | Clock plus the sunset hour |
| The week | Seven days, never resets; every seventh day is the Sabbath | Day count plus a start weekday |
| The date | "14 Nisan": month and day, with leap months | Day count plus the start date |

The calendar keeps no saved state of its own.

## 2. The week and the Sabbath

`weekday = (calendar_day - 1 + start_weekday) mod 7`. It does not look at months or years, so it cannot
reset at a new month, a new year or a leap month. Day 1 is "the first day" by default; `start_weekday`
can place it elsewhere, and the date does not depend on it. The Sabbath begins at sunset on the sixth
day and ends at sunset on the seventh. The afternoon of the sixth day (from 15:00 to sunset) is the day of
preparation. Midnight changes nothing: the day, weekday and date only turn over at sunset. The player is
never stopped or put to rest on the Sabbath.

## 3. Months

Each month is **29 or 30 days**, from a fixed mean lunation of 29.530589 days:

    length(n) = floor((n + 1) * 29.530589 + phase) - floor(n * 29.530589 + phase)

where `n` counts months continuously from the start (leap months included). Every playthrough and every
save gives the same lengths. **This is not observation.** In the first century a month began when
witnesses saw the new crescent, so real month lengths varied from this pattern. Individual months can be
pinned with `month_length_overrides` (year, month, length).

Month names, in the Nisan-based religious order: Nisan, Iyar, Sivan, Tammuz, Av, Elul, Tishri, Cheshvan,
Kislev, Tevet, Shevat, Adar. The HUD uses this order. The later civil year that begins with Tishri is a
different convention and is **not** modelled; the game numbers years from Nisan.

## 4. Leap years

An ordinary year has 12 months (353 to 355 days). A leap year has 13 (383 to 385): the year ends with
**Adar I** and **Adar II** in place of Adar. Which years are leap years is a policy in `calendar.json`:

- **`metonic`** (default): a repeating 19-year pattern with leap years at positions 3, 6, 8, 11, 14, 17, 19.
  This is a **modern computational convenience**. The 19-year cycle was known in antiquity, but first-century
  leap years were not decided by a fixed rule: they were declared, year by year, by a court that judged
  whether the spring was far enough advanced (the ripening of the barley and fruit, the season of the
  equinox). The pattern is used only so that the game keeps a steady relationship to the seasons.
- **`never`**: every year has twelve months.
- **`overrides`**: `{ "5": true, "9": false }` forces a particular year to be leap or ordinary, whichever the
  policy. Use this for story years.
- **`cycle_offset`** shifts where year 1 falls in the 19-year pattern.

The naming and placement of the added month (a second Adar at the end of the year) follows the later,
better-documented practice. Evidence for exactly how it was named in the first century is thin.

## 5. Epoch and chronology

`start_date` is `{year, month, day}` (month by name or number), and Day 1 is that date. `start_weekday`
and `start_minute` are separate. Nothing assumes a particular month or weekday. Years are numbered from
`start_date.year` with the label `year_label` ("Year 1"). **The game does not claim a historical year**; the
numbers are a fictional design assumption until the story needs otherwise.

**The opening is 1 Kislev, Year 1, 07:00.** That is a simulated gameplay anchor (the protagonist's game
opening), not a claim about when anything in Scripture happened, and not the baptism date. Kislev is the ninth
month of a Nisan-numbered year, so the first Passover after the opening is 14 Nisan, Year 2.

`anchors` pins other story events to a date: `Calendar.anchor_day(id)` gives its day number and
`Calendar.anchor_certainty(id)` its certainty class. Anchors only look dates up; an anchor never changes an
event. **There is no baptism anchor.**

**The Baptism Exception.** The baptism is ministry Day 0 and the one canonical event the player's arrival
triggers. Scripture gives no calendar date for it, so none is configured: when the player reaches the
designated Jordan trigger, `CanonicalTimeline.trigger_baptism` records the actual world minute
(certainty `simulated`, "recorded from the playthrough") and `Calendar.set_ministry_start` makes it Day 0. A
player who arrives on 2 Kislev is baptized on 2 Kislev; one who explores for weeks and arrives on 11 Nisan is
baptized on 11 Nisan. Before it, the world clock and calendar run normally, nothing is frozen, and the ministry
chronology has not begun. **Festivals never move**: Passover stays on 14 Nisan whatever the baptism date, and the
first Jerusalem Passover takes the earliest calendar Passover its preceding events allow (see
`docs/chronology.md`).

- `Calendar.ministry_elapsed(cal_day = today)`: calendar days since the baptism's calendar day (0 on it,
  negative before it). It is derived from the same day count as the date and the Sabbath, so it turns over
  at sunset with them and cannot drift. `Calendar.has_ministry_clock()` is false until the baptism is
  recorded (then it is 0).
- `Calendar.baptism_minutes()` / `baptism_day()` / `baptism_record()` / `ministry_minutes(abs)` /
  `world_minutes(day, minute)`: the same clock in minutes. Canonical events are scheduled in world minutes, and
  each is also reported as a ministry day.
- The roughly three-year ministry and the three Passovers John names (2:13, 6:4, 11:55) are recorded in
  `data/canon/events.json` as an *inferred* overall bound only. No precise date is invented from them.

## 6. Festivals (lookup only, nothing uses them yet)

`festivals.json` defines Passover (14 Nisan), Unleavened Bread (15 Nisan, seven days), Weeks/Pentecost,
Trumpets (1 Tishri), Atonement (10 Tishri) and Tabernacles (15 Tishri, seven days).
`Calendar.festivals_in_year(year)` and `festivals_on(day)` look them up. They are separate from the canonical
timeline and no festival id is a canon event.

**Pentecost** counts fifty days from "the morrow after the sabbath" (Leviticus 23:15-16), and the period
disputed which sabbath. Both readings are in the data and `pentecost.selected` chooses one:

- `pharisaic`: the Passover day is the sabbath; count from 16 Nisan (so Pentecost is 6 Sivan or so).
- `sadducean`: the weekly Sabbath in Unleavened Bread; count from the day after it (so Pentecost is a
  "first day" of the week).

The default is a design choice, not a settled fact. Other calendars of the period (such as the 364-day
solar calendar of Jubilees and some Qumran texts) are not modelled.

## 7. Saves and older games

Saves store only the clock (`day`, `minute`) and each journal or encounter stamp stores a day number. Dates
are always worked out, never stored, so:

- Existing saves load unchanged: the clock, progress and journal are kept exactly.
- Day numbers, weekdays and the Sabbath are **identical** to the previous (S1) calendar, because the
  week formula did not change.
- The *date* belonging to a day number is different from S1 (which used twelve 30-day months and five
  extra days). The journal shows a date such as "Day 12, 12 Kislev" using the current calendar. The stored stamp is never
  rewritten; if the calendar is configured again later, the shown date follows.

`Calendar` itself still saves nothing: the recorded baptism minute is stored in the canon block
(`CanonicalTimeline.serialize()`, key `baptism_minutes`, optional). A save without it loads as before the
baptism. Recording the baptism changes no date, weekday, Sabbath or phase for any day (tested).

## 8. How to change things

All in `data/world/calendar.json`: sunset hour, preparation hour, start minute, start weekday, start date,
month names, lunation length and phase, intercalation policy and overrides, month-length overrides,
anchors. After editing, run the headless tests.

# Sabbath and calendar: plan (not built yet)

Status: planning only. Nothing in this document is implemented. It exists so the decisions below can be
agreed before any code is written. Proposed home: its own milestone after 2B, because it touches the
world clock, NPC schedules and the village layout.

## 1. What exists today

`WorldSim` keeps `day` (a continuous counter starting at 1) and `minute_of_day` (starting 07:00). One real
second is half a game minute. Only the HUD reads it. There are no weekdays, months, years or schedules.
`day` is already saved, so a calendar derived from it needs no save-format change.

## 2. The calendar you described

A 360-day year with 5 extra days: twelve 30-day months (360), plus five extra days (365).

How I read it, and the decisions I need from you:

1. **The five extra days come in one block at the end of the year** (after month 12), as in the Egyptian
   civil calendar. They have names ("the five days") but belong to no month.
   - You said "random". A randomly placed block would make dates unpredictable and make saves harder to
     reason about, with no benefit to the Sabbath (see 3). My recommendation is a fixed block.
     If you want variety, a per-year seed (year number decides the placement) stays deterministic.
2. **365 days, no leap day.** A real Julian year is 365.25, but over the ~11 years the story covers a
   missing 0.25 day per year is invisible. Easy to add later.
3. **This is a game calendar, not the Jewish calendar.** The real calendar of first-century Judaea was
   lunisolar: months began at the new moon (29 or 30 days), and a thirteenth month was added in some years.
   So Passover (14 Nisan), Pentecost and Tabernacles fall on fixed *month* dates in a real calendar and
   drift against a fixed 360+5 year. If the feasts matter later (they will: Jerusalem, Acts), the calendar
   needs either a table of feast days per game-year or a lunar month length. I would **not** solve that now;
   I would keep a `feasts` data table keyed by (year, month, day) so it can be filled in from sources
   when we get there.

## 3. The Sabbath does not depend on the year at all

This is the key design point. The weekly cycle is a continuous count of days: every seventh day is the
Sabbath, forever, regardless of months, years or where the five extra days fall. It never resets at a
new month or new year. The year layout is for names and dates only.

    weekday = (day - 1 + weekday_of_day_1) mod 7        # 0 = first day ... 6 = Sabbath
    is_sabbath_day = weekday == 6

Because 365 = 52 weeks + 1 day, the weekday of "1 Nisan" shifts by one each year. That is correct
behaviour for a real week. It also means that **the five-extra-days question can never break the Sabbath.**

**Real weekdays.** If you want game days tied to real history (for example "the day of the baptism was a
Sunday"), the weekday for a date in the Julian calendar is computed from its Julian Day Number:
`(JDN + 1) mod 7` (0 = Sunday). That would let us anchor Day 1 to an actual historical date and keep
the Sabbath on the real Saturday. I recommend this only if you pick a specific start year; otherwise
Day 1 is simply a chosen weekday.

## 4. When the Sabbath begins and ends

Jewish days run evening to evening. The Sabbath is from sunset on the sixth day to sunset on the seventh.

- Add `sunset_minute(day)` from a small seasonal table in data (about 17:00 in winter to 19:30 in summer
  for Galilee). A fixed 18:00 is acceptable for a first version.
- Three day phases: **ordinary**, **preparation** (afternoon of the sixth day: people finish work, shops
  close early), **Sabbath** (sunset to sunset).
- The HUD shows the weekday and a small marker when the Sabbath is near or in force.

## 5. Which rules apply (about AD 29 to 40)

Scope: only observance that the New Testament, Acts or contemporary first-century evidence shows.
Anything that appears first in the Mishnah (around AD 200) stays out: the list of 39 categories of work,
the eruv, detailed carrying rules. The Pharisaic scribes did debate these matters in this period; the
game can mention that debate, but not present later codified rules as universal. Judaea, Galilee and the
Diaspora also differed.

Rules we can portray, with sources:

| Rule or custom | Source |
| --- | --- |
| Rest from ordinary labor | Exodus 20:8-11; Luke 23:56 |
| No buying and selling; city gates shut at dusk | Nehemiah 13:15-22; Jeremiah 17:21-22 |
| Gathering at the synagogue; the Law and the Prophets read | Luke 4:16-21; Acts 13:14-15, 15:21 |
| Teaching in the synagogue on the Sabbath | Mark 1:21, 6:2; Luke 13:10 |
| A limited walk: "a sabbath day's journey" | Acts 1:12 |
| Day of preparation before | Mark 15:42; Luke 23:54 |
| Debated: healing, plucking grain, rescuing an animal | Matthew 12:1-14; Luke 13:10-17, 14:1-6; John 5:9-18, 9:14 |

Paul's time in Jerusalem after his conversion (Galatians 1:18, about three years after, roughly AD 36 to 37)
falls inside this window, and so does the whole story. I propose **one rule set for the whole span**,
data-driven so it can be split by year later if evidence for a change appears.

Observance should also **vary by person**, not by faction: a profile or NPC trait ("strict", "ordinary",
"lax"), never by group, to keep the existing "individual behaviour only" rule. Not every village person
keeps it the same way, and some travelers are not Jews at all.

## 6. Gameplay effects (kept gentle: the village changes, the player is never blocked)

- No time skip, no movement lock, no forced rest. The player may walk, travel, fight and talk all day.
- Market stalls and traders (Yosef) are closed or absent. Field work and quest labor stop. A trade or
  errand that needs a stall is simply unavailable until the next day, and the dialogue says so.
- Many NPCs gather at the village's assembly place (the synagogue, where there is one). Scripture
  teachers are *easier* to find then: more people and more discussion. This is the intended reason to
  care about the calendar: **the Sabbath is when the investigation loop speeds up.**
- Ezra's scroll readings (2A.1) work on any day; on the Sabbath he can offer extra readings.
- Nothing required for story progress is locked behind a day of the week. If a quest needs an NPC who is
  away on the Sabbath, the quest data names an alternative.
- Danger is unaffected: highwaymen do not keep the Sabbath.

## 7. Data and systems

- `data/world/calendar.json`: weekday of day 1, historical anchor (optional), month names, epagomenal day
  names, sunset table, feast table (empty for now), observance rule set.
- A new `Calendar` autoload that is a pure function of `WorldSim.day` and `minute_of_day`:
  `weekday(day)`, `is_sabbath(day, minute)`, `phase(day, minute)`, `date(day)` returning
  (year, month, day or "extra day n"), `sunset_minute(day)`. No saved state of its own.
- Schedules: `data/world/schedules.json`, per-NPC rows of (phase, place, activity); `Npc` consults it.
  Today's NPC wandering stays the default.
- New condition keys: `weekday`, `sabbath`, `day_phase`. These follow the existing `check()` pattern.
- No new effects are needed; the calendar is read-only for content, like the canon timeline.

## 8. Order of work

1. **S1: Calendar core.** `Calendar` autoload, JSON, HUD weekday, condition keys, tests (weekday cycle
   across month and year boundaries and through the five extra days; Sabbath start and end; saves from
   before the calendar load with a defined Day 1).
2. **S2: Schedules.** NPCs follow phase-based schedules; stalls open and close.
3. **S3: The Sabbath in the village.** Assembly place, gathering, closed stalls, observance variety.
4. **S4: Scripture teaching at the gathering.** Extra scroll readings and teacher disagreement.

## 9. Questions to settle before S1

1. Is the five-day block fixed at year end (my recommendation) or seeded per year?
2. Should Day 1 be tied to a real historical date (and weekday), or just be a chosen weekday?
   If real: which year do you want the story to open in?
3. Is a fixed 18:00 sunset acceptable for the first version, or do you want seasonal sunsets from the start?
4. Do you want the feasts (Passover, Pentecost, Tabernacles) in scope for this milestone or left as a
   later table?

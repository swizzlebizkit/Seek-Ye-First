# Canonical chronology (schema v2)

`data/canon/events.json` holds the biblical events, `scripts/autoload/canonical_timeline.gd` schedules them and
`scripts/core/chronology_validator.gd` checks the data. KJV is canonical: every `refs` entry must pass
`Scripture.is_complete`, and Scripture wording is never altered.

## Hybrid timeline

Canonical events run on **world time**, not on player actions or quest progress. `WorldSim.advance` stops the
clock exactly at every event start and end and calls `CanonicalTimeline.sync_to`, so a rest or journey of any
length cannot skip or reorder an event; each is announced once, in time order (`event_occurred` when it
begins, `event_completed` when its duration is over). `story_advance(id)` is kept for compatibility but refuses
canonical ids with a warning and changes nothing. Quests, flags and personal story stay on the story side.
The player can only be present or absent; whether they witness an event never changes what happens or when.

## Certainty

Every chronological fact (an event, a dependency, a schedule, a duration) carries one of:

| value | meaning |
|---|---|
| `explicit` | Scripture states it. |
| `inferred` | Reasoned from Scripture (day markers, "the third day", harmonizing accounts). |
| `simulated` | A gameplay setting Scripture does not give. Never presented as history. |

A duration also has `basis`: `scripture` (a scriptural count, such as forty days) or `estimate` (a gameplay
guess, such as "not many days"). An `estimate` can never be `explicit`. The nine early-ministry events are a
**preliminary harmonization** (`preliminary_harmonization: true`); no event carries a fixed calendar date.

## Access

`public`: anyone present while it happens can see it (listed participants and witnesses in full, others in
part). `restricted`: only its scriptural participants and witnesses. `private`: nobody can witness it; a private
event lists no witnesses (the temptation, Matthew 4:1-11). Nothing is moved or blocked to preserve the story:
a knowledgeable player who arrives early and waits sees a public event.

## Event fields

All required unless marked optional; unknown fields fail validation.

| field | notes |
|---|---|
| `id`, `order`, `name`, `origin` | `order` is the harmonized sequence; `title` is derived from `name` for old callers. |
| `refs` | KJV references, each complete in `data/scripture/kjv.json`. |
| `certainty`, `access` | classes above. |
| `location` | an id from `data/world/geography.json` (area or location). |
| `dependencies` | `[{id, relation: after_start\|after_end, certainty, gap_days?}]`. No cycles. |
| `schedule` | `mode`, `certainty`, optional `note`, `window_days {earliest<=0<=latest}` (uncertainty window around the simulated time) and mode fields below. |
| `duration` | `{amount, unit: minutes\|hours\|days, basis, certainty, min, max, note?}` with `min <= amount <= max`. |
| `participants`, `witnesses`, `traveling_party`, `rumor_sources`, `testimony_sources` | lists of ids; participants is not empty. |
| `significance` | one line. |
| `notes`, `outcomes` (optional) | `outcomes` is `[{character_id, outcome: death\|injury\|arrest}]`, applied at the event's start only through `CanonicalProtection.apply_outcome(id, outcome, "timeline")`. |

Schedule modes: `opening_offset {days}` (relative to the game opening), `ministry_offset {days}` (relative to the
recorded baptism, ministry Day 0), `player_arrival` (the baptism only, below), `after_dependencies` (starts when its dependencies allow), `festival {festival,
minute?}` (the first occurrence of a `festivals.json` festival not earlier than its dependencies). Whatever the
mode, an event never starts before its dependencies allow. The start is a function of the data and
`calendar.json` only, so it is identical in every playthrough. The document also carries
`ministry {span_years, passovers[]}`: the inferred three-year bound and the Passovers of John 2:13, 6:4, 11:55.

## Queries

`scheduled_start/end(id)` (world minutes), `scheduled_calendar_day`, `scheduled_ministry_day`, `has_occurred`,
`is_completed`, `arrival_state(id, at)` (`before`, `during`, `after`), `witness_report(id, observer, location,
at)` and `can_witness`, and `witness(id, location)`, which records `witnessed` in `PlayerKnowledge` only when
legitimate. `event_location(id)` is fixed by the data; the player's position never changes it.

## Saves

`serialize()` returns `{occurred, completed}` plus `baptism_minutes` once the baptism is recorded. A block with only
`occurred` (older saves) loads as before the baptism: ids that cannot be placed without it are dropped; time then
fills in anything due.

## The Baptism Exception

Jesus' baptism is the **sole player-arrival-triggered canonical event**. Its schedule mode is `player_arrival`
(the validator allows it on `baptism_of_jesus` only). Until `CanonicalTimeline.trigger_baptism(location)` is
accepted, the ministry chronology has not begun: the baptism and every event that depends on it are
unscheduled (start `NEVER`, `arrival_state` "unscheduled"), nothing fires, `Calendar.has_ministry_clock()` is
false, and the world clock runs normally (never frozen or adjusted). John's preaching is already under way
from the opening.

- The trigger is refused unless `location` equals the baptism's own location id (`bethany_beyond_jordan`) and
  no baptism has been recorded. Entering a region or talking to John never calls it; the Jordan scene (GC-E) is
  a specific location or interaction with a clear on-screen indication.
- It is persistent and fires **exactly once**. A second call, from anywhere, at any time, is refused; the record
  survives saves (`baptism_minutes` in the canon block, optional) and loading a save cannot fire a second one.
- It records the **current world minute** as ministry Day 0. There is no baptism date in `calendar.json`
  (`certainty simulated`, "recorded from the playthrough"). Every later event is placed relative to it and the
  relative schedule is identical for any arrival date; only the absolute dates differ.
- The protagonist does not cause Jesus to be baptized: their arrival triggers the game's representation of an
  event Scripture establishes independently. Every later canonical event occurs on the world's schedule whatever
  the protagonist does or knows.

### The first Jerusalem Passover

**Explicit** (John 2:1-13): the Cana wedding, then Capernaum "not many days", then a Passover that was at hand.
**Simulated**: which calendar Passover it is, and the gaps (`gap_days` with `gap_certainty: simulated`, including
5 days of travel from Capernaum to Jerusalem, at least the walking time of the shortest land route: tested).
Festivals never move; Passover stays on 14 Nisan. `passover_jerusalem` takes the **earliest calendar Passover**
that is not before the end of the Capernaum stay plus the travel gap. The forty days are never compressed and no
event is skipped: a late baptism simply selects a later Passover (possibly the next year).

### Review flags

The choice of first Passover must not silently redefine the length of the ministry.
`CanonicalTimeline.first_passover_selection()` reports which Passover was chosen ({calendar_day, date,
ministry_day, baptism_to_passover_days, wait_days, skipped_count, skipped_days, certainty}) and
`chronology_flags()` raises:

| id | severity | when |
|---|---|---|
| `passion_passover_unreconciled` | info | always, while the Passion Passover is not in the data |
| `first_passover_skipped` | warning | a calendar Passover fell after the baptism but before the selected one |
| `first_passover_long_wait` | warning | the selected Passover is more than 150 days after the end of the preceding events |

These need **chronology review** before the Passion chronology is built: the baptism date moves the whole
ministry on the calendar, and the total length (the inferred three Passovers) has to be reconciled with the
Passion Passover.

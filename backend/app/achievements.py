"""
"Your story so far": the journey milestones and the hidden badges, worked
out from records the app already keeps (no table of its own).

- Milestones are always listed, as "Upcoming" until reached.
- Badges are hidden: one appears only once earned, on the day it was earned.
  An unearned badge is never sent, so its name can't show early.

The order is the story's order: everything reached, by date (on the same day,
milestones before badges, then the order below), then the upcoming
milestones in the order below.

Everything here describes what the user did, never what they didn't: no
streaks, nothing that can be lost by missing a day. storage.py reads the
records (get_achievement_records); this file only decides.
"""
from collections import Counter
from datetime import date, timedelta

from app.schemas import Milestone

# Activities for the "N small steps" milestones.
FIRST_STEP_GOAL = 5
SECOND_STEP_GOAL = 10
# Different days with a check-in (not in a row) for "Showing up for yourself".
CHECK_IN_DAYS_GOAL = 7
# How much lower than the first check-in's urge counts as "A lighter day".
LIGHTER_DAY_DROP = 3

# Badges
CATEGORY_BADGE_GOAL = 5
HIGH_URGE = 7                    # same line as recommendation_rules.HIGH_URGE
FEELING_BETTER_GOAL = 5
QUIET_MIND_GOAL = 3
STORYTELLER_GOAL = 10
AWAY_DAYS = 7                    # "Back Again": a check-in after this many days away
SUNDAY = 6                       # date.weekday()

BETTER = {"a_little_better", "much_better"}
CATEGORIES = ("outdoor_movement", "mindfulness_rest", "solo_exploration", "social_connection")

# (key, title, description). Titles are shown on the timeline; descriptions
# are for VoiceOver and anything that wants a second line.
MILESTONES = [
    ("started", "Started the journey", "You checked in for the first time."),
    ("first_activity", "Completed a first activity", "You finished your first activity."),
    ("first_photo", "Added a first photo memory", "You saved your first photo memory."),
    ("first_steps", f"{FIRST_STEP_GOAL} activities milestone",
     f"You completed {FIRST_STEP_GOAL} activities."),
    ("showing_up", "Showing up for yourself",
     f"You checked in on {CHECK_IN_DAYS_GOAL} different days."),
    ("lighter_day", "A lighter day",
     "Your urge to reach out was much lower than when you started."),
    ("more_steps", f"{SECOND_STEP_GOAL} small steps", f"You completed {SECOND_STEP_GOAL} activities."),
    ("moved_forward", "Moving forward check-in", "You chose to move forward."),
]

BADGES = [
    ("jack_of_all_trades", "Jack of All Trades", "You tried an activity of every kind."),
    ("in_control", "In Control",
     "Your energy was low and the urge was strong, and you still did something for yourself."),
    ("brave_hello", "Brave Hello",
     "Loneliness felt hardest, and you made time for some connection anyway."),
    ("outdoor_champ", "Outdoor Champ", f"You completed {CATEGORY_BADGE_GOAL} Outdoor & Movement activities."),
    ("calm_keeper", "Calm Keeper", f"You completed {CATEGORY_BADGE_GOAL} Mindfulness & Rest activities."),
    ("self_discovery_guru", "Self-Discovery Guru",
     f"You completed {CATEGORY_BADGE_GOAL} Solo Exploration activities."),
    ("connector", "Connector", f"You completed {CATEGORY_BADGE_GOAL} Social Connection activities."),
    ("feeling_it", "Feeling It", f"You felt better after {FEELING_BETTER_GOAL} activities."),
    ("quiet_mind", "Quiet Mind",
     f"{QUIET_MIND_GOAL} times, you barely thought about them during an activity."),
    ("storyteller", "Storyteller", f"You saved {STORYTELLER_GOAL} memories."),
    ("back_again", "Back Again", "You came back after some time away. Welcome back."),
    ("sunday_reset", "Sunday Reset", "You made time for yourself on a Sunday."),
]

CATEGORY_BADGES = {
    "outdoor_movement": "outdoor_champ",
    "mindfulness_rest": "calm_keeper",
    "solo_exploration": "self_discovery_guru",
    "social_connection": "connector",
}


def _nth(days: list[date], n: int) -> date | None:
    """The day of the n-th event (days already in order), or None."""
    return days[n - 1] if len(days) >= n else None


def _first(days) -> date | None:
    return next(iter(days), None)


def reached_milestones(records: dict) -> dict[str, date | None]:
    check_ins = records["check_ins"]          # in order
    completions = records["completions"]      # in order
    reflections = records["reflections"]      # in order
    done_days = [c["completed_on"] for c in completions]

    first_urge = check_ins[0]["contact_urge"] if check_ins else None
    check_in_days = sorted({c["local_date"] for c in check_ins})
    return {
        "started": _first(c["local_date"] for c in check_ins),
        "first_activity": _nth(done_days, 1),
        "first_photo": _first(r["local_date"] for r in reflections if r["has_photo"]),
        "first_steps": _nth(done_days, FIRST_STEP_GOAL),
        "showing_up": _nth(check_in_days, CHECK_IN_DAYS_GOAL),
        "lighter_day": _first(
            c["local_date"] for c in check_ins
            if c["contact_urge"] <= first_urge - LIGHTER_DAY_DROP
        ),
        "more_steps": _nth(done_days, SECOND_STEP_GOAL),
        "moved_forward": records["moved_forward_on"],
    }


def earned_badges(records: dict) -> dict[str, date]:
    check_ins = records["check_ins"]
    completions = records["completions"]
    reflections = records["reflections"]
    earned: dict[str, date | None] = {}

    # Kinds of activity: every kind, and CATEGORY_BADGE_GOAL of one kind.
    seen: set[str] = set()
    per_category: Counter = Counter()
    for c in completions:
        seen.add(c["category"])
        if len(seen) == len(CATEGORIES):
            earned.setdefault("jack_of_all_trades", c["completed_on"])
        per_category[c["category"]] += 1
        if per_category[c["category"]] == CATEGORY_BADGE_GOAL:
            earned.setdefault(CATEGORY_BADGES[c["category"]], c["completed_on"])

    # From the check-in the activity was recommended for.
    earned["in_control"] = _first(
        c["completed_on"] for c in completions
        if c["energy_level"] == "low" and c["contact_urge"] >= HIGH_URGE
    )
    earned["brave_hello"] = _first(
        c["completed_on"] for c in completions
        if c["category"] == "social_connection" and "feeling_lonely" in c["hardest_areas"]
    )
    earned["sunday_reset"] = _first(
        c["completed_on"] for c in completions if c["completed_on"].weekday() == SUNDAY
    )

    # From the reflections (memories).
    earned["feeling_it"] = _nth([r["local_date"] for r in reflections if r["mood_change"] in BETTER],
                                FEELING_BETTER_GOAL)
    earned["quiet_mind"] = _nth([r["local_date"] for r in reflections if r["thought_about_ex"] == "not_really"],
                                QUIET_MIND_GOAL)
    earned["storyteller"] = _nth([r["local_date"] for r in reflections if r["has_note"]], STORYTELLER_GOAL)

    # Coming back after time away (only ever a welcome, never a penalty).
    days = sorted({c["local_date"] for c in check_ins})
    earned["back_again"] = _first(
        later for earlier, later in zip(days, days[1:]) if later - earlier >= timedelta(days=AWAY_DAYS)
    )
    return {key: day for key, day in earned.items() if day is not None}


def story(records: dict) -> list[Milestone]:
    """The timeline: reached milestones and earned badges by date, then what's upcoming."""
    reached = reached_milestones(records)
    badges = earned_badges(records)

    done = []  # (day, 0 = milestone / 1 = badge, list position, item)
    upcoming = []
    for position, (key, title, description) in enumerate(MILESTONES):
        item = Milestone(label=title, reached_on=reached[key], kind="milestone", description=description)
        if reached[key] is None:
            upcoming.append(item)
        else:
            done.append((reached[key], 0, position, item))
    for position, (key, title, description) in enumerate(BADGES):
        if key in badges:
            item = Milestone(label=title, reached_on=badges[key], kind="badge", description=description)
            done.append((badges[key], 1, position, item))

    done.sort(key=lambda entry: entry[:3])
    return [entry[3] for entry in done] + upcoming

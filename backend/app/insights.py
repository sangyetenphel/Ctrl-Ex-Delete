"""
Progress & Insights calculations. Pure functions: storage.get_insight_records
fetches the rows, this file turns them into what the Progress screen shows.

Rules for every sentence produced here:
- It must be backed by the user's own records for the selected period.
- It describes what happened ("you reported", "was lower"), never why.
- With too little data it is simply left out; nothing is invented.
"""
from calendar import monthrange
from collections import Counter, defaultdict
from datetime import date, timedelta
from typing import Literal

from app.schemas import (
    CategoryShare,
    InsightPattern,
    InsightsResponse,
    MoodCount,
    MoodPoint,
    Takeaway,
    UrgePoint,
)

Period = Literal["week", "month"]

MOOD_LABELS = {
    "worse": "Worse",
    "about_the_same": "About the same",
    "a_little_better": "A little better",
    "much_better": "Much better",
}
BETTER = {"a_little_better", "much_better"}

# Internal scores for "How do you feel now compared to before?", used only to
# size the bars of the mood chart (on a 1–10 scale, like the urge chart).
# They are fixed so the same answers always draw the same bars. This is the
# only place they are defined; the app just draws what it is sent.
MOOD_SCORES = {
    "worse": 2,
    "about_the_same": 5,
    "a_little_better": 7,
    "much_better": 9,
}

# Smallest change in average urge (on the 1–10 scale) worth mentioning.
URGE_TREND_THRESHOLD = 1.0
# Fewest check-in days before comparing earlier and later urges.
MIN_DAYS_FOR_TREND = 3
# Fewest reflections in a category before describing how they felt.
MIN_MOODS_PER_CATEGORY = 2
# How many of the user's own weeks the month view's charts show at once.
JOURNEY_WEEKS_SHOWN = 5


def period_bounds(period: Period, today: date) -> tuple[date, date]:
    """The calendar week (Monday–Sunday) or month containing `today`."""
    if period == "week":
        start = today - timedelta(days=today.weekday())
        return start, start + timedelta(days=6)
    start = today.replace(day=1)
    return start, today.replace(day=monthrange(today.year, today.month)[1])


def journey_weeks(started_on: date | None, today: date) -> list[tuple[str, date, date]]:
    """
    The month view's chart bars: seven-day weeks counted from the user's first
    check-in (W1 = days 1–7, W2 = days 8–14, …), whatever the calendar says.
    Always JOURNEY_WEEKS_SHOWN bars: W1 onwards, then the latest weeks once the
    journey is longer than that (W2–W6 on day 36). Before any check-in, W1
    would start today.
    """
    first_day = started_on or today
    current_week = (today - first_day).days // 7 + 1
    first_week = max(current_week - JOURNEY_WEEKS_SHOWN + 1, 1)
    return [
        (f"W{week}", first_day + timedelta(weeks=week - 1), first_day + timedelta(weeks=week, days=-1))
        for week in range(first_week, first_week + JOURNEY_WEEKS_SHOWN)
    ]


def _buckets(period: Period, start: date, today: date) -> list[tuple[str, date, date]]:
    """Chart bars: one per day of the week, or the weeks of the user's journey."""
    if period == "week":
        return [
            ((start + timedelta(days=i)).strftime("%a"), start + timedelta(days=i), start + timedelta(days=i))
            for i in range(7)
        ]
    return journey_weeks(None, today)


def _plural(n: int, word: str, plural: str | None = None) -> str:
    return f"{n} {word if n == 1 else (plural or word + 's')}"


def build(period: Period, today: date, records: dict, weeks: list | None = None,
          week_records: dict | None = None) -> InsightsResponse:
    """
    `records` are the rows of the calendar week or month. The month view's two
    charts instead use `weeks` (journey_weeks) and `week_records`, the rows
    those weeks cover; everything else stays on the calendar period.
    """
    start, end = period_bounds(period, today)
    buckets = weeks or _buckets(period, start, today)
    chart_records = week_records or records
    # Category names and order come from the database (activity_categories),
    # the same names the activity cards show.
    category_labels = {row["category"]: row["label"] for row in records["categories"]}
    in_period = f"this {period}"

    # ── Urges: average rating per bar; None = no check-in (urges are 1–10, never 0)
    daily: dict[date, list[int]] = defaultdict(list)
    for row in records["check_ins"]:
        daily[row["local_date"]].append(row["contact_urge"])
    urges = []
    for label, first, last in buckets:
        ratings = [row["contact_urge"] for row in chart_records["check_ins"] if first <= row["local_date"] <= last]
        urges.append(UrgePoint(
            label=label,
            start=first,
            end=last,
            value=round(sum(ratings) / len(ratings)) if ratings else None,
            check_ins=len(ratings),
        ))
    check_in_days = len(daily)

    # ── Mood after activities: how many times each answer was given
    mood_counts = Counter(row["mood_change"] for row in records["moods"])
    moods = [MoodCount(response=key, label=label, count=mood_counts[key]) for key, label in MOOD_LABELS.items()]

    # ── Mood chart: per bar, the average score of the answers given on the
    # day the activity was completed (its reflection's local date). Answers
    # without a known score are skipped, never guessed; no answers = a gap.
    answers_by_day: dict[date, list[str]] = defaultdict(list)
    for row in chart_records["moods"]:
        if row["mood_change"] in MOOD_SCORES:
            answers_by_day[row["local_date"]].append(row["mood_change"])
    mood_points = []
    for label, first, last in buckets:
        answers = [a for day in sorted(answers_by_day) if first <= day <= last for a in answers_by_day[day]]
        scores = [MOOD_SCORES[a] for a in answers]
        mood_points.append(MoodPoint(
            label=label,
            start=first,
            end=last,
            value=round(sum(scores) / len(scores), 1) if scores else None,
            answers=answers,
        ))

    # ── What you made time for: completed activities per category
    completed_counts = Counter(row["category"] for row in records["completed"])
    completed_total = sum(completed_counts.values())
    categories = [
        CategoryShare(
            category=key,
            label=label,
            count=completed_counts[key],
            percent=round(100 * completed_counts[key] / completed_total) if completed_total else 0,
        )
        for key, label in category_labels.items()
    ]

    # ── Urge trend: earlier check-in days vs later ones, in order
    trend = None
    day_averages = [sum(daily[d]) / len(daily[d]) for d in sorted(daily)]
    if len(day_averages) >= MIN_DAYS_FOR_TREND:
        half = len(day_averages) // 2
        earlier = sum(day_averages[:half]) / half
        later = sum(day_averages[-half:]) / half
        if later - earlier <= -URGE_TREND_THRESHOLD:
            trend = "lower"
        elif later - earlier >= URGE_TREND_THRESHOLD:
            trend = "higher"
        else:
            trend = "steady"

    # Did the urge go up from one check-in day to the next at least once?
    urge_rose = any(later > earlier for earlier, later in zip(day_averages, day_averages[1:]))

    # ── Mood per category
    moods_by_category: dict[str, list[str]] = defaultdict(list)
    for row in records["moods"]:
        moods_by_category[row["category"]].append(row["mood_change"])
    better_total = sum(1 for row in records["moods"] if row["mood_change"] in BETTER)
    mood_total = len(records["moods"])

    # ── Main takeaway: one overall fact. The patterns below then add what it
    # didn't say, so the two never repeat each other.
    takeaway, takeaway_topic = _takeaway(
        in_period, check_in_days, completed_total, completed_counts, category_labels,
        trend, better_total, mood_total,
    )

    # ── Patterns you might recognize: heading + supporting sentence
    patterns = _category_patterns(category_labels, moods_by_category, in_period)
    urge_pattern = _urge_pattern(trend, urge_rose, in_period, takeaway_topic == "urge")
    if urge_pattern:
        patterns.append(urge_pattern)
    summary = _summary(check_in_days, completed_total, in_period)
    if summary and takeaway_topic != "check_ins_only":
        patterns.append(summary)

    return InsightsResponse(
        period=period,
        start=start,
        end=end,
        has_data=bool(completed_total or check_in_days),
        check_in_days=check_in_days,
        completed=completed_total,
        urges=urges,
        moods=moods,
        mood_points=mood_points,
        categories=categories,
        takeaway=takeaway,
        # Older app builds show plain sentences: the same items, body only.
        observations=[pattern.body for pattern in patterns],
        patterns=patterns,
    )


# ─────────────────────────────────────────────
# Wording. Every sentence says what the user reported ("was followed by",
# "you reported"), never that an activity caused it, and never that someone
# has healed. Higher urges and harder days are described without judgement.
# ─────────────────────────────────────────────

# Heading, the way the sentence is built, and a gentle closing suggestion for
# a category that was mostly followed by feeling better. Any category the
# catalog adds later falls back to DEFAULT_CATEGORY_PATTERN.
CATEGORY_PATTERNS = {
    "outdoor_movement": ("Getting outside seems to help", "reported",
                         "Stepping outside or moving your body may be worth keeping in your days."),
    "mindfulness_rest": ("Slowing down seems to help", "followed",
                         "Quiet moments to rest may be worth protecting."),
    "solo_exploration": ("Finding comfort in your own company", "reported",
                         "Making time for yourself may be worth continuing."),
    "social_connection": ("Connection seems to help", "followed",
                          "Spending time with people you trust may be worth making room for."),
}
DEFAULT_CATEGORY_PATTERN = ("{label} seems to help", "reported", "It may be worth making room for more of these.")

NUMBER_WORDS = {2: "two", 3: "three", 4: "four", 5: "five", 6: "six", 7: "seven", 8: "eight", 9: "nine", 10: "ten"}


def _mostly_better(better: int, total: int) -> bool:
    """At least two answers, and at least two thirds of them 'a little' or 'much better'."""
    return total >= MIN_MOODS_PER_CATEGORY and better * 3 >= total * 2


def _how_many(better: int, total: int) -> str:
    """'both', 'all three', 'all 12' or '3 of 4'."""
    if better == total:
        return "both" if total == 2 else f"all {NUMBER_WORDS.get(total, str(total))}"
    return f"{better} of {total}"


def _category_patterns(category_labels: dict, moods_by_category: dict, in_period: str) -> list:
    patterns, neutral = [], []
    for key, label in category_labels.items():
        answers = moods_by_category.get(key, [])
        total = len(answers)
        if total < MIN_MOODS_PER_CATEGORY:
            continue   # one answer is not a pattern
        better = sum(1 for a in answers if a in BETTER)
        if _mostly_better(better, total):
            heading, style, suggestion = CATEGORY_PATTERNS.get(key, DEFAULT_CATEGORY_PATTERN)
            amount = _how_many(better, total)
            if style == "followed":
                sentence = f"{amount[0].upper()}{amount[1:]} {label} activities {in_period} were followed by feeling better."
            else:
                sentence = f"You reported feeling better after {amount} {label} activities {in_period}."
            patterns.append(InsightPattern(kind="category", heading=heading.format(label=label),
                                           body=f"{sentence} {suggestion}"))
        else:
            neutral.append((total, label, better))
    # Mixed or not-better results: one gentle note at most (the category with
    # the most answers), so the card never fills up with "it varied".
    if neutral:
        total, label, better = max(neutral, key=lambda item: item[0])
        if better:
            patterns.append(InsightPattern(
                kind="category", heading="Still finding what fits",
                body=f"How you felt after {label} activities {in_period} was mixed. It’s okay to keep exploring.",
            ))
        else:
            patterns.append(InsightPattern(
                kind="category", heading="Not every activity fits every day",
                body=f"The {label} activities you completed {in_period} weren’t followed by feeling better. "
                     "Something different might suit you right now, and that’s okay.",
            ))
    return patterns


def _urge_pattern(trend: str | None, urge_rose: bool, in_period: str, takeaway_said_lower: bool):
    if trend == "lower":
        if urge_rose:
            body = (f"Your urge to reach out rose on some days {in_period}, and that’s okay."
                    if takeaway_said_lower else
                    f"Your urge to reach out has generally decreased {in_period}, even though it rose on some days.")
            return InsightPattern(kind="urge", heading="Some days are still harder than others", body=body)
        if takeaway_said_lower:
            return None
        return InsightPattern(kind="urge", heading="Your urge to reach out eased",
                              body=f"Your later check-ins {in_period} had lower urge ratings than your earlier ones.")
    if trend == "higher":
        return InsightPattern(kind="urge", heading="Urges can rise and fall",
                              body=f"Your later check-ins {in_period} had higher urge ratings than your earlier ones. "
                                   "That’s worth noticing, not a setback.")
    if trend == "steady":
        return InsightPattern(kind="urge", heading="Your urge stayed fairly steady",
                              body=f"Your urge ratings {in_period} stayed in a similar range.")
    return None


def _summary(check_in_days: int, completed_total: int, in_period: str):
    """The totals, once, in one short closing line."""
    parts = []
    if check_in_days:
        parts.append(f"checked in on {_plural(check_in_days, 'day')}")
    if completed_total:
        parts.append(f"completed {_plural(completed_total, 'activity', 'activities')}")
    if not parts:
        return None
    return InsightPattern(kind="summary", heading=None, body=f"You {' and '.join(parts)} {in_period}.")


def _takeaway(in_period, check_in_days, completed_total, completed_counts, category_labels,
              trend, better_total, mood_total) -> tuple[Takeaway, str | None]:
    """The most notable supported fact, in this order, and its topic."""
    if not completed_total and not check_in_days:
        return Takeaway(
            headline="Your patterns will appear here.",
            body=f"Check in and finish an activity {in_period}, and what you notice will start to show up here.",
        ), "empty"
    if _mostly_better(better_total, mood_total):
        body = (f"Every activity you completed {in_period} was followed by feeling better than before."
                if better_total == mood_total else
                f"Most activities you completed {in_period} were followed by feeling better than before.")
        return Takeaway(headline="You often felt better afterwards.", body=body), "mood"
    if trend == "lower":
        return Takeaway(
            headline="Your urge to reach out eased.",
            body=f"Your later check-ins {in_period} had lower urge ratings than your earlier ones.",
        ), "urge"
    top = completed_counts.most_common(2)
    if top and top[0][1] >= 2 and (len(top) == 1 or top[0][1] > top[1][1]):
        label = category_labels.get(top[0][0], top[0][0])
        return Takeaway(
            headline=f"{label} stood out.",
            body=f"You made the most time for {label} activities {in_period}.",
        ), "category"
    if completed_total:
        return Takeaway(
            headline="You made time for yourself.",
            body=f"Completing an activity takes effort, and you did it {in_period}. Small steps count.",
        ), "completed"
    return Takeaway(
        headline="You kept checking in.",
        body=f"You checked in on {_plural(check_in_days, 'day')} {in_period}. "
             "Noticing how you feel counts too; an activity can wait until it feels doable.",
    ), "check_ins_only"

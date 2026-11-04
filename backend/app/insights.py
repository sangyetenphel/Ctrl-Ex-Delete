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

    # ── Mood per category
    moods_by_category: dict[str, list[str]] = defaultdict(list)
    for row in records["moods"]:
        moods_by_category[row["category"]].append(row["mood_change"])
    better_total = sum(1 for row in records["moods"] if row["mood_change"] in BETTER)
    mood_total = len(records["moods"])

    # ── Patterns you might recognize
    observations = []
    if completed_total:
        observations.append(f"You completed {_plural(completed_total, 'activity', 'activities')} {in_period}.")
    if check_in_days:
        observations.append(f"You checked in on {_plural(check_in_days, 'day')} {in_period}.")
    if trend == "lower":
        observations.append(f"Your urge to reach out was lower in your later check-ins {in_period} than in the earlier ones.")
    elif trend == "higher":
        observations.append(f"Your urge to reach out was higher in your later check-ins {in_period}. Urges can rise and fall, and that’s okay.")
    elif trend == "steady":
        observations.append(f"Your urge to reach out stayed fairly steady across your check-ins {in_period}.")
    for key, label in category_labels.items():
        answers = moods_by_category.get(key, [])
        better = sum(1 for a in answers if a in BETTER)
        if len(answers) >= MIN_MOODS_PER_CATEGORY and better:
            observations.append(
                f"You reported feeling better after {better} of {len(answers)} {label} activities."
            )

    # ── Main takeaway: the most notable supported fact, in this order
    top = completed_counts.most_common(2)
    if not completed_total and not check_in_days:
        takeaway = Takeaway(
            headline="Your patterns will appear here.",
            body=f"Check in and finish an activity {in_period}, and what you notice will start to show up here.",
        )
    elif top and top[0][1] >= 2 and (len(top) == 1 or top[0][1] > top[1][1]):
        label = category_labels.get(top[0][0], top[0][0])
        takeaway = Takeaway(
            headline=f"{label} stood out.",
            body=f"You completed {top[0][1]} {label} activities {in_period}, more than any other kind.",
        )
    elif trend == "lower":
        takeaway = Takeaway(
            headline="Urges eased a little.",
            body=f"Your later check-ins {in_period} had lower urge ratings than the earlier ones.",
        )
    elif mood_total >= 2 and better_total * 2 >= mood_total:
        takeaway = Takeaway(
            headline="You often felt better afterwards.",
            body=f"After {better_total} of {mood_total} activities {in_period}, you said you felt better than before.",
        )
    elif completed_total:
        takeaway = Takeaway(
            headline="You made time for yourself.",
            body=f"You completed {_plural(completed_total, 'activity', 'activities')} {in_period}. Small steps count.",
        )
    else:
        takeaway = Takeaway(
            headline="You kept checking in.",
            body=f"You checked in on {_plural(check_in_days, 'day')} {in_period}. Try an activity when it feels doable.",
        )

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
        observations=observations,
    )

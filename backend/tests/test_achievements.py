"""
"Your story so far": journey milestones and hidden badges (app/achievements.py).
Unit tests with made-up records, plus one API check through /progress/summary.
"""
from datetime import date, timedelta

from fastapi.testclient import TestClient

from app import achievements
from app.main import app
from tests.conftest import upload_test_photo

client = TestClient(app)

MONDAY = date(2026, 10, 12)


def day(n: int) -> date:
    return MONDAY + timedelta(days=n)


def check_in(n, urge=4, energy="medium", areas=()):
    return {"local_date": day(n), "contact_urge": urge, "energy_level": energy, "hardest_areas": list(areas)}


def completion(n, category="mindfulness_rest", energy="medium", urge=4, areas=()):
    return {"completed_on": day(n), "category": category,
            "energy_level": energy, "contact_urge": urge, "hardest_areas": list(areas)}


def reflection(n, mood="about_the_same", thought="a_little", photo=False, note=True):
    return {"local_date": day(n), "mood_change": mood, "thought_about_ex": thought,
            "has_photo": photo, "has_note": note}


def records(check_ins=(), completions=(), reflections=(), moved_forward_on=None):
    return {"check_ins": list(check_ins), "completions": list(completions),
            "reflections": list(reflections), "moved_forward_on": moved_forward_on}


def badges(recs) -> dict:
    return achievements.earned_badges(recs)


def milestones(recs) -> dict:
    return achievements.reached_milestones(recs)


# ── Milestones ───────────────────────────────

def test_new_user_sees_every_milestone_upcoming_and_no_badges():
    story = achievements.story(records())
    assert [m.label for m in story] == [title for _, title, _ in achievements.MILESTONES]
    assert all(m.reached_on is None and m.kind == "milestone" for m in story)


def test_step_milestones_use_the_nth_completion_day():
    recs = records(completions=[completion(i) for i in range(10)])
    reached = milestones(recs)
    assert reached["first_activity"] == day(0)
    assert reached["first_steps"] == day(4)
    assert reached["more_steps"] == day(9)


def test_showing_up_counts_different_days_not_a_streak():
    days = [0, 2, 5, 9, 10, 14, 20]   # gaps are fine
    reached = milestones(records(check_ins=[check_in(n) for n in days]))
    assert reached["showing_up"] == day(20)
    assert milestones(records(check_ins=[check_in(n) for n in days[:-1]]))["showing_up"] is None


def test_lighter_day_is_three_lower_than_the_first_urge():
    recs = records(check_ins=[check_in(0, urge=8), check_in(1, urge=6), check_in(2, urge=5)])
    assert milestones(recs)["lighter_day"] == day(2)
    assert milestones(records(check_ins=[check_in(0, urge=8), check_in(1, urge=6)]))["lighter_day"] is None


def test_first_photo_and_moving_forward():
    recs = records(reflections=[reflection(0), reflection(3, photo=True)], moved_forward_on=day(9))
    reached = milestones(recs)
    assert reached["first_photo"] == day(3)
    assert reached["moved_forward"] == day(9)


# ── Badges ───────────────────────────────────

def test_jack_of_all_trades_on_the_day_the_fourth_kind_is_done():
    recs = records(completions=[
        completion(0, "mindfulness_rest"), completion(1, "mindfulness_rest"),
        completion(2, "outdoor_movement"), completion(3, "solo_exploration"),
        completion(5, "social_connection"),
    ])
    assert badges(recs)["jack_of_all_trades"] == day(5)
    assert "jack_of_all_trades" not in badges(records(completions=recs["completions"][:4]))


def test_category_badges_need_five_of_one_kind():
    recs = records(completions=[completion(n, "outdoor_movement") for n in range(5)]
                   + [completion(6, "social_connection") for _ in range(4)])
    earned = badges(recs)
    assert earned["outdoor_champ"] == day(4)
    assert "connector" not in earned
    assert "calm_keeper" not in earned


def test_in_control_needs_low_energy_and_a_strong_urge_on_that_check_in():
    assert badges(records(completions=[completion(2, energy="low", urge=7)]))["in_control"] == day(2)
    assert "in_control" not in badges(records(completions=[completion(2, energy="medium", urge=9)]))
    assert "in_control" not in badges(records(completions=[completion(2, energy="low", urge=6)]))


def test_brave_hello_is_social_connection_when_loneliness_was_hardest():
    lonely = ["feeling_lonely"]
    assert badges(records(completions=[completion(1, "social_connection", areas=lonely)]))["brave_hello"] == day(1)
    assert "brave_hello" not in badges(records(completions=[completion(1, "outdoor_movement", areas=lonely)]))
    assert "brave_hello" not in badges(records(completions=[completion(1, "social_connection")]))


def test_reflection_badges():
    better = [reflection(n, mood="a_little_better" if n % 2 else "much_better") for n in range(5)]
    assert badges(records(reflections=better))["feeling_it"] == day(4)
    quiet = [reflection(n, thought="not_really") for n in (1, 3, 8)]
    assert badges(records(reflections=quiet))["quiet_mind"] == day(8)
    stories = [reflection(n) for n in range(10)]
    assert badges(records(reflections=stories))["storyteller"] == day(9)
    assert "storyteller" not in badges(records(reflections=[reflection(n, note=False) for n in range(10)]))


def test_back_again_after_a_week_away_and_sunday_reset():
    assert badges(records(check_ins=[check_in(0), check_in(7)]))["back_again"] == day(7)
    assert "back_again" not in badges(records(check_ins=[check_in(0), check_in(6)]))
    sunday = MONDAY + timedelta(days=6)
    assert sunday.weekday() == 6
    assert badges(records(completions=[completion(2), completion(6)]))["sunday_reset"] == sunday


def test_unearned_badges_are_never_sent():
    story = achievements.story(records(completions=[completion(0)]))
    assert not [m for m in story if m.kind == "badge"]
    all_badge_titles = {title for _, title, _ in achievements.BADGES}
    assert not all_badge_titles & {m.label for m in story}


# ── Order ────────────────────────────────────

def test_story_is_reached_by_date_then_upcoming():
    recs = records(
        check_ins=[check_in(0)],
        completions=[completion(0, "outdoor_movement"), completion(1, "mindfulness_rest"),
                     completion(2, "solo_exploration"), completion(3, "social_connection")],
    )
    story = achievements.story(recs)
    reached = [m for m in story if m.reached_on]
    assert [m.label for m in reached] == ["Started the journey", "Completed a first activity", "Jack of All Trades"]
    assert reached[-1].kind == "badge" and reached[-1].description
    assert all(m.reached_on is None for m in story[len(reached):])
    assert [m.reached_on for m in reached] == sorted(m.reached_on for m in reached)


# ── API ──────────────────────────────────────

def test_summary_sends_kind_and_description(installation_id):
    headers = {"X-Installation-ID": installation_id}
    saved = client.post("/check-ins", headers=headers, json={
        "feeling": "heavy", "contact_urge": 8, "energy_level": "low",
        "hardest_areas": ["resisting_contact"], "local_date": "2026-10-12",
    })
    assert saved.status_code == 201, saved.text
    summary = client.get("/progress/summary", headers=headers).json()
    first = summary["milestones"][0]
    assert first == {
        "label": "Started the journey", "reached_on": "2026-10-12", "kind": "milestone",
        "description": "You checked in for the first time.",
    }
    assert all(m["kind"] == "milestone" for m in summary["milestones"])


def test_badge_earned_through_the_real_flow(installation_id, fake_s3):
    # Low energy and a strong urge, then an activity completed: "In Control".
    uploaded, _ = fake_s3
    headers = {"X-Installation-ID": installation_id}
    client.post("/check-ins", headers=headers, json={
        "feeling": "missing_them", "contact_urge": 9, "energy_level": "low",
        "hardest_areas": ["resisting_contact"], "local_date": "2026-10-13",
    })
    card = client.get("/recommendations/latest", headers=headers).json()["recommendations"][0]
    selection = client.post(f"/recommendations/{card['id']}/selection", headers=headers).json()
    saved = client.post("/reflections", headers=headers, json={
        "activity_selection_id": selection["id"], "local_date": "2026-10-13",
        "thought_about_ex": "not_really", "mood_change": "a_little_better",
        "note": "Walked it off", "photo_id": upload_test_photo(client, installation_id, uploaded),
    })
    assert saved.status_code == 201, saved.text

    story = client.get("/progress/summary", headers=headers).json()["milestones"]
    badge = next(m for m in story if m["kind"] == "badge")
    assert badge["label"] == "In Control" and badge["reached_on"] == "2026-10-13"

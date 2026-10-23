"""GET /progress/bookshelf: one book per completed activity, earliest first, at most 32."""
from datetime import date, timedelta

from fastapi.testclient import TestClient

from app.main import app
from tests.conftest import upload_test_photo

client = TestClient(app)
START = date(2026, 9, 1)


def headers(installation_id):
    return {"X-Installation-ID": installation_id}


def shelf(installation_id):
    response = client.get("/progress/bookshelf", headers=headers(installation_id))
    assert response.status_code == 200
    return response.json()


def check_in(installation_id, day: int):
    local_date = str(START + timedelta(days=day))
    assert client.post("/check-ins", headers=headers(installation_id), json={
        "feeling": "hopeful", "contact_urge": 3, "energy_level": "medium", "hardest_areas": [],
        "local_date": local_date}).status_code == 201
    return local_date


def choose(installation_id, card_index=0):
    cards = client.get("/recommendations/latest", headers=headers(installation_id)).json()["recommendations"]
    card = [c for c in cards if c["status"] is None][card_index]
    selection = client.post(f"/recommendations/{card['id']}/selection", headers=headers(installation_id)).json()
    return card, selection


def reflect(installation_id, uploaded, selection_id, local_date):
    return client.post("/reflections", headers=headers(installation_id), json={
        "activity_selection_id": selection_id, "thought_about_ex": "a_little", "mood_change": "a_little_better",
        "note": "A quiet moment", "local_date": local_date, "photo_id": upload_test_photo(client, installation_id, uploaded)})


def complete(installation_id, uploaded, day: int):
    local_date = check_in(installation_id, day)
    card, selection = choose(installation_id)
    assert reflect(installation_id, uploaded, selection["id"], local_date).status_code == 201
    return card, selection


def test_a_new_user_has_an_empty_shelf(installation_id):
    assert shelf(installation_id) == {"capacity": 32, "total_completed": 0, "books": []}


def test_only_a_saved_reflection_earns_a_book(installation_id, fake_s3):
    uploaded, _ = fake_s3
    local_date = check_in(installation_id, 0)                     # checking in: no book
    card, selection = choose(installation_id)                     # "I'll try this": no book
    client.put(f"/bookmarks/{card['activity']['id']}", headers=headers(installation_id))   # saving: no book
    assert shelf(installation_id)["books"] == []

    assert reflect(installation_id, uploaded, selection["id"], local_date).status_code == 201
    books = shelf(installation_id)["books"]
    assert [(b["selection_id"], b["category"], b["completed_on"]) for b in books] == [
        (selection["id"], card["activity"]["category"], local_date)]


def test_a_repeated_submission_adds_no_second_book(installation_id, fake_s3):
    uploaded, _ = fake_s3
    _, selection = complete(installation_id, uploaded, 0)
    again = reflect(installation_id, uploaded, selection["id"], str(START))
    assert again.status_code == 200                                # the first memory comes back
    assert shelf(installation_id)["total_completed"] == 1


def test_changing_activity_earns_nothing_and_a_deleted_memory_keeps_its_book(installation_id, fake_s3):
    uploaded, _ = fake_s3
    check_in(installation_id, 0)
    _, abandoned = choose(installation_id)
    client.post(f"/activity-selections/{abandoned['id']}/abandon", headers=headers(installation_id))
    assert shelf(installation_id)["books"] == []

    _, kept = complete(installation_id, uploaded, 1)
    memory = client.get("/reflections", headers=headers(installation_id)).json()[0]
    client.delete(f"/reflections/{memory['id']}", headers=headers(installation_id))
    assert [b["selection_id"] for b in shelf(installation_id)["books"]] == [kept["id"]]


def test_books_keep_their_order_and_repeats_earn_new_books(installation_id, fake_s3):
    uploaded, _ = fake_s3
    first_card, first = complete(installation_id, uploaded, 0)
    _, second = complete(installation_id, uploaded, 1)
    # The same activity again on a later day (if it's offered) is a new book.
    local_date = check_in(installation_id, 5)
    cards = client.get("/recommendations/latest", headers=headers(installation_id)).json()["recommendations"]
    card = next((c for c in cards if c["activity"]["id"] == first_card["activity"]["id"] and c["status"] is None), cards[0])
    third = client.post(f"/recommendations/{card['id']}/selection", headers=headers(installation_id)).json()
    reflect(installation_id, uploaded, third["id"], local_date)

    ids = [b["selection_id"] for b in shelf(installation_id)["books"]]
    assert ids == [first["id"], second["id"], third["id"]]
    assert [b["selection_id"] for b in shelf(installation_id)["books"]] == ids     # stable on every read


def test_the_shelf_holds_32_and_keeps_counting(installation_id, fake_s3):
    uploaded, _ = fake_s3
    selections = [complete(installation_id, uploaded, day)[1]["id"] for day in range(33)]
    body = shelf(installation_id)
    assert body["total_completed"] == 33
    assert [b["selection_id"] for b in body["books"]] == selections[:32]       # the first 32 stay put
    # A full shelf changes nothing else: the next day still works as usual.
    local_date = check_in(installation_id, 40)
    _, selection = choose(installation_id)
    assert reflect(installation_id, uploaded, selection["id"], local_date).status_code == 201
    assert client.put("/moving-forward", headers=headers(installation_id), json={
        "reflected_on": ["without_overwhelm", "own_routines", "urge_manageable", "connected_to_self",
                         "ready_not_pressured"], "local_date": local_date}).status_code == 201


def test_each_installation_has_its_own_shelf(installation_id, other_installation_id, fake_s3):
    uploaded, _ = fake_s3
    complete(installation_id, uploaded, 0)
    assert shelf(other_installation_id)["books"] == []

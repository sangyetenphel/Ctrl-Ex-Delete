from datetime import date, datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, Field, model_validator

# Allowed values. These must match db/migrations and the Swift app exactly.
Feeling = Literal["heavy", "getting_through", "missing_them", "hopeful"]
EnergyLevel = Literal["low", "medium", "high"]
HardestArea = Literal[
    "feeling_lonely",
    "missing_relationship",
    "wanting_answers",
    "resisting_contact",
    "rebuilding_confidence",
]
ActivityCategory = Literal[
    "outdoor_movement", "mindfulness_rest", "solo_exploration", "social_connection"
]
# Reflection answers, stored exactly as the user chose them.
ThoughtAboutEx = Literal["not_really", "a_little", "a_lot"]
MoodChange = Literal["worse", "about_the_same", "a_little_better", "much_better"]
# An "I'll try this" choice: in progress until its reflection is saved
# (completed) or the user picks "Change activity" (abandoned).
SelectionStatus = Literal["in_progress", "completed", "abandoned"]
# The moving-forward reflection questions, in the order the app shows them.
MovingForwardQuestion = Literal[
    "without_overwhelm",     # Can you think about the relationship without feeling overwhelmed?
    "own_routines",          # Are you building routines that don't include your ex?
    "urge_manageable",       # Has the urge to contact them become manageable?
    "connected_to_self",     # Do you feel more connected to yourself?
    "ready_not_pressured",   # Are you choosing to move forward because you feel ready, not pressured?
]


# ─────────────────────────────────────────────
# Check-ins
# ─────────────────────────────────────────────

class CheckInCreate(BaseModel):
    """What the iOS app SENDS when the user taps 'Enter my room'."""
    feeling: Feeling
    contact_urge: int = Field(ge=1, le=10)
    energy_level: EnergyLevel
    hardest_areas: list[HardestArea] = Field(default_factory=list)
    local_date: date

    @model_validator(mode="after")
    def _each_area_once(self):
        # Each area adds weight to the recommendations, so a repeat must not count twice.
        self.hardest_areas = list(dict.fromkeys(self.hardest_areas))
        return self


class RoomMessage(BaseModel):
    """Ced's message in the healing room (catalog id, pattern and the text shown)."""
    id: str
    pattern: str
    text: str


class CheckIn(CheckInCreate):
    """What the API SENDS BACK: the saved check-in plus server-made fields."""
    id: int
    installation_id: UUID
    created_at: datetime
    # Ced's message for this check-in (POST /check-ins and GET /check-ins/today).
    # Chosen once and kept, so it's the same every time the room opens.
    room_message: RoomMessage | None = None
    # How many activities the user completed on this check-in's local day
    # (POST /check-ins and GET /check-ins/today; null elsewhere). The room
    # invites them to try one while it's 0. Counted from completions, so
    # deleting a memory doesn't change it.
    activities_completed_today: int | None = None


class InstallationMarker(BaseModel):
    """
    Which server-side record this installation ID currently has. It changes
    only when the installation is reset (scripts/reset_installation.py deletes
    the row; the next write creates a new one), so the app can tell that its
    on-phone copies of the journey are out of date. Only ever about the
    caller's own installation; nothing personal.
    """
    exists: bool                       # false until the first write, and after a reset
    created_at: datetime | None = None


class CheckInStatus(BaseModel):
    """
    GET /check-ins/today: has the user checked in on their local day?
    The app asks on startup, before choosing the welcome, check-in or room screen.
    """
    local_date: date
    check_in: CheckIn | None      # that day's check-in, or null if there isn't one yet
    has_any_check_in: bool        # false for someone who has never checked in
    # Ced's room message: the check-in's assigned one, or a "let's check in"
    # message when there's no check-in yet today (null only if none could load).
    room_message: RoomMessage | None = None
    installation: InstallationMarker | None = None


# ─────────────────────────────────────────────
# Activities and recommendations
# ─────────────────────────────────────────────

class Activity(BaseModel):
    """One activity from the catalog, with everything a card shows."""
    id: int
    slug: str
    title: str
    category: ActivityCategory
    # The category's display name, e.g. "Mindfulness & Rest", from
    # activity_categories (the one place it's stored).
    category_label: str
    # Overall demand (physical, cognitive, social, preparation), separate from
    # duration; a check-in's energy decides which levels are recommended.
    energy_level: EnergyLevel
    duration_minutes: int
    instructions: str
    why_it_fits: str


class Recommendation(BaseModel):
    """One suggested activity for one check-in."""
    id: int
    position: int
    activity: Activity
    is_saved: bool = False                 # bookmarked with "Save for later"
    status: SelectionStatus | None = None  # null = not chosen (or abandoned)
    selected_at: datetime | None = None
    completed_at: datetime | None = None   # set once its reflection is saved


class CheckInAnswers(BaseModel):
    """The answers the recommendations were chosen from (shown as the page heading)."""
    feeling: Feeling
    contact_urge: int
    energy_level: EnergyLevel
    hardest_areas: list[HardestArea]


class RecommendationsResponse(BaseModel):
    """
    Recommendations for the installation's most recent check-in.
    check_in_id and check_in are null (and the list is empty) if there are no
    check-ins yet.
    """
    check_in_id: int | None
    check_in_local_date: date | None
    check_in: CheckInAnswers | None = None
    recommendations: list[Recommendation]


class ActivitySelection(BaseModel):
    """What the API SENDS BACK after the user taps 'I'll try this'."""
    id: int
    recommendation_id: int
    activity_id: int
    check_in_id: int
    status: SelectionStatus
    selected_at: datetime
    ended_at: datetime | None


class SelectedActivity(BaseModel):
    """The activity in progress: chosen with "I'll try this", not yet finished."""
    selection_id: int
    recommendation_id: int
    check_in_id: int
    selected_at: datetime
    activity: Activity


class CurrentSelectionResponse(BaseModel):
    """The activity in progress, or null."""
    selection: SelectedActivity | None


# ─────────────────────────────────────────────
# Scrapbook
# ─────────────────────────────────────────────

class PhotoUpload(BaseModel):
    """What the API SENDS BACK: where to PUT the JPEG."""
    id: int
    upload_url: str


class ScrapbookPhoto(BaseModel):
    """One uploaded photo. image_url is temporary (about 1 hour)."""
    id: int
    created_at: datetime
    image_url: str


# ─────────────────────────────────────────────
# Reflections (scrapbook memories)
# ─────────────────────────────────────────────

class ReflectionCreate(BaseModel):
    """
    What the iOS app SENDS from "Add to my scrapbook". Saving it completes the
    activity in progress. Everything is required: the two questions, the note
    ("What did you notice?", not blank) and an uploaded photo of this
    installation (see POST /scrapbook/photos; storage.py checks the photo).
    """
    activity_selection_id: int
    thought_about_ex: ThoughtAboutEx
    mood_change: MoodChange
    note: str | None = Field(default=None, max_length=1000)
    # Older app builds asked a second question and sent it as `noticed`.
    # It's still accepted so their text isn't lost, and joined into `note`.
    noticed: str | None = Field(default=None, max_length=1000, deprecated=True, exclude=True)
    photo_id: int
    local_date: date

    @model_validator(mode="after")
    def _note_is_required(self):
        note = (self.note or "").strip()
        extra = (self.__dict__.get("noticed") or "").strip()
        if extra:
            note = extra if not note or note == extra else f"{note}\n\n{extra}"
        self.__dict__["noticed"] = None
        if not note:
            raise ValueError("Please write what you noticed.")
        self.note = note
        return self


class Reflection(BaseModel):
    """One saved memory. image_url is temporary (about 1 hour)."""
    id: int
    activity_selection_id: int | None
    activity: Activity | None
    note: str | None              # the answer to "What did you notice?"
    thought_about_ex: ThoughtAboutEx | None
    mood_change: MoodChange | None
    local_date: date
    created_at: datetime          # when it was saved (= completed, with a selection)
    photo_id: int | None
    image_url: str | None


# ─────────────────────────────────────────────
# Bookmarks ("Save for later")
# ─────────────────────────────────────────────

class Bookmark(BaseModel):
    activity: Activity
    saved_at: datetime


# ─────────────────────────────────────────────
# Progress
# ─────────────────────────────────────────────

class Milestone(BaseModel):
    label: str
    reached_on: date | None   # null = not reached yet


class ShelfBook(BaseModel):
    """One book on the room's bookshelf: one completed activity."""
    selection_id: int
    category: ActivityCategory     # colours the book
    completed_on: date


class Bookshelf(BaseModel):
    """
    GET /progress/bookshelf: the user's completed activities, earliest first,
    one book each (at most `capacity`). total_completed keeps counting past
    the shelf's size; nothing else depends on it.
    """
    capacity: int
    total_completed: int
    books: list[ShelfBook]


class ProgressSummary(BaseModel):
    journey_started_on: date | None   # local date of the first check-in
    check_ins: int
    activities_selected: int
    activities_completed: int         # reflections linked to an activity
    memories: int                     # all reflections
    photos: int                       # reflections with a photo
    milestones: list[Milestone]


# ─────────────────────────────────────────────
# Insights (the Progress screen)
# ─────────────────────────────────────────────

class UrgePoint(BaseModel):
    """One bar: a day (week view) or a seven-day week of the user's journey (month view)."""
    label: str                 # "Mon" … "Sun", or "W1", "W2", …
    start: date
    end: date
    value: int | None          # average urge (1–10); null = no check-in
    check_ins: int


class MoodPoint(BaseModel):
    """
    One bar of "Mood after activities": a day (week view) or a seven-day week
    of the user's journey (month view). `value` is the average of the internal
    scores of the answers given then (see insights.MOOD_SCORES), only for
    sizing the bar; it is not a rating the user entered. null = no completed
    activity.
    """
    label: str                 # "Mon" … "Sun", or "W1", "W2", …
    start: date
    end: date
    value: float | None        # 1–10 scale, one decimal; null = gap
    answers: list[MoodChange]  # the answers behind the bar, in the order given


class MoodCount(BaseModel):
    """How often an answer to "How do you feel now compared to before?" was given."""
    response: MoodChange
    label: str
    count: int


class CategoryShare(BaseModel):
    category: ActivityCategory
    label: str
    count: int                 # completed activities only
    percent: int               # of all completed activities in the period


class Takeaway(BaseModel):
    headline: str
    body: str


class InsightsResponse(BaseModel):
    period: Literal["week", "month"]
    start: date
    end: date
    has_data: bool             # false = show the empty state
    check_in_days: int
    completed: int
    urges: list[UrgePoint]
    moods: list[MoodCount]     # how often each answer was given (totals)
    mood_points: list[MoodPoint] = []
    categories: list[CategoryShare]
    takeaway: Takeaway
    observations: list[str]


# ─────────────────────────────────────────────
# Moving forward and the farewell scrapbook
# ─────────────────────────────────────────────

class MovingForwardSave(BaseModel):
    """
    What the app SENDS when the user chooses "I'm ready to move forward".
    All five readiness questions must be ticked, like the app requires.
    """
    reflected_on: list[MovingForwardQuestion]
    local_date: date                     # the user's calendar day

    @model_validator(mode="after")
    def all_questions_ticked(self):
        order = list(MovingForwardQuestion.__args__)
        missing = [question for question in order if question not in self.reflected_on]
        if missing:
            raise ValueError(f"All five readiness questions must be ticked (missing: {', '.join(missing)}).")
        self.reflected_on = order        # each once, in the app's order
        return self


class MovingForward(BaseModel):
    reflected_on: list[MovingForwardQuestion]
    moved_forward_on: date        # the day they first chose to move forward
    updated_at: datetime


class MovingForwardResponse(BaseModel):
    moving_forward: MovingForward | None   # null = not chosen yet


class FarewellMemory(BaseModel):
    """A saved reflection, as written. image_url is temporary (about 1 hour)."""
    id: int
    note: str | None
    thought_about_ex: ThoughtAboutEx | None
    mood_change: MoodChange | None
    local_date: date
    created_at: datetime
    photo_id: int | None
    image_url: str | None


class FarewellActivity(BaseModel):
    """A completed activity, with its memory if one is still saved."""
    selection_id: int
    activity: Activity
    completed_on: date
    memory: FarewellMemory | None


class FarewellCheckIn(BaseModel):
    id: int
    local_date: date
    feeling: Feeling
    contact_urge: int
    energy_level: EnergyLevel
    hardest_areas: list[HardestArea]


class FarewellScrapbook(BaseModel):
    """
    GET /farewell-scrapbook: the installation's whole saved journey, oldest
    first, for the keepsake PDF the app makes. Nothing is summarised or left
    out here; the app lets the user exclude entries from their copy.
    """
    journey_started_on: date | None    # first check-in
    journey_last_on: date | None       # latest dated record of any kind
    check_ins: list[FarewellCheckIn]
    completed_activities: list[FarewellActivity]
    other_memories: list[FarewellMemory]   # memories not tied to a completed activity
    moving_forward: MovingForward | None


# ─────────────────────────────────────────────
# Affirmations ("Grow with Kindness" plant game)
# ─────────────────────────────────────────────

AffirmationTheme = Literal["self_kindness", "identity_values", "small_steps", "boundaries", "acceptance"]


class Affirmation(BaseModel):
    """One sentence the game shows. Editorial notes and sources stay out of this."""
    id: str                      # stable; the app bundles the same ids
    text: str
    theme: AffirmationTheme
    theme_label: str


class AffirmationsResponse(BaseModel):
    language: str
    affirmations: list[Affirmation]


# ─────────────────────────────────────────────
# Ced (AI chat). Nothing here is stored.
# ─────────────────────────────────────────────

class CedTurn(BaseModel):
    """One message of the conversation the app is showing."""
    role: Literal["user", "assistant"]
    content: str = Field(min_length=1, max_length=2000)


class CedChatRequest(BaseModel):
    """
    The conversation so far, ending with the user's new message. The app
    keeps it in memory only while the chat is open; the server never stores
    it. "unsent_message": the first message was written on the "Say it here
    first" screen (words for the ex that were NOT sent).
    """
    messages: list[CedTurn] = Field(min_length=1, max_length=40)
    mode: Literal["chat", "unsent_message"] = "chat"
    # The user's local calendar day, so Ced knows whether a check-in is from
    # today. Optional: older apps don't send it (then nothing counts as today).
    local_date: date | None = None


class CedChatResponse(BaseModel):
    """
    Ced's reply as 1–3 chat bubbles, shown in order.

    risk: how serious the latest message was (patterns and the model's own
      read combined; the more serious wins).
    support: crisis resources to show right under the reply. "crisis" = 988
      first (911 for immediate danger), "danger" = 911 first. The app shows
      them in the chat and never opens anything by itself.
    source: "ai" (written by the model) or "fallback" (a fixed, human-written
      reply used when the model couldn't be reached for a crisis message).
    """
    messages: list[str] = Field(min_length=1, max_length=3)
    risk: Literal["none", "distress", "harm_to_others", "self_harm", "in_danger", "violence"]
    support: Literal["crisis", "danger"] | None
    source: Literal["ai", "fallback"]

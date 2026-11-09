import Foundation

// Codable types that match the JSON in docs/api.md.
// APIClient converts camelCase here to the API's snake_case automatically
// (contactUrge <-> contact_urge). Dates stay as Strings for now, as the doc suggests.

// MARK: - Check-ins

/// Body of `POST /check-ins`.
struct CheckInRequest: Encodable {
    let feeling: Emotion
    let contactUrge: Int
    let energyLevel: EnergyLevel
    let hardestAreas: [HardestArea]
    let localDate: String   // "YYYY-MM-DD", the user's calendar day
}

/// Response of `POST /check-ins` (201): the saved check-in.
struct CheckInResponse: Codable {
    let id: Int
    let installationId: UUID
    let feeling: String
    let contactUrge: Int
    let energyLevel: String
    let hardestAreas: [String]
    let localDate: String
    let createdAt: String
    /// Ced's room message for this check-in (chosen once, then kept).
    let roomMessage: RoomMessageDTO?
    /// Activities completed on this check-in's local day (POST /check-ins and
    /// GET /check-ins/today; nil from an older backend).
    let activitiesCompletedToday: Int?
}

/// Ced's message in the healing room, chosen by the backend's rules.
struct RoomMessageDTO: Codable, Equatable {
    let id: String
    let pattern: String
    let text: String
}

// MARK: - Recommendations

/// Response of `GET /check-ins/today`: has the user checked in on their local day?
struct CheckInStatusDTO: Decodable {
    let localDate: String
    let checkIn: CheckInResponse?   // nil = not yet today
    let hasAnyCheckIn: Bool         // false for someone who has never checked in
    /// Today's room message: the check-in's, or a "let's check in" one before it.
    let roomMessage: RoomMessageDTO?
    /// Which server record this installation ID has (nil from an older backend).
    let installation: InstallationMarkerDTO?
}

/// `installation` in `GET /check-ins/today`: changes only when the installation is reset.
struct InstallationMarkerDTO: Decodable {
    let exists: Bool
    let createdAt: String?
}

/// Response of `GET /recommendations/latest`.
/// `checkInId` and `checkIn` are nil when this installation hasn't checked in yet.
struct RecommendationsResponse: Decodable {
    let checkInId: Int?
    let checkInLocalDate: String?
    let checkIn: CheckInAnswersDTO?     // the answers these cards were chosen from
    let recommendations: [RecommendationDTO]
}

/// The check-in answers behind a set of recommendations.
struct CheckInAnswersDTO: Decodable {
    let feeling: Emotion
    let contactUrge: Int
    let energyLevel: EnergyLevel
    let hardestAreas: [HardestArea]
}

struct RecommendationDTO: Decodable {
    let id: Int
    let position: Int
    let activity: ActivityDTO
    let isSaved: Bool           // bookmarked with "Save for later"
    let status: SelectionStatus?  // nil = not chosen (or the attempt was abandoned)
    let selectedAt: String?
    let completedAt: String?    // set once its reflection was saved
}

/// An "I'll try this" choice: in progress until its reflection is saved
/// (completed) or the user picks "Change activity" (abandoned).
enum SelectionStatus: String, Decodable {
    case inProgress = "in_progress"
    case completed
    case abandoned
}

struct ActivityDTO: Codable {
    let id: Int
    let slug: String
    let title: String
    let category: String        // e.g. "mindfulness_rest"
    let categoryLabel: String   // e.g. "Mindfulness & Rest"
    let durationMinutes: Int
    let instructions: String
    let whyItFits: String
}

/// Response of `POST /recommendations/{id}/selection` and `.../abandon`.
struct ActivitySelectionResponse: Decodable {
    let id: Int
    let recommendationId: Int
    let activityId: Int
    let checkInId: Int
    let status: SelectionStatus
    let selectedAt: String
    let endedAt: String?
}

/// Response of `GET /activity-selections/current`.
/// `selection` is nil when no activity is in progress.
struct CurrentSelectionResponse: Decodable {
    let selection: SelectedActivityDTO?
}

/// The activity in progress.
struct SelectedActivityDTO: Codable {
    let selectionId: Int
    let recommendationId: Int
    let checkInId: Int
    let selectedAt: String
    let activity: ActivityDTO
}

// MARK: - Scrapbook

/// Response of `POST /scrapbook/photos`: where to PUT the JPEG.
struct PhotoUploadTicket: Decodable {
    let id: Int
    let uploadUrl: URL
}

/// One uploaded photo. `imageUrl` is temporary, so don't store it.
struct ScrapbookPhotoDTO: Decodable, Identifiable {
    let id: Int
    let createdAt: String
    let imageUrl: URL
}

// MARK: - Reflections (scrapbook memories)

/// Body of `POST /reflections` ("Add to my scrapbook"): completes the activity
/// in progress. Everything is required: both answers, the note ("What did
/// you notice?", not blank) and the id of a photo already uploaded to S3.
struct ReflectionRequest: Encodable {
    let activitySelectionId: Int
    let thoughtAboutEx: ThoughtAboutEx
    let moodChange: MoodChange
    let note: String
    let photoId: Int
    let localDate: String
}

/// One saved memory. `imageUrl` is temporary (about an hour), so don't store it.
struct ReflectionDTO: Codable, Identifiable {
    let id: Int
    let activitySelectionId: Int?
    let activity: ActivityDTO?
    let note: String?           // the answer to "What did you notice?"
    let thoughtAboutEx: ThoughtAboutEx?
    let moodChange: MoodChange?
    let localDate: String
    let createdAt: String       // when it was saved (= completed, with a selection)
    let photoId: Int?
    let imageUrl: URL?
}

// MARK: - Bookmarks

/// One activity saved with "Save for later".
struct BookmarkDTO: Decodable {
    let activity: ActivityDTO
    let savedAt: String
}

// MARK: - Progress

/// Response of `GET /progress/summary`.
struct ProgressSummaryDTO: Codable {
    let journeyStartedOn: String?   // "YYYY-MM-DD" of the first check-in
    let checkIns: Int
    let activitiesSelected: Int
    let activitiesCompleted: Int
    let memories: Int
    let photos: Int
    let milestones: [MilestoneDTO]
}

struct MilestoneDTO: Codable {
    let label: String
    let reachedOn: String?          // nil = not reached yet
}

// MARK: - Insights

/// Response of `GET /insights?period=week|month&today=YYYY-MM-DD`.
/// Everything is calculated by the backend from this installation's records.
struct InsightsDTO: Decodable {
    let period: String
    let start: String
    let end: String
    let hasData: Bool
    let checkInDays: Int
    let completed: Int
    let urges: [UrgePointDTO]
    let moodPoints: [MoodPointDTO]?     // the mood chart; nil from an older backend
    let categories: [CategoryShareDTO]
    let takeaway: TakeawayDTO
    let observations: [String]
}

struct UrgePointDTO: Decodable {
    let label: String       // "Mon" or "W1"
    let start: String       // "YYYY-MM-DD", the bar's first day
    let value: Int?         // average urge 1–10; nil = no check-in
    let checkIns: Int
}

/// One bar of "Mood after activities". `value` is the backend's average of
/// fixed internal scores, used only for the bar's height; it is not a rating
/// the user gave, so the app never shows it. nil = a gap (no answers).
struct MoodPointDTO: Decodable {
    let label: String       // "Mon" or "W1"
    let start: String       // "YYYY-MM-DD"
    let value: Double?      // 1–10
    let answers: [MoodChange]
}

struct CategoryShareDTO: Decodable {
    let category: String
    let label: String
    let count: Int
    let percent: Int
}

struct TakeawayDTO: Decodable {
    let headline: String
    let body: String
}

// MARK: - Ced

/// Body of `POST /ced/messages`: the conversation so far, ending with the
/// user's new message. Kept only in memory while the chat is open; the
/// server never stores it.
struct CedChatRequest: Encodable {
    struct Turn: Encodable {
        let role: String        // "user" or "assistant"
        let content: String
    }
    let messages: [Turn]
    let mode: String            // "chat" or "unsent_message"
}

/// Response of `POST /ced/messages`: Ced's reply as 1–3 chat bubbles.
struct CedChatResponse: Decodable {
    let messages: [String]
    let risk: String            // "none", "distress", "harm_to_others", "self_harm", "in_danger", "violence"
    let support: CrisisSupport? // resources to show under the reply (never opened automatically)
    let source: String          // "ai", or "fallback" (fixed reply when the AI couldn't be reached)
}

/// Which crisis resources to show under Ced's reply.
enum CrisisSupport: String, Decodable {
    case crisis     // thoughts of self-harm: 988 first, 911 for immediate danger
    case danger     // immediate danger to the user or someone else: 911 first
}

/// For endpoints that answer `204 No Content`.
struct EmptyResponse: Decodable {}

/// FastAPI error bodies look like `{"detail": "..."}` (422s use a list instead).
struct APIErrorBody: Decodable {
    let detail: String
}

// MARK: - Moving forward and the farewell scrapbook

/// The moving-forward reflection questions. Raw values are what the API
/// stores (see docs/api.md); the order is the order on screen.
enum MovingForwardQuestion: String, CaseIterable, Identifiable, Codable {
    case withoutOverwhelm = "without_overwhelm"
    case ownRoutines = "own_routines"
    case urgeManageable = "urge_manageable"
    case connectedToSelf = "connected_to_self"
    case readyNotPressured = "ready_not_pressured"

    var id: String { rawValue }

    var text: String {
        switch self {
        case .withoutOverwhelm: "Can you think about the relationship without feeling overwhelmed?"
        case .ownRoutines: "Are you building routines that don\u{2019}t include your ex?"
        case .urgeManageable: "Has the urge to contact them become manageable?"
        case .connectedToSelf: "Do you feel more connected to yourself?"
        case .readyNotPressured: "Are you choosing to move forward because you feel ready\u{2014}not pressured?"
        }
    }
}

/// `PUT /moving-forward`: saved when the user chooses "I'm ready to move
/// forward", which needs all five questions ticked (the backend checks too).
struct MovingForwardRequest: Encodable {
    let reflectedOn: [MovingForwardQuestion]
    let localDate: String
}

struct MovingForwardDTO: Codable, Equatable {
    let reflectedOn: [MovingForwardQuestion]
    let movedForwardOn: String      // "YYYY-MM-DD", the day they first chose it
    let updatedAt: String
}

/// `GET /farewell-scrapbook`: the whole saved journey, oldest first.
struct FarewellScrapbookDTO: Decodable {
    let journeyStartedOn: String?
    let journeyLastOn: String?
    let completedActivities: [FarewellActivityDTO]
    let otherMemories: [FarewellMemoryDTO]
}

struct FarewellActivityDTO: Decodable, Identifiable {
    let selectionId: Int
    let activity: ActivityDTO
    let completedOn: String
    let memory: FarewellMemoryDTO?
    var id: Int { selectionId }
}

struct FarewellMemoryDTO: Decodable, Identifiable {
    let id: Int
    let note: String?
    let thoughtAboutEx: ThoughtAboutEx?
    let moodChange: MoodChange?
    let localDate: String
    let createdAt: String
    let photoId: Int?
    let imageUrl: URL?          // temporary; refresh with `scrapbookPhoto(id:)`
}

// MARK: - The room's bookshelf

/// `GET /progress/bookshelf`: one book per completed activity, earliest first.
struct BookshelfDTO: Codable, Equatable {
    let capacity: Int
    let totalCompleted: Int
    let books: [ShelfBookDTO]
}

struct ShelfBookDTO: Codable, Equatable, Identifiable {
    let selectionId: Int
    let category: String        // colours the book, like the activity cards
    let completedOn: String
    var id: Int { selectionId }
}

// MARK: - Affirmations ("Grow with Kindness")

/// `GET /affirmations`: the active, curated catalog (same ids as the bundled copy).
struct AffirmationsResponseDTO: Decodable {
    let language: String
    let affirmations: [Affirmation]
}

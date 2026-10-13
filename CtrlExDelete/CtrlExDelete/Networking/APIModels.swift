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
struct CheckInResponse: Decodable {
    let id: Int
    let installationId: UUID
    let feeling: String
    let contactUrge: Int
    let energyLevel: String
    let hardestAreas: [String]
    let localDate: String
    let createdAt: String
}

// MARK: - Recommendations

/// Response of `GET /recommendations/latest`.
/// `checkInId` is nil when this installation hasn't checked in yet.
struct RecommendationsResponse: Decodable {
    let checkInId: Int?
    let checkInLocalDate: String?
    let recommendations: [RecommendationDTO]
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

struct ActivityDTO: Decodable {
    let id: Int
    let slug: String
    let title: String
    let category: String        // e.g. "mindfulness_rest"
    let categoryLabel: String   // e.g. "Gentle Reset"
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
struct SelectedActivityDTO: Decodable {
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
/// in progress. Both questions are required; nil notes/photo are left out.
struct ReflectionRequest: Encodable {
    let activitySelectionId: Int
    let thoughtAboutEx: ThoughtAboutEx
    let moodChange: MoodChange
    let note: String?
    let noticed: String?
    let photoId: Int?
    let localDate: String
}

/// One saved memory. `imageUrl` is temporary (about an hour), so don't store it.
struct ReflectionDTO: Decodable, Identifiable {
    let id: Int
    let activitySelectionId: Int?
    let activity: ActivityDTO?
    let note: String?
    let noticed: String?
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
struct ProgressSummaryDTO: Decodable {
    let journeyStartedOn: String?   // "YYYY-MM-DD" of the first check-in
    let checkIns: Int
    let activitiesSelected: Int
    let activitiesCompleted: Int
    let memories: Int
    let photos: Int
    let milestones: [MilestoneDTO]
}

struct MilestoneDTO: Decodable {
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
    let moods: [MoodCountDTO]
    let categories: [CategoryShareDTO]
    let takeaway: TakeawayDTO
    let observations: [String]
}

struct UrgePointDTO: Decodable {
    let label: String       // "Mon" or "W1"
    let value: Int?         // average urge 1–10; nil = no check-in
    let checkIns: Int
}

struct MoodCountDTO: Decodable {
    let response: MoodChange
    let label: String
    let count: Int
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

/// For endpoints that answer `204 No Content`.
struct EmptyResponse: Decodable {}

/// FastAPI error bodies look like `{"detail": "..."}` (422s use a list instead).
struct APIErrorBody: Decodable {
    let detail: String
}

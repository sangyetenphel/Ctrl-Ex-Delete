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
    let selectedAt: String?
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

/// Response of `POST /recommendations/{id}/selection`.
struct ActivitySelectionResponse: Decodable {
    let id: Int
    let recommendationId: Int
    let activityId: Int
    let checkInId: Int
    let selectedAt: String
}

/// FastAPI error bodies look like `{"detail": "..."}` (422s use a list instead).
struct APIErrorBody: Decodable {
    let detail: String
}

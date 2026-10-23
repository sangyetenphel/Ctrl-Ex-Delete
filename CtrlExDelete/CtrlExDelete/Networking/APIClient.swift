import Foundation

/// Talks to the FastAPI backend with URLSession. Every request carries the
/// anonymous `X-Installation-ID` header. See docs/api.md for the endpoints.
struct APIClient {
    static let shared = APIClient()

    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 20
        session = URLSession(configuration: configuration)

        encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    // MARK: Endpoints

    /// `POST /check-ins`: saves today's check-in. One per local day: if there
    /// already is one for `localDate` (a second tap, a retry), the server
    /// returns that one instead of adding another.
    func submitCheckIn(_ checkIn: CheckInRequest) async throws -> CheckInResponse {
        try await send("POST", "check-ins", body: try encoder.encode(checkIn))
    }

    /// `GET /check-ins/today`: whether the user has checked in on `localDate`
    /// ("YYYY-MM-DD", their own calendar day).
    func checkInStatus(localDate: String) async throws -> CheckInStatusDTO {
        try await send("GET", "check-ins/today", query: [URLQueryItem(name: "local_date", value: localDate)])
    }

    /// `GET /recommendations/latest`: activity cards for the latest check-in.
    func latestRecommendations() async throws -> RecommendationsResponse {
        try await send("GET", "recommendations/latest")
    }

    /// `POST /recommendations/{id}/selection`: "I'll try this" starts the activity
    /// (in progress). The server answers 409 while another one is in progress.
    func selectRecommendation(id: Int) async throws -> ActivitySelectionResponse {
        try await send("POST", "recommendations/\(id)/selection")
    }

    /// `POST /activity-selections/{id}/abandon`: "Change activity". It doesn't
    /// count as completed, and saved memories are untouched.
    func abandonSelection(id: Int) async throws -> ActivitySelectionResponse {
        try await send("POST", "activity-selections/\(id)/abandon")
    }

    /// `PUT` / `DELETE /bookmarks/{activityId}`: "Save for later" on or off.
    /// Never selects the activity. Repeating either call is harmless.
    func setSaved(activityId: Int, _ isSaved: Bool) async throws {
        if isSaved {
            let _: BookmarkDTO = try await send("PUT", "bookmarks/\(activityId)")
        } else {
            let _: EmptyResponse = try await send("DELETE", "bookmarks/\(activityId)")
        }
    }

    /// `GET /activity-selections/current`: the activity in progress.
    func currentSelection() async throws -> SelectedActivityDTO? {
        let response: CurrentSelectionResponse = try await send("GET", "activity-selections/current")
        return response.selection
    }

    /// Uploads one photo: ask the backend for a URL, PUT the JPEG to S3, confirm.
    /// The photo joins a memory afterwards, through `saveReflection(photoId:)`.
    func uploadScrapbookPhoto(jpeg: Data) async throws -> ScrapbookPhotoDTO {
        let ticket: PhotoUploadTicket = try await send("POST", "scrapbook/photos")

        // Straight to S3, not through send(): no X-Installation-ID header,
        // and Content-Type must match what the backend signed.
        var put = URLRequest(url: ticket.uploadUrl)
        put.httpMethod = "PUT"
        put.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        do {
            let (_, response) = try await session.upload(for: put, from: jpeg)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw APIError.unexpectedResponse
            }
        } catch let error as URLError {
            throw APIError(urlError: error)
        }

        return try await send("POST", "scrapbook/photos/\(ticket.id)/complete")
    }

    /// `POST /reflections`: saves a memory and completes its selected activity.
    /// Saving the same selection twice returns the first memory.
    func saveReflection(_ reflection: ReflectionRequest) async throws -> ReflectionDTO {
        try await send("POST", "reflections", body: try encoder.encode(reflection))
    }

    /// `GET /reflections`: every scrapbook memory, newest first.
    func reflections() async throws -> [ReflectionDTO] {
        try await send("GET", "reflections")
    }

    /// `DELETE /reflections/{id}`: removes a memory and its photo (the
    /// activity still counts as completed).
    func deleteReflection(id: Int) async throws {
        let _: EmptyResponse = try await send("DELETE", "reflections/\(id)")
    }

    /// `GET /insights`: the Progress screen for the week or month containing
    /// the user's local `today`.
    func insights(period: InsightsPeriod, today: String) async throws -> InsightsDTO {
        try await send("GET", "insights", query: [
            URLQueryItem(name: "period", value: period.rawValue),
            URLQueryItem(name: "today", value: today),
        ])
    }

    /// `GET /affirmations`: the plant game's catalog (same for everyone).
    func affirmations() async throws -> AffirmationsResponseDTO {
        try await send("GET", "affirmations")
    }

    /// `GET /progress/bookshelf`: the room's books, one per completed activity.
    func bookshelf() async throws -> BookshelfDTO {
        try await send("GET", "progress/bookshelf")
    }

    /// `POST /ced/messages`: Ced's reply to the conversation so far.
    /// AI replies can take a while, so this waits longer than other requests.
    func cedReply(_ request: CedChatRequest) async throws -> CedChatResponse {
        try await send("POST", "ced/messages", body: try encoder.encode(request), timeout: 45)
    }

    /// `GET /progress/summary`: journey start, counts and milestones.
    func progressSummary() async throws -> ProgressSummaryDTO {
        try await send("GET", "progress/summary")
    }

    /// `PUT /moving-forward`: one per user; saving again updates it.
    func saveMovingForward(_ request: MovingForwardRequest) async throws -> MovingForwardDTO {
        try await send("PUT", "moving-forward", body: try encoder.encode(request))
    }

    /// `GET /farewell-scrapbook`: everything the keepsake PDF is made from.
    func farewellScrapbook() async throws -> FarewellScrapbookDTO {
        try await send("GET", "farewell-scrapbook")
    }

    /// `GET /scrapbook/photos/{id}`: a fresh private link for one photo.
    func scrapbookPhoto(id: Int) async throws -> ScrapbookPhotoDTO {
        try await send("GET", "scrapbook/photos/\(id)")
    }

    /// The bytes behind a temporary photo link (no installation header:
    /// the link itself is the permission, like AsyncImage).
    func downloadPhoto(from url: URL) async throws -> Data {
        do {
            let (data, response) = try await session.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty else {
                throw APIError.unexpectedResponse
            }
            return data
        } catch let error as URLError {
            throw APIError(urlError: error)
        }
    }

    // MARK: Shared request code

    private func send<Response: Decodable>(
        _ method: String,
        _ path: String,
        query: [URLQueryItem] = [],
        body: Data? = nil,
        timeout: TimeInterval? = nil
    ) async throws -> Response {
        var url = APIConfig.baseURL.appending(path: path)
        if !query.isEmpty { url.append(queryItems: query) }
        var request = URLRequest(url: url)
        if let timeout { request.timeoutInterval = timeout }
        request.httpMethod = method
        request.setValue(try InstallationID.current().uuidString, forHTTPHeaderField: "X-Installation-ID")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw APIError(urlError: error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.unexpectedResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let detail = try? decoder.decode(APIErrorBody.self, from: data).detail
            throw APIError.server(status: http.statusCode, detail: detail)
        }

        do {
            // 204 No Content has an empty body.
            return try decoder.decode(Response.self, from: data.isEmpty ? Data("{}".utf8) : data)
        } catch {
            throw APIError.unexpectedResponse
        }
    }
}

/// Every way a request can fail, with a message that's safe to show the user.
enum APIError: LocalizedError {
    case offline
    case cannotReachServer
    case timedOut
    case server(status: Int, detail: String?)
    case unexpectedResponse

    init(urlError: URLError) {
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
            self = .offline
        case .timedOut:
            self = .timedOut
        default:
            self = .cannotReachServer
        }
    }

    var errorDescription: String? {
        switch self {
        case .offline:
            return "You seem to be offline. Check your connection and try again."
        case .cannotReachServer:
            #if DEBUG
            if APIConfig.isMisconfiguredForDevice {
                return "This iPhone is set to reach the server at \(APIConfig.baseURL.absoluteString), which is the phone itself. Set your Mac\u{2019}s address in Config/DeveloperSettings.xcconfig and run again from Xcode."
            }
            return "Couldn\u{2019}t reach the server at \(APIConfig.baseURL.absoluteString). Is the backend running, and is this device on the same network as the Mac?"
            #else
            return "We couldn\u{2019}t reach the server. Please try again in a moment."
            #endif
        case .timedOut:
            return "The server is taking too long to respond. Please try again."
        case .server(let status, let detail):
            // These details are written for people, e.g. "Ced needs a short pause."
            if [404, 409, 429, 502, 503, 504].contains(status), let detail { return detail }
            if status >= 500 { return "Something went wrong on our side. Please try again." }
            return "That request wasn\u{2019}t accepted (error \(status)). Please try again."
        case .unexpectedResponse:
            return "The server sent an unexpected response. Please try again."
        }
    }
}

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

    /// `POST /check-ins`: saves today's check-in.
    func submitCheckIn(_ checkIn: CheckInRequest) async throws -> CheckInResponse {
        try await send("POST", "check-ins", body: try encoder.encode(checkIn))
    }

    /// `GET /recommendations/latest`: activity cards for the latest check-in.
    func latestRecommendations() async throws -> RecommendationsResponse {
        try await send("GET", "recommendations/latest")
    }

    /// `POST /recommendations/{id}/selection`: the user tapped "I'll try this".
    func selectRecommendation(id: Int) async throws -> ActivitySelectionResponse {
        try await send("POST", "recommendations/\(id)/selection")
    }

    /// `GET /scrapbook/photos`: uploaded photos, newest first.
    func scrapbookPhotos() async throws -> [ScrapbookPhotoDTO] {
        try await send("GET", "scrapbook/photos")
    }

    /// Uploads one photo: ask the backend for a URL, PUT the JPEG to S3, confirm.
    func uploadScrapbookPhoto(jpeg: Data, caption: String?, localDate: String) async throws -> ScrapbookPhotoDTO {
        let body = try encoder.encode(NewScrapbookPhotoRequest(caption: caption, localDate: localDate))
        let ticket: PhotoUploadTicket = try await send("POST", "scrapbook/photos", body: body)

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

    // MARK: Shared request code

    private func send<Response: Decodable>(
        _ method: String,
        _ path: String,
        body: Data? = nil
    ) async throws -> Response {
        var request = URLRequest(url: APIConfig.baseURL.appending(path: path))
        request.httpMethod = method
        request.setValue(InstallationID.current.uuidString, forHTTPHeaderField: "X-Installation-ID")
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
            return try decoder.decode(Response.self, from: data)
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
            return "Couldn\u{2019}t reach the server at \(APIConfig.baseURL.absoluteString). Is the backend running?"
            #else
            return "We couldn\u{2019}t reach the server. Please try again in a moment."
            #endif
        case .timedOut:
            return "The server is taking too long to respond. Please try again."
        case .server(let status, let detail):
            if status == 503, let detail { return detail }
            if status >= 500 { return "Something went wrong on our side. Please try again." }
            return "That request wasn\u{2019}t accepted (error \(status)). Please try again."
        case .unexpectedResponse:
            return "The server sent an unexpected response. Please try again."
        }
    }
}

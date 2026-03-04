import Foundation
import KuriStore

struct OAuthStartResponse: Decodable {
    let authorizeUrl: URL

    var authorizeURL: URL {
        authorizeUrl
    }
}

struct OAuthCompletion: Sendable {
    let sessionToken: String?
    let status: ConnectionStatus
    let databaseID: String?
    let workspaceName: String?
    let failureReason: String?
}

struct WorkspaceBootstrap: Decodable, Sendable {
    let databaseId: String
    let workspaceName: String
    let connectionStatus: String

    var databaseID: String {
        databaseId
    }

    var status: ConnectionStatus {
        ConnectionStatus(rawValue: connectionStatus) ?? .connected
    }
}

struct NotionConnectionClient {
    let baseURL: URL
    let session: URLSession

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func startOAuth(installationID: String) async throws -> URL {
        let response: OAuthStartResponse = try await postJSON(
            path: "/v1/oauth/notion/start",
            body: StartRequest(installationId: installationID)
        )
        return response.authorizeURL
    }

    func completeOAuth(from callbackURL: URL) async throws -> OAuthCompletion {
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
            throw ConnectionClientError.invalidCallback
        }

        let queryItems: [String: String] = Dictionary(
            uniqueKeysWithValues: components.queryItems?.compactMap { item in
                guard let value = item.value else { return nil }
                return (item.name, value)
            } ?? []
        )
        let status = queryItems["status"] ?? "failed"
        if status != "success" {
            return OAuthCompletion(
                sessionToken: nil,
                status: .actionRequired,
                databaseID: nil,
                workspaceName: nil,
                failureReason: queryItems["reason"]
            )
        }

        return OAuthCompletion(
            sessionToken: queryItems["sessionToken"],
            status: .connected,
            databaseID: queryItems["databaseId"],
            workspaceName: queryItems["workspaceName"],
            failureReason: nil
        )
    }

    func bootstrapWorkspace(sessionToken: String, installationID: String) async throws -> WorkspaceBootstrap {
        try await postJSON(
            path: "/v1/workspaces/bootstrap",
            body: StartRequest(installationId: installationID),
            bearerToken: sessionToken
        )
    }

    private func postJSON<Request: Encodable, Response: Decodable>(
        path: String,
        body: Request,
        bearerToken: String? = nil
    ) async throws -> Response {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let bearerToken {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(Response.self, from: data)
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ConnectionClientError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? ""
            throw ConnectionClientError.http(statusCode: httpResponse.statusCode, message: message)
        }
    }
}

private struct StartRequest: Encodable {
    let installationId: String
}

enum ConnectionClientError: LocalizedError {
    case invalidResponse
    case invalidCallback
    case http(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid server response."
        case .invalidCallback:
            return "Invalid callback URL."
        case let .http(statusCode, message):
            return "Request failed (\(statusCode)): \(message)"
        }
    }
}

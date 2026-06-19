import Foundation

/// Configuration for the GitHub OAuth App used by the device-flow login.
///
/// Only the public `clientID` is needed — the device flow requires **no client
/// secret**, so nothing sensitive is embedded in the binary. The OAuth App must
/// have "Enable Device Flow" turned on at https://github.com/settings/developers.
enum GitHubOAuthConfig {
    static let clientID = "Ov23liBIfzKlrQskIuWA"

    /// Space-separated GitHub scopes. `repo` for private repos + PRs,
    /// `notifications` for the notifications feed.
    static let scopes = "repo notifications"
}

enum GitHubOAuthError: LocalizedError {
    case cancelled
    case expired
    case http(Int)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return Localizer.t(.oauthCancelled)
        case .expired:
            return Localizer.t(.oauthExpired)
        case .http(let code):
            return Localizer.t(.oauthHTTP(code))
        case .server(let message):
            return Localizer.t(.oauthServer(message))
        }
    }
}

/// What `requestDeviceCode()` hands back to the UI.
struct DeviceCodeResponse: Decodable {
    let device_code: String
    let user_code: String
    let verification_uri: String
    let expires_in: Int
    let interval: Int
}

/// Implements GitHub's OAuth **Device Flow**: ask for a device + user code,
/// have the user type the user code at `verification_uri` in any browser, while
/// we poll for the resulting access token. No secret, no redirect, no URL scheme.
actor GitHubDeviceFlow {
    static let shared = GitHubDeviceFlow()

    private let decoder = JSONDecoder()

    /// Step ①: request a device/user code pair.
    func requestDeviceCode() async throws -> DeviceCodeResponse {
        let request = makeRequest(
            url: "https://github.com/login/device/code",
            fields: [
                "client_id": GitHubOAuthConfig.clientID,
                "scope": GitHubOAuthConfig.scopes
            ]
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkStatus(response)
        return try decoder.decode(DeviceCodeResponse.self, from: data)
    }

    /// Step ③: poll until the user authorizes (or the code expires / is denied).
    /// Returns the access token. Honors cancellation via `Task.sleep`.
    func poll(deviceCode: String, interval: Int, expiresIn: Int) async throws -> String {
        var currentInterval = max(interval, 1)
        var elapsed = 0

        while elapsed <= expiresIn {
            try await Task.sleep(nanoseconds: UInt64(currentInterval) * 1_000_000_000)
            elapsed += currentInterval

            let request = makeRequest(
                url: "https://github.com/login/oauth/access_token",
                fields: [
                    "client_id": GitHubOAuthConfig.clientID,
                    "device_code": deviceCode,
                    "grant_type": "urn:ietf:params:oauth:grant-type:device_code"
                ]
            )
            let (data, response) = try await URLSession.shared.data(for: request)
            try checkStatus(response)
            let result = try decoder.decode(PollResponse.self, from: data)

            if let token = result.access_token, !token.isEmpty {
                return token
            }
            switch result.error {
            case "authorization_pending":
                continue
            case "slow_down":
                // GitHub asks us to back off; it sends a new interval.
                currentInterval = result.interval ?? (currentInterval + 5)
            case "expired_token":
                throw GitHubOAuthError.expired
            case "access_denied":
                throw GitHubOAuthError.cancelled
            case .some(let other):
                throw GitHubOAuthError.server(result.error_description ?? other)
            case nil:
                throw GitHubOAuthError.server(Localizer.t(.unknownResponse))
            }
        }
        throw GitHubOAuthError.expired
    }

    // MARK: - Helpers

    private struct PollResponse: Decodable {
        let access_token: String?
        let error: String?
        let error_description: String?
        let interval: Int?
    }

    private func makeRequest(url: String, fields: [String: String]) -> URLRequest {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var body = URLComponents()
        body.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = body.percentEncodedQuery?.data(using: .utf8)
        return request
    }

    private func checkStatus(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw GitHubOAuthError.http(http.statusCode)
        }
    }
}

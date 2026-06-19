import Foundation

/// A GitHub repository identified by "owner/name".
struct Repository: Identifiable, Codable, Hashable {
    let owner: String
    let name: String

    var id: String { fullName }
    var fullName: String { "\(owner)/\(name)" }
    var webURL: URL { URL(string: "https://github.com/\(owner)/\(name)")! }

    init(owner: String, name: String) {
        self.owner = owner
        self.name = name
    }

    /// Parse "owner/name" or a full GitHub URL into a Repository.
    init?(fullName raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // Try to interpret as a URL first (https://github.com/owner/name[.git]).
        if let url = URL(string: trimmed), let host = url.host, host.contains("github.com") {
            let parts = url.path.split(separator: "/").map(String.init)
            if parts.count >= 2 {
                self.owner = parts[0]
                self.name = parts[1].replacingOccurrences(of: ".git", with: "")
                return
            }
        }

        // Otherwise treat it as "owner/name".
        let cleaned = trimmed.replacingOccurrences(of: ".git", with: "")
        let parts = cleaned.split(separator: "/").map(String.init)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        self.owner = parts[0]
        self.name = parts[1]
    }
}

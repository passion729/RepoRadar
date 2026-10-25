import Foundation

/// Where the GitHub token comes from: RepoRadar's own sign-in (Keychain), or the GitHub CLI's login,
/// as t3code does. The CLI's token is never copied: it's asked for again every few minutes, so
/// `gh auth logout` or a new `gh auth login` takes effect here too.
enum Credentials {
    enum Source: String { case keychain, githubCLI }

    static var source: Source {
        get { UserDefaults.standard.string(forKey: "tokenSource").flatMap(Source.init) ?? .keychain }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "tokenSource") }
    }

    /// Cheap enough for views: the CLI counts as signed in until a request says otherwise.
    static var isSignedIn: Bool { source == .githubCLI || Keychain.load() != nil }

    static func token() async -> String? {
        switch source {
        case .keychain: Keychain.load()
        case .githubCLI: await GitHubCLI.shared.token()
        }
    }

    /// After GitHub refuses the token: the CLI's may have changed, so ask it again next time.
    static func invalidate() async {
        if source == .githubCLI { await GitHubCLI.shared.invalidate() }
    }
}

/// The GitHub CLI (`gh`) as a token source.
actor GitHubCLI {
    static let shared = GitHubCLI()

    private var cached: (token: String, at: Date)?
    private static let lifetime: TimeInterval = 5 * 60

    /// Apps opened from the Finder don't get the shell's PATH, so look where gh gets installed.
    nonisolated static var executable: URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh", "\(home)/.local/bin/gh", "\(home)/bin/gh"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
            .map(URL.init(fileURLWithPath:))
    }

    func token() async -> String? {
        if let cached, Date().timeIntervalSince(cached.at) < Self.lifetime { return cached.token }
        guard let output = try? await Self.run(["auth", "token", "--hostname", "github.com"]) else { return nil }
        let token = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return nil }
        cached = (token, Date())
        return token
    }

    func invalidate() { cached = nil }

    /// The active github.com account, or nil when gh isn't installed or isn't signed in.
    nonisolated static func account() async -> String? {
        guard let output = try? await run(["auth", "status", "--hostname", "github.com", "--json", "hosts"]) else { return nil }
        return activeAccount(fromStatusJSON: output)
    }

    /// `gh auth status --json hosts`: the logged-in, active account for github.com.
    nonisolated static func activeAccount(fromStatusJSON json: String) -> String? {
        struct Status: Decodable {
            struct Account: Decodable { let state: String; let active: Bool; let login: String }
            let hosts: [String: [Account]]
        }
        guard let status = try? JSONDecoder().decode(Status.self, from: Data(json.utf8)) else { return nil }
        return status.hosts["github.com"]?.first { $0.active && $0.state == "success" }?.login
    }

    /// Runs gh without prompts or debug output (which could print the token), with a 10 s limit.
    private nonisolated static func run(_ arguments: [String]) async throws -> String {
        guard let executable else { throw GitHubError(message: "The GitHub CLI isn't installed.") }
        return try await Task.detached {
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            var environment = ProcessInfo.processInfo.environment
            environment["GH_PROMPT_DISABLED"] = "1"
            environment["GH_DEBUG"] = ""
            environment["NO_COLOR"] = "1"
            process.environment = environment
            let output = Pipe()
            process.standardOutput = output
            process.standardError = Pipe()
            try process.run()
            let deadline = Date().addingTimeInterval(10)
            while process.isRunning, Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
            if process.isRunning { process.terminate() }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            guard process.terminationStatus == 0 else {
                throw GitHubError(message: "The GitHub CLI isn't signed in to github.com. Run `gh auth login`.")
            }
            return String(decoding: data, as: UTF8.self)
        }.value
    }
}

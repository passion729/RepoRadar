import SwiftUI

/// Search and jump (G5 / N4): repositories, pull requests, issues and workflows from what's already loaded,
/// with `repo:`, `#123` and `author:` filters.
struct JumpQuery: Equatable {
    var repo: String?
    var author: String?
    var number: Int?
    var words: [String] = []

    init(_ text: String) {
        for token in text.split(separator: " ").map(String.init) {
            let lower = token.lowercased()
            if lower.hasPrefix("repo:"), token.count > 5 {
                repo = String(token.dropFirst(5))
            } else if lower.hasPrefix("author:"), token.count > 7 {
                author = String(token.dropFirst(7))
            } else if token.hasPrefix("#"), let number = Int(token.dropFirst()) {
                self.number = number
            } else {
                words.append(token)
            }
        }
    }

    var isEmpty: Bool { repo == nil && author == nil && number == nil && words.isEmpty }
}

struct JumpResult: Identifiable, Hashable {
    enum Target: Hashable {
        case repo(String)
        case pull(PullItem)
        case issue(GitHubNotification)
        case workflow(WorkflowRun)
        case web(URL)
    }

    let target: Target

    var id: String {
        switch target {
        case .repo(let repo): "repo:\(repo)"
        case .pull(let pull): "pull:\(pull.id)"
        case .issue(let note): "issue:\(note.id)"
        case .workflow(let run): "workflow:\(run.repo):\(run.workflowId)"
        case .web(let url): url.absoluteString
        }
    }

    var title: String {
        switch target {
        case .repo(let repo): repo
        case .pull(let pull): pull.title
        case .issue(let note): note.title
        case .workflow(let run): run.workflowName
        case .web(let url): "Open \(url.path.dropFirst()) on GitHub"
        }
    }

    var subtitle: String {
        switch target {
        case .repo: "Repository · show only this repository"
        case .pull(let pull): "\(pull.repo) #\(pull.number) · \(pull.author)"
        case .issue(let note): "\(note.repo)" + (note.ref.map { " #\($0.number)" } ?? "") + " · issue"
        case .workflow(let run): "\(run.repo) · workflow · \(run.state.label.lowercased())"
        case .web: "Not loaded in RepoRadar"
        }
    }

    var symbol: String {
        switch target {
        case .repo: "book.closed"
        case .pull: "arrow.triangle.pull"
        case .issue: "smallcircle.filled.circle"
        case .workflow: "bolt.circle"
        case .web: "safari"
        }
    }

    var webURL: URL {
        switch target {
        case .repo(let repo): URL(string: "https://github.com/\(repo)")!
        case .pull(let pull): pull.pr.htmlUrl
        case .issue(let note): note.webURL
        case .workflow(let run): run.htmlUrl
        case .web(let url): url
        }
    }
}

enum Jump {
    static func results(_ query: JumpQuery, repos: [String], pulls: [PullItem], notifications: [GitHubNotification],
                        runs: [WorkflowRun], limit: Int = 8) -> [JumpResult] {
        guard !query.isEmpty else { return [] }
        func inRepo(_ repo: String) -> Bool { query.repo.map { repo.localizedCaseInsensitiveContains($0) } ?? true }
        func matches(_ fields: String...) -> Bool {
            query.words.allSatisfy { word in fields.contains { $0.localizedCaseInsensitiveContains(word) } }
        }
        let plain = query.author == nil && query.number == nil  // filters only pull requests and issues have

        let repoResults = plain ? repos.filter { inRepo($0) && matches($0) }.prefix(3).map { JumpResult(target: .repo($0)) } : []
        let pullResults = pulls
            .filter { pull in
                inRepo(pull.repo) && (query.number.map { $0 == pull.number } ?? true)
                    && (query.author.map { pull.author.localizedCaseInsensitiveContains($0) } ?? true)
                    && matches(pull.title, pull.repo, pull.author)
            }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(4)
            .map { JumpResult(target: .pull($0)) }
        var seenIssues = Set<String>()
        let issueResults = query.author != nil ? [] : notifications
            .filter { note in
                guard note.subject.type == "Issue", let ref = note.ref, seenIssues.insert(note.subjectKey!).inserted else { return false }
                return inRepo(note.repo) && (query.number.map { $0 == ref.number } ?? true) && matches(note.title, note.repo)
            }
            .prefix(3)
            .map { JumpResult(target: .issue($0)) }
        let workflowResults = plain ? runs.latestPerWorkflow()
            .filter { inRepo($0.repo) && matches($0.workflowName, $0.repo) }
            .prefix(3)
            .map { JumpResult(target: .workflow($0)) } : []

        var results = Array(repoResults) + Array(pullResults) + Array(issueResults) + Array(workflowResults)
        // "repo:owner/name #123" that isn't loaded still has somewhere to go.
        if results.isEmpty, let number = query.number, let repo = query.repo, repo.split(separator: "/").count == 2 {
            results.append(JumpResult(target: .web(URL(string: "https://github.com/\(repo)/issues/\(number)")!)))
        }
        return Array(results.prefix(limit))
    }
}

/// The floating results list under the toolbar search field.
struct JumpResults: View {
    let results: [JumpResult]
    let selected: Int
    let open: (JumpResult, _ inBrowser: Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if results.isEmpty {
                Text("No matches. Try repo:, #123 or author:.")
                    .textStyle(.meta)
                    .foregroundStyle(Theme.Ink.secondary)
                    .padding(14)
            }
            ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                Button { open(result, false) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: result.symbol)
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.Ink.secondary)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.title).textStyle(.rowTitle).foregroundStyle(Theme.Ink.primary).lineLimit(1)
                            Text(result.subtitle).textStyle(.meta).foregroundStyle(Theme.Ink.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        if index == selected { Kbd("↵") }
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 44)
                    .background(index == selected ? Theme.Selection.row : .clear, in: .rect(cornerRadius: 10))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(index == selected ? .isSelected : [])
            }
            if !results.isEmpty {
                HStack(spacing: 12) {
                    HStack(spacing: 4) { Kbd("↵"); Text("open") }
                    HStack(spacing: 4) { Kbd("⌘↵"); Text("open in browser") }
                    HStack(spacing: 4) { Kbd("esc"); Text("close") }
                }
                .textStyle(.meta)
                .foregroundStyle(Theme.Ink.tertiary)
                .padding(.horizontal, 10)
                .padding(.top, 6)
            }
        }
        .padding(8)
        .frame(width: 400)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
}

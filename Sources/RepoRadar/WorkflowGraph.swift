import Foundation

/// A job as declared in the workflow file: its key, optional display name, and `needs`.
struct DeclaredJob: Equatable {
    let id: String
    let name: String?
    let needs: [String]
}

/// Reads the `jobs:` map of a workflow file — only what the dependency graph needs.
enum WorkflowYAML {
    // ponytail: indentation-based reader for jobs/name/needs; no anchors, aliases or multi-line scalars.
    // Swap in a real YAML parser if workflows using those need exact graphs.
    static func jobs(in yaml: String) -> [DeclaredJob] {
        let lines = yaml.components(separatedBy: .newlines).map(stripComment).filter {
            !$0.trimmingCharacters(in: .whitespaces).isEmpty
        }
        guard let start = lines.firstIndex(where: { indent($0) == 0 && key($0) == "jobs" }) else { return [] }
        let body = lines[(start + 1)...].prefix { indent($0) > 0 }
        guard let jobIndent = body.first.map(indent) else { return [] }

        var jobs: [DeclaredJob] = []
        var current: (id: String, lines: [String])?
        func flush() {
            guard let current else { return }
            jobs.append(parseJob(id: current.id, lines: current.lines))
        }
        for line in body {
            if indent(line) == jobIndent, let id = key(line) {
                flush()
                current = (id, [])
            } else {
                current?.lines.append(line)
            }
        }
        flush()
        return jobs
    }

    private static func parseJob(id: String, lines: [String]) -> DeclaredJob {
        guard let propIndent = lines.first.map(indent) else { return DeclaredJob(id: id, name: nil, needs: []) }
        var name: String?
        var needs: [String] = []
        for (index, line) in lines.enumerated() where indent(line) == propIndent {
            guard let key = key(line) else { continue }
            let value = self.value(line)
            if key == "name", !value.isEmpty {
                name = unquote(value)
            } else if key == "needs" {
                if value.hasPrefix("[") {
                    needs = value.trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
                        .split(separator: ",").map { unquote(String($0)) }.filter { !$0.isEmpty }
                } else if !value.isEmpty {
                    needs = [unquote(value)]
                } else {
                    needs = lines[(index + 1)...]
                        .prefix { indent($0) > propIndent }
                        .compactMap { line in
                            let item = line.trimmingCharacters(in: .whitespaces)
                            return item.hasPrefix("- ") ? unquote(String(item.dropFirst(2))) : nil
                        }
                }
            }
        }
        return DeclaredJob(id: id, name: name, needs: needs)
    }

    private static func indent(_ line: String) -> Int {
        line.prefix { $0 == " " }.count
    }

    /// `key:` or `key: value` → key; nil for list items and non-mapping lines.
    private static func key(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.hasPrefix("-"), let colon = trimmed.firstIndex(of: ":") else { return nil }
        let rest = trimmed[trimmed.index(after: colon)...]
        guard rest.isEmpty || rest.first == " " else { return nil }  // skip "http://…" style values
        return unquote(String(trimmed[..<colon]))
    }

    private static func value(_ line: String) -> String {
        guard let colon = line.firstIndex(of: ":") else { return "" }
        return line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
    }

    private static func unquote(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }

    private static func stripComment(_ line: String) -> String {
        if line.trimmingCharacters(in: .whitespaces).hasPrefix("#") { return "" }
        guard let range = line.range(of: " #") else { return line }
        return String(line[..<range.lowerBound])
    }
}

/// Jobs laid out left-to-right by dependency depth, like GitHub's workflow graph:
/// redundant edges are dropped, and jobs sharing both their upstream and downstream jobs share one box.
struct JobGraph {
    /// One box: a single job, or a group of jobs that sit in parallel between the same neighbours.
    struct Node: Identifiable {
        let jobs: [WorkflowJob]
        let column: Int
        let row: Int
        var id: WorkflowJob.ID { jobs[0].id }
        var isGroup: Bool { jobs.count > 1 }
    }

    struct Edge: Hashable {
        let from: Node.ID
        let to: Node.ID
    }

    let nodes: [Node]
    let edges: [Edge]
    var columns: Int { (nodes.map(\.column).max() ?? -1) + 1 }

    init(jobs: [WorkflowJob], declared: [DeclaredJob]) {
        // Which declared job produced each run job ("ci / check" comes from reusable job `ci`,
        // "build (ubuntu)" from a matrix of `build`).
        let owner: [WorkflowJob.ID: String] = Dictionary(uniqueKeysWithValues: jobs.compactMap { job in
            declared.first { Self.matches(job.name, $0) }.map { (job.id, $0.id) }
        })
        let needs = Dictionary(declared.map { ($0.id, $0.needs) }, uniquingKeysWith: { first, _ in first })

        var depthCache: [String: Int] = [:]
        func depth(of id: String, visiting: Set<String> = []) -> Int {
            if let cached = depthCache[id] { return cached }
            guard !visiting.contains(id) else { return 0 }  // tolerate cycles in malformed files
            let value = (needs[id] ?? []).map { depth(of: $0, visiting: visiting.union([id])) + 1 }.max() ?? 0
            depthCache[id] = value
            return value
        }
        let column = Dictionary(uniqueKeysWithValues: jobs.map { job in (job.id, owner[job.id].map { depth(of: $0) } ?? 0) })

        // Job-level edges, upstream → downstream.
        var downstream: [WorkflowJob.ID: Set<WorkflowJob.ID>] = [:]
        for job in jobs {
            guard let declaredID = owner[job.id] else { continue }
            for need in needs[declaredID] ?? [] {
                for upstream in jobs where owner[upstream.id] == need && upstream.id != job.id {
                    downstream[upstream.id, default: []].insert(job.id)
                }
            }
        }

        // Transitive reduction: drop a → c when c is also reachable from a through another job.
        func reachable(from start: WorkflowJob.ID, skippingDirect target: WorkflowJob.ID) -> Bool {
            var stack = Array((downstream[start] ?? []).subtracting([target]))
            var seen = Set(stack)
            while let next = stack.popLast() {
                if next == target { return true }
                for child in downstream[next] ?? [] where seen.insert(child).inserted { stack.append(child) }
            }
            return false
        }
        var reduced: [WorkflowJob.ID: Set<WorkflowJob.ID>] = [:]
        for (from, targets) in downstream {
            reduced[from] = targets.filter { !reachable(from: from, skippingDirect: $0) }
        }
        var upstream: [WorkflowJob.ID: Set<WorkflowJob.ID>] = [:]
        for (from, targets) in reduced { for to in targets { upstream[to, default: []].insert(from) } }

        // Group jobs in the same column with identical neighbours, keeping the run's job order.
        struct GroupKey: Hashable {
            let column: Int
            let upstream: Set<WorkflowJob.ID>
            let downstream: Set<WorkflowJob.ID>
        }
        var groups: [GroupKey: [WorkflowJob]] = [:]
        var order: [GroupKey] = []
        for job in jobs {
            let key = GroupKey(column: column[job.id]!, upstream: upstream[job.id] ?? [], downstream: reduced[job.id] ?? [])
            // Jobs with no neighbours at all stay separate; grouping unrelated standalone jobs would be misleading.
            let groupable = !key.upstream.isEmpty || !key.downstream.isEmpty
            let finalKey = groupable ? key : GroupKey(column: key.column, upstream: [job.id], downstream: [])
            if groups[finalKey] == nil { order.append(finalKey) }
            groups[finalKey, default: []].append(job)
        }

        var rowsUsed: [Int: Int] = [:]
        var nodeOf: [WorkflowJob.ID: Node.ID] = [:]
        nodes = order.map { key in
            let members = groups[key]!
            defer { rowsUsed[key.column, default: 0] += 1 }
            for job in members { nodeOf[job.id] = members[0].id }
            return Node(jobs: members, column: key.column, row: rowsUsed[key.column, default: 0])
        }

        var edges: [Edge] = []
        var seen = Set<Edge>()
        for job in jobs {
            for target in (reduced[job.id] ?? []).sorted() {
                let edge = Edge(from: nodeOf[job.id]!, to: nodeOf[target]!)
                if seen.insert(edge).inserted { edges.append(edge) }
            }
        }
        self.edges = edges
    }

    static func matches(_ runName: String, _ job: DeclaredJob) -> Bool {
        let display = job.name ?? job.id
        // Names built from expressions (`Build ${{ matrix.os }}`) only match on their literal prefix.
        let literal = display.components(separatedBy: "${{").first!.trimmingCharacters(in: .whitespaces)
        if display.contains("${{") { return !literal.isEmpty && runName.hasPrefix(literal) }
        return runName == display || runName == job.id
            || runName.hasPrefix(display + " (") || runName.hasPrefix(job.id + " / ") || runName.hasPrefix(display + " / ")
    }
}

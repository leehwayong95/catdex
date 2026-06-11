import Foundation

public struct OpenCodeActivityReader: Sendable {
    private let databaseURL: URL

    public init(databaseURL: URL? = nil) {
        self.databaseURL = databaseURL ?? Self.defaultDatabaseURL(
            environment: ProcessInfo.processInfo.environment,
            commandLocator: { CommandLocator.findExecutable($0) },
            commandRunner: Self.runCommand
        )
    }

    init(
        databaseURL: URL? = nil,
        environment: [String: String],
        commandLocator: @escaping @Sendable (String) -> URL?,
        commandRunner: @escaping @Sendable (URL, [String]) -> String?
    ) {
        self.databaseURL = databaseURL ?? Self.defaultDatabaseURL(
            environment: environment,
            commandLocator: commandLocator,
            commandRunner: commandRunner
        )
    }

    public func snapshot(workspace: String, startedAt: Date) -> AgentActivitySnapshot? {
        guard FileManager.default.fileExists(atPath: databaseURL.path),
              let sqlite = CommandLocator.findExecutable("sqlite3"),
              let session = latestSession(workspace: workspace, startedAt: startedAt, sqlite: sqlite)
        else {
            return nil
        }

        guard let latestPartType = latestPartType(sessionID: session.id, sqlite: sqlite) else {
            return AgentActivitySnapshot(
                state: .running,
                message: "😼 OpenCode running: \(session.title)",
                sessionPath: databaseURL.path
            )
        }

        switch latestPartType {
        case "step-finish":
            return AgentActivitySnapshot(
                state: .waiting,
                message: "👀 OpenCode answer complete; waiting",
                sessionPath: databaseURL.path
            )
        case "step-start":
            return AgentActivitySnapshot(
                state: .responding,
                message: "✍️ OpenCode thinking",
                sessionPath: databaseURL.path
            )
        case "tool":
            return AgentActivitySnapshot(
                state: .responding,
                message: "✍️ OpenCode running tool",
                sessionPath: databaseURL.path
            )
        default:
            return AgentActivitySnapshot(
                state: .responding,
                message: "✍️ OpenCode updating",
                sessionPath: databaseURL.path
            )
        }
    }

    private struct SessionRow {
        var id: String
        var title: String
    }

    private func latestSession(workspace: String, startedAt: Date, sqlite: URL) -> SessionRow? {
        let startedAtMilliseconds = Int(startedAt.addingTimeInterval(-10).timeIntervalSince1970 * 1_000)
        let query = """
        select id, title
        from session
        where directory = '\(sqlEscaped(workspace))'
          and time_created >= \(startedAtMilliseconds)
        order by time_updated desc
        limit 1;
        """
        guard let output = runSQLite(sqlite: sqlite, query: query) else { return nil }
        let columns = output.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard columns.count >= 2, !columns[0].isEmpty else { return nil }
        return SessionRow(id: columns[0], title: columns[1])
    }

    private func latestPartType(sessionID: String, sqlite: URL) -> String? {
        let query = """
        select json_extract(data, '$.type')
        from part
        where session_id = '\(sqlEscaped(sessionID))'
        order by time_created desc
        limit 1;
        """
        return runSQLite(sqlite: sqlite, query: query)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }

    private func runSQLite(sqlite: URL, query: String) -> String? {
        let process = Process()
        let output = Pipe()
        process.executableURL = sqlite
        process.arguments = ["-noheader", "-separator", "\t", databaseURL.path, query]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .newlines)
        } catch {
            return nil
        }
    }

    private func sqlEscaped(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "''")
    }

    private static func defaultDatabaseURL(
        environment: [String: String],
        commandLocator: (String) -> URL?,
        commandRunner: (URL, [String]) -> String?
    ) -> URL {
        if let databasePath = environment["CATDEX_OPENCODE_DB"],
           !databasePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: databasePath)
        }

        if let opencode = commandLocator("opencode"),
           let databasePath = commandRunner(opencode, ["db", "path"])?.trimmingCharacters(in: .whitespacesAndNewlines),
           !databasePath.isEmpty {
            return URL(fileURLWithPath: databasePath)
        }

        if let dataDirectory = environment["OPENCODE_DATA_DIR"],
           !dataDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: dataDirectory, isDirectory: true)
                .appendingPathComponent("opencode.db")
        }

        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local", isDirectory: true)
            .appendingPathComponent("share", isDirectory: true)
            .appendingPathComponent("opencode", isDirectory: true)
            .appendingPathComponent("opencode.db")
    }

    private static func runCommand(_ executable: URL, _ arguments: [String]) -> String? {
        let process = Process()
        let output = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

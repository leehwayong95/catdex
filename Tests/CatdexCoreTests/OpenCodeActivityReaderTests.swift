import XCTest
@testable import CatdexCore

final class OpenCodeActivityReaderTests: XCTestCase {
    func testSnapshotReturnsRespondingForRecentStepStartInWorkspace() throws {
        let database = try makeDatabase()
        let startedAt = Date(timeIntervalSince1970: 1_000)
        try insertSession(
            database: database,
            id: "ses_active",
            directory: "/tmp/project",
            title: "Implement OpenCode support",
            agent: "Sisyphus",
            timeCreated: 1_001_000,
            timeUpdated: 1_002_000
        )
        try insertPart(
            database: database,
            sessionID: "ses_active",
            timeCreated: 1_002_000,
            data: #"{"type":"step-start"}"#
        )

        let snapshot = OpenCodeActivityReader(databaseURL: database)
            .snapshot(workspace: "/tmp/project", startedAt: startedAt)

        XCTAssertEqual(snapshot?.state, .responding)
        XCTAssertEqual(snapshot?.message, "✍️ OpenCode thinking")
        XCTAssertEqual(snapshot?.sessionPath, database.path)
    }

    func testSnapshotReturnsWaitingForStepFinish() throws {
        let database = try makeDatabase()
        let startedAt = Date(timeIntervalSince1970: 1_000)
        try insertSession(
            database: database,
            id: "ses_done",
            directory: "/tmp/project",
            title: "Answer question",
            agent: "Sisyphus",
            timeCreated: 1_001_000,
            timeUpdated: 1_003_000
        )
        try insertPart(
            database: database,
            sessionID: "ses_done",
            timeCreated: 1_003_000,
            data: #"{"type":"step-finish","reason":"stop"}"#
        )

        let snapshot = OpenCodeActivityReader(databaseURL: database)
            .snapshot(workspace: "/tmp/project", startedAt: startedAt)

        XCTAssertEqual(snapshot?.state, .waiting)
        XCTAssertEqual(snapshot?.message, "👀 OpenCode answer complete; waiting")
    }

    func testSnapshotIgnoresOtherWorkspaceAndOldSessions() throws {
        let database = try makeDatabase()
        try insertSession(
            database: database,
            id: "ses_other",
            directory: "/tmp/other",
            title: "Other",
            agent: "Sisyphus",
            timeCreated: 1_001_000,
            timeUpdated: 1_002_000
        )
        try insertSession(
            database: database,
            id: "ses_old",
            directory: "/tmp/project",
            title: "Old",
            agent: "Sisyphus",
            timeCreated: 900_000,
            timeUpdated: 901_000
        )

        let snapshot = OpenCodeActivityReader(databaseURL: database)
            .snapshot(workspace: "/tmp/project", startedAt: Date(timeIntervalSince1970: 1_000))

        XCTAssertNil(snapshot)
    }

    func testSnapshotReturnsNilForUnsupportedSchema() throws {
        let database = FileManager.default.temporaryDirectory
            .appendingPathComponent("catdex-opencode-unsupported-\(UUID().uuidString).db")
        try runSQLite(database: database, sql: "create table unsupported (id text primary key);")

        let snapshot = OpenCodeActivityReader(databaseURL: database)
            .snapshot(workspace: "/tmp/project", startedAt: Date(timeIntervalSince1970: 1_000))

        XCTAssertNil(snapshot)
    }

    func testSnapshotDiscoversDatabasePathFromOpenCodeCommand() throws {
        let database = try makeDatabase()
        try insertSession(
            database: database,
            id: "ses_discovered",
            directory: "/tmp/project",
            title: "Discovered DB",
            agent: "Sisyphus",
            timeCreated: 1_001_000,
            timeUpdated: 1_002_000
        )
        try insertPart(
            database: database,
            sessionID: "ses_discovered",
            timeCreated: 1_002_000,
            data: #"{"type":"step-start"}"#
        )
        let fakeOpenCode = URL(fileURLWithPath: "/tmp/fake-opencode")

        let reader = OpenCodeActivityReader(
            environment: [:],
            commandLocator: { name in name == "opencode" ? fakeOpenCode : nil },
            commandRunner: { executable, arguments in
                executable == fakeOpenCode && arguments == ["db", "path"] ? database.path : nil
            }
        )

        let snapshot = reader.snapshot(
            workspace: "/tmp/project",
            startedAt: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertEqual(snapshot?.state, .responding)
        XCTAssertEqual(snapshot?.sessionPath, database.path)
    }

    private func makeDatabase() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("catdex-opencode-\(UUID().uuidString).db")
        try runSQLite(database: url, sql: """
        create table session (
            id text primary key,
            directory text not null,
            title text not null,
            agent text,
            model text,
            time_created integer not null,
            time_updated integer not null
        );
        create table part (
            id text primary key,
            session_id text not null,
            time_created integer not null,
            data text not null
        );
        """)
        return url
    }

    private func insertSession(
        database: URL,
        id: String,
        directory: String,
        title: String,
        agent: String,
        timeCreated: Int,
        timeUpdated: Int
    ) throws {
        try runSQLite(database: database, sql: """
        insert into session (id, directory, title, agent, model, time_created, time_updated)
        values ('\(id)', '\(directory)', '\(title)', '\(agent)', '{"id":"gpt-5.5"}', \(timeCreated), \(timeUpdated));
        """)
    }

    private func insertPart(database: URL, sessionID: String, timeCreated: Int, data: String) throws {
        try runSQLite(database: database, sql: """
        insert into part (id, session_id, time_created, data)
        values ('\(UUID().uuidString)', '\(sessionID)', \(timeCreated), '\(data.replacingOccurrences(of: "'", with: "''"))');
        """)
    }

    private func runSQLite(database: URL, sql: String) throws {
        guard let sqlite = CommandLocator.findExecutable("sqlite3") else {
            throw XCTSkip("sqlite3 is required for OpenCodeActivityReader tests")
        }
        let process = Process()
        process.executableURL = sqlite
        process.arguments = [database.path, sql]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }
}

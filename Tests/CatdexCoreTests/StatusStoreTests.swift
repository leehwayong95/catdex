import XCTest
@testable import CatdexCore

final class StatusStoreTests: XCTestCase {
    func testSaveAndLoadSessionsSortedByStateThenDate() throws {
        let root = try temporaryRoot()
        let store = StatusStore(paths: CatdexPaths(root: root))
        let old = Date(timeIntervalSince1970: 100)
        let recent = Date(timeIntervalSince1970: 200)

        try store.save(CatdexSession(
            id: "done",
            state: .done,
            task: "Done task",
            workspace: "/tmp/a",
            updatedAt: recent,
            lastMessage: "done"
        ))
        try store.save(CatdexSession(
            id: "failed",
            state: .failed,
            task: "Failed task",
            workspace: "/tmp/b",
            updatedAt: old,
            lastMessage: "failed"
        ))
        try store.save(CatdexSession(
            id: "review",
            state: .review,
            task: "Review task",
            workspace: "/tmp/review",
            updatedAt: old,
            lastMessage: "permission approval needed",
            reviewOptions: ["Yes, proceed", "No, stop"]
        ))
        try store.save(CatdexSession(
            id: "running",
            state: .running,
            task: "Running task",
            workspace: "/tmp/c",
            updatedAt: recent,
            lastMessage: "running"
        ))

        let sessions = store.loadSessions(now: recent, staleAfter: 1_000)

        XCTAssertEqual(sessions.map(\.id), ["review", "failed", "running", "done"])
        XCTAssertEqual(sessions.first?.reviewOptions, ["Yes, proceed", "No, stop"])
    }

    func testInvalidJsonIsIgnored() throws {
        let root = try temporaryRoot()
        let store = StatusStore(paths: CatdexPaths(root: root))
        try store.prepareDirectories()
        let invalid = store.paths.sessionsDirectory.appendingPathComponent("bad.json")
        try Data("not json".utf8).write(to: invalid)

        XCTAssertEqual(store.loadSessions(), [])
    }

    func testRunningSessionBecomesStaleAfterHeartbeatExpires() throws {
        let root = try temporaryRoot()
        let store = StatusStore(paths: CatdexPaths(root: root))
        let updatedAt = Date(timeIntervalSince1970: 100)
        try store.save(CatdexSession(
            id: "old-running",
            state: .running,
            task: "Old",
            workspace: "/tmp/old",
            updatedAt: updatedAt,
            lastMessage: "running"
        ))

        let sessions = store.loadSessions(now: Date(timeIntervalSince1970: 500), staleAfter: 60)

        XCTAssertEqual(sessions.first?.state, .stale)
    }

    func testRespondingSessionBecomesStaleAfterHeartbeatExpires() throws {
        let root = try temporaryRoot()
        let store = StatusStore(paths: CatdexPaths(root: root))
        let updatedAt = Date(timeIntervalSince1970: 100)
        try store.save(CatdexSession(
            id: "old-responding",
            state: .responding,
            task: "Old",
            workspace: "/tmp/old",
            updatedAt: updatedAt,
            lastMessage: "answering"
        ))

        let sessions = store.loadSessions(now: Date(timeIntervalSince1970: 500), staleAfter: 60)

        XCTAssertEqual(sessions.first?.state, .stale)
    }

    func testStaleTransitionIsPersistedForPruning() throws {
        let root = try temporaryRoot()
        let store = StatusStore(paths: CatdexPaths(root: root))
        let updatedAt = Date(timeIntervalSince1970: 100)
        try store.save(CatdexSession(
            id: "old-running",
            state: .running,
            task: "Old",
            workspace: "/tmp/old",
            updatedAt: updatedAt,
            lastMessage: "running"
        ))

        _ = store.loadSessions(now: Date(timeIntervalSince1970: 500), staleAfter: 60)
        try store.pruneFinished(olderThan: 300, now: Date(timeIntervalSince1970: 500))

        XCTAssertFalse(FileManager.default.fileExists(atPath: store.sessionURL(for: "old-running").path))
    }

    func testPruneFinishedRemovesOnlyOldFinishedSessions() throws {
        let root = try temporaryRoot()
        let store = StatusStore(paths: CatdexPaths(root: root))
        let now = Date(timeIntervalSince1970: 1_000)

        try store.save(CatdexSession(id: "old-done", state: .done, task: "Done", workspace: "/tmp", updatedAt: Date(timeIntervalSince1970: 100), lastMessage: "done"))
        try store.save(CatdexSession(id: "new-done", state: .done, task: "Done", workspace: "/tmp", updatedAt: Date(timeIntervalSince1970: 950), lastMessage: "done"))
        try store.save(CatdexSession(id: "running", state: .running, task: "Run", workspace: "/tmp", updatedAt: Date(timeIntervalSince1970: 100), lastMessage: "run"))

        let removed = try store.pruneFinished(olderThan: 300, now: now)
        let ids = store.loadSessions(now: now, staleAfter: 2_000).map(\.id)

        XCTAssertEqual(removed, 1)
        XCTAssertEqual(Set(ids), ["new-done", "running"])
    }

    func testRemoveSessionDeletesSessionAndLog() throws {
        let root = try temporaryRoot()
        let store = StatusStore(paths: CatdexPaths(root: root))
        try store.save(CatdexSession(id: "done", state: .done, task: "Done", workspace: "/tmp", updatedAt: Date(), lastMessage: "done"))
        try Data("log".utf8).write(to: store.logURL(for: "done"))

        try store.removeSession(id: "done")

        XCTAssertFalse(FileManager.default.fileExists(atPath: store.sessionURL(for: "done").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.logURL(for: "done").path))
    }

    func testUpdateSessionMutatesExistingSession() throws {
        let root = try temporaryRoot()
        let store = StatusStore(paths: CatdexPaths(root: root))
        try store.save(CatdexSession(
            id: "editable",
            state: .waiting,
            task: "Original",
            workspace: "/tmp/project",
            updatedAt: Date(),
            lastMessage: "waiting"
        ))

        try store.updateSession(id: "editable") { session in
            session.task = "Renamed"
        }

        XCTAssertEqual(store.loadSession(id: "editable")?.task, "Renamed")
    }

    func testLoadLegacySessionWithoutBackendDefaultsToCodex() throws {
        let root = try temporaryRoot()
        let store = StatusStore(paths: CatdexPaths(root: root))
        try store.prepareDirectories()
        let legacy = """
        {
          "id" : "legacy",
          "lastMessage" : "running",
          "state" : "running",
          "task" : "Legacy",
          "updatedAt" : "2026-06-11T00:00:00Z",
          "workspace" : "/tmp/project"
        }
        """
        try Data(legacy.utf8).write(to: store.sessionURL(for: "legacy"))

        let session = store.loadSession(id: "legacy")

        XCTAssertEqual(session?.backend, .codex)
    }

    func testSaveAndLoadOpenCodeBackend() throws {
        let root = try temporaryRoot()
        let store = StatusStore(paths: CatdexPaths(root: root))
        try store.save(CatdexSession(
            id: "opencode",
            state: .responding,
            task: "OpenCode",
            workspace: "/tmp/project",
            updatedAt: Date(timeIntervalSince1970: 100),
            lastMessage: "thinking",
            backend: .opencode
        ))

        let session = store.loadSession(id: "opencode")

        XCTAssertEqual(session?.backend, .opencode)
    }

    func testSessionIDContainsReadableSlug() {
        let id = SessionFactory.makeID(
            task: "API 테스트 수정!",
            date: Date(timeIntervalSince1970: 0),
            pid: 42
        )

        XCTAssertTrue(id.hasPrefix("19700101-090000-42-"))
        XCTAssertTrue(id.contains("api"))
    }

    private func temporaryRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("catdex-status-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

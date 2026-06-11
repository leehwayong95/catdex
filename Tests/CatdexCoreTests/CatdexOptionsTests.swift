import XCTest
@testable import CatdexCore

final class CatdexOptionsTests: XCTestCase {
    func testParseBackendOpenCodeUsesOpenCodeCommandAndPassesArguments() throws {
        let options = try CatdexOptions.parse(
            ["--backend", "opencode", "run this through omo"],
            environment: [:]
        )

        XCTAssertEqual(options.mode, .run)
        XCTAssertEqual(options.backend, .opencode)
        XCTAssertEqual(options.agentCommand, "opencode")
        XCTAssertEqual(options.agentArguments, ["run this through omo"])
    }

    func testParseOpenCodeBinSelectsOpenCodeBackend() throws {
        let options = try CatdexOptions.parse(
            ["--opencode-bin", "/opt/bin/opencode", "--", "--agent", "sisyphus"],
            environment: [:]
        )

        XCTAssertEqual(options.backend, .opencode)
        XCTAssertEqual(options.agentCommand, "/opt/bin/opencode")
        XCTAssertEqual(options.agentArguments, ["--agent", "sisyphus"])
    }

    func testParseLegacyCodexBinStillSelectsCodexBackend() throws {
        let options = try CatdexOptions.parse(
            ["--codex-bin", "/opt/bin/codex", "review api"],
            environment: [:]
        )

        XCTAssertEqual(options.backend, .codex)
        XCTAssertEqual(options.agentCommand, "/opt/bin/codex")
        XCTAssertEqual(options.agentArguments, ["review api"])
    }

    func testParseRejectsUnknownBackend() {
        XCTAssertThrowsError(try CatdexOptions.parse(["--backend", "claude"], environment: [:])) { error in
            XCTAssertEqual(error as? CatdexOptionError, .invalidBackend("claude"))
        }
    }

    func testParseUsesSettingsDefaultBackendWhenEnvironmentIsUnset() throws {
        let root = try temporaryRoot()
        try Data(#"{"defaultBackend":"opencode"}"#.utf8)
            .write(to: root.appendingPathComponent("settings.json"))

        let options = try CatdexOptions.parse([], environment: ["CATDEX_STATUS_DIR": root.path])

        XCTAssertEqual(options.backend, .opencode)
        XCTAssertEqual(options.agentCommand, "opencode")
    }

    func testEnvironmentBackendOverridesSettingsDefaultBackend() throws {
        let root = try temporaryRoot()
        try Data(#"{"defaultBackend":"opencode"}"#.utf8)
            .write(to: root.appendingPathComponent("settings.json"))

        let options = try CatdexOptions.parse(
            [],
            environment: [
                "CATDEX_STATUS_DIR": root.path,
                "CATDEX_BACKEND": "codex"
            ]
        )

        XCTAssertEqual(options.backend, .codex)
        XCTAssertEqual(options.agentCommand, "codex")
    }

    private func temporaryRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("catdex-options-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

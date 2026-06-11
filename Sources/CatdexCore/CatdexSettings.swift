import Foundation

public enum CatdexSettings {
    public static func defaultBackend(environment: [String: String] = ProcessInfo.processInfo.environment) -> AgentBackend? {
        let url = settingsURL(environment: environment)
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = object["defaultBackend"] as? String
        else {
            return nil
        }

        return AgentBackend(rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    private static func settingsURL(environment: [String: String]) -> URL {
        if let override = environment["CATDEX_STATUS_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
                .appendingPathComponent("settings.json")
        }

        let home = environment["HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.path
        return URL(fileURLWithPath: home, isDirectory: true)
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("cat-status", isDirectory: true)
            .appendingPathComponent("settings.json")
    }
}

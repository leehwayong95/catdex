import Foundation

public enum CatdexMode: Equatable, Sendable {
    case run
    case cleanup
    case doctor
}

public enum AgentBackend: String, Codable, Equatable, Sendable {
    case codex
    case opencode

    public var displayName: String {
        switch self {
        case .codex: "Codex"
        case .opencode: "OpenCode"
        }
    }

    public static func defaultBackend(environment: [String: String] = ProcessInfo.processInfo.environment) -> AgentBackend {
        guard let raw = environment["CATDEX_BACKEND"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !raw.isEmpty
        else {
            return CatdexSettings.defaultBackend(environment: environment) ?? .codex
        }
        return AgentBackend(rawValue: raw) ?? .codex
    }

    public func defaultCommand(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        switch self {
        case .codex:
            environment["CATDEX_CODEX_BIN"] ?? "codex"
        case .opencode:
            environment["CATDEX_OPENCODE_BIN"] ?? "opencode"
        }
    }
}

public enum CatdexOptionError: Error, Equatable, CustomStringConvertible {
    case help
    case message(String)
    case invalidBackend(String)

    public var description: String {
        switch self {
        case .help:
            "help requested"
        case .message(let message):
            message
        case .invalidBackend(let backend):
            "unknown backend: \(backend) (expected codex or opencode)"
        }
    }
}

public struct CatdexOptions: Equatable, Sendable {
    public var mode: CatdexMode
    public var task: String?
    public var backend: AgentBackend
    public var agentCommand: String
    public var agentArguments: [String]
    public var dryRun: Bool

    public init(
        mode: CatdexMode,
        task: String?,
        backend: AgentBackend,
        agentCommand: String,
        agentArguments: [String],
        dryRun: Bool
    ) {
        self.mode = mode
        self.task = task
        self.backend = backend
        self.agentCommand = agentCommand
        self.agentArguments = agentArguments
        self.dryRun = dryRun
    }

    public static func parse(
        _ arguments: [String],
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> CatdexOptions {
        var backend = AgentBackend.defaultBackend(environment: environment)
        var agentCommand = backend.defaultCommand(environment: environment)
        var commandOverridden = false

        if let command = arguments.first {
            switch command {
            case "cleanup", "doctor":
                guard arguments.count == 1 else {
                    throw CatdexOptionError.message("catdex \(command) does not accept extra arguments")
                }
                return CatdexOptions(
                    mode: command == "cleanup" ? .cleanup : .doctor,
                    task: nil,
                    backend: backend,
                    agentCommand: agentCommand,
                    agentArguments: [],
                    dryRun: false
                )
            default:
                break
            }
        }

        var taskParts: [String] = []
        var agentArguments: [String] = []
        var dryRun = false
        var parsingAgentArguments = false
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            if parsingAgentArguments {
                agentArguments.append(argument)
                index += 1
                continue
            }

            switch argument {
            case "--":
                parsingAgentArguments = true
            case "--help", "-h":
                throw CatdexOptionError.help
            case "--dry-run":
                dryRun = true
            case "--task":
                index += 1
                guard index < arguments.count else {
                    throw CatdexOptionError.message("--task requires a session name")
                }
                taskParts = [arguments[index]]
            case "--backend":
                index += 1
                guard index < arguments.count else {
                    throw CatdexOptionError.message("--backend requires codex or opencode")
                }
                let rawBackend = arguments[index].lowercased()
                guard let parsedBackend = AgentBackend(rawValue: rawBackend) else {
                    throw CatdexOptionError.invalidBackend(arguments[index])
                }
                backend = parsedBackend
                if !commandOverridden {
                    agentCommand = backend.defaultCommand(environment: environment)
                }
            case "--agent-bin":
                index += 1
                guard index < arguments.count else {
                    throw CatdexOptionError.message("--agent-bin requires a path or command name")
                }
                agentCommand = arguments[index]
                commandOverridden = true
            case "--codex-bin":
                index += 1
                guard index < arguments.count else {
                    throw CatdexOptionError.message("--codex-bin requires a path or command name")
                }
                backend = .codex
                agentCommand = arguments[index]
                commandOverridden = true
            case "--opencode-bin":
                index += 1
                guard index < arguments.count else {
                    throw CatdexOptionError.message("--opencode-bin requires a path or command name")
                }
                backend = .opencode
                agentCommand = arguments[index]
                commandOverridden = true
            default:
                agentArguments.append(argument)
            }
            index += 1
        }

        return CatdexOptions(
            mode: .run,
            task: taskParts.isEmpty ? nil : taskParts.joined(separator: " "),
            backend: backend,
            agentCommand: agentCommand,
            agentArguments: agentArguments,
            dryRun: dryRun
        )
    }
}

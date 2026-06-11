import Foundation

public enum CatdexState: String, Codable, CaseIterable, Sendable {
    case starting
    case running
    case responding
    case review
    case waiting
    case done
    case failed
    case stale
}

public extension CatdexState {
    var isActive: Bool {
        [.starting, .running, .responding, .review, .waiting].contains(self)
    }

    var isFinished: Bool {
        [.done, .failed, .stale].contains(self)
    }

    var needsAttention: Bool {
        [.review, .failed, .stale].contains(self)
    }
}

public struct CatdexSession: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var state: CatdexState
    public var task: String
    public var workspace: String
    public var branch: String?
    public var updatedAt: Date
    public var pid: Int32?
    public var lastMessage: String
    public var reviewOptions: [String]?
    public var logPath: String?
    public var codexSessionPath: String?
    public var exitCode: Int32?
    public var backend: AgentBackend

    public init(
        id: String,
        state: CatdexState,
        task: String,
        workspace: String,
        branch: String? = nil,
        updatedAt: Date,
        pid: Int32? = nil,
        lastMessage: String,
        reviewOptions: [String]? = nil,
        logPath: String? = nil,
        codexSessionPath: String? = nil,
        exitCode: Int32? = nil,
        backend: AgentBackend = .codex
    ) {
        self.id = id
        self.state = state
        self.task = task
        self.workspace = workspace
        self.branch = branch
        self.updatedAt = updatedAt
        self.pid = pid
        self.lastMessage = lastMessage
        self.reviewOptions = reviewOptions
        self.logPath = logPath
        self.codexSessionPath = codexSessionPath
        self.exitCode = exitCode
        self.backend = backend
    }

    enum CodingKeys: String, CodingKey {
        case id
        case state
        case task
        case workspace
        case branch
        case updatedAt
        case pid
        case lastMessage
        case reviewOptions
        case logPath
        case codexSessionPath
        case exitCode
        case backend
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        state = try container.decode(CatdexState.self, forKey: .state)
        task = try container.decode(String.self, forKey: .task)
        workspace = try container.decode(String.self, forKey: .workspace)
        branch = try container.decodeIfPresent(String.self, forKey: .branch)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        pid = try container.decodeIfPresent(Int32.self, forKey: .pid)
        lastMessage = try container.decode(String.self, forKey: .lastMessage)
        reviewOptions = try container.decodeIfPresent([String].self, forKey: .reviewOptions)
        logPath = try container.decodeIfPresent(String.self, forKey: .logPath)
        codexSessionPath = try container.decodeIfPresent(String.self, forKey: .codexSessionPath)
        exitCode = try container.decodeIfPresent(Int32.self, forKey: .exitCode)
        backend = try container.decodeIfPresent(AgentBackend.self, forKey: .backend) ?? .codex
    }
}

public extension CatdexSession {
    var backendDisplayName: String {
        backend.displayName
    }

    var projectName: String {
        URL(fileURLWithPath: workspace).lastPathComponent
    }

    var displayEmoji: String {
        switch state {
        case .starting: "🐾"
        case .running: "😼"
        case .responding: "✍️"
        case .review: "🐱❓"
        case .waiting: "👀"
        case .done: "😺"
        case .failed: "🙀"
        case .stale: "😿"
        }
    }

    var isActive: Bool {
        state.isActive
    }

    var isFinished: Bool {
        state.isFinished
    }

    var needsAttention: Bool {
        state.needsAttention
    }
}

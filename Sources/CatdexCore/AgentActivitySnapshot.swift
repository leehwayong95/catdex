import Foundation

public struct AgentActivitySnapshot: Equatable, Sendable {
    public var state: CatdexState
    public var message: String
    public var sessionPath: String?

    public init(state: CatdexState, message: String, sessionPath: String?) {
        self.state = state
        self.message = message
        self.sessionPath = sessionPath
    }
}

import CatdexCore
import Foundation
import Darwin

enum CatdexMaintenance {
    static func cleanup(store: StatusStore = StatusStore()) -> Int32 {
        _ = store.loadSessions()
        do {
            let removed = try store.pruneFinished(olderThan: 0)
            print("Removed \(removed) finished session\(removed == 1 ? "" : "s").")
            print("Status folder: \(store.paths.root.path)")
            return 0
        } catch {
            fputs("catdex cleanup failed: \(error)\n", stderr)
            return 1
        }
    }

    static func doctor(options: CatdexOptions, store: StatusStore = StatusStore()) -> Int32 {
        var failures = 0
        var warnings = 0

        func report(_ status: String, _ message: String) {
            print("[\(status)] \(message)")
        }

        do {
            try store.prepareDirectories()
            report("OK", "status directory is writable: \(store.paths.root.path)")
        } catch {
            failures += 1
            report("FAIL", "status directory is not writable: \(store.paths.root.path) (\(error))")
        }

        if let executable = CommandLocator.findExecutable(options.agentCommand) {
            report("OK", "\(options.backend.displayName) executable found: \(executable.path)")
        } else {
            failures += 1
            report("FAIL", "\(options.backend.displayName) executable not found: \(options.agentCommand)")
        }

        if let catdex = CommandLocator.findExecutable("catdex") {
            report("OK", "catdex on PATH: \(catdex.path)")
        } else {
            warnings += 1
            report("WARN", "catdex is not on PATH")
        }

        let menuApp = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
            .appendingPathComponent("CatdexMenu.app", isDirectory: true)
        if FileManager.default.fileExists(atPath: menuApp.path) {
            report("OK", "CatdexMenu.app installed: \(menuApp.path)")
        } else {
            warnings += 1
            report("WARN", "CatdexMenu.app not found at \(menuApp.path)")
        }

        let sessions = store.loadSessions()
        let counts = Dictionary(grouping: sessions, by: \.state).mapValues(\.count)
        report(
            "INFO",
            "sessions: starting=\(counts[.starting, default: 0]), responding=\(counts[.responding, default: 0]), waiting=\(counts[.waiting, default: 0]), review=\(counts[.review, default: 0]), running=\(counts[.running, default: 0]), failed=\(counts[.failed, default: 0]), stale=\(counts[.stale, default: 0]), done=\(counts[.done, default: 0])"
        )

        let orphanRunning = sessions.filter { session in
            session.state.isActive && !isProcessAlive(session.pid)
        }
        if orphanRunning.isEmpty {
            report("OK", "no orphan running sessions")
        } else {
            warnings += 1
            report("WARN", "\(orphanRunning.count) running session(s) have missing processes")
        }

        if failures == 0, warnings == 0 {
            report("OK", "doctor completed without issues")
        } else if failures == 0 {
            report("WARN", "doctor completed with \(warnings) warning\(warnings == 1 ? "" : "s")")
        } else {
            report("FAIL", "doctor found \(failures) failure\(failures == 1 ? "" : "s") and \(warnings) warning\(warnings == 1 ? "" : "s")")
        }

        return failures == 0 ? 0 : 1
    }

    private static func isProcessAlive(_ pid: Int32?) -> Bool {
        guard let pid else { return false }
        if Darwin.kill(pid, 0) == 0 {
            return true
        }

        return errno == EPERM
    }
}

protocol AgentEventMonitoring: AnyObject {
    func start()
    func stop()
}

final class SessionRunner {
    private let options: CatdexOptions
    private let store: StatusStore
    private let id: String
    private let task: String
    private let workspace: String
    private let branch: String?
    private let logURL: URL
    private var session: CatdexSession
    private var heartbeat: DispatchSourceTimer?
    private var eventMonitor: AgentEventMonitoring?
    private var signalSources: [DispatchSourceSignal] = []
    private var childPID: pid_t?
    private let sessionLock = NSLock()

    init(options: CatdexOptions, store: StatusStore = StatusStore()) throws {
        self.options = options
        self.store = store
        workspace = FileManager.default.currentDirectoryPath
        task = URL(fileURLWithPath: workspace).lastPathComponent
        id = SessionFactory.makeID(task: task)
        branch = Git.currentBranch(in: workspace)
        logURL = store.logURL(for: id)
        session = CatdexSession(
            id: id,
            state: .starting,
            task: task,
            workspace: workspace,
            branch: branch,
            updatedAt: Date(),
            pid: nil,
            lastMessage: "🐾 \(options.backend.displayName) starting",
            logPath: logURL.path,
            backend: options.backend
        )
    }

    private static func inferTask(from codexArguments: [String]) -> String? {
        let valueOptions: Set<String> = [
            "--add-dir",
            "--ask-for-approval",
            "--cd",
            "--config",
            "--image",
            "--local-provider",
            "--model",
            "--profile",
            "--remote",
            "--remote-auth-token-env",
            "--sandbox"
        ]
        let shortValueOptions: Set<String> = ["-a", "-c", "-C", "-i", "-m", "-p", "-s"]
        let commands: Set<String> = [
            "app", "app-server", "apply", "cloud", "completion", "debug", "doctor", "e", "exec",
            "exec-server", "features", "fork", "help", "login", "logout", "mcp", "mcp-server",
            "plugin", "remote-control", "resume", "review", "sandbox", "update"
        ]

        var positional: [String] = []
        var skipNext = false

        for argument in codexArguments {
            if skipNext {
                skipNext = false
                continue
            }

            if argument.hasPrefix("--") {
                let option = String(argument.split(separator: "=", maxSplits: 1).first ?? "")
                if valueOptions.contains(option), !argument.contains("=") {
                    skipNext = true
                }
                continue
            }

            if argument.hasPrefix("-") {
                let option = String(argument.prefix(2))
                if shortValueOptions.contains(option), argument.count == 2 {
                    skipNext = true
                }
                continue
            }

            let value = argument.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                positional.append(value)
            }
        }

        guard !positional.isEmpty else { return nil }

        if positional.count > 1, commands.contains(positional[0]) {
            positional.removeFirst()
        }

        return positional.isEmpty ? nil : positional.joined(separator: " ")
    }

    func run() -> Int32 {
        do {
            try store.prepareDirectories()
            try appendLog("catdex session \(id) started")
            try save(state: .starting, message: "🐾 Session created")

            if options.dryRun {
                try appendLog("dry run requested")
                try save(state: .done, message: "😺 Dry run complete", exitCode: 0)
                return 0
            }

            guard let executable = CommandLocator.findExecutable(options.agentCommand) else {
                try save(state: .failed, message: "🙀 Cannot find \(options.agentCommand)", exitCode: 127)
                try appendLog("cannot find command: \(options.agentCommand)")
                sendNotification(title: "🙀 \(options.backend.displayName) failed", body: "Cannot find \(options.agentCommand)")
                return 127
            }

            let process = try CodexProcess.start(
                executable: executable,
                arguments: options.agentArguments,
                workingDirectory: workspace
            )
            childPID = process.pid
            try appendLog("\(options.backend.displayName) pid \(process.pid) started")
            try save(state: .starting, message: "🐾 \(options.backend.displayName) starting", pid: process.pid)
            startHeartbeat(pid: process.pid)
            startEventMonitor(pid: process.pid)
            installSignalHandlers(for: process)

            let code = process.wait()
            heartbeat?.cancel()
            eventMonitor?.stop()
            cancelSignalHandlers()
            if code == 0 {
                try save(state: .done, message: "😺 \(options.backend.displayName) complete", pid: process.pid, exitCode: code)
                try appendLog("\(options.backend.displayName) completed with exit 0")
            } else {
                try save(state: .failed, message: "🙀 \(options.backend.displayName) failed: exit \(code)", pid: process.pid, exitCode: code)
                try appendLog("\(options.backend.displayName) failed with exit \(code)")
                sendNotification(title: "🙀 \(options.backend.displayName) failed", body: "\(task) exited with \(code)")
            }
            return code
        } catch {
            fputs("catdex error: \(error)\n", stderr)
            return 1
        }
    }

    private func startHeartbeat(pid: Int32) {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + 15, repeating: 15)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            try? self.touch(pid: pid)
        }
        timer.resume()
        heartbeat = timer
    }

    private func startEventMonitor(pid: Int32) {
        let update: (AgentActivitySnapshot) -> Void = { [weak self] snapshot in
            guard let self else { return }
            if let previousState = try? self.save(
                state: snapshot.state,
                message: snapshot.message,
                pid: pid,
                codexSessionPath: snapshot.sessionPath
            ), snapshot.state == .review, previousState != .review {
                self.sendNotification(title: "🐱❓ \(self.options.backend.displayName) needs review", body: self.task)
            }
        }

        let monitor: AgentEventMonitoring = switch options.backend {
        case .codex:
            CodexEventMonitor(workspace: workspace, startedAt: Date(), onUpdate: update)
        case .opencode:
            OpenCodeEventMonitor(workspace: workspace, startedAt: Date(), onUpdate: update)
        }
        monitor.start()
        eventMonitor = monitor
    }

    private func installSignalHandlers(for process: CodexProcess) {
        let signals = [SIGINT, SIGTERM, SIGHUP]
        for signalNumber in signals {
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(
                signal: signalNumber,
                queue: DispatchQueue.global(qos: .userInitiated)
            )
            source.setEventHandler { [weak self] in
                self?.heartbeat?.cancel()
                self?.eventMonitor?.stop()
                process.terminateProcessGroup(signalNumber)
                process.restoreTerminalIfNeeded()
                _ = try? self?.save(
                    state: .failed,
                    message: "🙀 Interrupted by signal \(signalNumber)",
                    pid: process.pid,
                    exitCode: 128 + Int32(signalNumber)
                )
                try? self?.appendLog("interrupted by signal \(signalNumber)")
                exit(128 + signalNumber)
            }
            source.resume()
            signalSources.append(source)
        }
    }

    private func cancelSignalHandlers() {
        signalSources.forEach { $0.cancel() }
        signalSources.removeAll()
    }

    @discardableResult
    private func save(
        state: CatdexState,
        message: String,
        pid: Int32? = nil,
        codexSessionPath: String? = nil,
        exitCode: Int32? = nil
    ) throws -> CatdexState {
        sessionLock.lock()
        defer {
            sessionLock.unlock()
        }

        let previousState = session.state
        if let storedTask = store.loadSession(id: id)?.task,
           !storedTask.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            session.task = storedTask
        }
        session.state = state
        session.updatedAt = Date()
        session.pid = pid ?? session.pid
        session.lastMessage = message
        session.codexSessionPath = codexSessionPath ?? session.codexSessionPath
        session.exitCode = exitCode
        try store.save(session)
        return previousState
    }

    private func touch(pid: Int32) throws {
        sessionLock.lock()
        defer {
            sessionLock.unlock()
        }

        if let storedTask = store.loadSession(id: id)?.task,
           !storedTask.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            session.task = storedTask
        }
        session.updatedAt = Date()
        session.pid = pid
        try store.save(session)
    }

    private func appendLog(_ message: String) throws {
        let formatter = ISO8601DateFormatter()
        let line = "\(formatter.string(from: Date())) \(message)\n"
        let data = Data(line.utf8)
        if FileManager.default.fileExists(atPath: logURL.path) {
            let handle = try FileHandle(forWritingTo: logURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
        } else {
            try data.write(to: logURL)
        }
    }

    private func sendNotification(title: String, body: String) {
        guard ProcessInfo.processInfo.environment["CATDEX_NOTIFY"] != "0",
              let osascript = CommandLocator.findExecutable("osascript")
        else {
            return
        }

        let escapedTitle = appleScriptEscaped(title)
        let escapedBody = appleScriptEscaped(body)
        let process = Process()
        process.executableURL = osascript
        process.arguments = ["-e", "display notification \"\(escapedBody)\" with title \"\(escapedTitle)\""]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    private func appleScriptEscaped(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

final class CodexEventMonitor: AgentEventMonitoring {
    private let workspace: String
    private let startedAt: Date
    private let onUpdate: (AgentActivitySnapshot) -> Void
    private let queue = DispatchQueue(label: "catdex.codex-event-monitor", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var sessionURL: URL?

    init(workspace: String, startedAt: Date, onUpdate: @escaping (AgentActivitySnapshot) -> Void) {
        self.workspace = workspace
        self.startedAt = startedAt
        self.onUpdate = onUpdate
    }

    func start() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 2)
        timer.setEventHandler { [weak self] in
            self?.refresh()
        }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func refresh() {
        if sessionURL == nil {
            sessionURL = findSessionURL()
        }

        guard let sessionURL,
              let snapshot = inferActivity(from: sessionURL)
        else {
            onUpdate(AgentActivitySnapshot(
                state: .starting,
                message: "🐾 Waiting for Codex session",
                sessionPath: nil
            ))
            return
        }

        onUpdate(snapshot)
    }

    private func findSessionURL() -> URL? {
        let codexHome = ProcessInfo.processInfo.environment["CODEX_HOME"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex", isDirectory: true)
        let root = codexHome
            .appendingPathComponent("sessions", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        var candidates: [(url: URL, modifiedAt: Date)] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modifiedAt = values.contentModificationDate,
                  modifiedAt >= startedAt.addingTimeInterval(-10),
                  sessionMetaMatches(url)
            else {
                continue
            }
            candidates.append((url, modifiedAt))
        }

        return candidates.sorted { $0.modifiedAt > $1.modifiedAt }.first?.url
    }

    private func sessionMetaMatches(_ url: URL) -> Bool {
        guard let firstLine = try? String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n", maxSplits: 1)
            .first,
              let object = parseJSONObject(String(firstLine)),
              object["type"] as? String == "session_meta",
              let payload = object["payload"] as? [String: Any],
              payload["cwd"] as? String == workspace
        else {
            return false
        }

        return true
    }

    private func inferActivity(from url: URL) -> AgentActivitySnapshot? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }

        var state = CatdexState.waiting
        var message = "👀 Waiting for prompt"
        var pendingReviewCalls = Set<String>()
        var completedCalls = Set<String>()

        for line in content.split(separator: "\n") {
            guard let object = parseJSONObject(String(line)),
                  let type = object["type"] as? String,
                  let payload = object["payload"] as? [String: Any],
                  let payloadType = payload["type"] as? String
            else {
                continue
            }

            switch (type, payloadType) {
            case ("event_msg", "task_started"),
                 ("event_msg", "user_message"):
                state = .responding
                message = "✍️ Answering"

            case ("event_msg", "agent_reasoning"),
                 ("response_item", "reasoning"):
                state = .responding
                message = "✍️ Thinking"

            case ("event_msg", "agent_message"):
                if payload["phase"] as? String == "final_answer" {
                    state = .waiting
                    message = "👀 Answer complete; waiting"
                } else {
                    state = .responding
                    message = "✍️ Updating progress"
                }

            case ("response_item", "message"):
                let role = payload["role"] as? String
                let phase = payload["phase"] as? String
                if phase == "final_answer" {
                    state = .waiting
                    message = "👀 Answer complete; waiting"
                } else if role == "assistant" {
                    state = .responding
                    message = "✍️ Updating progress"
                }

            case ("event_msg", "task_complete"):
                state = .waiting
                message = "👀 Answer complete; waiting"

            case ("event_msg", "turn_aborted"):
                state = .failed
                message = "🙀 Turn aborted"

            case ("response_item", "function_call"),
                 ("response_item", "custom_tool_call"):
                let name = payload["name"] as? String ?? "tool"
                let callID = payload["call_id"] as? String
                let arguments = payload["arguments"] as? String ?? payload["input"] as? String ?? ""
                if name == "request_user_input" || arguments.contains("\"sandbox_permissions\":\"require_escalated\"") || arguments.contains("require_escalated") {
                    if let callID {
                        pendingReviewCalls.insert(callID)
                    }
                    state = .review
                    message = "🐱❓ Confirmation required"
                } else {
                    state = .responding
                    message = "✍️ Running \(name)"
                }

            case ("response_item", "function_call_output"),
                 ("response_item", "custom_tool_call_output"):
                if let callID = payload["call_id"] as? String {
                    completedCalls.insert(callID)
                    pendingReviewCalls.remove(callID)
                }
                if state != .failed {
                    state = .responding
                    message = "✍️ Processing tool result"
                }

            default:
                continue
            }
        }

        if !pendingReviewCalls.subtracting(completedCalls).isEmpty {
            state = .review
            message = "🐱❓ Confirmation required"
        }

        return AgentActivitySnapshot(state: state, message: message, sessionPath: url.path)
    }

    private func parseJSONObject(_ string: String) -> [String: Any]? {
        guard let data = string.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        return object
    }
}

final class OpenCodeEventMonitor: AgentEventMonitoring {
    private let workspace: String
    private let startedAt: Date
    private let onUpdate: (AgentActivitySnapshot) -> Void
    private let reader: OpenCodeActivityReader
    private let queue = DispatchQueue(label: "catdex.opencode-event-monitor", qos: .utility)
    private var timer: DispatchSourceTimer?

    init(
        workspace: String,
        startedAt: Date,
        reader: OpenCodeActivityReader = OpenCodeActivityReader(),
        onUpdate: @escaping (AgentActivitySnapshot) -> Void
    ) {
        self.workspace = workspace
        self.startedAt = startedAt
        self.reader = reader
        self.onUpdate = onUpdate
    }

    func start() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 2)
        timer.setEventHandler { [weak self] in
            self?.refresh()
        }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func refresh() {
        if let snapshot = reader.snapshot(workspace: workspace, startedAt: startedAt) {
            onUpdate(snapshot)
        } else {
            onUpdate(AgentActivitySnapshot(
                state: .running,
                message: "😼 Waiting for OpenCode session",
                sessionPath: nil
            ))
        }
    }
}

enum Git {
    static func currentBranch(in workspace: String) -> String? {
        guard let git = CommandLocator.findExecutable("git") else { return nil }
        let process = Process()
        let pipe = Pipe()
        process.executableURL = git
        process.arguments = ["branch", "--show-current"]
        process.currentDirectoryURL = URL(fileURLWithPath: workspace, isDirectory: true)
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let branch = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return branch?.isEmpty == false ? branch : nil
        } catch {
            return nil
        }
    }
}

enum CodexProcessError: Error, CustomStringConvertible {
    case spawnFailed(Int32)
    case changeDirectoryFailed(String, Int32)

    var description: String {
        switch self {
        case .spawnFailed(let code):
            return "failed to start Codex: \(String(cString: strerror(code)))"
        case .changeDirectoryFailed(let path, let code):
            return "failed to enter \(path): \(String(cString: strerror(code)))"
        }
    }
}

final class CodexProcess {
    let pid: pid_t
    private let parentProcessGroup: pid_t
    private let managesTerminal: Bool
    private let terminalLock = NSLock()
    private var terminalRestored = false

    private init(pid: pid_t, parentProcessGroup: pid_t, managesTerminal: Bool) {
        self.pid = pid
        self.parentProcessGroup = parentProcessGroup
        self.managesTerminal = managesTerminal
    }

    static func start(executable: URL, arguments: [String], workingDirectory: String) throws -> CodexProcess {
        let originalDirectory = FileManager.default.currentDirectoryPath
        guard FileManager.default.changeCurrentDirectoryPath(workingDirectory) else {
            throw CodexProcessError.changeDirectoryFailed(workingDirectory, errno)
        }
        defer {
            FileManager.default.changeCurrentDirectoryPath(originalDirectory)
        }

        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer {
            posix_spawnattr_destroy(&attributes)
        }

        let flags = Int16(POSIX_SPAWN_SETPGROUP)
        posix_spawnattr_setflags(&attributes, flags)
        posix_spawnattr_setpgroup(&attributes, 0)

        let environment = ProcessInfo.processInfo.environment.map { "\($0.key)=\($0.value)" }
        let argvStorage = ([executable.path] + arguments).map { strdup($0)! }
        let envStorage = environment.map { strdup($0)! }
        defer {
            argvStorage.forEach { free($0) }
            envStorage.forEach { free($0) }
        }

        var argv: [UnsafeMutablePointer<CChar>?] = argvStorage
        argv.append(nil)
        var env: [UnsafeMutablePointer<CChar>?] = envStorage
        env.append(nil)

        var pid: pid_t = 0
        let result = argv.withUnsafeMutableBufferPointer { argvPointer in
            env.withUnsafeMutableBufferPointer { envPointer in
                posix_spawn(
                    &pid,
                    executable.path,
                    nil,
                    &attributes,
                    argvPointer.baseAddress,
                    envPointer.baseAddress
                )
            }
        }
        guard result == 0 else {
            throw CodexProcessError.spawnFailed(result)
        }

        let parentProcessGroup = getpgrp()
        let managesTerminal = isatty(STDIN_FILENO) == 1
        if managesTerminal {
            signal(SIGTTOU, SIG_IGN)
            tcsetpgrp(STDIN_FILENO, pid)
        }

        return CodexProcess(pid: pid, parentProcessGroup: parentProcessGroup, managesTerminal: managesTerminal)
    }

    func wait() -> Int32 {
        defer {
            restoreTerminalIfNeeded()
        }

        var status: Int32 = 0
        while true {
            let result = waitpid(pid, &status, 0)
            if result == pid {
                break
            }
            if result == -1, errno == EINTR {
                continue
            }
            return 1
        }

        if status & 0x7f == 0 {
            return (status >> 8) & 0xff
        }

        let signalNumber = status & 0x7f
        if signalNumber != 0x7f {
            return 128 + signalNumber
        }

        return 1
    }

    func terminateProcessGroup(_ signalNumber: Int32) {
        kill(-pid, signalNumber)
    }

    func restoreTerminalIfNeeded() {
        terminalLock.lock()
        defer {
            terminalLock.unlock()
        }

        guard managesTerminal, !terminalRestored else { return }
        tcsetpgrp(STDIN_FILENO, parentProcessGroup)
        terminalRestored = true
    }
}

func printUsage() {
    print("""
    Usage: catdex [catdex options] [agent options] [prompt]
           catdex cleanup
           catdex doctor

    Catdex options:
      --backend <codex|opencode>
                             Agent backend. Use opencode for oh-my-openagent. Defaults to CATDEX_BACKEND, Settings, or codex.
      --agent-bin <command>  Agent executable to run.
      --codex-bin <command>  Codex executable to run. Selects the codex backend.
      --opencode-bin <command>
                             OpenCode executable to run. Selects the opencode backend.
      --dry-run              Create and finish a session without launching the agent.
      --task <name>          Accepted for compatibility. Rename the display title from CatdexMenu.
      -h, --help             Show catdex help. Use `catdex -- --help` for agent help.

    Examples:
      catdex
      catdex --backend opencode -- run "use oh-my-openagent"
      catdex --opencode-bin /path/to/opencode -- run --agent sisyphus "use oh-my-openagent"
      catdex "batch reminder debug"
      catdex --model gpt-5.4 "review API"
      catdex cleanup
      catdex doctor
    """)
}

do {
    let options = try CatdexOptions.parse(Array(CommandLine.arguments.dropFirst()))
    switch options.mode {
    case .run:
        let runner = try SessionRunner(options: options)
        exit(runner.run())
    case .cleanup:
        exit(CatdexMaintenance.cleanup())
    case .doctor:
        exit(CatdexMaintenance.doctor(options: options))
    }
} catch CatdexOptionError.help {
    printUsage()
    exit(0)
} catch CatdexOptionError.message(let message) {
    fputs("catdex: \(message)\n", stderr)
    printUsage()
    exit(2)
} catch CatdexOptionError.invalidBackend(let backend) {
    fputs("catdex: unknown backend: \(backend) (expected codex or opencode)\n", stderr)
    printUsage()
    exit(2)
} catch {
    fputs("catdex: \(error)\n", stderr)
    exit(1)
}

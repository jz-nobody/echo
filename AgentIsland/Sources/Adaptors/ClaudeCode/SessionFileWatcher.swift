import Foundation

final class SessionFileWatcher: Sendable {
    private let directoryPath: String
    private let onChange: @Sendable ([ClaudeSessionFile]) -> Void
    nonisolated(unsafe) private var source: DispatchSourceFileSystemObject?
    nonisolated(unsafe) private var dirFD: Int32 = -1
    nonisolated(unsafe) private var debounceWork: DispatchWorkItem?
    private let queue = DispatchQueue(label: "com.agentisland.session-watcher", qos: .utility)
    private let debounceInterval: TimeInterval

    init(
        directoryPath: String = NSHomeDirectory() + "/.claude/sessions",
        debounceInterval: TimeInterval = 0.5,
        onChange: @escaping @Sendable ([ClaudeSessionFile]) -> Void
    ) {
        self.directoryPath = directoryPath
        self.debounceInterval = debounceInterval
        self.onChange = onChange
    }

    func start() {
        dirFD = open(directoryPath, O_EVTONLY)
        guard dirFD >= 0 else {
            NSLog("[SessionFileWatcher] Cannot open directory: \(directoryPath)")
            return
        }

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: dirFD,
            eventMask: [.write, .delete, .rename],
            queue: queue
        )
        src.setEventHandler { [weak self] in
            self?.scheduleScan()
        }
        src.setCancelHandler { [weak self] in
            guard let self, self.dirFD >= 0 else { return }
            close(self.dirFD)
            self.dirFD = -1
        }
        self.source = src
        src.resume()

        queue.async { [weak self] in
            self?.scan()
        }
    }

    func stop() {
        debounceWork?.cancel()
        source?.cancel()
        source = nil
    }

    func scanNow() -> [ClaudeSessionFile] {
        SessionFileParser.parseDirectory(at: directoryPath)
    }

    private func scheduleScan() {
        debounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.scan()
        }
        debounceWork = work
        queue.asyncAfter(deadline: .now() + debounceInterval, execute: work)
    }

    private func scan() {
        let sessions = SessionFileParser.parseDirectory(at: directoryPath)
        onChange(sessions)
    }
}

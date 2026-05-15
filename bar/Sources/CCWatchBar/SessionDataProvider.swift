import Foundation

final class SessionDataProvider {
    private var dirSource: DispatchSourceFileSystemObject?
    private var pollTimer: DispatchSourceTimer?
    private var debounceWorkItem: DispatchWorkItem?
    private var dirFd: Int32 = -1

    private(set) var sessions: [Session] = []
    var onChange: (([Session]) -> Void)?

    func start() {
        reload()
        watchSessionsDir()
        startPollTimer()
    }

    func refresh() {
        reload()
    }

    func stop() {
        dirSource?.cancel()
        pollTimer?.cancel()
        dirSource = nil
        pollTimer = nil
        if dirFd >= 0 { close(dirFd); dirFd = -1 }
    }

    private func reload() {
        sessions = SessionParser.loadSessions()
        onChange?(sessions)
    }

    private func debouncedReload() {
        debounceWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.reload()
        }
        debounceWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: item)
    }

    private func watchSessionsDir() {
        let fm = FileManager.default
        let dir = SessionParser.sessionsDir
        if !fm.fileExists(atPath: dir) {
            try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }

        dirFd = Darwin.open(dir, O_EVTONLY)
        guard dirFd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: dirFd,
            eventMask: [.write],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.debouncedReload()
        }
        source.setCancelHandler { [weak self] in
            if let fd = self?.dirFd, fd >= 0 {
                Darwin.close(fd)
                self?.dirFd = -1
            }
        }
        source.resume()
        dirSource = source
    }

    private func startPollTimer() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 2, repeating: 2)
        timer.setEventHandler { [weak self] in
            self?.reload()
        }
        timer.resume()
        pollTimer = timer
    }
}

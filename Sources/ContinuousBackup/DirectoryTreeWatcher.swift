import Foundation
import CoreServices

/// Recursively watches a filesystem tree using FSEvents. Coalesces events
/// by path with a debounce window. The callback is invoked on a background
/// queue with a deduplicated set of paths that changed since the last batch.
final class DirectoryTreeWatcher {

    private var stream: FSEventStreamRef?
    private let callbackQueue: DispatchQueue
    private var pendingPaths: Set<String> = []
    private var debounceWorkItem: DispatchWorkItem?
    private let debounceInterval: TimeInterval
    private let debounceLock = NSLock()

    var onBatch: ((Set<String>) -> Void)?

    init(debounceInterval: TimeInterval = 0.5,
         callbackQueue: DispatchQueue = DispatchQueue(label: "claude-sessions.backup.watcher", qos: .utility)) {
        self.debounceInterval = debounceInterval
        self.callbackQueue = callbackQueue
    }

    deinit {
        stop()
    }

    func start(paths: [String]) {
        stop()

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        var context = FSEventStreamContext(
            version: 0,
            info: selfPtr,
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let flags = UInt32(
            kFSEventStreamCreateFlagFileEvents
            | kFSEventStreamCreateFlagNoDefer
            | kFSEventStreamCreateFlagUseCFTypes
            | kFSEventStreamCreateFlagWatchRoot
        )

        let stream = FSEventStreamCreate(
            nil,
            fsEventCallback,
            &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.25,                           // OS-level coalesce
            flags
        )

        guard let stream else { return }
        FSEventStreamSetDispatchQueue(stream, callbackQueue)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    func stop() {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
        debounceLock.lock()
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        pendingPaths.removeAll()
        debounceLock.unlock()
    }

    fileprivate func ingest(paths: [String]) {
        debounceLock.lock()
        for p in paths { pendingPaths.insert(p) }
        debounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.debounceLock.lock()
            let batch = self.pendingPaths
            self.pendingPaths.removeAll()
            self.debounceWorkItem = nil
            self.debounceLock.unlock()
            if !batch.isEmpty {
                self.onBatch?(batch)
            }
        }
        debounceWorkItem = work
        callbackQueue.asyncAfter(deadline: .now() + debounceInterval, execute: work)
        debounceLock.unlock()
    }
}

// FSEvents C callback — forwards to the Swift instance.
private let fsEventCallback: FSEventStreamCallback = { _, clientInfo, numEvents, eventPaths, _, _ in
    guard let clientInfo else { return }
    let watcher = Unmanaged<DirectoryTreeWatcher>.fromOpaque(clientInfo).takeUnretainedValue()

    // With kFSEventStreamCreateFlagUseCFTypes, eventPaths is a CFArray of CFStrings.
    let cfArray = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue()
    let count = CFArrayGetCount(cfArray)
    var paths: [String] = []
    paths.reserveCapacity(count)
    for i in 0..<count {
        let ptr = CFArrayGetValueAtIndex(cfArray, i)
        guard let ptr else { continue }
        let cfStr = Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue()
        paths.append(cfStr as String)
    }
    _ = numEvents
    watcher.ingest(paths: paths)
}

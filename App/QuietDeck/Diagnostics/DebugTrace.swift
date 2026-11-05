#if DEBUG
    import Foundation

    /// Writes one line per step to a log in the app container, for diagnosing problems.
    enum DebugTrace {
        static func append(_ message: String) {
            let directory = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs/QuietDeck")
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appending(path: "ui-trace.log")
            let line = Data("\(Date().formatted(.iso8601.time(includingFractionalSeconds: true))) \(message)\n".utf8)
            if let handle = try? FileHandle(forWritingTo: url) {
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: line)
                try? handle.close()
            } else {
                try? line.write(to: url)
            }
        }
    }
#endif

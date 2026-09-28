import Foundation

/// Appends every finished dictation to a markdown log so nothing is ever lost.
enum History {
    static let fileURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("LiveFlow/transcripts.md")

    static func append(_ text: String) {
        guard !text.isEmpty else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let entry = "\n## \(formatter.string(from: Date()))\n\(text)\n"

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            try? "# LiveFlow Transcripts\n".write(to: fileURL, atomically: true, encoding: .utf8)
        }
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(entry.utf8))
        }
    }
}

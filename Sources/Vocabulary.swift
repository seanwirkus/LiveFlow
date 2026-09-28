import Foundation

/// Short phrases that bias recognition toward Sean's recurring project terms.
/// Add one phrase per line to ~/LiveFlow/vocabulary.txt; changes take effect on
/// the next dictation without rebuilding the app.
enum Vocabulary {
    static let fileURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("LiveFlow/vocabulary.txt")

    private static let defaults = [
        "LiveFlow", "Wispr Flow", "VESC", "VESC Tool", "ESP32", "ESP32-C3",
        "Bambu Lab", "Bambu Studio", "Shapr3D", "Fusion 360", "FreeCAD",
        "OpenSCAD", "STEP file", "STL file", "CAD", "LED", "LED ring",
        "USB-C", "PETG", "LiDAR", "PWM", "UART", "GPIO", "accelerometer",
        "gyroscope", "Roborock"
    ]

    static var phrases: [String] {
        ensureFileExists()
        let custom = (try? String(contentsOf: fileURL, encoding: .utf8))?
            .split(whereSeparator: \Character.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") } ?? []
        return Array((defaults + custom).uniqued().prefix(100))
    }

    /// The new general-purpose model doesn't currently apply contextual strings,
    /// so normalize a small set of unambiguous technical aliases afterward.
    static func normalize(_ text: String) -> String {
        let replacements: [(String, String)] = [
            (#"\b(?:E\s*S\s*P|S)\s*[- ]?\s*32\s*[- ]?\s*C\s*3\b"#, "ESP32-C3"),
            (#"\bE\s*S\s*P\s*[- ]?\s*32\b"#, "ESP32"),
            (#"\bV\s*E\s*S\s*C\b"#, "VESC"),
            (#"\bvest\s+tool\b"#, "VESC Tool"),
            (#"\bshap(?:er|r)\s*3D\b"#, "Shapr3D"),
            (#"\bbamboo\s+(studio|lab)\b"#, "Bambu $1"),
            (#"\busb\s*[- ]?\s*c\b"#, "USB-C"),
            (#"\bstep(?=\s+(?:file|model|assembly)\b)"#, "STEP"),
            (#"\bstl(?=\s+(?:file|model)\b)"#, "STL"),
            (#"\bcad\b"#, "CAD"),
            (#"\bleds\b"#, "LEDs"),
            (#"\bled\b"#, "LED"),
            (#"\b(\d+)\s+v\b"#, "$1V")
        ]

        return replacements.reduce(text) { current, replacement in
            current.replacingOccurrences(of: replacement.0,
                                         with: replacement.1,
                                         options: [.regularExpression, .caseInsensitive])
        }
    }

    static func preservesCapitalization(of token: String) -> Bool {
        let protected = [
            "liveflow", "wispr", "vesc", "esp32", "esp32-c3", "bambu",
            "shapr3d", "fusion", "freecad", "openscad", "step", "stl",
            "cad", "led", "leds", "usb-c", "petg", "lidar", "pwm",
            "uart", "gpio", "roborock"
        ]
        return protected.contains(token.lowercased())
    }

    static func ensureFileExists() {
        guard !FileManager.default.fileExists(atPath: fileURL.path) else { return }
        let header = "# LiveFlow vocabulary — one short word or phrase per line\n"
        let contents = header + defaults.joined(separator: "\n") + "\n"
        try? contents.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}

private extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

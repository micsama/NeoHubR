import AppKit
import NeoHubRLib
import SwiftUI

enum ProjectIconKind {
    case symbol
    case emoji
}

enum ProjectPathFormatter {
    static func displayPath(_ url: URL) -> String {
        displayPath(url.path(percentEncoded: false))
    }

    static func displayPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let lowerPath = path.lowercased()
        let lowerHome = home.lowercased()
        if lowerPath == lowerHome {
            return "~"
        }
        if lowerPath.hasPrefix(lowerHome + "/") {
            let suffix = path.dropFirst(home.count)
            return "~" + suffix
        }
        return path
    }

    static func expandTilde(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }
}

struct ProjectIconDescriptor {
    let kind: ProjectIconKind
    let value: String
}

extension ProjectEntry {
    var iconDescriptor: ProjectIconDescriptor? {
        guard let icon, !icon.isEmpty else { return nil }
        if icon.hasPrefix("symbol:") {
            return ProjectIconDescriptor(kind: .symbol, value: String(icon.dropFirst("symbol:".count)))
        }
        if icon.hasPrefix("emoji:") {
            return ProjectIconDescriptor(kind: .emoji, value: String(icon.dropFirst("emoji:".count)))
        }
        return ProjectIconDescriptor(kind: .symbol, value: icon)
    }

    var customColor: Color? {
        colorHex.flatMap { Color(hex: $0) }
    }

    var isSession: Bool {
        if sessionPath != nil {
            return true
        }
        return id.pathExtension.lowercased() == "vim"
    }
}

extension Color {
    init?(hex: String) {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        guard cleaned.count == 6 || cleaned.count == 8 else { return nil }

        var value: UInt64 = 0
        guard Scanner(string: cleaned).scanHexInt64(&value) else { return nil }

        let r, g, b: Double
        if cleaned.count == 6 {
            r = Double((value & 0xFF0000) >> 16) / 255
            g = Double((value & 0x00FF00) >> 8) / 255
            b = Double(value & 0x0000FF) / 255
        } else {
            r = Double((value & 0xFF000000) >> 24) / 255
            g = Double((value & 0x00FF0000) >> 16) / 255
            b = Double((value & 0x0000FF00) >> 8) / 255
        }

        self = Color(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }

    func hexString() -> String? {
        let nsColor = NSColor(self)
        guard let rgb = nsColor.usingColorSpace(.sRGB) else { return nil }
        let r = Int(round(rgb.redComponent * 255))
        let g = Int(round(rgb.greenComponent * 255))
        let b = Int(round(rgb.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

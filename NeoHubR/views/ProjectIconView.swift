import NeoHubRLib
import SwiftUI

struct ProjectIconView: View {
    let entry: ProjectEntry
    let fallbackSystemName: String
    let size: CGFloat
    let isInvalid: Bool
    let fallbackColor: Color

    var body: some View {
        if let descriptor = entry.iconDescriptor {
            iconView(for: descriptor)
        } else if entry.isSession {
            Image(systemName: "doc.text.fill")
                .font(.system(size: size))
                .foregroundStyle(iconStyle)
                .frame(width: size, height: size)
        } else {
            Image(systemName: fallbackSystemName)
                .font(.system(size: size))
                .foregroundStyle(iconStyle)
                .frame(width: size, height: size)
        }
    }

    @ViewBuilder
    private func iconView(for descriptor: ProjectIconDescriptor) -> some View {
        switch descriptor.kind {
        case .symbol:
            Image(systemName: descriptor.value)
                .font(.system(size: size))
                .foregroundStyle(iconStyle)
                .frame(width: size, height: size)
        case .emoji:
            Text(descriptor.value)
                .font(.system(size: size))
                .frame(width: size, height: size, alignment: .center)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(iconStyle)
        }
    }

    private var iconStyle: AnyShapeStyle {
        if isInvalid {
            return AnyShapeStyle(.tertiary)
        }
        if let customColor = entry.customColor {
            return AnyShapeStyle(customColor)
        }
        return AnyShapeStyle(fallbackColor)
    }
}

// MARK: - Supporting Types & Extensions

struct ProjectIconDescriptor {
    enum Kind {
        case symbol
        case emoji
    }
    let kind: Kind
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

        let r: Double
        let g: Double
        let b: Double
        if cleaned.count == 6 {
            r = Double((value & 0xFF0000) >> 16) / 255
            g = Double((value & 0x00FF00) >> 8) / 255
            b = Double(value & 0x0000FF) / 255
        } else {
            r = Double((value & 0xFF00_0000) >> 24) / 255
            g = Double((value & 0x00FF_0000) >> 16) / 255
            b = Double((value & 0x0000_FF00) >> 8) / 255
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
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

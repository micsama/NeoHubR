import SwiftUI

struct SettingsGroupModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
            )
    }
}

extension View {
    func settingsGroup() -> some View {
        self.modifier(SettingsGroupModifier())
    }
}

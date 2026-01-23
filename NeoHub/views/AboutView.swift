import SwiftUI

struct AboutView: View {
    static let defaultWidth: CGFloat = 200
    static let defaultHeight: CGFloat = 200

    private var versionText: String {
        String(format: String(localized: "Version %@ (%@)"), APP_VERSION, APP_BUILD)
    }

    var body: some View {
        let content = VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)

            Text(APP_NAME)
                .font(.title2)
                .fontWeight(.semibold)

            Text(versionText)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            VStack(spacing: 4) {
                Text("© 2023 Alex Fedoseev")

                HStack(spacing: 2) {
                    Text("Icon by")
                    Link("u/danbee", destination: URL(string: "https://www.reddit.com/user/danbee/")!)
                        .foregroundStyle(.link)
                        .focusable(false)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: Self.defaultWidth, height: Self.defaultHeight)
        content
    }
}

struct AboutWindowContent: View {
    var body: some View {
        let content = AboutView()
            .background {
                if #available(macOS 26.0, *) {
                    GlassEffectContainer {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .glassEffect(
                                .clear  // 使用 regular 提供基础的背景模糊（防干扰）
                                    .interactive(true)  // 解决拖动闪烁
                                    .tint(Color.white.opacity(0.35)),  // 增加到 35%，确保深色背景下有底色
                                in: .rect(cornerRadius: 18, style: .continuous)
                            )
                            .ignoresSafeArea()
                    }
                } else {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.regularMaterial)
                }
            }

        if #available(macOS 15.0, *) {
            content.containerBackground(.clear, for: .window)
        } else {
            content
        }
    }
}

#Preview {
    AboutWindowContent()
}

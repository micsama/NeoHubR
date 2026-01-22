import SwiftUI

struct AboutView: View {
    static let defaultWidth: CGFloat = 300
    static let defaultHeight: CGFloat = 220

    private let versionText = "Version \(APP_VERSION) (\(APP_BUILD))"

    var body: some View {
        VStack(spacing: 12) {
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
    }
}

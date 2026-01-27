import SwiftUI

struct SwitcherContentView: View {
    @Bindable var viewModel: SwitcherViewModel
    @Namespace private var highlightNamespace

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isEmpty {
                emptyState
            } else {
                content
            }
        }
        .frame(width: 720, height: 380)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.15), lineWidth: 1)
                .blendMode(.overlay)
        )
        .onKeyPress(phases: .down, action: handleKeyPress)
        .onChange(of: viewModel.switcherMaxItems) { _, _ in viewModel.refreshData() }
    }

    private var content: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)

                SwitcherSearchField(
                    text: $viewModel.searchText,
                    onUp: { viewModel.moveSelection(-1) },
                    onDown: { viewModel.moveSelection(1) },
                    onReturn: { viewModel.activateSelected() },
                    onEscape: { viewModel.onDismiss() }
                )
            }
            .padding(14)
            .background(.quaternary.opacity(0.5))
            .overlay(alignment: .bottom) { Divider().opacity(0.5) }

            // List
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        let items = viewModel.filteredEntries
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            SwitcherRow(
                                item: item,
                                index: index,
                                isSelected: item.id == viewModel.selectedID,
                                query: viewModel.searchText,
                                namespace: highlightNamespace
                            )
                            .id(item.id)
                            .onTapGesture { viewModel.activate(at: index) }
                            // 如果下一个是 inactive 而当前是 active，加个间距
                            .padding(
                                .bottom,
                                (item.isActive && index + 1 < items.count && !items[index + 1].isActive) ? 12 : 0)
                        }
                    }
                    .padding(10)
                    .padding(.bottom, 20)
                }
                .onChange(of: viewModel.selectedID) { _, newID in
                    if let id = newID {
                        withAnimation(.spring(response: 0.25, dampingFraction: 1.0)) {
                            proxy.scrollTo(id, anchor: nil)
                        }
                    }
                }
                .onAppear {
                    if let id = viewModel.selectedID { proxy.scrollTo(id, anchor: .center) }
                }
            }

            Divider().opacity(0.5)

            // Footer
            HStack {
                Spacer()
                FooterButton(title: "Quit Selected", shortcut: "⌘D", action: viewModel.quitSelected)
                FooterButton(title: "Quit All", shortcut: "⇧⌘D", action: viewModel.quitAll)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles.rectangle.stack").font(.system(size: 36)).foregroundStyle(.tertiary)
            Text("No projects found").font(.headline).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button("Settings", action: viewModel.onOpenSettings).buttonStyle(.bordered)
                Button("Close", action: viewModel.onDismiss).buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func handleKeyPress(_ press: KeyPress) -> KeyPress.Result {
        guard press.modifiers.contains(.command) else { return .ignored }
        switch press.characters {
        case "w":
            viewModel.onDismiss()
            return .handled
        case "d":
            press.modifiers.contains(.shift) ? viewModel.quitAll() : viewModel.quitSelected()
            return .handled
        default:
            if let d = press.characters.first?.wholeNumberValue {
                viewModel.activate(at: d == 0 ? 9 : d - 1)
                return .handled
            }
            return .ignored
        }
    }
}

// MARK: - Components

private struct SwitcherRow: View {
    let item: SwitcherItem
    let index: Int
    let isSelected: Bool
    let query: String
    let namespace: Namespace.ID

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            ProjectIconView(
                entry: item.entry,
                fallbackSystemName: "folder.fill",
                size: 16,
                isInvalid: item.isInvalid,
                fallbackColor: .secondary
            )
            .frame(width: 20, height: 20)
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        item.isActive
                            ? Color.green.opacity(0.12) : (item.isStarred ? Color.yellow.opacity(0.12) : .clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(item.isActive ? Color.green : (item.isStarred ? Color.yellow : .clear), lineWidth: 1)
            )

            // Text
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(highlight(item.name, query: query))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(item.isInvalid ? .secondary : .primary)

                    if item.isInvalid { StatusTag("Not available") }
                    if item.isSession { StatusTag("Session") }
                }

                Text(highlight(item.displayPath, query: query))
                    .font(.system(size: 11))
                    .foregroundStyle(item.isInvalid ? Color.secondary.opacity(0.6) : .secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Shortcut
            if index < 10 {
                Text("⌘\(index == 9 ? 0 : index + 1)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(isSelected ? .secondary : .tertiary)
                    .padding(4)
                    .background(
                        isSelected ? .white.opacity(0.2) : .primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 4)
                    )
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .contentShape(Rectangle())
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
                    .matchedGeometryEffect(id: "bg", in: namespace)
            }
        }
        .overlay(alignment: .leading) {
            if item.isActive {
                Capsule().fill(Color.green).frame(width: 3, height: 32).padding(.leading, 1)
            }
        }
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.accentColor, lineWidth: 1)
            }
        }
    }

    private func highlight(_ text: String, query: String) -> AttributedString {
        guard !query.isEmpty else { return AttributedString(text) }
        var attr = AttributedString(text)
        if let range = attr.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) {
            attr[range].foregroundColor = .accentColor
        }
        return attr
    }
}

private struct StatusTag: View {
    let text: LocalizedStringKey
    init(_ text: LocalizedStringKey) { self.text = text }
    var body: some View {
        (Text("(") + Text(text) + Text(")"))
            .font(.system(size: 12))
            .foregroundStyle(.tertiary)
    }
}

private struct FooterButton: View {
    let title: String, shortcut: String, action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                Text(shortcut).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 4))
            }
            .font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }
}

struct SwitcherSearchField: NSViewRepresentable {
    @Binding var text: String
    var onUp: () -> Void
    var onDown: () -> Void
    var onReturn: () -> Void
    var onEscape: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.delegate = context.coordinator
        field.placeholderString = String(localized: "Search")
        field.isBordered = false
        field.backgroundColor = .clear
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 16)
        DispatchQueue.main.async { field.window?.makeFirstResponder(field) }
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        if field.stringValue != text { field.stringValue = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SwitcherSearchField
        init(_ parent: SwitcherSearchField) { self.parent = parent }

        func controlTextDidChange(_ obj: Notification) {
            if let field = obj.object as? NSTextField { parent.text = field.stringValue }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            let map: [Selector: () -> Void] = [
                #selector(NSResponder.moveUp(_:)): parent.onUp,
                #selector(NSResponder.insertBacktab(_:)): parent.onUp,
                #selector(NSResponder.moveDown(_:)): parent.onDown,
                #selector(NSResponder.insertTab(_:)): parent.onDown,
                #selector(NSResponder.insertNewline(_:)): parent.onReturn,
                #selector(NSResponder.cancelOperation(_:)): parent.onEscape,
            ]
            if let action = map[selector] {
                action()
                return true
            }
            return false
        }
    }
}

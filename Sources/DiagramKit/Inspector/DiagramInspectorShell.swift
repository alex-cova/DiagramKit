import SwiftUI

/// Shared inspector chrome: theme + geometry hooks, with plugin domain content slotted in.
public struct DiagramInspectorShell<Content: View>: View {
    @Binding public var themeID: String
    public var title: String
    public var onClose: () -> Void
    public var showThemePicker: Bool = true
    @ViewBuilder public var content: () -> Content

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Theme.Spacing.sm) {
                Text(title)
                    .font(Theme.Typography.paneTitle)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: Theme.Spacing.sm)
                Button("Close inspector", systemImage: "xmark.circle.fill", action: onClose)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                    .help("Close inspector")
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.md)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    if showThemePicker {
                        Picker("Theme", selection: $themeID) {
                            ForEach(DiagramThemeCatalog.all) { theme in
                                Text(theme.displayName).tag(theme.id)
                            }
                        }
                    }
                    content()
                }
                .padding(Theme.Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
        }
        .inspectorSurface()
        .themedAnimation(Theme.Motion.standard, value: title)
    }
    public init(
        themeID: Binding<String>,
        title: String,
        onClose: @escaping () -> Void,
        showThemePicker: Bool = true,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self._themeID = themeID
        self.title = title
        self.onClose = onClose
        self.showThemePicker = showThemePicker
        self.content = content
    }
}

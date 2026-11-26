import SwiftUI

/// List-and-detail layout built on Apple's `NavigationSplitView`, which Apple
/// describes as fully adaptive on iPhone Duo:
///
/// - Folded (outer screen, compact width): one column. Tapping a row pushes its detail.
/// - Unfolded (inner screen, regular width): list and detail side by side.
///
/// The system decides from the size class and handles the Duo's asymmetric safe areas
/// (camera, status bar, vertical toolbars and tab bar) itself, so there are no hand-picked
/// widths or safe-area overrides here. The selection is owned by the parent view, so
/// folding or unfolding keeps you on the same item.
struct AdaptiveSplitView<Item: Hashable, Sidebar: View, Detail: View, Placeholder: View>: View {
    @Binding var selection: Item?
    var sidebar: () -> Sidebar
    var detail: (Item) -> Detail
    var placeholder: () -> Placeholder

    /// Keep both columns tiled side by side when unfolded, rather than hiding the list.
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    /// When folded, show the detail while something is selected, otherwise the list.
    @State private var compactColumn: NavigationSplitViewColumn = .sidebar

    init(
        selection: Binding<Item?>,
        @ViewBuilder sidebar: @escaping () -> Sidebar,
        @ViewBuilder detail: @escaping (Item) -> Detail,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        _selection = selection
        self.sidebar = sidebar
        self.detail = detail
        self.placeholder = placeholder
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility, preferredCompactColumn: $compactColumn) {
            sidebar()
                .navigationSplitViewColumnWidth(min: 300, ideal: 360, max: 440)
        } detail: {
            if let selection {
                detail(selection)
                    .id(selection)
            } else {
                placeholder()
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear {
            compactColumn = selection == nil ? .sidebar : .detail
        }
        .onChange(of: selection) { _, newValue in
            compactColumn = newValue == nil ? .sidebar : .detail
        }
    }
}

enum DuoLayout {
    /// Keeps long text readable on the wide unfolded screen.
    static let readableWidth: CGFloat = 720
}

extension View {
    /// Centers content and caps its width, so text doesn't stretch across the unfolded screen.
    func readableWidth() -> some View {
        frame(maxWidth: DuoLayout.readableWidth)
            .frame(maxWidth: .infinity)
    }
}

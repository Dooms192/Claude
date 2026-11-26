import SwiftUI

/// The layout that makes Recap work properly on the iPhone Duo.
///
/// - Folded (5.4" outer screen): one column. Tap a row to push its detail.
/// - Unfolded (7.6" inner screen): list on the left, detail on the right.
///
/// It decides from the real width the app has, not from the device model or size
/// class, so it does the right thing however iOS labels each Duo screen, in Split View,
/// and on any future device. The selection is owned by the parent view, so folding or
/// unfolding keeps you on the same item: unfold while reading a day and it shows on the
/// right; fold and that day stays open full-screen.
struct AdaptiveSplitView<Item: Hashable, Sidebar: View, Detail: View, Placeholder: View>: View {
    @Binding var selection: Item?
    var splitWidth: CGFloat
    var sidebar: () -> Sidebar
    var detail: (Item) -> Detail
    var placeholder: () -> Placeholder

    @State private var width: CGFloat = 0

    init(
        selection: Binding<Item?>,
        splitWidth: CGFloat = DuoLayout.splitWidth,
        @ViewBuilder sidebar: @escaping () -> Sidebar,
        @ViewBuilder detail: @escaping (Item) -> Detail,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        _selection = selection
        self.splitWidth = splitWidth
        self.sidebar = sidebar
        self.detail = detail
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if width >= splitWidth {
                HStack(spacing: 0) {
                    NavigationStack { sidebar() }
                        .frame(width: min(400, max(300, width * 0.38)))
                    Divider().ignoresSafeArea()
                    NavigationStack {
                        if let selection {
                            detail(selection)
                        } else {
                            placeholder()
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                NavigationStack {
                    sidebar()
                        .navigationDestination(item: $selection) { item in
                            detail(item)
                        }
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newWidth in
            width = newWidth
        }
    }
}

enum DuoLayout {
    /// Widths at or above this get two columns. The Duo's 5.4" outer screen is about
    /// 466 points wide in portrait, and the unfolded 7.6" inner screen is at least about
    /// 626 points, so this sits safely between them.
    static let splitWidth: CGFloat = 560
    /// Keeps long text readable on the wide unfolded screen.
    static let readableWidth: CGFloat = 720
}

/// Measures the width a view has, for layouts that rearrange themselves when the Duo unfolds.
struct WidthReader: ViewModifier {
    @Binding var width: CGFloat

    func body(content: Content) -> some View {
        content.onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newWidth in
            width = newWidth
        }
    }
}

extension View {
    func readWidth(into width: Binding<CGFloat>) -> some View {
        modifier(WidthReader(width: width))
    }

    /// Centers content and caps its width, so text doesn't stretch across the unfolded screen.
    func readableWidth() -> some View {
        frame(maxWidth: DuoLayout.readableWidth)
            .frame(maxWidth: .infinity)
    }
}

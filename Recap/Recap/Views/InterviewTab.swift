import SwiftUI

/// The Interview tab: Prep (build stories) and Competencies (browse your evidence), switched
/// with the control at the top of each list.
///
/// Both stay alive while you switch, so a half-typed request or an open competency is still
/// there when you come back.
struct InterviewTab: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        ZStack {
            layer(InterviewPrepView(), isShowing: router.interviewMode == .prep)
            layer(CompetenciesView(), isShowing: router.interviewMode == .competencies)
        }
    }

    private func layer(_ content: some View, isShowing: Bool) -> some View {
        content
            .opacity(isShowing ? 1 : 0)
            // Swap instantly. A cross-fade briefly showed both screens' Prep/Competencies
            // switches at once, which looked like a stray highlight.
            .transaction(value: router.interviewMode) { $0.animation = nil }
            .allowsHitTesting(isShowing)
            .accessibilityHidden(!isShowing)
    }
}

import SwiftUI

// MARK: - TourHostModifier

/// Hosts a guided tour over a screen's content: it reads every `.tourAnchor` in the subtree, resolves the
/// current step's target in its own coordinate space, and draws the `TourOverlay` on top. The tour
/// auto-starts once — when the screen is `enabled` and its `hasSeen` flag is still false — and flips the
/// flag on finish or skip. Re-arming the flag (Settings → Replay) restarts it on the next appearance.
struct TourHostModifier: ViewModifier {
    let tour: Tour
    @Binding var hasSeen: Bool
    /// Whether this host's screen is the one on-screen right now (e.g. the Spaces tab is selected).
    var enabled: Bool

    @State private var active = false
    @State private var index = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlayPreferenceValue(TourAnchorKey.self) { anchors in
                // Outer reader *respects* the safe area, so its insets include the status bar and any
                // navigation bar — exactly what the coach panel needs to clear that chrome. (Reading the
                // insets off the inner full-screen reader instead gives zero, which slid the panel under
                // the nav bar on the Simulate / Editor screens.)
                GeometryReader { safeProxy in
                    let insets = safeProxy.safeAreaInsets
                    // Inner reader ignores the safe area, so anchors, scrim, spotlight and arrow all resolve
                    // in one full-screen space aligned with the real controls (no drift).
                    GeometryReader { proxy in
                        if active, enabled, tour.steps.indices.contains(index) {
                            let step = tour.steps[index]
                            let rect = step.anchor.flatMap { anchors[$0] }.map { proxy[$0] }
                            TourOverlay(
                                step: step,
                                targetRect: rect,
                                containerSize: proxy.size,
                                safeArea: insets,
                                index: index,
                                total: tour.steps.count,
                                reduceMotion: reduceMotion,
                                onNext: advance,
                                onSkip: finish
                            )
                        }
                    }
                    .ignoresSafeArea()
                }
            }
            // Re-evaluates on appear, when the screen becomes current, and when the flag is re-armed.
            .task(id: "\(enabled)-\(hasSeen)") { await maybeStart() }
    }

    private func maybeStart() async {
        guard enabled, !hasSeen, !active, !tour.steps.isEmpty else { return }
        // Let the screen's own entrance settle so anchors are laid out before the spotlight reads them.
        try? await Task.sleep(for: .milliseconds(500))
        guard !Task.isCancelled, enabled, !hasSeen, !active else { return }
        index = 0
        withAnimation(reduceMotion ? nil : Motion.card) { active = true }
    }

    private func advance() {
        if index + 1 < tour.steps.count {
            withAnimation(reduceMotion ? nil : Motion.card) { index += 1 }
        } else {
            finish()
        }
    }

    private func finish() {
        withAnimation(reduceMotion ? nil : Motion.dismiss) { active = false }
        hasSeen = true
    }
}

extension View {
    /// Attach a guided tour to this screen. `hasSeen` persists the "already shown" flag; `enabled` gates
    /// screens that share a hierarchy (e.g. the Spaces tab) so the tour only fires when they're current.
    func tourHost(_ tour: Tour, hasSeen: Binding<Bool>, enabled: Bool = true) -> some View {
        modifier(TourHostModifier(tour: tour, hasSeen: hasSeen, enabled: enabled))
    }
}

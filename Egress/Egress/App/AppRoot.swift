import EgressEngine
import SwiftUI

// MARK: - RootGate

/// The launch gate: the pixel landing screen, then the app. Shown on every launch (design decision) —
/// START cross-fades into the tab bar. Sits above the environment injection in `EgressApp`, so both the
/// landing and the app inherit dependencies, feedback and the model container.
struct RootGate: View {
    @State private var entered = false

    var body: some View {
        ZStack {
            if entered {
                AppRoot()
                    .transition(.opacity)
            } else {
                LandingView { withAnimation(.easeInOut(duration: 0.5)) { entered = true } }
                    .transition(.opacity)
            }
        }
    }
}

// MARK: - AppRoot

/// The app root (A-02). Two home destinations — **Spaces** and **Learn** — under a floating pill tab bar
/// with a raised centre **＋**. A simulation can't start without a space to run, so the ＋ is an *action*,
/// not a screen: it opens the editor on a blank room; tapping a preset opens the editor seeded with that
/// preset. Both open as full-screen covers, so the editor and any run it pushes sit *above* the tab bar
/// (the bar never draws over them) and the home bar shows only on the two home screens.
struct AppRoot: View {
    @State private var selection: AppTab = .spaces
    /// Non-nil while a preset-seeded editor cover is up.
    @State private var editorPreset: VenuePreset?
    /// Drives the blank-editor cover raised by the centre ＋.
    @State private var showBlankEditor = false
    /// Raised by a full-bleed pushed screen (a case-study detail) that wants the floating bar out of the
    /// way, so its own bottom CTA can reach the true screen edge.
    @State private var hideTabBar = false
    @Environment(FeedbackServices.self)
    private var feedback: FeedbackServices?

    var body: some View {
        ZStack {
            Color.egGround.ignoresSafeArea()

            screen
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if !hideTabBar {
                        EgressTabBar(selection: $selection, onCreate: openBlankEditor)
                    }
                }
                .onPreferenceChange(HidesTabBarKey.self) { hideTabBar = $0 }
        }
        // The Spaces coachmark tour is hosted here so it can point at both the page and the tab bar ＋;
        // it only arms while Spaces is the current tab.
        .tourHost(
            Tours.spaces,
            hasSeen: Binding(
                get: { feedback?.settings.seenSpacesTour ?? true },
                set: { feedback?.settings.seenSpacesTour = $0 }
            ),
            enabled: selection == .spaces
        )
        .tint(Color.egDataGreen) // the single accent
        .preferredColorScheme(.light) // one committed cream look — never the system dark theme
        .fullScreenCover(isPresented: $showBlankEditor) {
            // The editor lives in a stack (its Run button pushes the sim); give it one, plus an explicit
            // close since its own `dismiss` can't reach out of the stack to shut the cover.
            NavigationStack { EditorRootView(onClose: { showBlankEditor = false }) }
        }
        .fullScreenCover(item: $editorPreset) { preset in
            NavigationStack { EditorRootView(preset: preset, onClose: { editorPreset = nil }) }
        }
        #if DEBUG
            .touchIndicators() // recording aid; compiled out of release (§E.3)
        #endif
    }

    @ViewBuilder
    private var screen: some View {
        switch selection {
        case .spaces: SpacesRootView(onOpenPreset: { editorPreset = $0 })
        case .learn: LearnRootView(onPlay: { editorPreset = $0 })
        }
    }

    private func openBlankEditor() {
        feedback?.haptics.play(.toolTap)
        showBlankEditor = true
    }
}

// MARK: - HidesTabBarKey

/// A pushed screen sets this to pull the floating tab bar (and its reserved bottom inset) off-screen —
/// so a full-bleed detail like a case study reads edge-to-edge with its own bottom CTA. `AppRoot` reads
/// it via `onPreferenceChange`; leaving the screen resets it to the default (bar shown).
struct HidesTabBarKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

extension View {
    /// Hide the home tab bar while this screen is on top (see `HidesTabBarKey`).
    func hidesTabBar(_ hidden: Bool = true) -> some View {
        preference(key: HidesTabBarKey.self, value: hidden)
    }
}

// MARK: - CanvasHost

/// Hosts the simulation canvas + HUD, forced dark regardless of system appearance
/// (the canvas is dark even in Light Mode — design spec).
struct CanvasHost<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.egCanvasBase)
            .environment(\.colorScheme, .dark)
    }
}

#Preview {
    AppRoot().environment(\.dependencies, .preview())
}

import SwiftUI

// MARK: - EgressSoundButtonStyle

/// A `ButtonStyle` that triggers a subtle, low-volume button tap sound effect on tap.
struct EgressSoundButtonStyle: ButtonStyle {
    @Environment(FeedbackServices.self) private var feedback: FeedbackServices?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.75 : 1.0)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed {
                    feedback?.sound.play(.buttonTap)
                }
            }
    }
}

extension View {
    /// Applies global button tap sound feedback to all buttons in this view tree.
    func egButtonSound() -> some View {
        buttonStyle(EgressSoundButtonStyle())
    }
}

import SwiftUI

// MARK: - TypewriterText

/// Reveals a string one character at a time — the guide "talking" effect used in the coachmark bubbles —
/// and fires a short blip per spoken letter so it reads like Celeste-style dialogue.
///
/// Purely visual: it renders a plain `Text`, so the caller styles it with the usual `.font` /
/// `.foregroundStyle` / `.frame` modifiers (they propagate through the environment). The *full* string is
/// always what accessibility reads — the parent bubble already exposes `step.message` via its combined
/// label, so VoiceOver never waits on the animation. Set `instant` (e.g. under Reduce Motion) to show the
/// whole line at once and stay silent. Tapping the text completes the current line immediately.
struct TypewriterText: View {
    /// The full line to type out.
    let text: String
    /// Seconds between revealed characters.
    var interval: Double = 0.032
    /// Extra dwell after sentence-ending punctuation, for a natural spoken cadence.
    var punctuationPause: Double = 0.20
    /// Fire a blip every Nth *spoken* (non-whitespace) character — 1 is every letter, 2 softens the patter.
    var blipStride: Int = 2
    /// Reveal everything instantly and emit no blips (Reduce Motion, or a re-shown line).
    var instant: Bool = false
    /// Play one speech blip. Called on spoken characters, throttled by `blipStride`.
    var onBlip: () -> Void = {}

    /// How many leading characters are currently visible.
    @State private var shown = 0
    /// Set by a tap to finish the current line at once.
    @State private var completed = false

    var body: some View {
        Text(String(text.prefix(shown)))
            .contentShape(Rectangle())
            .onTapGesture { completed = true }
            // Re-typing keys on both the copy and the instant flag, so a new step (or a Reduce-Motion
            // change) restarts cleanly rather than continuing the previous line.
            .task(id: "\(instant)\u{1F}\(text)") { await type() }
    }

    private func type() async {
        completed = false
        guard !instant else { shown = text.count; return }

        let characters = Array(text)
        shown = 0
        var spoken = 0
        let stride = max(1, blipStride)

        for index in characters.indices {
            if completed { shown = characters.count; return }
            shown = index + 1

            let character = characters[index]
            if !character.isWhitespace {
                spoken += 1
                if spoken % stride == 0 { onBlip() }
            }

            var pause = interval
            if ".!?".contains(character) {
                pause += punctuationPause
            } else if ",;:".contains(character) {
                pause += punctuationPause * 0.5
            }

            try? await Task.sleep(for: .seconds(pause))
            if Task.isCancelled { return }
        }
    }
}

import SwiftUI

// MARK: - SettingsSheet

/// The app's one settings surface (§4.2): the audio and haptic controls (§3.6 / §5.5.4), a plain-language
/// note on how the Safety Score is built, and the safety-framing disclaimer that must ride along with any
/// verdict — "educational analysis, not certified engineering advice" (§D). Deliberately small: v3 keeps
/// the settings scope to what actually ships. Dressed in the app's pixel chrome (design: the Settings
/// screenshot) — each section is a cream card inside a chunky charcoal pixel border, letter-spaced section
/// labels above and quiet footers below, and the switches use the pixel toggle. Content is unchanged.
struct SettingsSheet: View {
    @Environment(FeedbackServices.self)
    private var feedback
    @Environment(\.dismiss)
    private var dismiss

    var body: some View {
        @Bindable var settings = feedback.settings
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: EgressSpacing.xl) {
                    Text("Settings")
                        .font(.system(size: 34, weight: .black, design: .serif))
                        .foregroundStyle(Color.egTextPrimary)
                        .padding(.top, EgressSpacing.sm)

                    settingsCard("Sound", footer: SettingsCopy.soundFooter) {
                        toggleRow(
                            "Sound effects", isOn: $settings.soundEnabled,
                            hint: "Master switch for the alarm, escalation and verdict cues"
                        )
                        rowDivider
                        toggleRow(
                            "Reduce audio intensity", isOn: $settings.reduceAudioIntensity,
                            hint: "Softens the cues by about six decibels"
                        )
                        .disabled(!settings.soundEnabled)
                    }

                    settingsCard("Haptics", footer: SettingsCopy.hapticsFooter) {
                        toggleRow(
                            "Reduce haptic intensity", isOn: $settings.reduceHapticIntensity,
                            hint: "Halves haptic strength and simplifies the crush pattern"
                        )
                    }

                    settingsCard("Accessibility", footer: SettingsCopy.accessibilityFooter) {
                        toggleRow(
                            "Colour-blind patterns", isOn: $settings.colorBlindPatterns,
                            hint: "Adds dot and hatch textures to the density bands so crowding reads without colour"
                        )
                    }

                    settingsCard("Tutorials", footer: SettingsCopy.tutorialsFooter) {
                        Button {
                            settings.replayTours()
                            feedback.haptics.play(.toolTap)
                            dismiss() // return to the screen so the re-armed coachmarks can play
                        } label: {
                            HStack {
                                Label("Replay tutorials", systemImage: "sparkles")
                                    .font(.system(.body, design: .rounded, weight: .semibold))
                                    .foregroundStyle(Color.egTextPrimary)
                                Spacer()
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color.egTextTertiary)
                            }
                            .padding(.horizontal, EgressSpacing.lg)
                            .padding(.vertical, EgressSpacing.md)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Shows the guided tips again on Spaces, the editor and a simulation")
                    }

                    settingsCard("How scoring works") {
                        prose(SettingsCopy.scoring, style: .callout)
                    }

                    settingsCard("Disclaimer", footer: SettingsCopy.privacyFooter) {
                        prose(SettingsCopy.disclaimer, style: .footnote)
                    }
                }
                .padding(.horizontal, EgressSpacing.lg)
                .padding(.bottom, EgressSpacing.xxl)
            }
            .background(Color.egGround)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.egTextPrimary)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear { feedback.sound.play(.popup) }
        .egButtonSound()
    }

    // MARK: Pieces

    /// One titled section: a letter-spaced uppercase label, a pixel-bordered cream card of rows, and an
    /// optional quiet footer beneath — the Form section restyled as pixel chrome.
    private func settingsCard(
        _ title: String,
        footer: String? = nil,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: EgressSpacing.sm) {
            Text(title)
                .font(.system(.footnote, weight: .heavy))
                .fontWidth(.condensed)
                .textCase(.uppercase)
                .tracking(1.4)
                .foregroundStyle(Color.egTextTertiary)
                .padding(.leading, EgressSpacing.xs)

            VStack(spacing: 0) { content() }
                .egPixelSurface(radius: EgressRadius.lg)

            if let footer {
                Text(footer)
                    .egBody(.footnote)
                    .foregroundStyle(Color.egTextSecondary)
                    .padding(.horizontal, EgressSpacing.xs)
            }
        }
    }

    /// A labelled switch row inside a card — pixel toggle on the right, rounded-sans label on the left.
    private func toggleRow(_ title: String, isOn: Binding<Bool>, hint: String) -> some View {
        Toggle(title, isOn: isOn)
            .toggleStyle(PixelToggleStyle())
            .font(.system(.body, design: .rounded, weight: .semibold))
            .foregroundStyle(Color.egTextPrimary)
            .padding(.horizontal, EgressSpacing.lg)
            .padding(.vertical, EgressSpacing.md)
            .accessibilityHint(hint)
    }

    /// A prose block inside a card — the scoring note and the disclaimer.
    private func prose(_ text: String, style: Font.TextStyle) -> some View {
        Text(text)
            .egBody(style)
            .foregroundStyle(Color.egTextSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(EgressSpacing.lg)
    }

    /// The tan hairline between rows in a card.
    private var rowDivider: some View {
        Rectangle()
            .fill(Color.egSeparator)
            .frame(height: 1)
            .padding(.horizontal, EgressSpacing.lg)
    }
}

// MARK: - PixelToggleStyle

/// The app's switch, drawn in pixel chrome (design: the Settings screenshot): a chunky charcoal pixel
/// border around a stadium track that fills sage green when on, with a cream pixel-cornered knob that
/// slides between the ends. Built on the real `Toggle`, so VoiceOver still reads it as a switch.
struct PixelToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        PixelSwitch(configuration: configuration)
    }

    private struct PixelSwitch: View {
        let configuration: ToggleStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled

        private let trackWidth: CGFloat = 52
        private let trackHeight: CGFloat = 30
        private let knob: CGFloat = 22

        var body: some View {
            HStack(spacing: EgressSpacing.md) {
                configuration.label
                    .frame(maxWidth: .infinity, alignment: .leading)
                track
            }
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(Motion.tap) { configuration.isOn.toggle() } }
            .opacity(isEnabled ? 1 : 0.45)
        }

        private var track: some View {
            PixelCornerRect(radius: trackHeight / 2, pixel: 4)
                .fill(configuration.isOn ? Color.egDataGreen : Color.egSurfaceSunken)
                .frame(width: trackWidth, height: trackHeight)
                .overlay(PixelCornerRect(radius: trackHeight / 2, pixel: 4).strokeBorder(Color.egOutline, lineWidth: 2))
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    PixelCornerRect(radius: knob / 2, pixel: 3)
                        .fill(Color.egSurfaceRaised)
                        .overlay(PixelCornerRect(radius: knob / 2, pixel: 3).strokeBorder(Color.egOutline, lineWidth: 1.5))
                        .frame(width: knob, height: knob)
                        .padding((trackHeight - knob) / 2)
                }
        }
    }
}

// MARK: - SettingsCopy

/// The long-form copy, held apart so the view above stays readable. Unchanged from the shipping settings.
private enum SettingsCopy {
    // swiftlint:disable line_length
    static let soundFooter = "Cues respect the silent switch and mix with your own audio. No safety event is ever signalled by sound alone."
    static let hapticsFooter = "Haptics play on device only, and only for events that concern the analyst — thresholds, casualties and verdicts."
    static let accessibilityFooter = "The crowding bands carry a texture as well as a colour — sparse dots for congestion, diagonal hatch for at-risk, cross-hatch for a crush — so density is never signalled by colour alone."
    static let tutorialsFooter = "Bring back the guided coachmarks — the safety inspector will walk you through each screen again."
    static let scoring = "The Safety Score starts at 100 and deducts for casualties, dangerous density, the fraction of the crowd left at risk, and slow clearance. A run PASSES, gets a WARN, or FAILS on those same thresholds."
    static let disclaimer = "Egress is an educational analysis tool, not certified engineering advice. Runs are simplified models — always defer to a qualified fire-safety professional and your local building code."
    static let privacyFooter = "100% on-device. Egress asks for no permissions — no network, location, camera or contacts — and nothing you simulate ever leaves this iPhone."
    // swiftlint:enable line_length
}

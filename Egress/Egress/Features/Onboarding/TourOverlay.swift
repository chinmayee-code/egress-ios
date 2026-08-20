import SwiftUI

// MARK: - TourOverlay

/// The coachmark itself: a dimming scrim with a spotlight cut around the current target, an arrow pointing
/// at it, and the guide mascot speaking from a comic bubble with Next / Skip and progress dots. Pure
/// presentation — the host owns state and hands in the resolved target rect and callbacks.
struct TourOverlay: View {
    let step: TourStep
    /// The highlighted control's frame in the host's coordinate space, or nil for an untethered step.
    let targetRect: CGRect?
    let containerSize: CGSize
    /// The screen's real safe-area insets — used to keep the top-positioned bubble below the status bar
    /// and any navigation bar, since the overlay itself draws edge-to-edge.
    let safeArea: EdgeInsets
    let index: Int
    let total: Int
    let reduceMotion: Bool
    let onNext: () -> Void
    let onSkip: () -> Void

    /// Drives the per-letter speech blip as the mascot's line types on. Optional to match the app's
    /// crash-safe read pattern — a nil (e.g. in previews) simply types silently.
    @Environment(FeedbackServices.self) private var feedback: FeedbackServices?

    /// Extra ring of clear space around the spotlit control.
    private let cut: CGFloat = 12

    /// The mascot speaks from the top when the target sits low on screen, so the bubble never covers it.
    private var panelAtTop: Bool {
        guard let rect = targetRect else { return false }
        return rect.midY > containerSize.height * 0.60
    }

    var body: some View {
        ZStack {
            scrim
            if let rect = targetRect {
                spotlightRing(rect)
                arrow(rect)
            }
            coachPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: panelAtTop ? .top : .bottom)
                .padding(.horizontal, EgressSpacing.lg)
                // The overlay fills the full screen, so clear the status bar / nav bar / home indicator
                // manually from the real insets (the fixed 64 pt used to slide under stacked nav bars).
                .padding(.top, panelAtTop ? safeArea.top + EgressSpacing.md : 0)
                .padding(.bottom, panelAtTop ? 0 : max(safeArea.bottom, 34) + EgressSpacing.sm)
        }
        .animation(reduceMotion ? nil : Motion.card, value: index)
    }

    // MARK: Scrim + spotlight

    private var scrim: some View {
        Rectangle()
            .fill(Color.black.opacity(0.6))
            .reverseMask {
                if let rect = targetRect {
                    RoundedRectangle(cornerRadius: EgressRadius.sm, style: .continuous)
                        .frame(width: rect.width + cut * 2, height: rect.height + cut * 2)
                        .position(x: rect.midX, y: rect.midY)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {} // absorb taps so the dimmed UI beneath can't be triggered mid-tour
            .accessibilityHidden(true)
    }

    private func spotlightRing(_ rect: CGRect) -> some View {
        RoundedRectangle(cornerRadius: EgressRadius.sm, style: .continuous)
            .strokeBorder(Color.egDataGreen, lineWidth: 3)
            .frame(width: rect.width + cut * 2, height: rect.height + cut * 2)
            .position(x: rect.midX, y: rect.midY)
            .allowsHitTesting(false)
    }

    /// A bobbing arrow just outside the spotlight, on the side facing the mascot, pointing at the control.
    private func arrow(_ rect: CGRect) -> some View {
        let pointsUp = !panelAtTop // panel at bottom ⇒ target above ⇒ arrow sits below it, pointing up
        let y = pointsUp ? rect.maxY + cut + 16 : rect.minY - cut - 16
        return Image(systemName: pointsUp ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
            .font(.system(size: 24, weight: .bold))
            .foregroundStyle(Color.egDataGreen)
            .position(x: min(max(rect.midX, 24), containerSize.width - 24), y: y)
            .modifier(ArrowBob(active: !reduceMotion, up: pointsUp))
            .allowsHitTesting(false)
    }

    // MARK: Coach panel — mascot + comic bubble

    private var coachPanel: some View {
        HStack(alignment: .bottom, spacing: EgressSpacing.xs) {
            Image("guide_mascot")
                .resizable()
                .interpolation(.none)
                .aspectRatio(contentMode: .fit)
                .frame(width: 80, height: 108)
                .accessibilityHidden(true)
            bubble
        }
        .transition(reduceMotion
            ? .opacity
            : .move(edge: panelAtTop ? .top : .bottom).combined(with: .opacity))
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: EgressSpacing.sm) {
            Text(step.title.uppercased()).egMicroLabel()
            TypewriterText(
                text: step.message,
                instant: reduceMotion,
                onBlip: { feedback?.sound.play(.speechBlip) }
            )
                .font(.system(.callout, design: .rounded, weight: .medium))
                .foregroundStyle(Color.egTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: EgressSpacing.sm) {
                progressDots
                Spacer(minLength: EgressSpacing.sm)
                Button(action: onSkip) {
                    Text("Skip")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(Color.egTextSecondary)
                }
                .accessibilityHint("Ends the tour")
                Button(action: onNext) {
                    Text(index == total - 1 ? "Done" : "Next")
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .foregroundStyle(Color.egOutline)
                        .padding(.horizontal, EgressSpacing.md)
                        .padding(.vertical, EgressSpacing.sm)
                        .background(Capsule().fill(Color.egDataGreen))
                }
            }
        }
        .padding(EgressSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PixelCornerRect(radius: EgressRadius.md, pixel: 4).fill(Color.egSurfaceRaised))
        .overlay(PixelCornerRect(radius: EgressRadius.md, pixel: 4).strokeBorder(Color.egOutline, lineWidth: 2))
        .overlay(alignment: .leading) {
            BubbleTail().offset(x: -10) // points back at the mascot
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(step.title). \(step.message). Step \(index + 1) of \(total).")
    }

    private var progressDots: some View {
        HStack(spacing: 5) {
            ForEach(0 ..< total, id: \.self) { dot in
                Circle()
                    .fill(dot == index ? Color.egDataGreenDeep : Color.egSeparator)
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - ArrowBob

/// A gentle repeating nudge toward the target, so the arrow reads as "look here". Static under Reduce Motion.
private struct ArrowBob: ViewModifier {
    let active: Bool
    let up: Bool
    @State private var on = false

    func body(content: Content) -> some View {
        content
            .offset(y: active ? (on ? (up ? -6 : 6) : 0) : 0)
            .onAppear {
                guard active else { return }
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { on = true }
            }
    }
}

// MARK: - reverseMask

private extension View {
    /// Masks *out* the given shape — used to punch the spotlight hole in the scrim.
    func reverseMask<Mask: View>(@ViewBuilder _ mask: () -> Mask) -> some View {
        self.mask {
            ZStack {
                Rectangle()
                mask().blendMode(.destinationOut)
            }
            .compositingGroup()
        }
    }
}

import SwiftUI

// MARK: - AppTab

/// The two home destinations. The centre ＋ is an *action* (opens the editor), not a destination, so it
/// isn't a case here — it can't be "selected".
enum AppTab: Hashable { case spaces, learn }

// MARK: - EgressTabBar

/// The floating home tab bar (design: the Spaces screenshot). A cream pill — **Spaces** on the left,
/// **Learn** on the right — each inside the chunky pixel border, with the centre ＋ a *full* pixel-bordered
/// circle sitting on top and cresting the pill's edge. So both parts of the bar carry the pixel outline: a
/// complete circle for the ＋, a stadium for the pill. The ＋ opens the editor (a simulation needs a space
/// first), the two ends switch destinations. It floats above the page ground; screens reserve room for it
/// with a bottom safe-area inset, so nothing hides behind it.
struct EgressTabBar: View {
    @Binding var selection: AppTab
    /// Raised by the centre ＋ — opens the blank editor.
    let onCreate: () -> Void

    /// How far the ＋ circle crests above the pill's top edge — about half the circle, like the screenshot.
    private let plusRise: CGFloat = 27
    private let plusDiameter: CGFloat = 58
    private let pillHeight: CGFloat = 62

    var body: some View {
        ZStack(alignment: .top) {
            pill
            plusButton
                .offset(y: -plusRise) // a full circle cresting the pill's top edge
        }
        .padding(.top, plusRise) // reserve the part of the circle that rises above the pill
        .padding(.horizontal, 40) // narrower bar — more breathing room at the screen edges (design)
        .padding(.bottom, EgressSpacing.xs)
        .egButtonSound()
    }

    // MARK: Pieces

    /// The pill body — Spaces and Learn either side of the ＋'s slot — inside its own pixel border.
    private var pill: some View {
        HStack(spacing: 0) {
            end(.spaces, icon: .spaces, label: "Spaces")
            Color.clear.frame(width: plusDiameter + EgressSpacing.md) // slot for the centre ＋
            end(.learn, icon: .learn, label: "Learn")
        }
        .padding(.horizontal, EgressSpacing.md)
        .frame(height: pillHeight)
        .background(PixelCornerRect(radius: pillHeight / 2, pixel: 6).fill(Color.egSurfaceRaised))
        .overlay(PixelCornerRect(radius: pillHeight / 2, pixel: 6).strokeBorder(Color.egOutline, lineWidth: 2))
    }

    /// The centre ＋ — a full pixel-bordered circle on top of the pill (design: the screenshot). Its cream
    /// fill masks the pill border beneath it, so its own outline reads as a complete circle.
    private var plusButton: some View {
        Button(action: onCreate) {
            Image(systemName: "plus")
                .font(.system(size: 26, weight: .heavy))
                .foregroundStyle(Color.egTextPrimary)
                .frame(width: plusDiameter, height: plusDiameter)
                .background(PixelCornerRect(radius: plusDiameter / 2, pixel: 5).fill(Color.egSurfaceRaised))
                .overlay(PixelCornerRect(radius: plusDiameter / 2, pixel: 5).strokeBorder(Color.egOutline, lineWidth: 2))
        }
        .buttonStyle(PlusPress())
        .accessibilityLabel("Create a space")
        .accessibilityHint("Opens the editor")
    }

    private func end(_ tab: AppTab, icon: AppSymbol, label: String) -> some View {
        Button {
            selection = tab
        } label: {
            VStack(spacing: 3) {
                Image(app: icon).font(.system(size: 19, weight: .semibold))
                Text(label).font(.system(size: 11, weight: .bold, design: .rounded))
            }
            .foregroundStyle(selection == tab ? Color.egDataGreenDeep : Color.egTextPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, EgressSpacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(Motion.tap, value: selection)
        .accessibilityAddTraits(selection == tab ? [.isSelected] : [])
    }
}

// MARK: - PlusPress

/// A springy dip for the centre ＋ — it presses like a physical arcade button.
private struct PlusPress: ButtonStyle {
    @Environment(FeedbackServices.self) private var feedback: FeedbackServices?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(Motion.tap, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed {
                    feedback?.sound.play(.buttonTap)
                }
            }
    }
}

#Preview {
    ZStack(alignment: .bottom) {
        Color.egGround.ignoresSafeArea()
        EgressTabBar(selection: .constant(.spaces), onCreate: {})
    }
    .preferredColorScheme(.light)
}

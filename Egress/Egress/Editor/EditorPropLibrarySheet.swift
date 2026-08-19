import EgressEngine
import SwiftUI

// MARK: - PropLibrarySheet

/// The prop catalogue the Props button opens (design's "PROP LIBRARY" board). Picking a prop sets
/// `EditorModel.activeProp` and dismisses; the Props tool stays selected, so the user then drags the
/// prop out on the canvas exactly as they place a plain object today. The first card is that plain
/// `Object` box — the default — so the current behaviour is always one tap away.
struct PropLibrarySheet: View {
    let model: EditorModel
    @Environment(\.dismiss)
    private var dismiss
    @Environment(FeedbackServices.self)
    private var feedback: FeedbackServices?

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: EgressSpacing.sm)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: EgressSpacing.md) {
                    Text("Pick a prop, then drag it out on the canvas. Three chrome treatments carry the "
                        + "sim-class, so you always know what the coach may move.")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Color.egTextSecondary)

                    legend

                    LazyVGrid(columns: columns, spacing: EgressSpacing.sm) {
                        ForEach(EditorProp.library) { prop in
                            propCard(prop)
                        }
                    }
                }
                .padding(EgressSpacing.md)
            }
            .scrollContentBackground(.hidden)
            .background(Color.egGround)
            .navigationTitle("Prop Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear { feedback?.sound.play(.popup) }
        .egButtonSound()
    }

    // MARK: Legend — the three sim-class chrome treatments

    private var legend: some View {
        VStack(alignment: .leading, spacing: EgressSpacing.sm) {
            legendRow(.egDataGreen, "Relocatable", "Furniture the coach may suggest moving.")
            legendRow(.egCyan, "Structural", "Fixed — routes are planned around it.")
            legendRow(.egTextTertiary, "Decor", "Sim-inert — never blocks a body.")
        }
        .padding(EgressSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle.egSquircle(EgressRadius.md).fill(Color.egSurfaceRaised))
        .overlay(RoundedRectangle.egSquircle(EgressRadius.md).strokeBorder(Color.egOutline, lineWidth: 1.5))
    }

    private func legendRow(_ tint: Color, _ name: String, _ detail: String) -> some View {
        HStack(spacing: EgressSpacing.sm) {
            RoundedRectangle(cornerRadius: 3)
                .fill(tint)
                .frame(width: 14, height: 14)
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.egOutline, lineWidth: 1))
            Text(name)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(Color.egTextPrimary)
            Text(detail)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color.egTextSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Prop card

    private func propCard(_ prop: EditorProp) -> some View {
        let selected = model.activeProp.kind == prop.kind
        return Button {
            model.activeProp = prop
            model.tool = .obstacle
            feedback?.haptics.play(.toolTap)
            dismiss()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: prop.symbol)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(prop.tint)
                    .frame(height: 26)
                Text(prop.name)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Color.egTextPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text("\(prop.venue ?? "Freeform") · \(prop.classLabel)")
                    .egMicroLabel()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, EgressSpacing.md)
            .padding(.horizontal, EgressSpacing.sm)
            .background(
                RoundedRectangle.egSquircle(EgressRadius.md)
                    .fill(selected ? prop.tint.opacity(0.14) : Color.egSurfaceRaised)
            )
            .overlay(
                RoundedRectangle.egSquircle(EgressRadius.md)
                    .strokeBorder(selected ? prop.tint : Color.egOutline, lineWidth: selected ? 2.5 : 1.5)
            )
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(prop.tint)
                        .padding(6)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(prop.name), \(prop.venue ?? "freeform"), \(prop.classLabel)")
        .accessibilityHint("Selects this prop to drag onto the canvas")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

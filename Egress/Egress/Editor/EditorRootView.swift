import EgressEngine
import SwiftUI

// MARK: - EditorRootView

/// The parametric venue editor (§3.5), as an immersive full-screen dark game-screen (design: "DRAW A
/// METRICALLY-TRUE VENUE"). The whole screen is the canvas so there's room to draw; a slim top bar
/// carries the title, a ⋯ that opens the full configuration sheet, and a compact Run button; a grouped
/// Build · Props · Hazards tray sits at the bottom. Selecting an item with the Select tool raises a
/// floating pad to move and configure it in place — the per-item controls that used to live in a scroll
/// list. The app tab bar is hidden here so nothing steals the space.
struct EditorRootView: View {
    @State private var model: EditorModel
    @State private var goToSimulate = false
    @State private var showConfig = false
    @State private var showPropLibrary = false
    /// The live size of the canvas card, so the "fit to content" button can frame the drawing.
    @State private var canvasSize: CGSize = .zero
    /// Frame the drawing once, the first time we learn the canvas size, so a preset or draft opens
    /// centred rather than parked at the camera's default corner.
    @State private var didInitialFit = false
    @Environment(FeedbackServices.self)
    private var feedback: FeedbackServices?
    @Environment(\.dismiss)
    private var dismiss
    /// Explicit close for when the editor is the *root* of a modal stack (the ＋ Create cover), where the
    /// environment `dismiss` would only try to pop the empty stack. Nil on the pushed preset path, where
    /// `dismiss` correctly pops back to Spaces.
    private let onClose: (() -> Void)?

    /// A blank room the user shapes from scratch. `onClose` closes the presenting cover, if any.
    init(onClose: (() -> Void)? = nil) {
        _model = State(initialValue: EditorModel())
        self.onClose = onClose
    }

    /// A furnished preset the user can tweak, then run — the Spaces gallery entry point. Presented as a
    /// full-screen cover (like ＋ Create), so `onClose` dismisses the cover; the floating tab bar lives
    /// outside the cover and is never drawn over the editor or a run.
    init(preset: VenuePreset, onClose: (() -> Void)? = nil) {
        _model = State(initialValue: EditorModel(preset: preset))
        self.onClose = onClose
    }

    var body: some View {
        ZStack {
            Color.egGround.ignoresSafeArea()
            VStack(spacing: 0) {
                topChrome
                canvasArea
                toolTray
            }
        }
        .preferredColorScheme(.light) // cream editorial shell; the canvas alone stays a dark game-screen
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar) // reclaim the space — no tab bar while editing
        .sheet(isPresented: $showConfig) { EditorConfigSheet(model: model) }
        .sheet(isPresented: $showPropLibrary) { PropLibrarySheet(model: model) }
        .navigationDestination(isPresented: $goToSimulate) {
            SimulateScreen(venue: model.venue, config: model.config)
        }
        .tourHost(
            Tours.editor,
            hasSeen: Binding(
                get: { feedback?.settings.seenEditorTour ?? true },
                set: { feedback?.settings.seenEditorTour = $0 }
            )
        )
    }

    // MARK: Top bar — title · settings · run

    private var topChrome: some View {
        VStack(spacing: EgressSpacing.sm) {
            HStack(spacing: EgressSpacing.sm) {
                circleButton("chevron.left", label: "Back") {
                    if let onClose {
                        onClose()
                    } else {
                        dismiss()
                    }
                }
                Button { showConfig = true } label: {
                    HStack(spacing: 6) {
                        Text(model.displayName)
                            .font(EgressFont.display(.title3))
                            .foregroundStyle(Color.egTextPrimary)
                            .lineLimit(1)
                        Image(systemName: "pencil")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.egTextTertiary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Rename and configure venue")
                Spacer(minLength: EgressSpacing.xs)
                circleButton("ellipsis", label: "All settings") { showConfig = true }
                    .tourAnchor(.editorConfig)
                runButton
            }
            HStack {
                toolStatePill
                Spacer()
                Text("1 block = 0.25 m").egMicroLabel()
            }
            if let issue = model.blockingIssue {
                Label(issue, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.egVerdictWarn)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, EgressSpacing.md)
        .padding(.top, EgressSpacing.xs)
        .padding(.bottom, EgressSpacing.sm)
    }

    private func circleButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.egTextPrimary)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.egSurfaceRaised))
                .overlay(Circle().strokeBorder(Color.egOutline, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var runButton: some View {
        Button { goToSimulate = true } label: {
            Image(systemName: "play.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(model.isSimulable ? Color.egOutline : Color.egTextTertiary)
                .frame(width: 46, height: 46)
                .background(Circle().fill(model.isSimulable ? Color.egDataGreen : Color.egSurfaceSunken))
                .overlay(Circle().strokeBorder(model.isSimulable ? Color.egOutline : Color.egSeparator, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .disabled(!model.isSimulable)
        .accessibilityLabel("Run simulation")
        .accessibilityHint(model.isSimulable ? "Runs the evacuation" : (model.blockingIssue ?? "Not ready to run"))
        .tourAnchor(.editorRun)
    }

    private var toolStatePill: some View {
        let label = model.tool == .obstacle ? model.obstaclePlacementLabel : model.tool.actionLabel
        let symbol = model.tool == .obstacle ? model.activeProp.symbol : model.tool.symbol
        return Label(label, systemImage: symbol)
            .font(.system(.caption2, weight: .bold))
            .fontWidth(.condensed)
            .textCase(.uppercase)
            .tracking(0.6)
            .padding(.horizontal, EgressSpacing.md)
            .padding(.vertical, EgressSpacing.xs)
            .foregroundStyle(model.tool.tint)
            .background(Capsule().fill(model.tool.tint.opacity(0.18)))
            .overlay(Capsule().strokeBorder(model.tool.tint, lineWidth: 1.5))
            .accessibilityLabel("Active tool: \(model.tool.label)")
    }

    // MARK: Canvas + floating selection pad

    private var canvasArea: some View {
        EditorCanvasView(model: model)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                GeometryReader { proxy in
                    Color.egCanvasBase
                        .onChange(of: proxy.size, initial: true) { _, size in
                            canvasSize = size
                            if !didInitialFit, size.width > 1, size.height > 1 {
                                didInitialFit = true
                                model.camera.fit(model.contentBounds, in: size)
                            }
                        }
                }
            }
            .clipShape(RoundedRectangle.egSquircle(EgressRadius.lg))
            .overlay(RoundedRectangle.egSquircle(EgressRadius.lg).strokeBorder(Color.egOutline, lineWidth: 2))
            .overlay(alignment: .topTrailing) {
                zoomCluster.padding(EgressSpacing.sm)
            }
            .overlay(alignment: .bottom) {
                if model.selection != nil {
                    selectionPad
                        .padding(.horizontal, EgressSpacing.md)
                        .padding(.bottom, EgressSpacing.md)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.horizontal, EgressSpacing.md)
            .padding(.bottom, EgressSpacing.xs)
            .animation(.easeInOut(duration: 0.2), value: model.selection)
    }

    /// Floating camera controls over the dark canvas — zoom in / fit-to-content / zoom out. Discoverable
    /// (and VoiceOver-operable, since a pinch isn't) counterparts to the two-finger pan and pinch.
    private var zoomCluster: some View {
        VStack(spacing: EgressSpacing.xs) {
            zoomButton("plus.magnifyingglass", "Zoom in") {
                model.camera.zoom(by: 1.3, aroundWorld: model.camera.center)
            }
            zoomButton("arrow.down.forward.and.arrow.up.backward", "Fit to content") {
                model.camera.fit(model.contentBounds, in: canvasSize)
            }
            zoomButton("minus.magnifyingglass", "Zoom out") {
                model.camera.zoom(by: 0.77, aroundWorld: model.camera.center)
            }
        }
    }

    private func zoomButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
            feedback?.haptics.play(.toolTap)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.egCanvasText)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle.egSquircle(EgressRadius.xs).fill(Color.egCanvasRaised.opacity(0.92)))
                .overlay(RoundedRectangle.egSquircle(EgressRadius.xs).strokeBorder(Color.egCanvasSeparator, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// The floating pad that appears over the canvas when an item is selected — move arrows plus that
    /// item's own controls (exit width, duplicate, delete). This is the direct-manipulation replacement
    /// for the per-item rows that used to sit in the scroll form.
    private var selectionPad: some View {
        VStack(spacing: EgressSpacing.sm) {
            HStack(spacing: EgressSpacing.sm) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.selectionTitle ?? "Selected")
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(Color.egTextPrimary)
                    if let detail = model.selectionDetail {
                        Text(detail).egMicroLabel()
                    }
                }
                Spacer(minLength: 0)
                if model.selectionIsObstacle {
                    padButton("plus.square.on.square", "Duplicate") {
                        model.duplicateSelection()
                        feedback?.haptics.play(.toolTap)
                    }
                }
                padButton("trash", "Delete", tint: .egVerdictFail) {
                    model.deleteSelection()
                    feedback?.haptics.play(.deleteConfirmed)
                }
                padButton("xmark", "Deselect") { model.clearSelection() }
            }

            HStack(alignment: .center, spacing: EgressSpacing.lg) {
                movePad
                if model.selectionIsExit, let id = model.selectedExitID {
                    Rectangle().fill(Color.egSeparator).frame(width: 1, height: 56)
                    exitWidthControl(id)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(EgressSpacing.md)
        .background(RoundedRectangle.egSquircle(EgressRadius.lg).fill(Color.egSurfaceRaised))
        .overlay(RoundedRectangle.egSquircle(EgressRadius.lg).strokeBorder(Color.egOutline, lineWidth: 2))
    }

    /// A four-way arrow pad — nudges the selection half a metre. Locked (structural) props dim it out.
    private var movePad: some View {
        VStack(spacing: 4) {
            moveArrow("chevron.up", "up", Vec2(0, -0.5))
            HStack(spacing: 4) {
                moveArrow("chevron.left", "left", Vec2(-0.5, 0))
                Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.egTextTertiary)
                    .frame(width: 34, height: 34)
                moveArrow("chevron.right", "right", Vec2(0.5, 0))
            }
            moveArrow("chevron.down", "down", Vec2(0, 0.5))
        }
        .disabled(!model.selectionIsMovable)
        .opacity(model.selectionIsMovable ? 1 : 0.4)
    }

    private func moveArrow(_ symbol: String, _ direction: String, _ delta: Vec2) -> some View {
        Button {
            model.nudgeSelection(by: delta)
            feedback?.haptics.play(.toolTap)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.egTextPrimary)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle.egSquircle(EgressRadius.xs).fill(Color.egSurfaceSunken))
                .overlay(RoundedRectangle.egSquircle(EgressRadius.xs).strokeBorder(Color.egOutline, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Move \(direction) half a metre")
    }

    private func padButton(_ symbol: String, _ label: String, tint: Color = .egTextPrimary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle.egSquircle(EgressRadius.xs).fill(Color.egSurfaceSunken))
                .overlay(RoundedRectangle.egSquircle(EgressRadius.xs).strokeBorder(Color.egOutline, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func exitWidthControl(_ id: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Clear width").egMicroLabel()
            HStack(spacing: EgressSpacing.sm) {
                padButton("minus", "Narrower") {
                    model.setExitWidth(id, to: model.exitWidth(id) - EditorModel.exitStep)
                    feedback?.haptics.play(.toolTap)
                }
                Text(String(format: "%.1f m", model.exitWidth(id)))
                    .egData(.subheadline)
                    .foregroundStyle(Color.egTextPrimary)
                    .frame(minWidth: 48)
                padButton("plus", "Wider") {
                    model.setExitWidth(id, to: model.exitWidth(id) + EditorModel.exitStep)
                    feedback?.haptics.play(.toolTap)
                }
            }
        }
    }

    // MARK: Tool tray — Build · Props · Hazards

    private var toolTray: some View {
        HStack(alignment: .top) {
            toolGroupView(.build)
            Spacer(minLength: EgressSpacing.xs)
            toolDivider
            Spacer(minLength: EgressSpacing.xs)
            toolGroupView(.props)
            Spacer(minLength: EgressSpacing.xs)
            toolDivider
            Spacer(minLength: EgressSpacing.xs)
            toolGroupView(.hazards)
        }
        .frame(maxWidth: .infinity)
        .padding(EgressSpacing.md)
        .background(RoundedRectangle.egSquircle(EgressRadius.lg).fill(Color.egSurfaceRaised))
        .overlay(RoundedRectangle.egSquircle(EgressRadius.lg).strokeBorder(Color.egOutline, lineWidth: 2))
        .tourAnchor(.editorTools)
        .padding(.horizontal, EgressSpacing.md)
        .padding(.bottom, EgressSpacing.sm)
    }

    private func toolGroupView(_ group: EditorToolGroup) -> some View {
        VStack(alignment: .leading, spacing: EgressSpacing.xs) {
            Text(group.label).egMicroLabel()
            HStack(spacing: EgressSpacing.xs) {
                ForEach(EditorTool.allCases.filter { $0.group == group }) { tool in
                    toolButton(tool)
                }
            }
        }
    }

    private func toolButton(_ tool: EditorTool) -> some View {
        let selected = model.tool == tool
        // The Props tool is a prop-library launcher: it wears the active prop's icon/name and always
        // reopens the picker on tap, so choosing a prop and choosing "the Props tool" are one action.
        let isProps = tool == .obstacle
        let symbol = isProps ? model.activeProp.symbol : tool.symbol
        let title = isProps ? model.activeProp.name : tool.label
        return Button {
            model.tool = tool
            feedback?.haptics.play(.toolTap)
            if isProps {
                showPropLibrary = true
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 15, weight: .semibold))
                Text(title)
                    .font(.system(size: 8.5, weight: .semibold)).fontWidth(.condensed)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            .frame(width: 40, height: 44)
            .background(
                RoundedRectangle.egSquircle(EgressRadius.xs)
                    .fill(selected ? tool.tint.opacity(0.20) : Color.egSurfaceSunken)
            )
            .overlay(
                RoundedRectangle.egSquircle(EgressRadius.xs)
                    .strokeBorder(selected ? tool.tint : Color.egOutline, lineWidth: selected ? 2 : 1.5)
            )
            .foregroundStyle(selected ? tool.tint : Color.egTextPrimary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isProps ? "Props — \(model.activeProp.name)" : "\(tool.label) tool")
        .accessibilityHint(isProps ? "Opens the prop library, then drag to place the chosen prop." : tool.hint)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private var toolDivider: some View {
        RoundedRectangle(cornerRadius: 0.5).fill(Color.egSeparator).frame(width: 1, height: 52)
    }
}

// MARK: - EditorConfigSheet

/// Everything that isn't direct on-canvas manipulation: name, type, room size, crowd, the accessible
/// exit/object lists (VoiceOver authors here), hazards, and clear-layout. Opened from the ⋯ button —
/// a cream sheet, like the rest of the app's chrome.
private struct EditorConfigSheet: View {
    @Bindable var model: EditorModel
    @Environment(\.dismiss)
    private var dismiss
    @Environment(FeedbackServices.self)
    private var feedback: FeedbackServices?

    var body: some View {
        NavigationStack {
            Form {
                Section("Venue") {
                    TextField("Name", text: $model.name, prompt: Text(model.type.displayName))
                    Picker("Type", selection: $model.type) {
                        ForEach(VenueType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                }
                .listRowBackground(Color.egSurfaceSunken)

                Section {
                    LabeledContent("Auto size", value: String(format: "%.1f × %.1f m", model.worldWidth, model.worldHeight))
                    LabeledContent("Floor area", value: String(format: "%.0f m²", model.venue.netFloorArea))
                    Button {
                        model.fitBaseToContent()
                        feedback?.haptics.play(.toolTap)
                    } label: {
                        Label("Fit room to drawing", systemImage: "arrow.down.forward.and.arrow.up.backward")
                    }
                    .disabled(model.walls.isEmpty && model.exits.isEmpty && model.obstacles.isEmpty && model.waterZones.isEmpty)
                } header: {
                    Text("Room")
                } footer: {
                    Text(
                        "No fixed size — the room is whatever your walls enclose, and grows as you draw beyond it. Draw the shape you want, then fit the floor tightly to it. Each grid square is 0.25 m."
                    )
                }
                .listRowBackground(Color.egSurfaceSunken)

                Section("Crowd") {
                    VStack(alignment: .leading, spacing: EgressSpacing.xs) {
                        HStack {
                            Text("\(model.crowd) people").egData(.body)
                            Spacer()
                            Text(model.crowdLoadLabel)
                                .font(.system(.caption, design: .rounded, weight: .semibold))
                                .padding(.horizontal, EgressSpacing.sm)
                                .padding(.vertical, 2)
                                .background(model.crowdLoadTint.opacity(0.18), in: Capsule())
                                .foregroundStyle(model.crowdLoadTint)
                        }
                        Slider(
                            value: Binding(get: { Double(model.crowd) }, set: { model.crowd = Int($0) }),
                            in: Double(EditorModel.minCrowd) ... Double(EditorModel.maxCrowd),
                            step: 1
                        )
                        .tint(.egDataGreen)
                        Text(String(format: "%.1f people/m² average loading", model.crowdDensity))
                            .egMicroLabel()
                    }
                }
                .listRowBackground(Color.egSurfaceSunken)

                exitsSection
                    .listRowBackground(Color.egSurfaceSunken)
                objectsSection
                    .listRowBackground(Color.egSurfaceSunken)
                hazardsSection
                    .listRowBackground(Color.egSurfaceSunken)

                Section("Layout") {
                    LabeledContent("Walls", value: "\(model.walls.count)")
                    Button(role: .destructive) {
                        model.clearElements()
                        feedback?.haptics.play(.deleteConfirmed)
                    } label: {
                        Label("Clear layout", systemImage: "trash")
                    }
                    .disabled(model.walls.isEmpty && model.exits.isEmpty && model.obstacles.isEmpty && model.ignitions.isEmpty && model
                        .waterZones.isEmpty)
                }
                .listRowBackground(Color.egSurfaceSunken)
            }
            .scrollContentBackground(.hidden)
            .background(Color.egGround)
            .navigationTitle("Configure")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.egGround)
        .onAppear { feedback?.sound.play(.popup) }
        .egButtonSound()
    }

    /// Exits as an accessible list (§5.6): a clear-width stepper and remove, plus an add-on-edge menu so
    /// authoring never requires a drag. Widths below the 1.2 m minimum flag themselves.
    private var exitsSection: some View {
        Section {
            ForEach(model.exits) { exit in
                VStack(alignment: .leading, spacing: EgressSpacing.xs) {
                    Stepper(
                        value: Binding(
                            get: { model.exitWidth(exit.id) },
                            set: { model.setExitWidth(exit.id, to: $0) }
                        ),
                        in: EditorModel.minEditableExit ... max(EditorModel.minEditableExit, model.maxExitWidth(exit.id)),
                        step: EditorModel.exitStep
                    ) {
                        LabeledContent("Exit \(exit.id)", value: String(format: "%.1f m", model.exitWidth(exit.id)))
                    }
                    .accessibilityHint("Adjusts the clear width of exit \(exit.id) in tenths of a metre")
                    if model.exitWidth(exit.id) + 0.001 < SafetyStandards.minExitWidth {
                        Label("Below the 1.2 m exit minimum", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(Color.egVerdictWarn)
                    }
                    Button(role: .destructive) {
                        model.removeExit(exit.id)
                        feedback?.haptics.play(.deleteConfirmed)
                    } label: {
                        Label("Remove", systemImage: "minus.circle").font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Remove exit \(exit.id)")
                }
                .padding(.vertical, 2)
            }
            Menu {
                ForEach(EditorModel.RoomEdge.allCases) { edge in
                    Button(edge.label) {
                        model.addExit(on: edge)
                        feedback?.haptics.play(.toolTap)
                    }
                }
            } label: {
                Label("Add exit on a wall", systemImage: "plus.rectangle.on.rectangle")
            }
            .accessibilityHint("Adds a doorway centred on the wall you choose")
        } header: {
            Text("Exits (\(model.exits.count))")
        } footer: {
            if model.exits.isEmpty {
                Text("Add at least one exit so the crowd can escape.")
            }
        }
    }

    /// Objects as an accessible list (§5.6): relocatable furniture gets nudge controls and remove;
    /// structural elements show a disabled `LOCKED — STRUCTURAL` row (V5).
    private var objectsSection: some View {
        Section {
            if model.obstacles.isEmpty {
                Text("No objects placed.")
                    .font(.callout)
                    .foregroundStyle(Color.egTextSecondary)
            }
            ForEach(model.obstacles) { object in
                VStack(alignment: .leading, spacing: EgressSpacing.xs) {
                    LabeledContent(model.propName(for: object), value: String(format: "%.1f × %.1f m", object.size.x, object.size.y))
                    HStack(spacing: EgressSpacing.md) {
                        nudge(object.id, "arrow.left", "left", Vec2(-0.5, 0))
                        nudge(object.id, "arrow.right", "right", Vec2(0.5, 0))
                        nudge(object.id, "arrow.up", "up", Vec2(0, -0.5))
                        nudge(object.id, "arrow.down", "down", Vec2(0, 0.5))
                        Spacer()
                        Button(role: .destructive) {
                            model.removeObstacle(object.id)
                            feedback?.haptics.play(.deleteConfirmed)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .accessibilityLabel("Remove \(model.propName(for: object)) \(object.id)")
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("Objects (\(model.obstacles.count))")
        }
    }

    /// Editor-placed hazards (§2.7): fire ignition points and standing-water flood zones — each with a
    /// count and a clear action, the accessible counterpart to the Fire/Water tools on the canvas.
    private var hazardsSection: some View {
        Section {
            if model.ignitions.isEmpty {
                Text("No fire placed. Pick the Fire tool and tap the canvas to drop an ignition point.")
                    .font(.callout)
                    .foregroundStyle(Color.egTextSecondary)
            } else {
                LabeledContent("Fire ignition points", value: "\(model.ignitions.count)")
                Button(role: .destructive) {
                    model.clearIgnitions()
                    feedback?.haptics.play(.deleteConfirmed)
                } label: {
                    Label("Clear fire", systemImage: "flame")
                }
            }
            if model.waterZones.isEmpty {
                Text("No water placed. Pick the Water tool and drag a box to flood an area.")
                    .font(.callout)
                    .foregroundStyle(Color.egTextSecondary)
            } else {
                LabeledContent("Water zones", value: "\(model.waterZones.count)")
                Button(role: .destructive) {
                    model.clearWater()
                    feedback?.haptics.play(.deleteConfirmed)
                } label: {
                    Label("Clear water", systemImage: "water.waves")
                }
            }
        } header: {
            Text("Hazards (\(model.ignitions.count + model.waterZones.count))")
        } footer: {
            Text(
                "Fire spreads from each point once the run starts; water is a standing flood that never spreads. Either way, the crowd has to route around it."
            )
        }
    }

    private func nudge(_ id: Int, _ symbol: String, _ direction: String, _ delta: Vec2) -> some View {
        Button {
            model.nudgeObstacle(id, by: delta)
            feedback?.haptics.play(.toolTap)
        } label: {
            Image(systemName: symbol)
        }
        .accessibilityLabel("Move object \(id) \(direction) by half a metre")
    }
}

#Preview {
    NavigationStack { EditorRootView() }
}

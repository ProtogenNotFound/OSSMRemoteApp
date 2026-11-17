//
//  StrokeEngineView.swift
//  OSSM Control
//

import SwiftUI
import SwiftData
import AppIntents

struct StrokeEngineView: PlatformSplitView {
    @Environment(\.modelContext) var modelContext
    @Query(sort: [SortDescriptor(\StrokeEnginePreset.sortOrder), SortDescriptor(\StrokeEnginePreset.name)]) var presets: [StrokeEnginePreset]

    @State var selectedPresetID: UUID?
    @State var suppressPresetSelectionApply = false
    @State var showPresetEditor: Bool = false
    @State var showAddPresetPrompt: Bool = false
    @State var newPresetName: String = ""
    @State var showPresetError = false
    @State var presetErrorMessage = ""
    @State var showHighSpeedPresetWarning = false
    @State var pendingPresetActivationID: UUID?
    @State private var localSettingsPresented = false
    private let externalSettingsPresented: Binding<Bool>?

    @EnvironmentObject var bleManager: OSSMBLEManager
    @AppStorage("strokeEngine.settings.showPresetsSection") var showPresetsSection = true
    @AppStorage("strokeEngine.settings.highSpeedWarningEnabled") var highSpeedWarningEnabled = true
    @AppStorage("strokeEngine.settings.highSpeedWarningThreshold") var highSpeedWarningThresholdSetting = 20
    @AppStorage("strokeEngine.settings.showLiveSessionData") var showLiveSessionData = true
    @AppStorage("strokeEngine.settings.saveLiveSessionData") var saveLiveSessionData = true
    @AppStorage("strokeEngine.settings.speedStepAmount") var speedStepAmountSetting = 5
    @AppStorage("strokeEngine.settings.strokeStepAmount") var strokeStepAmountSetting = 5
    @AppStorage("strokeEngine.settings.depthStepAmount") var depthStepAmountSetting = 5
    @AppStorage("strokeEngine.settings.sensationStepAmount") var sensationStepAmountSetting = 5
    @AppStorage("strokeEngine.settings.sliderDebugLogging") var sliderDebugLogging = true

    #if !os(visionOS)
    let heroTransitionNamespace: Namespace.ID
    #endif

    #if os(visionOS)
    init(showSettings: Binding<Bool>? = nil) {
        self.externalSettingsPresented = showSettings
    }
    #else
    init(heroTransitionNamespace: Namespace.ID, showSettings: Binding<Bool>? = nil) {
        self.heroTransitionNamespace = heroTransitionNamespace
        self.externalSettingsPresented = showSettings
    }
    #endif

    @StateObject var controls = AppIntentShared.strokeEngineViewModel
    @State var showSensationInfo: Bool = false

    let sliderRange: ClosedRange<Int> = 0...100
    let settingsRange: ClosedRange<Int> = 1...100
    var highSpeedPresetThreshold: Int {
        clampSettingsValue(highSpeedWarningThresholdSetting)
    }
    var speedStepAmount: Int {
        clampSettingsValue(speedStepAmountSetting)
    }
    var strokeStepAmount: Int {
        clampSettingsValue(strokeStepAmountSetting)
    }
    var depthStepAmount: Int {
        clampSettingsValue(depthStepAmountSetting)
    }
    var sensationStepAmount: Int {
        clampSettingsValue(sensationStepAmountSetting)
    }

    var availablePatterns: [OSSMPattern] {
        if bleManager.patterns.isEmpty {
            return KnownPattern.allCases.map { pattern in
                OSSMPattern(
                    idx: pattern.rawValue,
                    name: pattern.name,
                    description: pattern.description,
                    sensationDescription: pattern.sensationDescription
                )
            }
        }

        return bleManager.patterns.sorted { $0.idx < $1.idx }
    }

    var currentControls: OSSMPlayData {
        controls.desiredState
    }

    var sensationDisplayValue: Int {
        Int((Double(currentControls.sensation) * 2) - 100)
    }

    var selectedPatternInfo: OSSMPattern? {
        availablePatterns.first(where: { $0.idx == currentControls.pattern })
    }

    var selectedPreset: StrokeEnginePreset? {
        guard let selectedPresetID else { return nil }
        return presets.first(where: { $0.id == selectedPresetID })
    }

    var pendingPresetActivation: StrokeEnginePreset? {
        guard let pendingPresetActivationID else { return nil }
        return presets.first(where: { $0.id == pendingPresetActivationID })
    }

    var settingsPresented: Binding<Bool> {
        externalSettingsPresented ?? $localSettingsPresented
    }

    var suggestedPresetName: String {
        let existingNames = Set(presets.map { $0.name.lowercased() })
        var index = 1
        while existingNames.contains("preset \(index)") {
            index += 1
        }
        return "Preset \(index)"
    }

    #if !os(visionOS)
    var iosBody: some View {
        List {
            if showLiveSessionData {
                StrokeEngineSessionStatsRow(
                    runtimeData: bleManager.runtimeData,
                    supportsSessionStats: bleManager.supportsSessionStats
                )
            }
            if showPresetsSection {
                Section("Presets") {
                    HStack {
                        Picker("Selected:", selection: $selectedPresetID) {
                            Text("None").tag(Optional<UUID>.none)
                            ForEach(presets) { preset in
                                Text(preset.name).tag(Optional(preset.id))
                            }
                        }
                        .padding(.trailing)
                        Button("Edit", systemImage: "pencil") {
                            showPresetEditor.toggle()
                        }
                        Button("Add", systemImage: "plus") {
                            newPresetName = suggestedPresetName
                            showAddPresetPrompt = true
                        }
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)

                    if let selectedPreset {
                        Text(selectedPreset.summaryText)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else if presets.isEmpty {
                        Text("No presets yet. Tap Add to save the current settings.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            // Speed Control
            Section {
                VStack(alignment: .leading) {
                    HStack {
                        Button {
                            adjust(.speed, by: -speedStepAmount)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .buttonStyle(.borderless)
                        .disabled(currentControls.speed <= sliderRange.lowerBound)

                        Slider(value: sliderBinding(for: .speed), in: 0...100, step: 1)

                        Button {
                            adjust(.speed, by: speedStepAmount)
                        } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                        .buttonStyle(.borderless)
                        .disabled(currentControls.speed >= sliderRange.upperBound)
                    }.labelStyle(.iconOnly)
                }
            } header: {
                HStack {
                    Text("Speed")
                    Spacer()
                    Text("\(currentControls.speed)%")
                        .foregroundColor(.secondary)
                }

            }

            // Stroke Control
            Section {
                VStack(alignment: .leading) {
                    HStack {
                        Button {
                            adjust(.stroke, by: -strokeStepAmount)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .buttonStyle(.borderless)
                        .disabled(currentControls.stroke <= sliderRange.lowerBound)

                        Slider(value: sliderBinding(for: .stroke), in: 0...100, step: 1)

                        Button {
                            adjust(.stroke, by: strokeStepAmount)
                        } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                        .buttonStyle(.borderless)
                        .disabled(currentControls.stroke >= sliderRange.upperBound)
                    }
                    .labelStyle(.iconOnly)
                }
            } header: {
                HStack {
                    Text("Stroke")
                    Spacer()
                    Text("\(currentControls.stroke)%")
                        .foregroundColor(.secondary)
                }
            }

            // Depth Control
            Section {
                VStack(alignment: .leading) {
                    HStack {
                        Button {
                            adjust(.depth, by: -depthStepAmount)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .buttonStyle(.borderless)
                        .disabled(currentControls.depth <= sliderRange.lowerBound)

                        Slider(value: sliderBinding(for: .depth), in: 0...100, step: 1)

                        Button {
                            adjust(.depth, by: depthStepAmount)
                        } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                        .buttonStyle(.borderless)
                        .disabled(currentControls.depth >= sliderRange.upperBound)
                    }
                    .labelStyle(.iconOnly)
                }
            } header: {
                HStack {
                    Text("Depth")
                    Spacer()
                    Text("\(currentControls.depth)%")
                        .foregroundColor(.secondary)
                }
            }

            // Sensation Control
            Section {
                VStack(alignment: .leading) {
                    HStack {
                        Button {
                            adjust(.sensation, by: -sensationStepAmount)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .buttonStyle(.borderless)
                        .disabled(currentControls.sensation <= sliderRange.lowerBound)

                        Slider(value: sliderBinding(for: .sensation), in: 0...100, step: 1)

                        Button {
                            adjust(.sensation, by: sensationStepAmount)
                        } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                        .buttonStyle(.borderless)
                        .disabled(currentControls.sensation >= sliderRange.upperBound)
                    }
                    .labelStyle(.iconOnly)
                }
            } header: {
                HStack {
                    Text("Sensation")
                    Button("info", systemImage: "info.circle") {
                        showSensationInfo.toggle()
                    }
                    .labelStyle(.iconOnly)
                    .popover(isPresented: $showSensationInfo) {
                        Text(selectedPatternInfo?.sensationDescription ?? LocalizedStringKey("Error"))
                            .font(.caption2)
                            .minimumScaleFactor(0.5)
                            .padding(.horizontal, 8)
                            .presentationCompactAdaptation(.popover)
                    }
                    Spacer()
                    Text("\(sensationDisplayValue)")
                        .foregroundColor(.secondary)
                }
            }.disabled(selectedPatternInfo?.sensationDescription == nil)

            // Pattern Selection
            Section("Pattern") {
                Picker("Selected:", selection: patternBinding) {
                    ForEach(availablePatterns) { pattern in
                        Section(pattern.name) {
                            Text(pattern.description ?? "")
                                .font(.caption2)
                                .minimumScaleFactor(0.5)
                                .lineLimit(3, reservesSpace: true)
                                .padding(.horizontal, 8)
                        }.tag(pattern.idx)
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Settings", systemImage: "slider.horizontal.3"){
                    settingsPresented.wrappedValue = true
                }
            }
            ToolbarItemGroup(placement: .bottomBar) {
                Button {
                    controls.setValue(0, for: .speed)
                } label: {
                    HStack {
                        Image(systemName: "stop.circle.fill")
                        Text("EMERGENCY STOP")
                            .fontWeight(.bold)
                    }
                }
                .tint(.red)
                .buttonStyle(.borderedProminent)
                Button {
                    bleManager.pullOut()
                } label: {
                    HStack {
                        Image(systemName: "arrow.backward.to.line")
                        Text("Pull Out")
                    }
                }

            }
        }
        .sheet(isPresented: settingsPresented) {
            StrokeEngineSettingsView(
                showPresetsSection: $showPresetsSection,
                highSpeedWarningEnabled: $highSpeedWarningEnabled,
                highSpeedWarningThreshold: clampedSettingsBinding(for: $highSpeedWarningThresholdSetting),
                showLiveSessionData: $showLiveSessionData,
                saveLiveSessionData: $saveLiveSessionData,
                speedStepAmount: clampedSettingsBinding(for: $speedStepAmountSetting),
                strokeStepAmount: clampedSettingsBinding(for: $strokeStepAmountSetting),
                depthStepAmount: clampedSettingsBinding(for: $depthStepAmountSetting),
                sensationStepAmount: clampedSettingsBinding(for: $sensationStepAmountSetting),
                sliderDebugLogging: $sliderDebugLogging,
                settingsRange: settingsRange
            )
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showPresetEditor) {
            StrokePresetManagerView(selectedPresetID: $selectedPresetID)
                .presentationDetents([.medium, .large])
        }
        .alert("Save Preset", isPresented: $showAddPresetPrompt) {
            TextField("Preset Name", text: $newPresetName)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                saveCurrentValuesAsPreset(named: newPresetName)
            }
        } message: {
            Text("Save current speed, stroke, depth, sensation, and pattern.")
        }
        .alert("Preset Error", isPresented: $showPresetError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(presetErrorMessage)
        }
        .alert("High Speed Preset", isPresented: $showHighSpeedPresetWarning) {
            Button("Hell yeah >:3") {
                confirmPendingPresetActivation()
            }
            Button("Set Speed to 0") {
                confirmPendingPresetActivation(speedOverride: 0)
            }
            Button("Cancel", role: .cancel) {
                clearPendingPresetActivation()
            }
        } message: {
            if let pendingPresetActivation {
                Text("\"\(pendingPresetActivation.name)\" is set to \(pendingPresetActivation.speed)% speed. Thats pretty fast :3 are you sure?")
            } else {
                Text("The selected preset exceeds \(highSpeedPresetThreshold)% speed. Thats pretty fast :3 are you sure?")
            }
        }
        .onChange(of: selectedPresetID) { oldValue, newValue in
            handlePresetSelectionChange(from: oldValue, to: newValue)
        }
        .onChange(of: presets.count) { _, _ in
            ensureSelectedPresetStillExists()
        }
        .monospacedDigit()
        .disabled(bleManager.currentPage != .strokeEngine)
        .navigationTitle("Stroke Engine")
        .navigationTransition(.zoom(sourceID: "strokeEngineTitleZoom", in: heroTransitionNamespace))
        .onAppear {
            sanitizeStoredSettings()
            controls.bind(to: bleManager)
            controls.debugLoggingEnabled = sliderDebugLogging
            controls.bootstrap(from: bleManager.runtimeData.currentState)
            ensureSelectedPresetStillExists()
        }
        .onReceive(bleManager.runtimeData.$currentState) { state in
            controls.receiveDeviceState(state)
        }
        .onChange(of: sliderDebugLogging) { _, newValue in
            controls.debugLoggingEnabled = newValue
        }
    }
    #endif

    func ensureSelectedPresetStillExists() {
        guard let selectedPresetID else { return }
        if !presets.contains(where: { $0.id == selectedPresetID }) {
            self.selectedPresetID = nil
        }
    }

    func saveCurrentValuesAsPreset(named rawName: String) {
        let trimmedName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmedName.isEmpty ? suggestedPresetName : trimmedName

        let preset = StrokeEnginePreset(
            name: name,
            speed: currentControls.speed,
            stroke: currentControls.stroke,
            depth: currentControls.depth,
            sensation: currentControls.sensation,
            pattern: currentControls.pattern,
            sortOrder: (presets.map(\.sortOrder).max() ?? -1) + 1
        )

        modelContext.insert(preset)
        do {
            try modelContext.save()
            suppressPresetSelectionApply = true
            selectedPresetID = preset.id
        } catch {
            modelContext.delete(preset)
            presetErrorMessage = "Could not save preset: \(error.localizedDescription)"
            showPresetError = true
        }
    }

    func applyPreset(_ preset: StrokeEnginePreset, speedOverride: Int? = nil) {
        controls.apply(
            OSSMPlayData(
                speed: speedOverride ?? preset.speed,
                stroke: preset.stroke,
                depth: preset.depth,
                sensation: preset.sensation,
                pattern: preset.pattern
            )
        )
    }

    func handlePresetSelectionChange(from oldValue: UUID?, to newValue: UUID?) {
        guard !suppressPresetSelectionApply else {
            suppressPresetSelectionApply = false
            return
        }

        guard oldValue != newValue else { return }
        guard let newValue else { return }
        guard let preset = presets.first(where: { $0.id == newValue }) else { return }

        if highSpeedWarningEnabled && preset.speed > highSpeedPresetThreshold {
            pendingPresetActivationID = preset.id
            suppressPresetSelectionApply = true
            selectedPresetID = oldValue
            showHighSpeedPresetWarning = true
            return
        }

        applyPreset(preset)
    }

    func confirmPendingPresetActivation(speedOverride: Int? = nil) {
        guard let pendingPresetActivationID,
              let preset = presets.first(where: { $0.id == pendingPresetActivationID }) else {
            clearPendingPresetActivation()
            return
        }

        suppressPresetSelectionApply = true
        selectedPresetID = preset.id
        applyPreset(preset, speedOverride: speedOverride)
        clearPendingPresetActivation()
    }

    func clearPendingPresetActivation() {
        pendingPresetActivationID = nil
        showHighSpeedPresetWarning = false
    }

    func adjust(_ parameter: StrokeEngineParameter, by delta: Int) {
        controls.adjustValue(for: parameter, by: delta)
    }

    func sliderBinding(for parameter: StrokeEngineParameter) -> Binding<Double> {
        Binding(
            get: {
                Double(controls.value(for: parameter))
            },
            set: { newValue in
                controls.setValue(Int(newValue.rounded()), for: parameter)
            }
        )
    }

    var patternBinding: Binding<Int> {
        Binding(
            get: {
                controls.value(for: .pattern)
            },
            set: { newValue in
                controls.setValue(newValue, for: .pattern)
            }
        )
    }

    func clampSettingsValue(_ value: Int) -> Int {
        max(settingsRange.lowerBound, min(settingsRange.upperBound, value))
    }

    static func formatDistance(_ distanceM: Double) -> String {
        distanceM.formatted(
            .number
                .precision(.fractionLength(1))
        )
    }

    static func formatElapsedTime(_ elapsedMs: Int) -> String {
        let totalSeconds = max(0, elapsedMs / 1000)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            if minutes > 0 {
                return "\(hours)h\(minutes)m\(seconds)s"
            }
            return "\(hours)h\(seconds)s"
        }

        if minutes > 0 {
            return "\(minutes)m\(seconds)s"
        }

        return "\(seconds)s"
    }

    func clampedSettingsBinding(for binding: Binding<Int>) -> Binding<Int> {
        Binding(
            get: {
                clampSettingsValue(binding.wrappedValue)
            },
            set: { newValue in
                binding.wrappedValue = clampSettingsValue(newValue)
            }
        )
    }

    func sanitizeStoredSettings() {
        highSpeedWarningThresholdSetting = clampSettingsValue(highSpeedWarningThresholdSetting)
        speedStepAmountSetting = clampSettingsValue(speedStepAmountSetting)
        strokeStepAmountSetting = clampSettingsValue(strokeStepAmountSetting)
        depthStepAmountSetting = clampSettingsValue(depthStepAmountSetting)
        sensationStepAmountSetting = clampSettingsValue(sensationStepAmountSetting)
    }

    @available(iOS 27.3, visionOS 27.3, *)
    @AppIntent(.tool)
    struct SetParameter: AppIntent {
        static let title: LocalizedStringResource = "Change Stroke Engine Settings"
        static let description: IntentDescription =
            """
            Set or adjust OSSM movement settings. Omitted settings remain unchanged.
            Movement is measured in percentages of full travel and spans max(0,depth-stroke) to depth.
            """

        @Parameter(
            title: "Speed",
            description: "Speed from 0% (stopped) to 100% (maximum). Adjust in percentage points."
        )
        var speed: StrokeEngineParameterChange?

        @Parameter(
            title: "Stroke",
            description: "Stroke length from 0% to 100% of full travel, extending outward from depth. Adjust in percentage points."
        )
        var stroke: StrokeEngineParameterChange?

        @Parameter(
            title: "Depth",
            description: "Inner endpoint from 0% (fully out) to 100% (fully in). Adjust in percentage points."
        )
        var depth: StrokeEngineParameterChange?

        @Parameter(
            title: "Sensation",
            description: "Pattern modifier from −100 to 100, with 0 neutral. Adjust in points. Has no effect in Simple Stroke."
        )
        var sensation: StrokeEngineParameterChange?

        @Parameter(
            title: "Pattern",
            description: "Movement pattern to select."
        )
        var pattern: KnownPattern?

        @Dependency
        private var strokeEngineModel: StrokeEngineControlViewModel

        @Dependency
        private var navigationPath: OSSMNavigationPath

        @Dependency
        private var ossmBLEManager: OSSMBLEManager

        @MainActor
        func perform() async throws -> some IntentResult {
            guard navigationPath.path.last == .strokeEngine else {
                throw AppIntentError(description: "Open Stroke Engine to change its settings.")
            }
            var patternIndex: Int?
            if let pattern {
                guard let mappedPattern = ossmBLEManager.patterns.first(where: { $0.name == pattern.name }) else {
                    throw AppIntentError(description: "The connected device does not offer \(pattern.name).")
                }
                patternIndex = mappedPattern.idx
            }

            let changes: [(StrokeEngineParameter, StrokeEngineParameterChange?)] = [
                (.speed, speed),
                (.stroke, stroke),
                (.depth, depth),
                (.sensation, sensation)
            ]
            for (parameter, change) in changes {
                guard let change else { continue }
                switch change.operation {
                case .set:
                    var target = change.amount
                    if parameter == .sensation {
                        // The BLE setting encodes neutral (0 onscreen) as 50.
                        let signedValue = min(100, max(-100, target))
                        target = Int((Double(signedValue + 100) / 2).rounded())
                    }
                    strokeEngineModel.setValue(target, for: parameter)
                case .adjust:
                    let limit = parameter == .sensation ? 200 : 100
                    var delta = min(limit, max(-limit, change.amount))
                    if parameter == .sensation {
                        delta = Int((Double(delta) / 2).rounded())
                    }
                    strokeEngineModel.adjustValue(for: parameter, by: delta)
                }
            }
            if let patternIndex {
                strokeEngineModel.setValue(patternIndex, for: .pattern)
            }

            return .result()
        }
    }
}

@available(iOS 27.3, visionOS 27.3, *)
enum StrokeEngineChangeOperation: String, AppEnum {
    case set
    case adjust

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Operation"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .set: "Set",
        .adjust: "Adjust"
    ]
}

@available(iOS 27.3, visionOS 27.3, *)
@AppEntity(.generable)
struct StrokeEngineParameterChange: TransientAppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Setting Change"

    @Property(title: "Operation", description: "Set an absolute target or adjust the current setting.")
    var operation: StrokeEngineChangeOperation

    @Property(title: "Amount", description: "Target for Set. For Adjust, positive increases and negative decreases.")
    var amount: Int

    var displayRepresentation: DisplayRepresentation {
        switch operation {
        case .set: DisplayRepresentation(title: "Set to \(amount)")
        case .adjust: DisplayRepresentation(title: "Adjust by \(amount)")
        }
    }

    init() {}
}

#if !os(visionOS)


private struct RollingCounterView: View {
    var font: Font = .largeTitle
    var weight: Font.Weight = .regular
    @Binding var value: Double

    @State private var lastRenderedValue: Double?

    private var sanitizedValue: Double {
        guard value.isFinite else { return 0 }
        return max(0, value)
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Self.decimalPlaces(for: sanitizedValue), id: \.self) { place in
                CounterDigitWheel(
                    font: font,
                    weight: weight,
                    digitCount: 10,
                    initialPosition: Self.wheelPosition(for: lastRenderedValue ?? sanitizedValue, place: place),
                    targetPosition: Self.wheelPosition(for: sanitizedValue, place: place)
                )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(sanitizedValue.formatted()))
        .onAppear {
            lastRenderedValue = sanitizedValue
        }
        .onChange(of: value) { _, _ in
            lastRenderedValue = sanitizedValue
        }
    }

    private static func decimalPlaces(for value: Double) -> [Int] {
        let wholeValue = Int(min(Double(Int.max), max(0, value.rounded(.up))))
        var places = [1]
        var place = 10

        while wholeValue >= place {
            places.insert(place, at: 0)

            guard place <= Int.max / 10 else { break }
            place *= 10
        }

        return places
    }

    private static func wheelPosition(for value: Double, place: Int) -> Double {
        let sanitizedValue = value.isFinite ? max(0, value) : 0
        let lowerValue = sanitizedValue.rounded(.down)
        let upperValue = sanitizedValue.rounded(.up)
        let progress = sanitizedValue - lowerValue
        let placeValue = Double(place)
        let lowerPosition = (lowerValue / placeValue).rounded(.down)
        let upperPosition = (upperValue / placeValue).rounded(.down)

        return lowerPosition + ((upperPosition - lowerPosition) * progress)
    }
}

private struct CounterDigitWheel: View {
    let font: Font
    let weight: Font.Weight
    let digitCount: Int
    let initialPosition: Double
    let targetPosition: Double

    @State private var displayedPosition: Double?

    private let animation = Animation.interactiveSpring(
        response: 0.8,
        dampingFraction: 1,
        blendDuration: 0.25
    )

    var body: some View {
        CounterDigitWheelFace(
            font: font,
            weight: weight,
            digitCount: digitCount,
            position: displayedPosition ?? initialPosition
        )
        .onAppear {
            guard displayedPosition == nil else { return }

            displayedPosition = initialPosition

            guard initialPosition != targetPosition else { return }

            DispatchQueue.main.async {
                withAnimation(animation) {
                    displayedPosition = targetPosition
                }
            }
        }
        .onChange(of: targetPosition) { _, newPosition in
            withAnimation(animation) {
                displayedPosition = newPosition
            }
        }
    }
}

private struct CounterDigitWheelFace: View, Animatable {
    let font: Font
    let weight: Font.Weight
    let digitCount: Int
    var position: Double

    var animatableData: Double {
        get { position }
        set { position = newValue }
    }

    var body: some View {
        Text("8")
            .font(font)
            .fontWeight(weight)
            .opacity(0)
            .overlay {
                GeometryReader { proxy in
                    let size = proxy.size
                    let basePosition = floor(position)
                    let offset = position - basePosition

                    VStack(spacing: 0) {
                        ForEach(-1...1, id: \.self) { relativePosition in
                            Text("\(Self.digit(for: Int(basePosition) + relativePosition, digitCount: digitCount))")
                                .font(font)
                                .fontWeight(weight)
                                .frame(width: size.width, height: size.height, alignment: .center)
                        }
                    }
                    .offset(y: -CGFloat(offset + 1) * size.height)
                }
                .clipped()
            }
    }

    private static func digit(for position: Int, digitCount: Int) -> Int {
        let count = max(1, digitCount)
        let digit = position % count
        return digit >= 0 ? digit : digit + count
    }
}

private struct RollingTimeCounterView: View {
    var font: Font = .headline.monospacedDigit()
    var weight: Font.Weight = .semibold
    @Binding var elapsedMs: Double

    @State private var lastRenderedElapsedSeconds: Double?

    private var elapsedSeconds: Double {
        guard elapsedMs.isFinite else { return 0 }
        return max(0, elapsedMs / 1000)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            HStack(spacing: 0) {
                ForEach(Self.minutePlaces(for: elapsedSeconds), id: \.self) { place in
                    CounterDigitWheel(
                        font: font,
                        weight: weight,
                        digitCount: 10,
                        initialPosition: Self.minuteWheelPosition(
                            for: lastRenderedElapsedSeconds ?? elapsedSeconds,
                            place: place
                        ),
                        targetPosition: Self.minuteWheelPosition(for: elapsedSeconds, place: place)
                    )
                }
            }

            Text(":")
                .font(font)
                .fontWeight(weight)

            HStack(spacing: 0) {
                CounterDigitWheel(
                    font: font,
                    weight: weight,
                    digitCount: 6,
                    initialPosition: Self.secondsWheelPosition(
                        for: lastRenderedElapsedSeconds ?? elapsedSeconds,
                        place: 10
                    ),
                    targetPosition: Self.secondsWheelPosition(for: elapsedSeconds, place: 10)
                )

                CounterDigitWheel(
                    font: font,
                    weight: weight,
                    digitCount: 10,
                    initialPosition: Self.secondsWheelPosition(
                        for: lastRenderedElapsedSeconds ?? elapsedSeconds,
                        place: 1
                    ),
                    targetPosition: Self.secondsWheelPosition(for: elapsedSeconds, place: 1)
                )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(Self.accessibilityTime(for: elapsedSeconds)))
        .onAppear {
            lastRenderedElapsedSeconds = elapsedSeconds
        }
        .onChange(of: elapsedMs) { _, _ in
            lastRenderedElapsedSeconds = elapsedSeconds
        }
    }

    private static func minutePlaces(for elapsedSeconds: Double) -> [Int] {
        let upperMinutes = Int(
            min(
                Double(Int.max),
                max(0, elapsedSeconds.rounded(.up) / 60).rounded(.down)
            )
        )
        var places = [1]
        var place = 10

        while upperMinutes >= place {
            places.insert(place, at: 0)

            guard place <= Int.max / 10 else { break }
            place *= 10
        }

        return places
    }

    private static func minuteWheelPosition(for elapsedSeconds: Double, place: Int) -> Double {
        wheelPosition(for: elapsedSeconds, every: Double(place) * 60)
    }

    private static func secondsWheelPosition(for elapsedSeconds: Double, place: Int) -> Double {
        wheelPosition(for: elapsedSeconds, every: Double(place))
    }

    private static func wheelPosition(for elapsedSeconds: Double, every interval: Double) -> Double {
        let sanitizedSeconds = elapsedSeconds.isFinite ? max(0, elapsedSeconds) : 0
        let lowerSeconds = sanitizedSeconds.rounded(.down)
        let upperSeconds = sanitizedSeconds.rounded(.up)
        let progress = sanitizedSeconds - lowerSeconds
        let lowerPosition = (lowerSeconds / interval).rounded(.down)
        let upperPosition = (upperSeconds / interval).rounded(.down)

        return lowerPosition + ((upperPosition - lowerPosition) * progress)
    }

    private static func accessibilityTime(for elapsedSeconds: Double) -> String {
        let roundedSeconds = Int(max(0, elapsedSeconds.rounded()))
        let minutes = roundedSeconds / 60
        let seconds = roundedSeconds % 60

        return "\(minutes):\(String(format: "%02d", seconds))"
    }
}

private struct StrokeEngineSessionStatsRow: View {
    @ObservedObject var runtimeData: OSSMRuntimeData
    let supportsSessionStats: Bool

    var body: some View {
        if supportsSessionStats,
           runtimeData.currentState.state.rawValue.contains(OSSMPage.strokeEngine.rawValue),
           let stats = runtimeData.currentSessionStats {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "waveform.path.ecg")
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 28)
                let strokesBinding = Binding<Double>(
                    get: { Double(stats.strokes) },
                    set: { _ in }
                )
                rollingCounterMetric(value: strokesBinding, name: "strokes")
                let distanceBinding = Binding<Double>(
                    get: { stats.distanceM },
                    set: { _ in }
                )
                rollingCounterMetric(value: distanceBinding, unit: "m", name: "distance")
                let elapsedMsBinding = Binding<Double>(
                    get: { Double(stats.elapsedMs) },
                    set: { _ in }
                )
                rollingTimeMetric(elapsedMs: elapsedMsBinding)
                Spacer()
                    .frame(width: 28)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .id(stats.sessionId)
            .animation(.linear(duration: 1), value: stats.strokes)
            .animation(.linear(duration: 1), value: stats.elapsedMs)
            .animation(.linear(duration: 1), value: stats.distanceM)
        }
    }


    private func rollingCounterMetric(value: Binding<Double>, unit: String? = nil, name: String) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                RollingCounterView(
                    font: .headline.monospacedDigit(),
                    weight: .semibold,
                    value: value
                )

                if let unit{
                    Text(unit)
                        .font(.headline.weight(.semibold).monospacedDigit())
                }
            }
            .foregroundStyle(.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)

            Text(name)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func rollingTimeMetric(elapsedMs: Binding<Double>) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            RollingTimeCounterView(elapsedMs: elapsedMs)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text("time")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    nonisolated private static func formatStrokes(_ strokes: Double) -> String {
        strokes.formatted(
            .number
                .precision(.fractionLength(0))
        )
    }

    nonisolated private static func formatElapsedTime(_ elapsedMs: Double) -> String {
        let seconds = max(0, elapsedMs / 1000)
        let minutes = Int(seconds / 60)
        let secondsRemainder = seconds - Double(minutes * 60)

        if minutes > 0 {
            return "\(minutes)m \(secondsRemainder.formatted(.number.precision(.fractionLength(0))))s"
        }

        return "\(seconds.formatted(.number.precision(.fractionLength(0))))s"
    }

    nonisolated private static func formatDistance(_ distanceM: Double) -> String {
        "\(distanceM.formatted(.number.precision(.fractionLength(1)))) m"
    }
}

private struct StrokeEngineAnimatedValueText: View, Animatable {
    var value: Double
    let formatter: (Double) -> String

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(formatter(value))
            .contentTransition(.numericText(countsDown: true))
    }
}
#endif

struct StrokeEngineSettingsView: PlatformSplitView {
    @Binding var showPresetsSection: Bool
    @Binding var highSpeedWarningEnabled: Bool
    @Binding var highSpeedWarningThreshold: Int

    @Binding var showLiveSessionData: Bool
    @Binding var saveLiveSessionData: Bool

    @Binding var speedStepAmount: Int
    @Binding var strokeStepAmount: Int
    @Binding var depthStepAmount: Int
    @Binding var sensationStepAmount: Int
    @Binding var sliderDebugLogging: Bool
    let settingsRange: ClosedRange<Int>

    @State var showSafeguardInfoPopover: Bool = false

    @Environment(\.dismiss) var dismiss

    #if !os(visionOS)
    var iosBody: some View {
        NavigationStack {
            Form {
                Section("Presets") {
                    Toggle("Show Presets Section", isOn: $showPresetsSection)
                }

                if showPresetsSection {
                    Section{
                        Toggle("Enable High Speed Warning", isOn: $highSpeedWarningEnabled)
                        if highSpeedWarningEnabled {
                            Stepper(value: $highSpeedWarningThreshold, in: settingsRange) {
                                HStack {
                                    Text("Warning Threshold")
                                    Spacer()
                                    Text("\(highSpeedWarningThreshold)%")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    } header: {
                        HStack {
                            Text("Preset Switching Safeguards")
                            Button("Info", systemImage: "info.circle") {showSafeguardInfoPopover.toggle()}
                                .popover(isPresented: $showSafeguardInfoPopover) {
                                    Text("""
                                        When switching to a profile with a
                                        speed value that exceeds the warning
                                        threshold, confirmation is required
                                        """)
                                    .font(.caption2)
                                    .minimumScaleFactor(0.5)
                                    .padding(.horizontal, 8)
                                    .presentationCompactAdaptation(.popover)
                                }
                                .labelStyle(.iconOnly)
                        }
                    }
                    .animation(.spring, value: highSpeedWarningEnabled)
                }

                Section("Live Session Data") {
                    Toggle("Show Live Session Data", isOn: $showLiveSessionData)
                    Toggle("Save Live Session Data", isOn: $saveLiveSessionData)
                }

                Section("Button Step Ammount") {
                    stepperRow(title: "Speed", value: $speedStepAmount)
                    stepperRow(title: "Stroke", value: $strokeStepAmount)
                    stepperRow(title: "Depth", value: $depthStepAmount)
                    stepperRow(title: "Sensation", value: $sensationStepAmount)
                }

                Section("Diagnostics") {
                    Toggle("Enable Slider Debug Logging", isOn: $sliderDebugLogging)
                }
            }
            .animation(.spring, value: showPresetsSection)
            .navigationTitle("Stroke Engine Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    #endif

    @ViewBuilder
    func stepperRow(title: String, value: Binding<Int>) -> some View {
        Stepper(value: value, in: settingsRange) {
            HStack {
                Text(title)
                Spacer()
                Text("\(value.wrappedValue)")
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct StrokePresetManagerView: PlatformSplitView {
    @Binding var selectedPresetID: UUID?

    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) var modelContext
    @Query(sort: [SortDescriptor(\StrokeEnginePreset.sortOrder), SortDescriptor(\StrokeEnginePreset.name)]) var presets: [StrokeEnginePreset]

    @State var showSaveError = false
    @State var saveErrorMessage = ""

    #if !os(visionOS)
    var iosBody: some View {
        NavigationStack {
            List {
                if presets.isEmpty {
                    Text("No presets saved.")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(presets) { preset in
                        NavigationLink {
                            StrokePresetDetailView(preset: preset)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.name)
                                Text(preset.summaryText)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .onDelete(perform: deletePresets)
                    .onMove(perform: movePresets)
                }
            }
            .navigationTitle("Edit Presets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !presets.isEmpty {
                        EditButton()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Preset Error", isPresented: $showSaveError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveErrorMessage)
            }
        }
    }
    #endif

    func deletePresets(at offsets: IndexSet) {
        let removedIDs = offsets.map { presets[$0].id }
        var remainingPresets = presets
        remainingPresets.remove(atOffsets: offsets)
        for (index, preset) in remainingPresets.enumerated() {
            preset.sortOrder = index
        }
        for index in offsets {
            modelContext.delete(presets[index])
        }
        if let selectedPresetID, removedIDs.contains(selectedPresetID) {
            self.selectedPresetID = nil
        }
        persistChanges()
    }

    func movePresets(from source: IndexSet, to destination: Int) {
        var reorderedPresets = presets
        reorderedPresets.move(fromOffsets: source, toOffset: destination)
        for (index, preset) in reorderedPresets.enumerated() {
            preset.sortOrder = index
        }
        persistChanges()
    }

    func persistChanges() {
        do {
            try modelContext.save()
        } catch {
            saveErrorMessage = "Could not save preset changes: \(error.localizedDescription)"
            showSaveError = true
        }
    }
}

struct StrokePresetDetailView: PlatformSplitView {
    @Bindable var preset: StrokeEnginePreset

    @Environment(\.modelContext) var modelContext

    @State var showSaveError = false
    @State var saveErrorMessage = ""

    let valueRange: ClosedRange<Double> = 0...100

    #if !os(visionOS)
    var iosBody: some View {
        Form {
            Section("Name") {
                TextField("Preset Name", text: $preset.name)
            }
            Section("Parameters") {
                parameterSliderRow(
                    title: "Speed",
                    valueText: "\(preset.speed)%",
                    binding: sliderBinding(for: \.speed)
                )
                parameterSliderRow(
                    title: "Stroke",
                    valueText: "\(preset.stroke)%",
                    binding: sliderBinding(for: \.stroke)
                )
                parameterSliderRow(
                    title: "Depth",
                    valueText: "\(preset.depth)%",
                    binding: sliderBinding(for: \.depth)
                )
                parameterSliderRow(
                    title: "Sensation",
                    valueText: "\(Int((Double(preset.sensation) * 2) - 100))",
                    binding: sliderBinding(for: \.sensation)
                )
            }
            Section("Pattern") {
                Picker("Selected:", selection: $preset.pattern) {
                    ForEach(KnownPattern.allCases) { pattern in
                        Text(pattern.name).tag(pattern.rawValue)
                    }
                }
            }
        }
        .navigationTitle("Preset")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    save()
                }
            }
        }
        .alert("Preset Error", isPresented: $showSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveErrorMessage)
        }
    }
    #endif

    @ViewBuilder
    func parameterSliderRow(title: String, valueText: String, binding: Binding<Double>) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Text(title)
                Spacer()
                Text(valueText)
                    .foregroundColor(.secondary)
            }
            Slider(value: binding, in: valueRange, step: 1)
        }
    }

    func sliderBinding(for keyPath: ReferenceWritableKeyPath<StrokeEnginePreset, Int>) -> Binding<Double> {
        Binding(
            get: {
                Double(preset[keyPath: keyPath])
            },
            set: { newValue in
                preset[keyPath: keyPath] = max(0, min(100, Int(newValue.rounded())))
            }
        )
    }

    func save() {
        let trimmedName = preset.name.trimmingCharacters(in: .whitespacesAndNewlines)
        preset.name = trimmedName.isEmpty ? "Preset" : trimmedName
        preset.speed = max(0, min(100, preset.speed))
        preset.stroke = max(0, min(100, preset.stroke))
        preset.depth = max(0, min(100, preset.depth))
        preset.sensation = max(0, min(100, preset.sensation))

        do {
            try modelContext.save()
        } catch {
            saveErrorMessage = "Could not save preset: \(error.localizedDescription)"
            showSaveError = true
        }
    }
}

extension StrokeEnginePreset {
    var summaryText: String {
        "Speed \(speed)% · Stroke \(stroke)% · Depth \(depth)% · Sensation \(Int((Double(sensation) * 2) - 100)) · Pattern \(pattern)"
    }
}

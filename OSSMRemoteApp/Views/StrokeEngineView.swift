//
//  StrokeEngineView.swift
//  OSSM Control
//

import SwiftUI
import SwiftData

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
    @State var showSettings = false

    @EnvironmentObject var bleManager: OSSMBLEManager
    @AppStorage("strokeEngine.settings.showPresetsSection") var showPresetsSection = true
    @AppStorage("strokeEngine.settings.highSpeedWarningEnabled") var highSpeedWarningEnabled = true
    @AppStorage("strokeEngine.settings.highSpeedWarningThreshold") var highSpeedWarningThresholdSetting = 20
    @AppStorage("strokeEngine.settings.speedStepAmount") var speedStepAmountSetting = 5
    @AppStorage("strokeEngine.settings.strokeStepAmount") var strokeStepAmountSetting = 5
    @AppStorage("strokeEngine.settings.depthStepAmount") var depthStepAmountSetting = 5
    @AppStorage("strokeEngine.settings.sensationStepAmount") var sensationStepAmountSetting = 5
    @AppStorage("strokeEngine.settings.sliderDebugLogging") var sliderDebugLogging = true

    @State var speed: Double = 0
    @State var stroke: Double = 50
    @State var depth: Double = 50
    @State var sensation: Double = 50
    @State var selectedPattern: Int = 0

    @State var showSensationInfo: Bool = false

    // Dragging state tracking
    @State var isDraggingSpeed = false
    @State var isDraggingStroke = false
    @State var isDraggingDepth = false
    @State var isDraggingSensation = false

    @State var pendingSpeedTarget: Int?
    @State var pendingSpeedTargetSetAt: Date = .distantPast
    @State var pendingStrokeTarget: Int?
    @State var pendingStrokeTargetSetAt: Date = .distantPast
    @State var pendingDepthTarget: Int?
    @State var pendingDepthTargetSetAt: Date = .distantPast
    @State var pendingSensationTarget: Int?
    @State var pendingSensationTargetSetAt: Date = .distantPast

    @State var lastSpeedPendingLogAt: Date = .distantPast
    @State var lastStrokePendingLogAt: Date = .distantPast
    @State var lastDepthPendingLogAt: Date = .distantPast
    @State var lastSensationPendingLogAt: Date = .distantPast

    let sliderRange: ClosedRange<Int> = 0...100
    let settingsRange: ClosedRange<Int> = 1...100
    let pendingSliderSyncTimeout: TimeInterval = 4.0
    let pendingLogThrottle: TimeInterval = 0.5
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

    var selectedPatternInfo: OSSMPattern? {
        availablePatterns.first(where: { $0.idx == selectedPattern })
    }

    var selectedPreset: StrokeEnginePreset? {
        guard let selectedPresetID else { return nil }
        return presets.first(where: { $0.id == selectedPresetID })
    }

    var pendingPresetActivation: StrokeEnginePreset? {
        guard let pendingPresetActivationID else { return nil }
        return presets.first(where: { $0.id == pendingPresetActivationID })
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
                            adjustSpeed(by: -speedStepAmount)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .buttonStyle(.borderless)
                        .disabled(clampSliderValue(Int(speed)) <= sliderRange.lowerBound)

                        Slider(value: $speed, in: 0...100, step: 1) { editing in
                            isDraggingSpeed = editing
                            if !editing {
                                commitSpeed(Int(speed), source: .sliderRelease)
                            }
                        }

                        Button {
                            adjustSpeed(by: speedStepAmount)
                        } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                        .buttonStyle(.borderless)
                        .disabled(clampSliderValue(Int(speed)) >= sliderRange.upperBound)
                    }.labelStyle(.iconOnly)
                }
            } header: {
                HStack {
                    Text("Speed")
                    Spacer()
                    Text("\(Int(speed))%")
                        .foregroundColor(.secondary)
                }

            }

            // Stroke Control
            Section {
                VStack(alignment: .leading) {
                    HStack {
                        Button {
                            adjustStroke(by: -strokeStepAmount)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .buttonStyle(.borderless)
                        .disabled(clampSliderValue(Int(stroke)) <= sliderRange.lowerBound)

                        Slider(value: $stroke, in: 0...100, step: 1) { editing in
                            isDraggingStroke = editing
                            if !editing {
                                commitStroke(Int(stroke), source: .sliderRelease)
                            }
                        }

                        Button {
                            adjustStroke(by: strokeStepAmount)
                        } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                        .buttonStyle(.borderless)
                        .disabled(clampSliderValue(Int(stroke)) >= sliderRange.upperBound)
                    }
                    .labelStyle(.iconOnly)
                }
            } header: {
                HStack {
                    Text("Stroke")
                    Spacer()
                    Text("\(Int(stroke))%")
                        .foregroundColor(.secondary)
                }
            }

            // Depth Control
            Section {
                VStack(alignment: .leading) {
                    HStack {
                        Button {
                            adjustDepth(by: -depthStepAmount)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .buttonStyle(.borderless)
                        .disabled(clampSliderValue(Int(depth)) <= sliderRange.lowerBound)

                        Slider(value: $depth, in: 0...100, step: 1) { editing in
                            isDraggingDepth = editing
                            if !editing {
                                commitDepth(Int(depth), source: .sliderRelease)
                            }
                        }

                        Button {
                            adjustDepth(by: depthStepAmount)
                        } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                        .buttonStyle(.borderless)
                        .disabled(clampSliderValue(Int(depth)) >= sliderRange.upperBound)
                    }
                    .labelStyle(.iconOnly)
                }
            } header: {
                HStack {
                    Text("Depth")
                    Spacer()
                    Text("\(Int(depth))%")
                        .foregroundColor(.secondary)
                }
            }

            // Sensation Control
            Section {
                VStack(alignment: .leading) {
                    HStack {
                        Button {
                            adjustSensation(by: -sensationStepAmount)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .buttonStyle(.borderless)
                        .disabled(clampSliderValue(Int(sensation)) <= sliderRange.lowerBound)

                        Slider(value: $sensation, in: 0...100, step: 1) { editing in
                            isDraggingSensation = editing
                            if !editing {
                                commitSensation(Int(sensation), source: .sliderRelease)
                            }
                        }

                        Button {
                            adjustSensation(by: sensationStepAmount)
                        } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                        .buttonStyle(.borderless)
                        .disabled(clampSliderValue(Int(sensation)) >= sliderRange.upperBound)
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
                    Text("\(Int((sensation * 2) - 100))")
                        .foregroundColor(.secondary)
                }
            }.disabled(selectedPatternInfo?.sensationDescription == nil)

            // Pattern Selection
            Section("Pattern") {
                Picker("Selected:", selection: $selectedPattern) {
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
                .onChange(of: selectedPattern) { _, newValue in
                    lastInteractionTime = Date() // Record interaction time
                    bleManager.setPattern(newValue)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Settings", systemImage: "slider.horizontal.3"){
                    showSettings = true
                }
            }
            ToolbarItemGroup(placement: .bottomBar) {
                Button {
                    bleManager.emergencyStop()
                    speed = 0
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
                    speed = 5
                    stroke = 0
                    depth = 0
                } label: {
                    HStack {
                        Image(systemName: "arrow.backward.to.line")
                        Text("Pull Out")
                    }
                }

            }
        }
        .sheet(isPresented: $showSettings) {
            StrokeEngineSettingsView(
                showPresetsSection: $showPresetsSection,
                highSpeedWarningEnabled: $highSpeedWarningEnabled,
                highSpeedWarningThreshold: clampedSettingsBinding(for: $highSpeedWarningThresholdSetting),
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
        .onAppear {
            sanitizeStoredSettings()
            syncState()
            ensureSelectedPresetStillExists()
        }
        .onReceive(bleManager.runtimeData.$currentState) { _ in
            syncState()
        }
    }
    #endif

    // Lockout timer to prevent incoming packets from resetting selection while user is interacting
    @State var lastInteractionTime: Date = Date.distantPast

    func syncState() {
        let state = bleManager.runtimeData.currentState
        let now = Date()

        if !isDraggingSpeed {
            if let pendingTarget = pendingSpeedTarget, state.speed != pendingTarget {
                if now.timeIntervalSince(pendingSpeedTargetSetAt) < pendingSliderSyncTimeout {
                    if now.timeIntervalSince(lastSpeedPendingLogAt) >= pendingLogThrottle {
                        logSlider("Holding speed UI at \(Int(speed)) while awaiting \(pendingTarget); incoming \(state.speed)")
                        lastSpeedPendingLogAt = now
                    }
                } else {
                    logSlider("Speed pending target \(pendingTarget) timed out; applying incoming \(state.speed)")
                    speed = Double(state.speed)
                    clearPendingSpeedTarget()
                }
            } else {
                if let pendingTarget = pendingSpeedTarget, state.speed == pendingTarget {
                    logSlider("Speed matched pending target \(pendingTarget)")
                }
                speed = Double(state.speed)
                clearPendingSpeedTarget()
            }
        }
        if !isDraggingStroke {
            if let pendingTarget = pendingStrokeTarget, state.stroke != pendingTarget {
                if now.timeIntervalSince(pendingStrokeTargetSetAt) < pendingSliderSyncTimeout {
                    if now.timeIntervalSince(lastStrokePendingLogAt) >= pendingLogThrottle {
                        logSlider("Holding stroke UI at \(Int(stroke)) while awaiting \(pendingTarget); incoming \(state.stroke)")
                        lastStrokePendingLogAt = now
                    }
                } else {
                    logSlider("Stroke pending target \(pendingTarget) timed out; applying incoming \(state.stroke)")
                    stroke = Double(state.stroke)
                    clearPendingStrokeTarget()
                }
            } else {
                if let pendingTarget = pendingStrokeTarget, state.stroke == pendingTarget {
                    logSlider("Stroke matched pending target \(pendingTarget)")
                }
                stroke = Double(state.stroke)
                clearPendingStrokeTarget()
            }
        }
        if !isDraggingDepth {
            if let pendingTarget = pendingDepthTarget, state.depth != pendingTarget {
                if now.timeIntervalSince(pendingDepthTargetSetAt) < pendingSliderSyncTimeout {
                    if now.timeIntervalSince(lastDepthPendingLogAt) >= pendingLogThrottle {
                        logSlider("Holding depth UI at \(Int(depth)) while awaiting \(pendingTarget); incoming \(state.depth)")
                        lastDepthPendingLogAt = now
                    }
                } else {
                    logSlider("Depth pending target \(pendingTarget) timed out; applying incoming \(state.depth)")
                    depth = Double(state.depth)
                    clearPendingDepthTarget()
                }
            } else {
                if let pendingTarget = pendingDepthTarget, state.depth == pendingTarget {
                    logSlider("Depth matched pending target \(pendingTarget)")
                }
                depth = Double(state.depth)
                clearPendingDepthTarget()
            }
        }
        if !isDraggingSensation {
            if let pendingTarget = pendingSensationTarget, state.sensation != pendingTarget {
                if now.timeIntervalSince(pendingSensationTargetSetAt) < pendingSliderSyncTimeout {
                    if now.timeIntervalSince(lastSensationPendingLogAt) >= pendingLogThrottle {
                        logSlider("Holding sensation UI at \(Int(sensation)) while awaiting \(pendingTarget); incoming \(state.sensation)")
                        lastSensationPendingLogAt = now
                    }
                } else {
                    logSlider("Sensation pending target \(pendingTarget) timed out; applying incoming \(state.sensation)")
                    sensation = Double(state.sensation)
                    clearPendingSensationTarget()
                }
            } else {
                if let pendingTarget = pendingSensationTarget, state.sensation == pendingTarget {
                    logSlider("Sensation matched pending target \(pendingTarget)")
                }
                sensation = Double(state.sensation)
                clearPendingSensationTarget()
            }
        }

        // Only sync pattern if we haven't interacted with it recently (1.5s lockout)
        if Date().timeIntervalSince(lastInteractionTime) > 1.5 {
             if selectedPattern != state.pattern {
                selectedPattern = state.pattern
            }
        }
    }

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
            speed: clampSliderValue(Int(speed)),
            stroke: clampSliderValue(Int(stroke)),
            depth: clampSliderValue(Int(depth)),
            sensation: clampSliderValue(Int(sensation)),
            pattern: selectedPattern,
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
        let targetSpeed = speedOverride ?? preset.speed
        logSlider("Applying preset '\(preset.name)' at speed \(targetSpeed)%")
        lastInteractionTime = Date()
        if selectedPattern != preset.pattern {
            selectedPattern = preset.pattern
        } else {
            bleManager.setPattern(preset.pattern)
        }
        commitSpeed(targetSpeed, source: .presetLoad)
        commitStroke(preset.stroke, source: .presetLoad)
        commitDepth(preset.depth, source: .presetLoad)
        commitSensation(preset.sensation, source: .presetLoad)
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

    func adjustSpeed(by delta: Int) {
        logSlider("Tap speed \(delta > 0 ? "+" : "-")")
        isDraggingSpeed = false
        commitSpeed(Int(speed) + delta, source: .buttonTap)
    }

    func adjustStroke(by delta: Int) {
        logSlider("Tap stroke \(delta > 0 ? "+" : "-")")
        isDraggingStroke = false
        commitStroke(Int(stroke) + delta, source: .buttonTap)
    }

    func adjustDepth(by delta: Int) {
        logSlider("Tap depth \(delta > 0 ? "+" : "-")")
        isDraggingDepth = false
        commitDepth(Int(depth) + delta, source: .buttonTap)
    }

    func adjustSensation(by delta: Int) {
        logSlider("Tap sensation \(delta > 0 ? "+" : "-")")
        isDraggingSensation = false
        commitSensation(Int(sensation) + delta, source: .buttonTap)
    }

    func commitSpeed(_ value: Int, source: SliderUpdateSource) {
        let clampedValue = clampSliderValue(value)
        logSlider("Commit speed (\(source.rawValue)): \(Int(speed)) -> \(clampedValue)")
        speed = Double(clampedValue)
        pendingSpeedTarget = clampedValue
        pendingSpeedTargetSetAt = Date()
        bleManager.setSpeed(clampedValue) { result in
            if case .failure(let error) = result {
                DispatchQueue.main.async {
                    self.logSlider("Speed command failed: \(error.localizedDescription)")
                    self.clearPendingSpeedTarget()
                }
            }
        }
    }

    func commitStroke(_ value: Int, source: SliderUpdateSource) {
        let clampedValue = clampSliderValue(value)
        logSlider("Commit stroke (\(source.rawValue)): \(Int(stroke)) -> \(clampedValue)")
        stroke = Double(clampedValue)
        pendingStrokeTarget = clampedValue
        pendingStrokeTargetSetAt = Date()
        bleManager.setStroke(clampedValue) { result in
            if case .failure(let error) = result {
                DispatchQueue.main.async {
                    self.logSlider("Stroke command failed: \(error.localizedDescription)")
                    self.clearPendingStrokeTarget()
                }
            }
        }
    }

    func commitDepth(_ value: Int, source: SliderUpdateSource) {
        let clampedValue = clampSliderValue(value)
        logSlider("Commit depth (\(source.rawValue)): \(Int(depth)) -> \(clampedValue)")
        depth = Double(clampedValue)
        pendingDepthTarget = clampedValue
        pendingDepthTargetSetAt = Date()
        bleManager.setDepth(clampedValue) { result in
            if case .failure(let error) = result {
                DispatchQueue.main.async {
                    self.logSlider("Depth command failed: \(error.localizedDescription)")
                    self.clearPendingDepthTarget()
                }
            }
        }
    }

    func commitSensation(_ value: Int, source: SliderUpdateSource) {
        let clampedValue = clampSliderValue(value)
        logSlider("Commit sensation (\(source.rawValue)): \(Int(sensation)) -> \(clampedValue)")
        sensation = Double(clampedValue)
        pendingSensationTarget = clampedValue
        pendingSensationTargetSetAt = Date()
        bleManager.setSensation(clampedValue) { result in
            if case .failure(let error) = result {
                DispatchQueue.main.async {
                    self.logSlider("Sensation command failed: \(error.localizedDescription)")
                    self.clearPendingSensationTarget()
                }
            }
        }
    }

    func clampSliderValue(_ value: Int) -> Int {
        max(sliderRange.lowerBound, min(sliderRange.upperBound, value))
    }

    func clampSettingsValue(_ value: Int) -> Int {
        max(settingsRange.lowerBound, min(settingsRange.upperBound, value))
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

    func clearPendingSpeedTarget() {
        pendingSpeedTarget = nil
        pendingSpeedTargetSetAt = .distantPast
        lastSpeedPendingLogAt = .distantPast
    }

    func clearPendingStrokeTarget() {
        pendingStrokeTarget = nil
        pendingStrokeTargetSetAt = .distantPast
        lastStrokePendingLogAt = .distantPast
    }

    func clearPendingDepthTarget() {
        pendingDepthTarget = nil
        pendingDepthTargetSetAt = .distantPast
        lastDepthPendingLogAt = .distantPast
    }

    func clearPendingSensationTarget() {
        pendingSensationTarget = nil
        pendingSensationTargetSetAt = .distantPast
        lastSensationPendingLogAt = .distantPast
    }

    func logSlider(_ message: String) {
        guard sliderDebugLogging else { return }
        print("[StrokeEngine][Slider] \(message)")
    }

    enum SliderUpdateSource: String {
        case sliderRelease = "slider"
        case buttonTap = "button"
        case presetLoad = "preset"
    }
}

struct StrokeEngineSettingsView: PlatformSplitView {
    @Binding var showPresetsSection: Bool
    @Binding var highSpeedWarningEnabled: Bool
    @Binding var highSpeedWarningThreshold: Int
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

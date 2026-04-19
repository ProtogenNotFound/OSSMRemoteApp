//
//  StrokeEngineView+visionOS.swift
//  OSSM Control
//

import SwiftUI
import SwiftData

#if os(visionOS)
extension StrokeEngineView {
    var visionBody: some View {
        visionLifecycleContent
    }

    private var visionLifecycleContent: some View {
        visionAlertContent
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

    private var visionAlertContent: some View {
        visionSheetContent
            .alert("Save Preset", isPresented: $showAddPresetPrompt) {
                visionSavePresetAlertActions
            } message: {
                Text("Save current speed, stroke, depth, sensation, and pattern.")
            }
            .alert("Preset Error", isPresented: $showPresetError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(verbatim: presetErrorMessage)
            }
            .alert("High Speed Preset", isPresented: $showHighSpeedPresetWarning) {
                visionHighSpeedPresetAlertActions
            } message: {
                visionHighSpeedPresetAlertMessage
            }
    }

    private var visionSheetContent: some View {
        visionChromeContent
            .sheet(isPresented: settingsPresented) {
                visionSettingsSheet
            }
            .sheet(isPresented: $showPresetEditor) {
                visionPresetManagerSheet
            }
    }

    private var visionChromeContent: some View {
        visionControlsContent
            .toolbar {
                visionToolbar
            }
    }

    private var visionSettingsSheet: some View {
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

    private var visionPresetManagerSheet: some View {
        StrokePresetManagerView(selectedPresetID: $selectedPresetID)
            .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private var visionSavePresetAlertActions: some View {
        TextField("Preset Name", text: $newPresetName)
        Button("Cancel", role: .cancel) {}
        Button("Save") {
            saveCurrentValuesAsPreset(named: newPresetName)
        }
    }

    @ViewBuilder
    private var visionHighSpeedPresetAlertActions: some View {
        Button("Hell yeah >:3") {
            confirmPendingPresetActivation()
        }
        Button("Set Speed to 0") {
            confirmPendingPresetActivation(speedOverride: 0)
        }
        Button("Cancel", role: .cancel) {
            clearPendingPresetActivation()
        }
    }

    @ViewBuilder
    private var visionHighSpeedPresetAlertMessage: some View {
        if let pendingPresetActivation {
            Text(verbatim: "\"\(pendingPresetActivation.name)\" is set to \(pendingPresetActivation.speed)% speed. Thats pretty fast :3 are you sure?")
        } else {
            Text(verbatim: "The selected preset exceeds \(highSpeedPresetThreshold)% speed. Thats pretty fast :3 are you sure?")
        }
    }

    @ToolbarContentBuilder
    private var visionToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .bottomOrnament) {
            Button("EMERGENCY STOP", systemImage: "stop.circle.fill") {
                controls.setValue(0, for: .speed)
            }
            .fontWeight(.bold)
            .tint(.red)
            .buttonStyle(.borderedProminent)
            .labelStyle(.titleAndIcon)
            Button("Pull Out", systemImage: "arrow.backward.to.line") {
                bleManager.pullOut()
            }
            .labelStyle(.titleAndIcon)
        }
    }

    private var visionControlsContent: some View {
        VStack {
            visionPresetsSection
            visionControlSection(
                title: "Speed",
                parameter: .speed,
                value: currentControls.speed,
                stepAmount: speedStepAmount
            )
            visionControlSection(
                title: "Stroke",
                parameter: .stroke,
                value: currentControls.stroke,
                stepAmount: strokeStepAmount
            )
            visionControlSection(
                title: "Depth",
                parameter: .depth,
                value: currentControls.depth,
                stepAmount: depthStepAmount
            )
            visionSensationSection
            visionPatternSelectionSection
        }
        .padding([.horizontal, .bottom])
    }

    @ViewBuilder
    private var visionPresetsSection: some View {
        if showPresetsSection {
            Section("Presets") {
                HStack {
                    Picker("Selected:", selection: $selectedPresetID) {
                        Text("None").tag(Optional<UUID>.none)
                        ForEach(presets) { preset in
                            Text(verbatim: preset.name)
                                .tag(Optional<UUID>.some(preset.id))
                        }
                    }
                    Spacer()
                    Button("Edit", systemImage: "pencil") {
                        showPresetEditor.toggle()
                    }
                    Button("Add", systemImage: "plus") {
                        newPresetName = suggestedPresetName
                        showAddPresetPrompt = true
                    }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.bordered)

                if let selectedPreset {
                    Text(verbatim: selectedPreset.summaryText)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else if presets.isEmpty {
                    Text("No presets yet. Tap Add to save the current settings.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            Divider()
        }
    }

    private func visionControlSection(
        title: LocalizedStringKey,
        parameter: StrokeEngineParameter,
        value: Int,
        stepAmount: Int
    ) -> some View {
        Section {
            visionSliderControls(parameter: parameter, value: value, stepAmount: stepAmount)
        } header: {
            visionControlHeader(title: title, valueText: "\(value)%")
        }
    }

    private func visionSliderControls(
        parameter: StrokeEngineParameter,
        value: Int,
        stepAmount: Int
    ) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Button("Minus", systemImage: "minus") {
                    adjust(parameter, by: -stepAmount)
                }
                .buttonStyle(.bordered)
                .disabled(value <= sliderRange.lowerBound)

                Slider(value: sliderBinding(for: parameter), in: 0...100, step: 1)

                Button("Plus", systemImage: "plus") {
                    adjust(parameter, by: stepAmount)
                }
                .buttonStyle(.bordered)
                .disabled(value >= sliderRange.upperBound)
            }
            .labelStyle(.iconOnly)
        }
    }

    private func visionControlHeader(
        title: LocalizedStringKey,
        valueText: String
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(verbatim: valueText)
                .foregroundColor(.secondary)
        }
    }

    private var visionSensationSection: some View {
        Section {
            visionSliderControls(
                parameter: .sensation,
                value: currentControls.sensation,
                stepAmount: sensationStepAmount
            )
        } header: {
            HStack {
                Text("Sensation")
                Button("info", systemImage: "info.circle.fill") {
                    showSensationInfo.toggle()
                }
                .buttonStyle(.borderless)
                .labelStyle(.iconOnly)
                .popover(isPresented: $showSensationInfo) {
                    Text(selectedPatternInfo?.sensationDescription ?? LocalizedStringKey("Error"))
                        .font(.caption2)
                        .minimumScaleFactor(0.5)
                        .padding(.horizontal, 8)
                        .presentationCompactAdaptation(.popover)
                }
                Spacer()
                Text(verbatim: "\(sensationDisplayValue)")
                    .foregroundColor(.secondary)
            }
        }
        .disabled(selectedPatternInfo?.sensationDescription == nil)
    }

    private var visionPatternSelectionSection: some View {
        Section("Pattern") {
            Picker("Selected:", selection: patternBinding) {
                ForEach(availablePatterns) { pattern in
                    visionPatternPickerRow(for: pattern)
                        .tag(pattern.idx)
                }
            }
        }
    }

    @ViewBuilder
    private func visionPatternPickerRow(for pattern: OSSMPattern) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: pattern.name)

            if let description = pattern.description, !description.isEmpty {
                Text(verbatim: description)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .minimumScaleFactor(0.5)
                    .lineLimit(3, reservesSpace: true)
                    .padding(.horizontal, 8)
            }
        }
    }
}

extension StrokeEngineSettingsView {
    var visionBody: some View {
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
}

extension StrokePresetManagerView {
    var visionBody: some View {
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
}

extension StrokePresetDetailView {
    var visionBody: some View {
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
}
#endif

//
//  StrokeEngineView+visionOS.swift
//  OSSM Control
//

import SwiftUI
import SwiftData

#if os(visionOS)
extension StrokeEngineView {
    var visionBody: some View {
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

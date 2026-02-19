//
//  StrokeEngineView.swift
//  OSSM Control
//

import SwiftUI

struct StrokeEngineView: View {

    @EnvironmentObject private var bleManager: OSSMBLEManager

    @State private var speed: Double = 0
    @State private var stroke: Double = 50
    @State private var depth: Double = 50
    @State private var sensation: Double = 50
    @State private var selectedPattern: Int = 0

    @State private var isUpdating = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showSensationInfo: Bool = false

    // Dragging state tracking
    @State private var isDraggingSpeed = false
    @State private var isDraggingStroke = false
    @State private var isDraggingDepth = false
    @State private var isDraggingSensation = false

    @State private var pendingSpeedTarget: Int?
    @State private var pendingSpeedTargetSetAt: Date = .distantPast
    @State private var pendingStrokeTarget: Int?
    @State private var pendingStrokeTargetSetAt: Date = .distantPast
    @State private var pendingDepthTarget: Int?
    @State private var pendingDepthTargetSetAt: Date = .distantPast
    @State private var pendingSensationTarget: Int?
    @State private var pendingSensationTargetSetAt: Date = .distantPast

    @State private var lastSpeedPendingLogAt: Date = .distantPast
    @State private var lastStrokePendingLogAt: Date = .distantPast
    @State private var lastDepthPendingLogAt: Date = .distantPast
    @State private var lastSensationPendingLogAt: Date = .distantPast

    private let sliderRange: ClosedRange<Int> = 0...100
    private let sliderStepAmount: Int = 5
    private let pendingSliderSyncTimeout: TimeInterval = 4.0
    private let pendingLogThrottle: TimeInterval = 0.5
    private let sliderDebugLogging: Bool = true

    private var availablePatterns: [OSSMPattern] {
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

    private var selectedPatternInfo: OSSMPattern? {
        availablePatterns.first(where: { $0.idx == selectedPattern })
    }

    var body: some View {
        List {
            // Speed Control
            Section {
                VStack(alignment: .leading) {
                    HStack {
                        Button {
                            adjustSpeed(by: -sliderStepAmount)
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
                            adjustSpeed(by: sliderStepAmount)
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
                            adjustStroke(by: -sliderStepAmount)
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
                            adjustStroke(by: sliderStepAmount)
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
                            adjustDepth(by: -sliderStepAmount)
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
                            adjustDepth(by: sliderStepAmount)
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
                            adjustSensation(by: -sliderStepAmount)
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
                            adjustSensation(by: sliderStepAmount)
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
                    Text("\(Int((sensation*2)-100))")
                        .foregroundColor(.secondary)
                }
            }.disabled(selectedPatternInfo?.sensationDescription == nil)

            // Pattern Selection
            Section("Pattern") {
                Picker("Pattern", selection: $selectedPattern) {
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
        .toolbar{
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
        .monospacedDigit()
        .disabled(bleManager.currentPage != .strokeEngine)
        .navigationTitle("Stroke Engine")
        .onAppear {
            syncState()
        }
        .onReceive(bleManager.runtimeData.$currentState) { _ in
            syncState()
        }
    }

    // Lockout timer to prevent incoming packets from resetting selection while user is interacting
    @State private var lastInteractionTime: Date = Date.distantPast

    private func syncState() {
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

    private func adjustSpeed(by delta: Int) {
        logSlider("Tap speed \(delta > 0 ? "+" : "-")")
        isDraggingSpeed = false
        commitSpeed(Int(speed) + delta, source: .buttonTap)
    }

    private func adjustStroke(by delta: Int) {
        logSlider("Tap stroke \(delta > 0 ? "+" : "-")")
        isDraggingStroke = false
        commitStroke(Int(stroke) + delta, source: .buttonTap)
    }

    private func adjustDepth(by delta: Int) {
        logSlider("Tap depth \(delta > 0 ? "+" : "-")")
        isDraggingDepth = false
        commitDepth(Int(depth) + delta, source: .buttonTap)
    }

    private func adjustSensation(by delta: Int) {
        logSlider("Tap sensation \(delta > 0 ? "+" : "-")")
        isDraggingSensation = false
        commitSensation(Int(sensation) + delta, source: .buttonTap)
    }

    private func commitSpeed(_ value: Int, source: SliderUpdateSource) {
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

    private func commitStroke(_ value: Int, source: SliderUpdateSource) {
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

    private func commitDepth(_ value: Int, source: SliderUpdateSource) {
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

    private func commitSensation(_ value: Int, source: SliderUpdateSource) {
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

    private func clampSliderValue(_ value: Int) -> Int {
        max(sliderRange.lowerBound, min(sliderRange.upperBound, value))
    }

    private func clearPendingSpeedTarget() {
        pendingSpeedTarget = nil
        pendingSpeedTargetSetAt = .distantPast
        lastSpeedPendingLogAt = .distantPast
    }

    private func clearPendingStrokeTarget() {
        pendingStrokeTarget = nil
        pendingStrokeTargetSetAt = .distantPast
        lastStrokePendingLogAt = .distantPast
    }

    private func clearPendingDepthTarget() {
        pendingDepthTarget = nil
        pendingDepthTargetSetAt = .distantPast
        lastDepthPendingLogAt = .distantPast
    }

    private func clearPendingSensationTarget() {
        pendingSensationTarget = nil
        pendingSensationTargetSetAt = .distantPast
        lastSensationPendingLogAt = .distantPast
    }

    private func logSlider(_ message: String) {
        guard sliderDebugLogging else { return }
        print("[StrokeEngine][Slider] \(message)")
    }

    private enum SliderUpdateSource: String {
        case sliderRelease = "slider"
        case buttonTap = "button"
    }
}

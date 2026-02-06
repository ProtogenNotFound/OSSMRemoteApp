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

    // Value increments
    @State private var speedIncrement: Int = 5

    var body: some View {
        List {
            // Speed Control
            Section {
                VStack(alignment: .leading) {
                    HStack {
//                        Button("Decrease", systemImage: "minus") {
//                            isDraggingSpeed = false
//                            let newSpeed = max(0, Int(speed) - speedIncrement)
//                            bleManager.setSpeed(newSpeed)
//                            speed = Double(newSpeed)
//                        }
                        Slider(value: $speed, in: 0...100, step: 1) { editing in
                            isDraggingSpeed = editing
                            if !editing {
                                bleManager.setSpeed(Int(speed))
                            }
                        }
//                        Button("Increase", systemImage: "minus") {
//                            isDraggingSpeed = false
//                            print("speed is currently \(speed)")
//                            let newSpeed = min(100, Int(speed) + speedIncrement)
//                            print("new speed is \(newSpeed)")
//                            bleManager.setSpeed(newSpeed) { res in
//                                print("speed set completion")
//                                print(res)
//                            }
//                            print("setting speed to \(newSpeed)")
//                            speed = Double(newSpeed)
//                            print("set speed to \(speed)")
//                        }
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
                    Slider(value: $stroke, in: 0...100, step: 1) { editing in
                        isDraggingStroke = editing
                        if !editing {
                            bleManager.setStroke(Int(stroke))
                        }
                    }
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
                    Slider(value: $depth, in: 0...100, step: 1) { editing in
                        isDraggingDepth = editing
                        if !editing {
                            bleManager.setDepth(Int(depth))
                        }
                    }
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
                    Slider(value: $sensation, in: 0...100, step: 1) { editing in
                        isDraggingSensation = editing
                        if !editing {
                            bleManager.setSensation(Int(sensation))
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Sensation")
                    Button("info", systemImage: "info.circle") {
                        showSensationInfo.toggle()
                    }
                    .labelStyle(.iconOnly)
                    .popover(isPresented: $showSensationInfo) {
                        Text(KnownPattern(rawValue: selectedPattern)?.sensationDescription ?? LocalizedStringKey("Error"))
                            .font(.caption2)
                            .minimumScaleFactor(0.5)
                            .padding(.horizontal, 8)
                            .presentationCompactAdaptation(.popover)
                    }
                    Spacer()
                    Text("\(Int((sensation*2)-100))")
                        .foregroundColor(.secondary)
                }
            }.disabled(KnownPattern(rawValue: selectedPattern)?.sensationDescription == nil)

            // Pattern Selection
            Section("Pattern") {
                Picker("Pattern", selection: $selectedPattern) {
                    ForEach(KnownPattern.allCases) { pattern in
                        Section(pattern.name){
                            Text(pattern.description)
                                .font(.caption2)
                                .minimumScaleFactor(0.5)
                                .lineLimit(3, reservesSpace: true)
                                .padding(.horizontal, 8)
                        }.tag(pattern.rawValue)
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
        print("syncing state")
        let state = bleManager.runtimeData.currentState
        if !isDraggingSpeed { speed = Double(state.speed); print("syncing speed: \(speed)") }
        if !isDraggingStroke { stroke = Double(state.stroke) }
        if !isDraggingDepth { depth = Double(state.depth) }
        if !isDraggingSensation { sensation = Double(state.sensation) }

        // Only sync pattern if we haven't interacted with it recently (1.5s lockout)
        if Date().timeIntervalSince(lastInteractionTime) > 1.5 {
             if selectedPattern != state.pattern {
                selectedPattern = state.pattern
            }
        }
    }
}

//
//  OSSMControlView.swift
//  OSSM Control
//
//  Main SwiftUI View for OSSM Control
//

import SwiftUI
import CoreBluetooth

struct OSSMControlView: View {
    @EnvironmentObject private var bleManager: OSSMBLEManager
    @State private var path: [OSSMPage] = []
    @AppStorage("savedUUID") private var savedUUID: String?

    @State private var speed: Double = 0
    @State private var stroke: Double = 50
    @State private var depth: Double = 50
    @State private var sensation: Double = 50
    @State private var selectedPattern: Int = 0

    @State private var isUpdating = false
    @State private var showError = false
    @State private var errorMessage = ""

    // Dragging state tracking
    @State private var isDraggingSpeed = false
    @State private var isDraggingStroke = false
    @State private var isDraggingDepth = false
    @State private var isDraggingSensation = false

    // Homing sheet animation toggle (true for 1.5s, false for 0.5s)
    @State private var homingPulse = false
    @State private var homingPulseTask: Task<Void, Never>? = nil

    fileprivate func toolbarMenu() -> ToolbarItem<(), Menu<some View, TupleView<(Section<Text, some View, EmptyView>, Section<Text, Text, EmptyView>, Button<Text>)>>> {
        return ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Section("Connection Status"){
                    connectionStatusView
                }
                // Status Section
                Section("Device Status") {
                    Text(bleManager.currentState.state.rawValue)
                }
                Button("Disconnect", role: .destructive) {
                    bleManager.disconnect()
                    // Remove saved device so we don't auto-reconnect
                    savedUUID = nil
                    // Start scanning for new devices
                    bleManager.startScanning()
                }
            } label: {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
            }
            
        }
    }
    
    var body: some View {
        NavigationStack (path: $path){
            Group {
                if bleManager.connectionStatus == .ready {
                    MenuView()
                        .sheet(
                            isPresented: Binding(
                                get: { bleManager.homing },
                                set: { _ in }
                            )
                        ) {
                            let forward = bleManager.currentState.state.rawValue.contains("forward")
                            let homingString = forward ? "Homing Forward" : "Homing Backward"
                            let homingImage = forward ? "arrow.forward.to.line" : "arrow.backward.to.line"

                            VStack(spacing: 16) {
                                ProgressView(homingString)
                                    .contentTransition(.numericText())
                                Image(systemName: homingImage)
                                    // drawOn/drawOff are effectively the same right now, so we toggle isActive to keep it animating
                                    .symbolEffect(.drawOn.byLayer, isActive: homingPulse)
                                    .contentTransition(.symbolEffect(.replace))
                            }
                            .animation(.easeInOut, value: homingString)
                            .font(.largeTitle.bold())
                            .fontDesign(.rounded)
                            .onAppear {
                                startHomingPulseLoop()
                            }
                            .onDisappear {
                                stopHomingPulseLoop()
                            }
                            .interactiveDismissDisabled()
                            .presentationDetents([.medium])
                        }
                } else if !bleManager.discoveredPeripherals.isEmpty {
                    deviceListView
                } else {
                    scanningView
                }
            }
            .navigationDestination(for: OSSMPage.self) { page in
                switch page {
                case .menu:
                    MenuView()
                        .toolbar {
                            toolbarMenu()
                        }
                case .simplePenetration:
                    SimplePenetrationView()
                        .toolbar {
                            toolbarMenu()
                        }
                case .strokeEngine:
                    StrokeEngineView()
                        .toolbar {
                            toolbarMenu()
                        }
                }
            }
            .toolbar {
                toolbarMenu()
            }
            .navigationTitle("OSSM Control")
        }
        .onChange(of: path, { _, newPath in
            let target = newPath.last ?? .menu
            bleManager.navigateTo(target)
        })
        .onChange(of: bleManager.discoveredPeripherals) { _, _ in
            tryConnectIfSaved()
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .onChange(of: bleManager.lastError) { _, newValue in
            if let error = newValue {
                errorMessage = error
                showError = true
            }
        }
        .onChange(of: bleManager.currentState) { _, newState in
            // Sync UI with device state (only if not currently updating)
            if !isUpdating {
                if !isDraggingSpeed { speed = Double(newState.speed) }
                if !isDraggingStroke { stroke = Double(newState.stroke) }
                if !isDraggingDepth { depth = Double(newState.depth) }
                if !isDraggingSensation { sensation = Double(newState.sensation) }
                selectedPattern = newState.pattern
            }
        }
        .onChange(of: bleManager.connectionStatus) { _, status in
            if status == .ready {
                path = []
                bleManager.navigateTo(.menu)
            }
        }
    }

    // MARK: - Subviews


    private var disconnectedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("No OSSM Device Connected")
                .font(.headline)

            Text("Scanning for nearby OSSM devices...")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
    }

    private var scanningView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)

            Text("Scanning for OSSM devices...")
                .font(.headline)
        }
        .padding()
    }

    private var deviceListView: some View {
        List {
            Section("Discovered Devices") {
                ForEach(bleManager.discoveredPeripherals, id: \.identifier) { peripheral in
                    Button(action: {
                        bleManager.connect(to: peripheral)
                        savedUUID = peripheral.identifier.uuidString
                    }) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(peripheral.name ?? "Unknown Device")
                                    .font(.headline)
                                Text(peripheral.identifier.uuidString)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                    }
                    .foregroundColor(.primary)
                }
            }
        }
        .refreshable {
            bleManager.startScanning()
        }
        .onChange(of: bleManager.discoveredPeripherals) { _, _ in
            tryConnectIfSaved()
        }
    }


    private var connectionStatusView: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(bleManager.connectionStatus.rawValue)
                .font(.caption)
        }
    }

    private var statusColor: Color {
        switch bleManager.connectionStatus {
        case .ready:
            return .green
        case .connected, .connecting:
            return .yellow
        case .scanning:
            return .blue
        case .disconnected:
            return .red
        }
    }

    // MARK: - Actions

    @MainActor
    private func startHomingPulseLoop() {
        // Avoid creating multiple loops if SwiftUI re-renders
        homingPulseTask?.cancel()
        homingPulseTask = Task { @MainActor in
            while !Task.isCancelled {
                homingPulse = false
                try? await Task.sleep(for: .seconds(2))
                homingPulse = true
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    @MainActor
    private func stopHomingPulseLoop() {
        homingPulseTask?.cancel()
        homingPulseTask = nil
        homingPulse = false
    }

    private func tryConnectIfSaved() {
        guard let saved = savedUUID else { return }
        // Attempt to find a matching peripheral by UUID among discovered peripherals and connect
        if let match = bleManager.discoveredPeripherals.first(where: { $0.identifier.uuidString == saved }) {
            bleManager.connect(to: match)
        }
    }
}

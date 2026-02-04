//
//  OSSMControlView.swift
//  OSSM Control
//
//  Main SwiftUI View for OSSM Control
//

import SwiftUI
import CoreBluetooth

struct OSSMControlView: View {
    @AppStorage("homingForwardTime") private var homingForwardTime: Double?
    @AppStorage("homingBackwardTime") private var homingBackwardTime: Double?
    @EnvironmentObject private var bleManager: OSSMBLEManager
    @State private var path: [OSSMPage] = []
    @AppStorage("savedUUID") private var savedUUID: String?
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""

    // Dragging state tracking
    // Removed redundant state variables to prevent flickering


    // Homing sheet animation toggle (true for 1.5s, false for 0.5s)
    @State private var homingPulse = false
    @State private var homingPulseTask: Task<Void, Never>? = nil

    fileprivate func resetAppStorage() {
        // Remove saved device so we don't auto-reconnect
        savedUUID = nil
        homingBackwardTime = nil
        homingForwardTime = nil
    }
    
    fileprivate func toolbarMenu() -> ToolbarItem<(), Menu<some View, TupleView<(Section<Text, some View, EmptyView>, Section<Text, Text, EmptyView>, Button<Text>)>>> {
        return ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Section("Connection Status"){
                    connectionStatusView
                }
                // Status Section
                Section("Device Status") {
                    Text(bleManager.currentRootState.rawValue)
                }
                Button("Disconnect", role: .destructive) {
                    bleManager.disconnect()
                    resetAppStorage()
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
                        .sheet(isPresented: .constant(bleManager.homing)) {
                            HomingSheetView(
                                forward: bleManager.currentRootState.rawValue.contains("forward"),
                                homingPulse: $homingPulse,
                                onAppear: startHomingPulseLoop,
                                onDisappear: stopHomingPulseLoop
                            )
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
        // Removed redundant .onChange(of: bleManager.currentState) to prevent main view refreshes
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

private struct HomingProgressBar: View {
    @EnvironmentObject var bleManager: OSSMBLEManager
    let duration: TimeInterval

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0/30.0)) { _ in
            let progress: CGFloat = {
                guard duration > 0, let end = bleManager.homingEstimatedEndTime else { return 0 }
                let remaining = end.timeIntervalSinceNow
                let p = 1 - (remaining / duration)
                return CGFloat(max(0, min(1, p)))
            }()

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.quaternary)
                    Capsule()
                        .fill(.tint)
                        .frame(width: progress * geo.size.width)
                        .animation(.linear(duration: 1.0/30.0), value: progress)
                }
            }
            .frame(height: 10)
        }
    }
}

private struct HomingSheetView: View {
    @EnvironmentObject var bleManager: OSSMBLEManager

    @AppStorage("homingForwardTime") private var homingForwardTime: Double?
    @AppStorage("homingBackwardTime") private var homingBackwardTime: Double?

    let forward: Bool
    @Binding var homingPulse: Bool
    let onAppear: () -> Void
    let onDisappear: () -> Void

    var body: some View {
        let homingString = forward ? "Homing Forward" : "Homing Backward"
        let homingImage = forward ? "arrow.forward.to.line" : "arrow.backward.to.line"

        VStack(spacing: 16) {
            let homingSeconds = forward ? homingForwardTime ?? 0 : homingBackwardTime ?? 0
            TimelineView(.periodic(from: .now, by: 1.0/30.0)) { _ in
                let progress: CGFloat = {
                    guard homingSeconds > 0, let end = bleManager.homingEstimatedEndTime else { return 0 }
                    let remaining = end.timeIntervalSinceNow
                    let p = 1 - (remaining / homingSeconds)
                    return CGFloat(max(0, min(1, p)))
                }()

                ZStack(alignment: .leading) {
                    // Base text (unfilled) in light gray
                    Text(homingString)
                        .foregroundStyle(.secondary)

                    // Filled portion in white, clipped by progress width
                    Text(homingString)
                        .contentTransition(.numericText())
                        .foregroundStyle(.white)
                        .overlay {
                            GeometryReader { geo in
                                Color.clear
                                    .frame(width: progress * geo.size.width)
                            }
                        }
                        .mask {
                            GeometryReader { geo in
                                Rectangle()
                                    .frame(width: progress * geo.size.width)
                                    .animation(.linear(duration: 1.0/30.0), value: progress)
                            }
                        }
                }
            }
            Image(systemName: homingImage)
                .symbolEffect(.drawOn.byLayer, isActive: homingPulse)
                .contentTransition(.symbolEffect(.replace))
        }
        .animation(.easeInOut, value: homingString)
        .font(.largeTitle.bold())
        .fontDesign(.rounded)
        .onAppear { onAppear() }
        .onDisappear { onDisappear() }
    }
}


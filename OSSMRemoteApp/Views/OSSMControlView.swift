//
//  OSSMControlView.swift
//  OSSM Control
//
//  Main SwiftUI View for OSSM Control
//

import SwiftUI
import CoreBluetooth
import SwiftData

struct OSSMControlView: PlatformSplitView {
    @AppStorage("homingForwardTime") var homingForwardTime: Double?
    @AppStorage("homingBackwardTime") var homingBackwardTime: Double?
    @AppStorage("savedUUID") var savedUUID: String?
    @AppStorage("debug.sessionData.persist") var persistDebugSessionData = false
    @AppStorage("strokeEngine.settings.saveLiveSessionData") var saveLiveSessionData = true
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var bleManager: OSSMBLEManager
    @State var path: [OSSMPage] = []
    @State var showSettings: Bool = false
    @State var showError: Bool = false
    @State var errorMessage: String = ""

    // Dragging state tracking
    // Removed redundant state variables to prevent flickering

    // Homing sheet animation toggle (true for 1.5s, false for 0.5s)
    @State var homingPulse = false
    @State var homingPulseTask: Task<Void, Never>? = nil

    #if !os(visionOS)
    @Namespace private var strokeEngineTransition
    #endif

    func resetAppStorage() {
        // Remove saved device so we don't auto-reconnect
        savedUUID = nil
        homingBackwardTime = nil
        homingForwardTime = nil
    }

    func persistSessionStats(_ sessionStats: OSSMSessionStats) {
        guard saveLiveSessionData else { return }

        if bleManager.isDebugMode && !persistDebugSessionData {
            return
        }

        let sessionId = sessionStats.sessionId
        var descriptor = FetchDescriptor<OSSMSessionStatsRecord>(
            predicate: #Predicate { $0.sessionId == sessionId }
        )
        descriptor.fetchLimit = 1

        do {
            if let existingRecord = try modelContext.fetch(descriptor).first {
                existingRecord.update(from: sessionStats)
            } else {
                modelContext.insert(OSSMSessionStatsRecord(sessionStats: sessionStats))
            }
        } catch {
            print("[OSSM] Failed to persist session stats for sessionId \(sessionId): \(error)")
        }
    }

    @ToolbarContentBuilder
    var toolbarMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            statusMenu
        }
    }

    var statusMenu: some View {
        Menu {
            Section("Connection Status"){
                connectionStatusView
            }
            // Status Section
            Section("Device Status") {
                Text(bleManager.currentRootState.rawValue)
            }
        } label: {
            if !bleManager.isDebugMode {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
            } else {
                Image(systemName: "ladybug")
                    .foregroundStyle(statusColor)
            }
        }
    }

    #if !os(visionOS)
    var iosBody: some View {
        NavigationStack (path: $path){
            Group {
                if bleManager.connectionStatus == .ready {
                    MenuView(heroTransitionNamespace: strokeEngineTransition)
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
                } else if savedUUID != nil {
                    savedDeviceReconnectView
                } else if !bleManager.discoveredPeripherals.isEmpty {
                    deviceListView
                } else {
                    scanningView
                }
            }
            .navigationDestination(for: OSSMPage.self) { page in
                switch page {
                case .menu:
                    MenuView(heroTransitionNamespace: strokeEngineTransition)
                        .toolbar {
                            toolbarMenu
                        }
                case .simplePenetration:
                    SimplePenetrationView()
                        .toolbar {
                            toolbarMenu
                        }
                case .strokeEngine:
                    StrokeEngineView(heroTransitionNamespace: strokeEngineTransition)
                        .toolbar {
                            toolbarMenu
                        }
                case .streaming:
                    StreamingView(heroTransitionNamespace: strokeEngineTransition)
                    .toolbar {
                        toolbarMenu
                    }
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    statusMenu
                    Button("Settings", systemImage: "gear") {
                        showSettings.toggle()
                    }
                    .labelStyle(.iconOnly)
                }
            }
            .navigationTitle("OSSM Control")
        }
        .sheet(isPresented: $showSettings) {
            settingsSheet
                .presentationDetents([.large])
        }
        .onChange(of: path, { _, newPath in
            let target = newPath.last ?? .menu
            Task {
                try? await bleManager.navigateTo(target)
            }
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
                Task {
                    try? await bleManager.navigateTo(.menu)
                }
            }
        }
        .onReceive(bleManager.runtimeData.$currentSessionStats) { sessionStats in
            guard let sessionStats else { return }
            persistSessionStats(sessionStats)
        }
    }
    #endif

    // MARK: - Settings Sheet (shared across platforms)

    var settingsSheet: some View {
        NavigationStack {
            Form {
                Section("Connectivity"){
                    Button("Disconnect", role: .destructive) {
                        bleManager.disconnect()
                        resetAppStorage()
                        // Start scanning for new devices
                        bleManager.startScanning()
                    }.disabled(bleManager.connectionStatus != .connected)
                }
                Section("Debug Mode"){
                    Button {
                        withAnimation(.spring) {
                            if !bleManager.isDebugMode {
                                bleManager.enableDebugMode()
                            } else {
                                bleManager.disableDebugMode()
                            }
                        }
                    } label: {
                        Text(bleManager.isDebugMode ? "Disable" : "Enable")
                    }
                    let liveDataBinding = Binding<Bool> {
                        bleManager.debugSessionSimulator.isEnabled
                    } set: {
                        bleManager.setDebugSessionSimulationEnabled($0)
                    }
                    Toggle("Simulate live session data", isOn: liveDataBinding)
                    Toggle("Persist simulated session data", isOn: $persistDebugSessionData)
                    let spsBinding = Binding<Double> {
                        bleManager.debugSessionSimulator.strokesPerSecond
                    } set: {
                        bleManager.debugSessionSimulator.strokesPerSecond = $0
                    }
                    let cmsBinding = Binding<Double> {
                        bleManager.debugSessionSimulator.distancePerSecondCm
                    } set: {
                        bleManager.debugSessionSimulator.distancePerSecondCm = $0
                    }
                    Stepper("Simulated Strokes/sec: \(spsBinding.wrappedValue, specifier: "%.1f")", value: spsBinding, step: 0.5)
                    Stepper("Simulated Distance/sec: \(Int(cmsBinding.wrappedValue))cm", value: cmsBinding, step: 10)
                }
            }
            .navigationTitle("Settings")
        }
    }

    // MARK: - Subviews


    var disconnectedView: some View {
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

    var scanningView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)

            Text("Scanning for OSSM devices...")
                .font(.headline)
        }
        .padding()
    }

    #if !os(visionOS)
    var savedDeviceReconnectView: some View {
        let found = !bleManager.discoveredPeripherals.isEmpty
        return VStack(spacing: 16) {
            Color.primary
                .frame(width: 100, height: 100)
                .mask {
                    Image("ossm")
                        .resizable()
                }
                .overlay(alignment: .topTrailing) {
                    Image(systemName: found ? "antenna.radiowaves.left.and.right.circle.fill" : "magnifyingglass.circle.fill")
                        .symbolRenderingMode(.multicolor)
                        .symbolEffect(.breathe)
                        .foregroundStyle(Color.accentColor)
                        .font(.largeTitle)
                        .offset(x: 10, y: -10)
                        .contentTransition(.symbolEffect(.replace))
                }
                .padding()
                .background(.ultraThickMaterial, in: .rect(cornerRadius: 16))
                .glassEffect(.clear, in: .rect(cornerRadius: 16))
            ProgressView("\(found ? "Connecting to" : "Looking for") your OSSM")
            if let savedUUID {
                Text(savedUUID)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .animation(.easeInOut, value: found)
        .padding()
    }
    #endif

    var deviceListView: some View {
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


    var connectionStatusView: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(bleManager.connectionStatus.rawValue)
                .font(.caption)
        }
    }

    var statusColor: Color {
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
    func startHomingPulseLoop() {
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
    func stopHomingPulseLoop() {
        homingPulseTask?.cancel()
        homingPulseTask = nil
        homingPulse = false
    }

    func tryConnectIfSaved() {
        guard let saved = savedUUID else { return }
        // Attempt to find a matching peripheral by UUID among discovered peripherals and connect
        if let match = bleManager.discoveredPeripherals.first(where: { $0.identifier.uuidString == saved }) {
            bleManager.connect(to: match)
        }
    }
}

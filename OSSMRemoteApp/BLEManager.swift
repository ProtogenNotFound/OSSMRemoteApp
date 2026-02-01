//
//  OSSMBLEManager.swift
//  OSSM Control
//
//  SwiftUI BLE Manager for OSSM Device Control
//  Based on KinkyMakers/OSSM-hardware firmware
//

import Foundation
import CoreBluetooth
import Combine
import SwiftUI

// MARK: - OSSM Data Types

/// Represents the connection status of the OSSM device
enum OSSMConnectionStatus: String {
    case disconnected = "Disconnected"
    case scanning = "Scanning..."
    case connecting = "Connecting..."
    case connected = "Connected"
    case ready = "Ready"
}

/// OSSM device status states (from firmware)
enum OSSMStatus: String, CaseIterable {
    case idle = "idle"
    case homing = "homing"
    case homingForward = "homing.forward"
    case homingBackward = "homing.backward"
    case menu = "menu"
    case menuIdle = "menu.idle"
    case simplePenetration = "simplePenetration"
    case simplePenetrationIdle = "simplePenetration.idle"
    case simplePenetrationPreflight = "simplePenetration.preflight"
    case strokeEngine = "strokeEngine"
    case strokeEngineIdle = "strokeEngine.idle"
    case strokeEnginePreflight = "strokeEngine.preflight"
    case strokeEnginePattern = "strokeEngine.pattern"
    case streaming = "streaming"
    case update = "update"
    case wifi = "wifi"
    case help = "help"
    case error = "error"
    case restart = "restart"
}

/// OSSM pages for navigation (must match firmware regex exactly)
enum OSSMPage: String, CaseIterable, Hashable{
    case menu = "menu"
    case simplePenetration = "simplePenetration"
    case strokeEngine = "strokeEngine"
    // Note: "streaming" is also valid in firmware
    init(_ status: OSSMStatus) throws {
        guard let pageString = status.rawValue.split(separator: ".").first else {
            throw NSError(domain: "OSSMBLEManager", code: 0, userInfo: nil)
        }
        guard let page = OSSMPage(rawValue: String(pageString)) else {
            throw NSError(domain: "OSSMBLEManager", code: 0, userInfo: nil)
        }
        self = page
    }
}

struct MenuView: View {
    @EnvironmentObject private var bleManager: OSSMBLEManager
    @AppStorage("savedUUID") private var savedUUID: String?
    var body: some View {
        List {
            NavigationLink("Simple Penetration", value: OSSMPage.simplePenetration)
            NavigationLink("Stroke Engine", value: OSSMPage.strokeEngine)


        }
    }
}

struct SimplePenetrationView: View {
    @EnvironmentObject private var bleManager: OSSMBLEManager
    var body: some View {
        Group{
            if bleManager.currentPage == .simplePenetration {
                Text("Simple Penetration")
                Button("Test"){
                    bleManager.navigateTo(.menu)
                }
            } else {
                ProgressView()
            }
        }.navigationTitle("Simple Penetration")
    }
}

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

    var body: some View {
        List {
            // Speed Control
            Section {
                VStack(alignment: .leading) {
                    Slider(value: $speed, in: 0...100, step: 1) { editing in
                        isDraggingSpeed = editing
                        if !editing {
                            bleManager.setSpeed(Int(speed))
                        }
                    }
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
            ToolbarItem(placement: .bottomBar) {
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
            }
        }
        .monospacedDigit()
        .disabled(bleManager.currentPage != .strokeEngine )
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
        
        if !isDraggingSpeed { speed = Double(state.speed) }
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

/// Known stroke patterns (from firmware - 7 patterns, 0-6)
enum KnownPattern: Int, CaseIterable, Identifiable {
    case simpleStroke = 0
    case teasingPounding = 1
    case roboStroke = 2
    case halfNHalf = 3
    case deeper = 4
    case stopNGo = 5
    case insist = 6

    var id: Int { rawValue }

    var name: String {
        switch self {
        case .simpleStroke: return "Simple Stroke"
        case .teasingPounding: return "Teasing/Pounding"
        case .roboStroke: return "Robo Stroke"
        case .halfNHalf: return "Half N Half"
        case .deeper: return "Deeper"
        case .stopNGo: return "Stop N Go"
        case .insist: return "Insist"
        }
    }

    var description: String {
        switch self {
        case .simpleStroke: return "Balanced acceleration, coasting and deceleration"
        case .teasingPounding: return "Adjusts the speed ratio between in and out movements using the sensation value"
        case .roboStroke: return "Sensation varies acceleration from robotic to gradual"
        case .halfNHalf: return "Alternates between full and half depth strokes"
        case .deeper: return "Stroke depth increases each cycle"
        case .stopNGo: return "Pauses between strokes"
        case .insist: return "Modifies strokelength while maintaining speed"
        }
    }

    var sensationDescription: LocalizedStringKey? {
        switch self {
        case .simpleStroke: return nil
        case .teasingPounding: return """
            **>0:** Makes the in-move faster for a hard pounding sensation
            **<0:** Makes the out-move faster for a more teasing sensation
            """
        case .roboStroke: return """
            **>0:** Increase acceleration until motion becomes constant speed
            **=0:** Equal to Simple Stroke
            **<0:** Reduce acceleration into a triangle profile
            """
        case .halfNHalf: return """
            **>0:** Makes the in-move faster for a hard poinding senation
            **<0:** Makes the out-move faster for a more teasing sensation
            """
        case .deeper: return """
            Value controls how many strokes complete one ramp cycle
            """
        case .stopNGo: return """
            Value controls the pause duration between stroke series
            """
        case .insist: return """
            **>0:** Strokes wander towards the front
            **<0:** Strokes wander towards the back
            """
        }
    }

}

/// Represents a pattern available on the OSSM device
struct OSSMPattern: Identifiable {
    let idx: Int
    let name: String
    var description: String?
    var id: Int { idx }
}

/// Represents the current state of the OSSM device
/// Note: Firmware sends "state" not "status" in JSON
struct OSSMState: Equatable {
    var state: OSSMStatus  // Called "state" in firmware JSON
    var speed: Int
    var stroke: Int
    var depth: Int
    var sensation: Int
    var pattern: Int

    init(state: String = "idle", speed: Int = 0, stroke: Int = 0, depth: Int = 0, sensation: Int = 0, pattern: Int = 0) {
        self.state = .init(rawValue: state) ?? .error
        self.speed = speed
        self.stroke = stroke
        self.depth = depth
        self.sensation = sensation
        self.pattern = pattern
    }

    /// Parse from JSON data received from firmware
    static func fromJSON(_ data: Data) -> OSSMState? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        return OSSMState(
            state: json["state"] as? String ?? "idle",
            speed: json["speed"] as? Int ?? 0,
            stroke: json["stroke"] as? Int ?? 0,
            depth: json["depth"] as? Int ?? 0,
            sensation: json["sensation"] as? Int ?? 0,
            pattern: json["pattern"] as? Int ?? 0
        )
    }
}

/// Data structure for running stroke engine patterns
struct OSSMPlayData {
    var speed: Int
    var stroke: Int
    var depth: Int
    var sensation: Int
    var pattern: Int
}

// MARK: - OSSM BLE Constants (from firmware)

enum OSSMConstants {
    static let deviceName = "OSSM"

    // Primary Service UUID
    static let primaryServiceUUID = CBUUID(string: "522b443a-4f53-534d-0001-420badbabe69")

    // Characteristic UUIDs (from firmware nimble.cpp)
    static let commandCharacteristicUUID = CBUUID(string: "522b443a-4f53-534d-1000-420badbabe69")
    static let speedKnobConfigCharacteristicUUID = CBUUID(string: "522b443a-4f53-534d-1010-420badbabe69")
    static let currentStateCharacteristicUUID = CBUUID(string: "522b443a-4f53-534d-2000-420badbabe69")
    static let patternListCharacteristicUUID = CBUUID(string: "522b443a-4f53-534d-3000-420badbabe69")
    static let patternDescriptionCharacteristicUUID = CBUUID(string: "522b443a-4f53-534d-3010-420badbabe69")

    // Firmware command regex pattern (for reference):
    // go:(simplePenetration|strokeEngine|menu)|set:(speed|stroke|depth|sensation|pattern):\d+
}

// MARK: - OSSM BLE Manager

/// Main BLE Manager class for OSSM device control
/// Based on KinkyMakers/OSSM-hardware firmware implementation
class OSSMBLEManager: NSObject, ObservableObject {

    // MARK: - Published Properties

    @Published var connectionStatus: OSSMConnectionStatus = .disconnected
    // REMOVED @Published var currentState to prevent massive re-renders
    // @Published var currentState: OSSMState = OSSMState() 
    
    // Derived status for the main view to switch pages
    @Published var currentRootState: OSSMStatus = .idle 
    
    @Published var patterns: [OSSMPattern] = []
    @Published var isReady: Bool = false
    @Published var lastError: String?
    @Published var discoveredPeripherals: [CBPeripheral] = []
    @Published var speedKnobAsLimit: Bool = true 
    
    // High-frequency data container (Not @Published in the manager itself)
    let runtimeData = OSSMRuntimeData()

    // MARK: - Computed Properties

    var currentPage: OSSMPage? {
        try? OSSMPage(currentRootState)
    }
    var homing: Bool {
        let homingStates: [OSSMStatus] = [.homing, .homingForward, .homingBackward]
        return homingStates.contains(currentRootState)
    }


    // MARK: - Private Properties

    private var centralManager: CBCentralManager!
    private var ossmPeripheral: CBPeripheral?
    private var autoReconnect: Bool = true

    // Characteristics
    private var commandCharacteristic: CBCharacteristic?
    private var speedKnobConfigCharacteristic: CBCharacteristic?
    private var currentStateCharacteristic: CBCharacteristic?
    private var patternListCharacteristic: CBCharacteristic?
    private var patternDescriptionCharacteristic: CBCharacteristic?

    // Command response handling
    private var pendingCommandCompletion: ((Result<Void, Error>) -> Void)?
    private var pendingReadCompletion: ((Result<Data, Error>) -> Void)?

    // MARK: - Initialization

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: DispatchQueue.main)
    }

    // MARK: - Public Methods

    /// Start scanning for OSSM devices
    func startScanning() {
        guard centralManager.state == .poweredOn else {
            lastError = "Bluetooth is not powered on"
            return
        }

        connectionStatus = .scanning
        discoveredPeripherals.removeAll()

        // Scan for devices with our service UUID or by name
        centralManager.scanForPeripherals(
            withServices: [OSSMConstants.primaryServiceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )

        // Also do a general scan to find by name
        centralManager.scanForPeripherals(withServices: nil, options: nil)
    }

    /// Stop scanning
    func stopScanning() {
        centralManager.stopScan()
        if connectionStatus == .scanning {
            connectionStatus = .disconnected
        }
    }

    /// Connect to a specific peripheral
    func connect(to peripheral: CBPeripheral) {
        stopScanning()
        connectionStatus = .connecting
        ossmPeripheral = peripheral
        ossmPeripheral?.delegate = self
        centralManager.connect(peripheral, options: nil)
    }

    /// Disconnect from the current device
    func disconnect() {
        autoReconnect = false

        // Try to stop the device safely before disconnecting
        if isReady {
            sendCommandFireAndForget("set:speed:0")
        }

        if let peripheral = ossmPeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }

        resetState()
    }

    // MARK: - Command Methods

    /// Emergency stop - immediately stops the OSSM device
    func emergencyStop() {
        sendCommandFireAndForget("set:speed:0")
    }

    /// Set speed (0-100)
    /// IMPORTANT: If speedKnobAsLimit is true (default), this is a percentage of the physical knob position
    /// Set speedKnobAsLimit to false for direct BLE speed control
    func setSpeed(_ speed: Int, completion: ((Result<Void, Error>) -> Void)? = nil) {
        guard speed >= 0 && speed <= 100 else {
            completion?(.failure(OSSMError.invalidParameter("Speed must be between 0 and 100")))
            return
        }
        // Firmware expects raw value, no adjustment needed
        sendCommand("set:speed:\(speed)", completion: completion)
    }

    /// Set stroke length (0-100)
    func setStroke(_ stroke: Int, completion: ((Result<Void, Error>) -> Void)? = nil) {
        guard stroke >= 0 && stroke <= 100 else {
            completion?(.failure(OSSMError.invalidParameter("Stroke must be between 0 and 100")))
            return
        }
        // Firmware expects raw value, no adjustment needed
        sendCommand("set:stroke:\(stroke)", completion: completion)
    }

    /// Set depth (0-100)
    func setDepth(_ depth: Int, completion: ((Result<Void, Error>) -> Void)? = nil) {
        guard depth >= 0 && depth <= 100 else {
            completion?(.failure(OSSMError.invalidParameter("Depth must be between 0 and 100")))
            return
        }
        // Firmware expects raw value, no adjustment needed
        sendCommand("set:depth:\(depth)", completion: completion)
    }

    /// Set sensation (0-100)
    func setSensation(_ sensation: Int, completion: ((Result<Void, Error>) -> Void)? = nil) {
        guard sensation >= 0 && sensation <= 100 else {
            completion?(.failure(OSSMError.invalidParameter("Sensation must be between 0 and 100")))
            return
        }
        // Firmware expects raw value, no adjustment needed
        sendCommand("set:sensation:\(sensation)", completion: completion)
    }

    /// Set pattern by ID (0-6, will be modulo 7 in firmware)
    func setPattern(_ patternId: Int, completion: ((Result<Void, Error>) -> Void)? = nil) {
        guard patternId >= 0 else {
            completion?(.failure(OSSMError.invalidParameter("Pattern ID must be non-negative")))
            return
        }
        sendCommand("set:pattern:\(patternId)", completion: completion)
    }

    /// Navigate to a specific page
    /// Valid values: menu, simplePenetration, strokeEngine
    func navigateTo(_ page: OSSMPage, completion: ((Result<Void, Error>) -> Void)? = nil) {
        sendCommand("go:\(page.rawValue)", completion: completion)
    }

    /// Configure speed knob behavior
    /// - Parameter knobAsLimit: When true (default), BLE speed is percentage of physical knob.
    ///                          When false, BLE speed commands control speed directly.
    /// IMPORTANT: You likely need to set this to false for BLE speed control to work independently!
    func setSpeedKnobConfig(knobAsLimit: Bool, completion: ((Result<Void, Error>) -> Void)? = nil) {
        guard let characteristic = speedKnobConfigCharacteristic else {
            completion?(.failure(OSSMError.notReady))
            return
        }

        // Firmware accepts: "true", "1", "t" for true; "false", "0", "f" for false
        let value = knobAsLimit ? "true" : "false"
        guard let data = value.data(using: .utf8) else {
            completion?(.failure(OSSMError.invalidParameter("Failed to encode config value")))
            return
        }

        ossmPeripheral?.writeValue(data, for: characteristic, type: .withResponse)

        // Update local state
        DispatchQueue.main.async {
            self.speedKnobAsLimit = knobAsLimit
        }

        completion?(.success(()))
    }

    // MARK: - Private Command Methods

    /// Send a command and don't wait for response (fire and forget)
    private func sendCommandFireAndForget(_ command: String) {
        guard let characteristic = commandCharacteristic,
              let data = command.data(using: .utf8) else {
            return
        }

        ossmPeripheral?.writeValue(data, for: characteristic, type: .withResponse)
    }

    /// Send a command with completion handler
    private func sendCommand(_ command: String, completion: ((Result<Void, Error>) -> Void)?) {
        guard isReady else {
            completion?(.failure(OSSMError.notReady))
            return
        }

        guard let characteristic = commandCharacteristic,
              let data = command.data(using: .utf8) else {
            completion?(.failure(OSSMError.characteristicNotFound))
            return
        }

        pendingCommandCompletion = completion
        ossmPeripheral?.writeValue(data, for: characteristic, type: .withResponse)
    }

    private func resetState() {
        connectionStatus = .disconnected
        isReady = false
        ossmPeripheral = nil
        commandCharacteristic = nil
        speedKnobConfigCharacteristic = nil
        currentStateCharacteristic = nil
        patternListCharacteristic = nil
        patternDescriptionCharacteristic = nil
        patterns.removeAll()
        patterns.removeAll()
        runtimeData.currentState = OSSMState()
        currentRootState = .idle
        speedKnobAsLimit = true
    }
}

// MARK: - CBCentralManagerDelegate

extension OSSMBLEManager: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("[OSSM] Bluetooth is powered on")
            startScanning()
        case .poweredOff:
            stopScanning()
            lastError = "Bluetooth is powered off"
            resetState()
        case .unauthorized:
            stopScanning()
            lastError = "Bluetooth access is unauthorized"
        case .unsupported:
            stopScanning()
            lastError = "Bluetooth is not supported on this device"
        default:
            stopScanning()
            break
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        // Check if this is an OSSM device by name
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? ""

        if name == OSSMConstants.deviceName {
            if !discoveredPeripherals.contains(where: { $0.identifier == peripheral.identifier }) {
                print("[OSSM] Discovered OSSM device: \(peripheral.identifier)")
                discoveredPeripherals.append(peripheral)
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("[OSSM] Connected to device")
        connectionStatus = .connected
        peripheral.discoverServices([OSSMConstants.primaryServiceUUID])
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("[OSSM] Disconnected from device")
        isReady = false
        connectionStatus = .disconnected

        if autoReconnect {
            // Attempt to reconnect after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.connectionStatus = .connecting
                self.centralManager.connect(peripheral, options: nil)
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        lastError = error?.localizedDescription ?? "Failed to connect"
        connectionStatus = .disconnected
    }
}

// MARK: - CBPeripheralDelegate

extension OSSMBLEManager: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else {
            lastError = error?.localizedDescription
            return
        }

        guard let services = peripheral.services else { return }

        for service in services {
            if service.uuid == OSSMConstants.primaryServiceUUID {
                print("[OSSM] Found primary service")
                peripheral.discoverCharacteristics([
                    OSSMConstants.commandCharacteristicUUID,
                    OSSMConstants.speedKnobConfigCharacteristicUUID,
                    OSSMConstants.currentStateCharacteristicUUID,
                    OSSMConstants.patternListCharacteristicUUID,
                    OSSMConstants.patternDescriptionCharacteristicUUID
                ], for: service)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil else {
            lastError = error?.localizedDescription
            return
        }

        guard let characteristics = service.characteristics else { return }

        for characteristic in characteristics {
            switch characteristic.uuid {
            case OSSMConstants.commandCharacteristicUUID:
                print("[OSSM] Found command characteristic")
                commandCharacteristic = characteristic

            case OSSMConstants.speedKnobConfigCharacteristicUUID:
                print("[OSSM] Found speed knob config characteristic")
                speedKnobConfigCharacteristic = characteristic
                // Read current config
                peripheral.readValue(for: characteristic)

            case OSSMConstants.currentStateCharacteristicUUID:
                print("[OSSM] Found state characteristic")
                currentStateCharacteristic = characteristic
                // Subscribe to state notifications
                peripheral.setNotifyValue(true, for: characteristic)

            case OSSMConstants.patternListCharacteristicUUID:
                print("[OSSM] Found pattern list characteristic")
                patternListCharacteristic = characteristic

            case OSSMConstants.patternDescriptionCharacteristicUUID:
                print("[OSSM] Found pattern description characteristic")
                patternDescriptionCharacteristic = characteristic

            default:
                break
            }
        }

        // Check if we have all required characteristics
        if commandCharacteristic != nil && currentStateCharacteristic != nil {
            print("[OSSM] Device is ready")
            isReady = true
            connectionStatus = .ready

            // IMPORTANT: Set speed knob config to false for independent BLE speed control
            // Uncomment the next line if you want BLE to control speed directly
            setSpeedKnobConfig(knobAsLimit: false)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let data = characteristic.value else {
            print("[OSSM] Error reading characteristic: \(error?.localizedDescription ?? "unknown")")
            pendingReadCompletion?(.failure(error ?? OSSMError.invalidResponse))
            pendingReadCompletion = nil
            return
        }

        switch characteristic.uuid {
        case OSSMConstants.currentStateCharacteristicUUID:
            // Parse state JSON from firmware
            if let state = OSSMState.fromJSON(data) {
                DispatchQueue.main.async {
                    // 1. Update the high-frequency data container
                    self.runtimeData.update(with: state)
                    
                    // 2. Only update the main published property if the high-level state changed
                    // This prevents the root view from re-rendering on every speed change
                    if self.currentRootState != state.state {
                        self.currentRootState = state.state
                    }
                }
                print("[OSSM] State update: \(state.state.rawValue)")
            } else if let jsonString = String(data: data, encoding: .utf8) {
                print("[OSSM] Failed to parse state JSON: \(jsonString)")
            }

        case OSSMConstants.speedKnobConfigCharacteristicUUID:
            if let value = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    self.speedKnobAsLimit = (value == "true")
                }
                print("[OSSM] Speed knob config: \(value)")
            }

        case OSSMConstants.commandCharacteristicUUID:
            // Command response
            if let response = String(data: data, encoding: .utf8) {
                print("[OSSM] Command response: \(response)")
                if response.hasPrefix("fail:") {
                    pendingCommandCompletion?(.failure(OSSMError.commandFailed(response)))
                } else {
                    pendingCommandCompletion?(.success(()))
                }
                pendingCommandCompletion = nil
            }

        case OSSMConstants.patternListCharacteristicUUID:
            // Pattern list JSON
            pendingReadCompletion?(.success(data))
            pendingReadCompletion = nil

        default:
            pendingReadCompletion?(.success(data))
            pendingReadCompletion = nil
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("[OSSM] Write error: \(error.localizedDescription)")
            pendingCommandCompletion?(.failure(error))
            pendingCommandCompletion = nil
        } else {
            print("[OSSM] Write successful for \(characteristic.uuid)")
            // For command characteristic, read back to get response
            if characteristic.uuid == OSSMConstants.commandCharacteristicUUID {
                // Firmware validates and sets response, we can read it
                // But the didUpdateValueFor will be called via notification
            } else {
                // For other characteristics, consider success
                pendingCommandCompletion?(.success(()))
                pendingCommandCompletion = nil
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("[OSSM] Notification state error: \(error.localizedDescription)")
        } else {
            print("[OSSM] Notifications enabled for \(characteristic.uuid)")
        }
    }
}

// MARK: - OSSM Errors

enum OSSMError: LocalizedError {
    case notReady
    case characteristicNotFound
    case invalidParameter(String)
    case commandFailed(String)
    case unexpectedResponse(String)
    case invalidResponse
    case timeout

    var errorDescription: String? {
        switch self {
        case .notReady:
            return "OSSM device is not ready"
        case .characteristicNotFound:
            return "Required characteristic not found"
        case .invalidParameter(let message):
            return "Invalid parameter: \(message)"
        case .commandFailed(let command):
            return "Command failed: \(command)"
        case .unexpectedResponse(let response):
            return "Unexpected response: \(response)"
        case .invalidResponse:
            return "Invalid response from device"
        case .timeout:
            return "Operation timed out"
        }
    }
}

/// Container for high-frequency updates that doesn't trigger the main BLEManager to publish changes
class OSSMRuntimeData: ObservableObject {
    @Published var currentState: OSSMState = OSSMState()
    
    func update(with newState: OSSMState) {
        // Only publish if something actually changed to be safe, 
        // though SwiftUI handles this well usually.
        if currentState != newState {
            currentState = newState
        }
    }
}

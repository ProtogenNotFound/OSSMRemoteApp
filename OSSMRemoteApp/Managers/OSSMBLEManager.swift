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
    @Published var isDebugMode: Bool = false
    @Published var lastError: String?
    @Published var discoveredPeripherals: [CBPeripheral] = []
    @Published var speedKnobAsLimit: Bool = true
    @Published var homingEstimatedEndTime: Date?

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
    private var pendingReadTimeoutTask: Task<Void, Never>?

    // Async command/response handling
    private var pendingCommandResponseContinuation: CheckedContinuation<String, Error>?
    private var pendingCommandResponseTimeoutTask: Task<Void, Never>?

    private var patternFetchTask: Task<Void, Never>?

    // Homing timing tracking
    private var homingForwardStartTime: Date?
    private var homingBackwardStartTime: Date?

    // MARK: - Initialization

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: DispatchQueue.main)
    }

    // MARK: - Public Methods

    /// Start scanning for OSSM devices
    func startScanning() {
        if isDebugMode {
            connectionStatus = .ready
            isReady = true
            applyDebugState(.menuIdle)
            refreshPatterns()
            return
        }
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
        if isDebugMode {
            return
        }
        stopScanning()
        connectionStatus = .connecting
        ossmPeripheral = peripheral
        ossmPeripheral?.delegate = self
        centralManager.connect(peripheral, options: nil)
    }

    /// Disconnect from the current device
    func disconnect() {
        if isDebugMode {
            applyDebugState(.menuIdle)
            connectionStatus = .ready
            isReady = true
            return
        }
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

    func refreshPatterns() {
        patternFetchTask?.cancel()

        if isDebugMode {
            patterns = buildFallbackPatterns()
            return
        }

        guard isReady else { return }

        patternFetchTask = Task { @MainActor in
            do {
                let patterns = try await fetchPatternsFromDevice()
                self.patterns = patterns
            } catch {
                print("[OSSM] Failed to fetch patterns: \(error)")
                self.patterns = self.buildFallbackPatterns()
            }
        }
    }

    // MARK: - Command Methods

    /// Emergency stop - immediately stops the OSSM device
    func emergencyStop() {
        sendCommandFireAndForget("set:speed:0")
    }

    func pullOut() {
        Task {
            // Speed 5, Stroke 5, Depth 0
            setSpeed(5)
            setStroke(5)
            try! await Task.sleep(for: .seconds(2))
            setDepth(0)
        }
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

    /// Go to positon (0-100%) in time (ms), only works in stream mode
    func streamGoTo(position: Int, time: Int, completion: ((Result<Void, Error>) -> Void)? = nil) {
        guard self.currentPage == .streaming else {
            completion?(.failure(OSSMError.notReady))
            return
        }
        guard position >= 0 && position <= 100 else {
            completion?(.failure(OSSMError.invalidParameter("Position must be between 0 and 100")))
            return
        }
        guard time >= 0 else {
            completion?(.failure(OSSMError.invalidParameter("Time must be non-negative")))
            return
        }
        sendCommandFireAndForget("stream:\(position):\(time)")
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
        if isDebugMode {
            DispatchQueue.main.async {
                self.speedKnobAsLimit = knobAsLimit
            }
            completion?(.success(()))
            return
        }
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

    /// Send a command and await the firmware response string.
    /// - Parameters:
    ///   - command: Firmware command string (e.g. "set:speed:50").
    ///   - timeout: Maximum time to wait for a response.
    /// - Returns: The raw response string received from the device.
    func sendCommandAndAwaitResponse(_ command: String, timeout: TimeInterval = 2.0) async throws -> String {
        if isDebugMode {
            handleDebugCommand(command, completion: nil)
            return "ok"
        }
        guard isReady else { throw OSSMError.notReady }
        guard let characteristic = commandCharacteristic else { throw OSSMError.characteristicNotFound }
        guard let data = command.data(using: .utf8) else {
            throw OSSMError.invalidParameter("Failed to encode command")
        }

        // Only one outstanding awaited command at a time.
        if pendingCommandResponseContinuation != nil {
            throw OSSMError.unexpectedResponse("Another command is already awaiting a response")
        }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            self.pendingCommandResponseContinuation = continuation

            // Timeout task
            self.pendingCommandResponseTimeoutTask?.cancel()
            self.pendingCommandResponseTimeoutTask = Task { [weak self] in
                guard let self else { return }
                do {
                    try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                } catch {
                    // Task cancelled
                    return
                }

                // If still pending, fail with timeout
                if let cont = self.pendingCommandResponseContinuation {
                    self.pendingCommandResponseContinuation = nil
                    cont.resume(throwing: OSSMError.timeout)
                }
            }

            // Write the command (transport-level ack handled in didWriteValueFor)
            self.ossmPeripheral?.writeValue(data, for: characteristic, type: .withResponse)
        }
    }

    /// Send a command with completion handler
    private func sendCommand(_ command: String, completion: ((Result<Void, Error>) -> Void)?) {
        if isDebugMode {
            handleDebugCommand(command, completion: completion)
            return
        }
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

    @MainActor
    private func readValue(for characteristic: CBCharacteristic, timeout: TimeInterval = 2.0) async throws -> Data {
        guard ossmPeripheral != nil else {
            throw OSSMError.notReady
        }
        if pendingReadCompletion != nil {
            throw OSSMError.unexpectedResponse("Another read is already pending")
        }
        return try await withCheckedThrowingContinuation { continuation in
            pendingReadCompletion = { result in
                self.pendingReadTimeoutTask?.cancel()
                self.pendingReadTimeoutTask = nil
                switch result {
                case .success(let data):
                    continuation.resume(returning: data)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }

            pendingReadTimeoutTask?.cancel()
            pendingReadTimeoutTask = Task { [weak self] in
                guard let self else { return }
                do {
                    try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                } catch {
                    return
                }
                if let completion = self.pendingReadCompletion {
                    self.pendingReadCompletion = nil
                    completion(.failure(OSSMError.timeout))
                }
            }

            self.ossmPeripheral?.readValue(for: characteristic)
        }
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
        homingForwardStartTime = nil
        homingBackwardStartTime = nil
        pendingCommandResponseTimeoutTask?.cancel()
        pendingCommandResponseTimeoutTask = nil
        pendingCommandResponseContinuation = nil
        pendingReadTimeoutTask?.cancel()
        pendingReadTimeoutTask = nil
        patternFetchTask?.cancel()
        patternFetchTask = nil
    }
}

// MARK: - CBCentralManagerDelegate

extension OSSMBLEManager: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if isDebugMode {
            return
        }
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
                // Subscribe to command responses (firmware writes response back to this characteristic)
                peripheral.setNotifyValue(true, for: characteristic)

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

            refreshPatterns()
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let data = characteristic.value else {
            print("[OSSM] Error reading characteristic: \(error?.localizedDescription ?? "unknown")")
            pendingReadCompletion?(.failure(error ?? OSSMError.invalidResponse))
            pendingReadCompletion = nil
            pendingReadTimeoutTask?.cancel()
            pendingReadTimeoutTask = nil
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
                        self.handleStateTransition(from: self.currentRootState, to: state.state)
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

                // Resume async waiter (raw response returned)
                if let cont = pendingCommandResponseContinuation {
                    pendingCommandResponseTimeoutTask?.cancel()
                    pendingCommandResponseTimeoutTask = nil
                    pendingCommandResponseContinuation = nil
                    cont.resume(returning: response)
                }

                // Also satisfy legacy completion handler
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
            pendingReadTimeoutTask?.cancel()
            pendingReadTimeoutTask = nil

        default:
            pendingReadCompletion?(.success(data))
            pendingReadCompletion = nil
            pendingReadTimeoutTask?.cancel()
            pendingReadTimeoutTask = nil
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("[OSSM] Write error: \(error.localizedDescription)")
            pendingCommandCompletion?(.failure(error))
            pendingCommandCompletion = nil
            if let cont = pendingCommandResponseContinuation {
                pendingCommandResponseTimeoutTask?.cancel()
                pendingCommandResponseTimeoutTask = nil
                pendingCommandResponseContinuation = nil
                cont.resume(throwing: error)
            }
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

// MARK: - State Transition Logic
extension OSSMBLEManager {
    private func handleStateTransition(from oldState: OSSMStatus, to newState: OSSMStatus) {
        // Homing Forward Logic
        if newState == .homingForward {
            // Started homing forward
            homingForwardStartTime = Date()
            let storedDuration = UserDefaults.standard.double(forKey: "homingForwardTime")
            // If storedDuration is 0 (not set), default to 5.0 for estimation
            let duration = storedDuration > 0 ? storedDuration : 5.0
            homingEstimatedEndTime = Date().addingTimeInterval(duration)
            print("[OSSM] Homing Forward started at \(homingForwardStartTime!). Estimated end: \(homingEstimatedEndTime!)")
        } else if oldState == .homingForward {
            // Finished homing forward
            if let startTime = homingForwardStartTime {
                let duration = Date().timeIntervalSince(startTime)
                let storedDuration = UserDefaults.standard.double(forKey: "homingForwardTime")
                let newMaxDuration = max(storedDuration, duration)

                print("[OSSM] Homing Forward finished. Duration: \(duration)s. New Max: \(newMaxDuration)s")
                UserDefaults.standard.set(newMaxDuration, forKey: "homingForwardTime")

                homingForwardStartTime = nil
                homingEstimatedEndTime = nil
            }
        }

        // Homing Backward Logic
        if newState == .homingBackward {
            // Started homing backward
            homingBackwardStartTime = Date()
            let storedDuration = UserDefaults.standard.double(forKey: "homingBackwardTime")
            // If storedDuration is 0 (not set), default to 5.0 for estimation
            let duration = storedDuration > 0 ? storedDuration : 5.0
            homingEstimatedEndTime = Date().addingTimeInterval(duration)
            print("[OSSM] Homing Backward started at \(homingBackwardStartTime!). Estimated end: \(homingEstimatedEndTime!)")
        } else if oldState == .homingBackward {
            // Finished homing backward
            if let startTime = homingBackwardStartTime {
                let duration = Date().timeIntervalSince(startTime)
                let storedDuration = UserDefaults.standard.double(forKey: "homingBackwardTime")
                let newMaxDuration = max(storedDuration, duration)

                print("[OSSM] Homing Backward finished. Duration: \(duration)s. New Max: \(newMaxDuration)s")
                UserDefaults.standard.set(newMaxDuration, forKey: "homingBackwardTime")

                homingBackwardStartTime = nil
                homingEstimatedEndTime = nil
            }
        }
    }
}

// MARK: - Pattern Fetching

extension OSSMBLEManager {
    private func buildFallbackPatterns() -> [OSSMPattern] {
        KnownPattern.allCases.map { pattern in
            OSSMPattern(
                idx: pattern.rawValue,
                name: pattern.name,
                description: pattern.description,
                sensationDescription: pattern.sensationDescription
            )
        }
    }

    @MainActor
    private func fetchPatternsFromDevice() async throws -> [OSSMPattern] {
        guard let listCharacteristic = patternListCharacteristic else {
            throw OSSMError.characteristicNotFound
        }
        guard let _ = ossmPeripheral else {
            throw OSSMError.notReady
        }

        let listData = try await readValue(for: listCharacteristic)
        var patterns = parsePatternList(listData)

        if patterns.isEmpty {
            return buildFallbackPatterns()
        }

        let descriptions = try await fetchPatternDescriptions(for: patterns)
        let fallbackMap = Dictionary(uniqueKeysWithValues: buildFallbackPatterns().map { ($0.idx, $0) })

        patterns = patterns.map { pattern in
            let fallback = fallbackMap[pattern.idx]
            let deviceDescription = descriptions[pattern.idx]
            let name = pattern.name.isEmpty ? (fallback?.name ?? "Pattern \(pattern.idx)") : pattern.name
            let description = fallback?.description ?? deviceDescription
            let sensationDescription = fallback?.sensationDescription ?? deviceDescription.map { LocalizedStringKey($0) }
            return OSSMPattern(
                idx: pattern.idx,
                name: name,
                description: description,
                sensationDescription: sensationDescription
            )
        }

        return patterns
    }

    @MainActor
    private func fetchPatternDescriptions(for patterns: [OSSMPattern]) async throws -> [Int: String] {
        guard let descriptionCharacteristic = patternDescriptionCharacteristic else {
            throw OSSMError.characteristicNotFound
        }
        guard let peripheral = ossmPeripheral else {
            throw OSSMError.notReady
        }

        var descriptions: [Int: String] = [:]
        for pattern in patterns {
            if Task.isCancelled { break }
            let payload = "\(pattern.idx)"
            guard let data = payload.data(using: .utf8) else { continue }
            peripheral.writeValue(data, for: descriptionCharacteristic, type: .withResponse)
            let response = try await readValue(for: descriptionCharacteristic)
            if let description = String(data: response, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !description.isEmpty {
                descriptions[pattern.idx] = description
            }
        }

        return descriptions
    }

    private func parsePatternList(_ data: Data) -> [OSSMPattern] {
        if let json = try? JSONSerialization.jsonObject(with: data) {
            if let dict = json as? [String: Any], let patterns = dict["patterns"] {
                return parsePatternListObject(patterns)
            }
            if let array = json as? [[String: Any]] {
                return parsePatternListArray(array)
            }
            if let array = json as? [String] {
                return parsePatternListNames(array)
            }
            if let map = json as? [String: String] {
                let pairs = map.compactMap { key, value -> OSSMPattern? in
                    guard let idx = Int(key) else { return nil }
                    return OSSMPattern(idx: idx, name: value, description: nil, sensationDescription: nil)
                }
                return pairs.sorted { $0.idx < $1.idx }
            }
        }

        if let string = String(data: data, encoding: .utf8) {
            let names = string
                .split { $0 == "\n" || $0 == "," }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return parsePatternListNames(names)
        }

        return []
    }

    private func parsePatternListObject(_ object: Any) -> [OSSMPattern] {
        if let array = object as? [[String: Any]] {
            return parsePatternListArray(array)
        }
        if let array = object as? [String] {
            return parsePatternListNames(array)
        }
        return []
    }

    private func parsePatternListArray(_ array: [[String: Any]]) -> [OSSMPattern] {
        var results: [OSSMPattern] = []
        for (index, item) in array.enumerated() {
            let idx = item["idx"] as? Int ?? item["id"] as? Int ?? index
            let name = item["name"] as? String ?? ""
            results.append(OSSMPattern(idx: idx, name: name, description: nil, sensationDescription: nil))
        }
        return results.sorted { $0.idx < $1.idx }
    }

    private func parsePatternListNames(_ names: [String]) -> [OSSMPattern] {
        names.enumerated().map { index, name in
            OSSMPattern(idx: index, name: name, description: nil, sensationDescription: nil)
        }
    }
}

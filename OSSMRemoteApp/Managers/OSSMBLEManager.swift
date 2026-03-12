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
    private var wifiCharacteristic: CBCharacteristic?
    private var currentStateCharacteristic: CBCharacteristic?
    private var patternListCharacteristic: CBCharacteristic?
    private var patternDescriptionCharacteristic: CBCharacteristic?
    private var gpioCharacteristic: CBCharacteristic?

    // Command response handling
    private enum PendingCommandDelivery {
        case completion(((Result<Void, Error>) -> Void)?)
        case rawResponse(CheckedContinuation<String, Error>)
    }

    private struct PendingCommand {
        let eventID: UUID
        let command: String
        let delivery: PendingCommandDelivery
        let timeout: TimeInterval
    }

    private enum CommandTransportResult: CustomStringConvertible {
        case pending
        case success
        case failure(String)

        var description: String {
            switch self {
            case .pending:
                return "pending"
            case .success:
                return "success"
            case .failure(let reason):
                return "failure(\(reason))"
            }
        }
    }

    private enum CommandOutcome: String {
        case pending
        case succeeded
        case firmwareFailed
        case malformedResponse
        case timedOut
        case transportFailed
        case unmatchedResponse
    }

    private struct CommandEvent {
        let command: String
        let sentAt: Date
        var transportResult: CommandTransportResult
        var firmwareResponse: String?
        var outcome: CommandOutcome
    }

    // Generic characteristic read tracking
    private var pendingReadCompletion: ((Result<Data, Error>) -> Void)?
    private var pendingReadTimeoutTask: Task<Void, Never>?

    // Serialized command pipeline
    private var pendingCommands: [PendingCommand] = []
    private var activeCommand: PendingCommand?
    private var commandEvents: [UUID: CommandEvent] = [:]
    private var activeCommandTimeoutTask: Task<Void, Never>?
    private let defaultCommandResponseTimeout: TimeInterval = 2.0

    private var patternFetchTask: Task<Void, Never>?
    private var initialSetupTask: Task<Void, Never>?

    // Homing timing tracking
    private var homingForwardStartTime: Date?
    private var homingBackwardStartTime: Date?
    private let speedKnobPreferenceKey = "speedKnobAsLimitPreference"

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
        autoReconnect = true
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

    /// Persist and apply preferred speed knob behavior.
    /// The default if no preference is stored is independent BLE control (false).
    func setSpeedKnobPreference(_ knobAsLimit: Bool, persist: Bool = true) {
        if persist {
            UserDefaults.standard.set(knobAsLimit, forKey: speedKnobPreferenceKey)
        }
        setSpeedKnobConfig(knobAsLimit: knobAsLimit, completion: nil)
    }

    /// Load the user's persisted speed knob preference.
    /// Defaults to false to preserve current behavior for knobless setups.
    func loadSpeedKnobPreference() -> Bool {
        if UserDefaults.standard.object(forKey: speedKnobPreferenceKey) == nil {
            return false
        }
        return UserDefaults.standard.bool(forKey: speedKnobPreferenceKey)
    }

    func readWiFiValue() async throws -> Data {
        guard let wifiCharacteristic else {
            throw OSSMError.characteristicNotFound
        }
        return try await readValue(for: wifiCharacteristic)
    }

    func writeWiFiValue(_ data: Data) throws {
        guard let peripheral = ossmPeripheral else {
            throw OSSMError.notReady
        }
        guard let wifiCharacteristic else {
            throw OSSMError.characteristicNotFound
        }
        peripheral.writeValue(data, for: wifiCharacteristic, type: .withResponse)
    }

    func readGPIOValue() async throws -> Data {
        guard let gpioCharacteristic else {
            throw OSSMError.characteristicNotFound
        }
        return try await readValue(for: gpioCharacteristic)
    }

    func writeGPIOValue(_ data: Data) throws {
        guard let peripheral = ossmPeripheral else {
            throw OSSMError.notReady
        }
        guard let gpioCharacteristic else {
            throw OSSMError.characteristicNotFound
        }
        peripheral.writeValue(data, for: gpioCharacteristic, type: .withResponse)
    }

    // MARK: - Private Command Methods

    /// Send a command and don't wait for response (fire and forget)
    private func sendCommandFireAndForget(_ command: String) {
        enqueueCommand(command, delivery: .completion(nil), timeout: defaultCommandResponseTimeout)
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
        guard commandCharacteristic != nil else { throw OSSMError.characteristicNotFound }
        guard command.data(using: .utf8) != nil else {
            throw OSSMError.invalidParameter("Failed to encode command")
        }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            self.enqueueCommand(command, delivery: .rawResponse(continuation), timeout: timeout)
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
        guard commandCharacteristic != nil else {
            completion?(.failure(OSSMError.characteristicNotFound))
            return
        }
        enqueueCommand(command, delivery: .completion(completion), timeout: defaultCommandResponseTimeout)
    }

    private func enqueueCommand(
        _ command: String,
        delivery: PendingCommandDelivery,
        timeout: TimeInterval
    ) {
        guard commandCharacteristic != nil else {
            switch delivery {
            case .completion(let completion):
                completion?(.failure(OSSMError.characteristicNotFound))
            case .rawResponse(let continuation):
                continuation.resume(throwing: OSSMError.characteristicNotFound)
            }
            return
        }
        guard command.data(using: .utf8) != nil else {
            switch delivery {
            case .completion(let completion):
                completion?(.failure(OSSMError.invalidParameter("Failed to encode command")))
            case .rawResponse(let continuation):
                continuation.resume(throwing: OSSMError.invalidParameter("Failed to encode command"))
            }
            return
        }

        pendingCommands.append(
            PendingCommand(
                eventID: registerCommandEvent(command),
                command: command,
                delivery: delivery,
                timeout: timeout
            )
        )
        processNextQueuedCommandIfPossible()
    }

    @discardableResult
    private func registerCommandEvent(_ command: String) -> UUID {
        let id = UUID()
        commandEvents[id] = CommandEvent(
            command: command,
            sentAt: Date(),
            transportResult: .pending,
            firmwareResponse: nil,
            outcome: .pending
        )
        return id
    }

    private func recordTransportResult(eventID: UUID, result: CommandTransportResult) {
        guard var event = commandEvents[eventID] else { return }
        event.transportResult = result
        if case .failure = result {
            event.outcome = .transportFailed
        }
        commandEvents[eventID] = event
        pruneResolvedCommandEventsIfNeeded()
    }

    private func recordCommandResponse(eventID: UUID, response: String?, outcome: CommandOutcome) {
        guard var event = commandEvents[eventID] else { return }
        event.firmwareResponse = response
        event.outcome = outcome
        commandEvents[eventID] = event
        pruneResolvedCommandEventsIfNeeded()
    }

    private func pruneResolvedCommandEventsIfNeeded(maxResolvedEvents: Int = 500) {
        let resolved = commandEvents.filter { $0.value.outcome != .pending }
        guard resolved.count > maxResolvedEvents else { return }
        let overflow = resolved.count - maxResolvedEvents
        let idsToDrop = resolved
            .sorted { $0.value.sentAt < $1.value.sentAt }
            .prefix(overflow)
            .map { $0.key }
        for id in idsToDrop {
            commandEvents.removeValue(forKey: id)
        }
    }

    private func processNextQueuedCommandIfPossible() {
        guard activeCommand == nil else { return }
        guard let characteristic = commandCharacteristic,
              let peripheral = ossmPeripheral,
              !pendingCommands.isEmpty else { return }

        let nextCommand = pendingCommands.removeFirst()
        guard let data = nextCommand.command.data(using: .utf8) else {
            failCommand(nextCommand, error: OSSMError.invalidParameter("Failed to encode command"))
            processNextQueuedCommandIfPossible()
            return
        }

        activeCommand = nextCommand
        peripheral.writeValue(data, for: characteristic, type: .withResponse)
    }

    private func scheduleActiveCommandTimeout() {
        activeCommandTimeoutTask?.cancel()
        guard let activeCommand else { return }

        activeCommandTimeoutTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: UInt64(activeCommand.timeout * 1_000_000_000))
            } catch {
                return
            }
            await MainActor.run {
                guard let pending = self.activeCommand, pending.eventID == activeCommand.eventID else { return }
                self.activeCommand = nil
                self.activeCommandTimeoutTask = nil
                self.recordCommandResponse(eventID: pending.eventID, response: nil, outcome: .timedOut)
                self.logCommandWarning(for: pending.eventID, message: "Timed out waiting for command response")
                self.failCommand(pending, error: OSSMError.timeout)
                self.processNextQueuedCommandIfPossible()
            }
        }
    }

    private func finishActiveCommand(with response: String) {
        guard let activeCommand else {
            let unmatchedEventID = registerCommandEvent("<unmatched-response>")
            recordTransportResult(eventID: unmatchedEventID, result: .success)
            recordCommandResponse(eventID: unmatchedEventID, response: response, outcome: .unmatchedResponse)
            logCommandWarning(for: unmatchedEventID, message: "Unmatched command response with no pending command")
            return
        }

        self.activeCommand = nil
        activeCommandTimeoutTask?.cancel()
        activeCommandTimeoutTask = nil

        let outcome = parseCommandResponseOutcome(response)
        recordCommandResponse(eventID: activeCommand.eventID, response: response, outcome: outcome)
        switch outcome {
        case .succeeded:
            logCommandInfo(for: activeCommand.eventID, message: "Command response received")
            succeedCommand(activeCommand, response: response)
        case .firmwareFailed:
            logCommandWarning(for: activeCommand.eventID, message: "Firmware reported command failure")
            failCommand(activeCommand, error: OSSMError.commandFailed(response))
        case .malformedResponse:
            logCommandWarning(for: activeCommand.eventID, message: "Command returned malformed response")
            switch activeCommand.delivery {
            case .completion:
                failCommand(activeCommand, error: OSSMError.invalidResponse)
            case .rawResponse:
                succeedCommand(activeCommand, response: response)
            }
        default:
            failCommand(activeCommand, error: OSSMError.invalidResponse)
        }

        processNextQueuedCommandIfPossible()
    }

    private func failActiveCommand(error: Error, outcome: CommandOutcome) {
        guard let activeCommand else { return }

        self.activeCommand = nil
        activeCommandTimeoutTask?.cancel()
        activeCommandTimeoutTask = nil
        recordCommandResponse(eventID: activeCommand.eventID, response: nil, outcome: outcome)
        logCommandError(for: activeCommand.eventID, message: error.localizedDescription)
        failCommand(activeCommand, error: error)
        processNextQueuedCommandIfPossible()
    }

    private func flushPendingCommandQueues(error: Error) {
        if let activeCommand {
            activeCommandTimeoutTask?.cancel()
            activeCommandTimeoutTask = nil
            self.activeCommand = nil
            recordCommandResponse(eventID: activeCommand.eventID, response: nil, outcome: .timedOut)
            logCommandWarning(for: activeCommand.eventID, message: "Command response dropped during reset")
            failCommand(activeCommand, error: error)
        }

        for pendingCommand in pendingCommands {
            recordTransportResult(eventID: pendingCommand.eventID, result: .failure(error.localizedDescription))
            logCommandError(for: pendingCommand.eventID, message: "Queued command aborted before send: \(error.localizedDescription)")
            failCommand(pendingCommand, error: error)
        }
        pendingCommands.removeAll()
    }

    private func succeedCommand(_ command: PendingCommand, response: String) {
        switch command.delivery {
        case .completion(let completion):
            completion?(.success(()))
        case .rawResponse(let continuation):
            continuation.resume(returning: response)
        }
    }

    private func failCommand(_ command: PendingCommand, error: Error) {
        switch command.delivery {
        case .completion(let completion):
            completion?(.failure(error))
        case .rawResponse(let continuation):
            continuation.resume(throwing: error)
        }
    }

    private func beginInitialDeviceSetup() {
        initialSetupTask?.cancel()
        initialSetupTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if !Task.isCancelled,
                   self.ossmPeripheral != nil,
                   self.commandCharacteristic != nil,
                   self.currentStateCharacteristic != nil {
                    self.initialSetupTask = nil
                    self.isReady = true
                    self.connectionStatus = .ready

                    if self.speedKnobConfigCharacteristic != nil {
                        self.setSpeedKnobConfig(knobAsLimit: self.loadSpeedKnobPreference())
                    }

                    self.refreshPatterns()
                }
            }

            if let currentStateCharacteristic {
                do {
                    let stateData = try await self.readValue(for: currentStateCharacteristic)
                    self.handleStateUpdateData(stateData)
                } catch {
                    print("[OSSM] Failed to read initial state: \(error)")
                }
            }

            if let speedKnobConfigCharacteristic {
                do {
                    let speedKnobConfigData = try await self.readValue(for: speedKnobConfigCharacteristic)
                    self.handleSpeedKnobConfigData(speedKnobConfigData)
                } catch {
                    print("[OSSM] Failed to read initial speed knob config: \(error)")
                }
            }
        }
    }

    private func handleStateUpdateData(_ data: Data) {
        if let state = OSSMState.fromJSON(data) {
            runtimeData.update(with: state)

            if currentRootState != state.state {
                handleStateTransition(from: currentRootState, to: state.state)
                currentRootState = state.state
            }
        } else if let jsonString = String(data: data, encoding: .utf8) {
            print("[OSSM] Failed to parse state JSON: \(jsonString)")
        }
    }

    private func handleSpeedKnobConfigData(_ data: Data) {
        if let value = String(data: data, encoding: .utf8) {
            speedKnobAsLimit = (value == "true")
            print("[OSSM] Speed knob config: \(value)")
        }
    }

    private func resolvePendingRead(_ result: Result<Data, Error>) {
        pendingReadTimeoutTask?.cancel()
        pendingReadTimeoutTask = nil
        pendingReadCompletion?(result)
        pendingReadCompletion = nil
    }

    private func parseCommandResponseOutcome(_ response: String) -> CommandOutcome {
        if response.hasPrefix("ok:") || response == "ok" {
            return .succeeded
        }
        if response.hasPrefix("fail:") {
            return .firmwareFailed
        }
        return .malformedResponse
    }

    private func logCommandInfo(for eventID: UUID, message: String) {
        if let event = commandEvents[eventID] {
            let ageMs = Int(Date().timeIntervalSince(event.sentAt) * 1000)
            print("[OSSM][Command] \(message) | cmd=\(event.command) ageMs=\(ageMs) transport=\(event.transportResult) outcome=\(event.outcome.rawValue) response=\(event.firmwareResponse ?? "nil")")
        } else {
            print("[OSSM][Command] \(message)")
        }
    }

    private func logCommandWarning(for eventID: UUID, message: String) {
        logCommandInfo(for: eventID, message: "WARN: \(message)")
    }

    private func logCommandError(for eventID: UUID, message: String) {
        logCommandInfo(for: eventID, message: "ERROR: \(message)")
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
                self.resolvePendingRead(.failure(OSSMError.timeout))
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
        wifiCharacteristic = nil
        currentStateCharacteristic = nil
        patternListCharacteristic = nil
        patternDescriptionCharacteristic = nil
        gpioCharacteristic = nil
        patterns.removeAll()
        runtimeData.currentState = OSSMState()
        currentRootState = .idle
        speedKnobAsLimit = true
        homingForwardStartTime = nil
        homingBackwardStartTime = nil
        flushPendingCommandQueues(error: OSSMError.notReady)
        activeCommandTimeoutTask?.cancel()
        activeCommandTimeoutTask = nil
        commandEvents.removeAll()
        pendingReadTimeoutTask?.cancel()
        pendingReadTimeoutTask = nil
        pendingReadCompletion = nil
        patternFetchTask?.cancel()
        patternFetchTask = nil
        initialSetupTask?.cancel()
        initialSetupTask = nil
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
        initialSetupTask?.cancel()
        initialSetupTask = nil
        flushPendingCommandQueues(error: error ?? OSSMError.notReady)
        resolvePendingRead(.failure(error ?? OSSMError.notReady))
        patternFetchTask?.cancel()
        patternFetchTask = nil

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
                    OSSMConstants.wifiCharacteristicUUID,
                    OSSMConstants.currentStateCharacteristicUUID,
                    OSSMConstants.patternListCharacteristicUUID,
                    OSSMConstants.patternDescriptionCharacteristicUUID,
                    OSSMConstants.gpioCharacteristicUUID
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
                // Keep notify enabled as a compatibility fallback while reads remain the primary response path.
                peripheral.setNotifyValue(true, for: characteristic)

            case OSSMConstants.speedKnobConfigCharacteristicUUID:
                print("[OSSM] Found speed knob config characteristic")
                speedKnobConfigCharacteristic = characteristic

            case OSSMConstants.wifiCharacteristicUUID:
                print("[OSSM] Found WiFi characteristic")
                wifiCharacteristic = characteristic

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

            case OSSMConstants.gpioCharacteristicUUID:
                print("[OSSM] Found GPIO characteristic")
                gpioCharacteristic = characteristic

            default:
                break
            }
        }

        // Check if we have all required characteristics
        if commandCharacteristic != nil && currentStateCharacteristic != nil {
            print("[OSSM] Required characteristics discovered, beginning initial device setup")
            beginInitialDeviceSetup()
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let data = characteristic.value else {
            print("[OSSM] Error reading characteristic: \(error?.localizedDescription ?? "unknown")")
            if characteristic.uuid == OSSMConstants.commandCharacteristicUUID {
                failActiveCommand(error: error ?? OSSMError.invalidResponse, outcome: .malformedResponse)
            } else {
                resolvePendingRead(.failure(error ?? OSSMError.invalidResponse))
            }
            return
        }

        switch characteristic.uuid {
        case OSSMConstants.currentStateCharacteristicUUID:
            handleStateUpdateData(data)

        case OSSMConstants.speedKnobConfigCharacteristicUUID:
            handleSpeedKnobConfigData(data)

        case OSSMConstants.commandCharacteristicUUID:
            if let response = String(data: data, encoding: .utf8) {
                print("[OSSM] Command response: \(response)")
                finishActiveCommand(with: response)
            } else if let activeCommand {
                recordCommandResponse(eventID: activeCommand.eventID, response: nil, outcome: .malformedResponse)
                logCommandWarning(for: activeCommand.eventID, message: "Failed to decode command response as UTF-8")
                failActiveCommand(error: OSSMError.invalidResponse, outcome: .malformedResponse)
            }

        case OSSMConstants.patternListCharacteristicUUID:
            // Pattern list JSON
            resolvePendingRead(.success(data))

        default:
            resolvePendingRead(.success(data))
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if characteristic.uuid != OSSMConstants.commandCharacteristicUUID {
            if let error {
                print("[OSSM] Write error: \(error.localizedDescription)")
            } else {
                print("[OSSM] Write successful for \(characteristic.uuid)")
            }
            return
        }
        if let error {
            print("[OSSM] Write error: \(error.localizedDescription)")
            failActiveCommand(error: error, outcome: .transportFailed)
            return
        }

        guard let activeCommand else {
            print("[OSSM] Command write ACK without pending command")
            return
        }

        recordTransportResult(eventID: activeCommand.eventID, result: .success)
        logCommandInfo(for: activeCommand.eventID, message: "Transport ACK received; reading command response")
        scheduleActiveCommandTimeout()
        peripheral.readValue(for: characteristic)
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

        let fallbackMap = Dictionary(uniqueKeysWithValues: buildFallbackPatterns().map { ($0.idx, $0) })
        let customPatterns = patterns.filter { fallbackMap[$0.idx] == nil }
        let descriptions = customPatterns.isEmpty ? [:] : try await fetchPatternDescriptions(for: customPatterns)

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

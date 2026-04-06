//
//  OSSMBLEManager+Debug.swift
//  OSSM Control
//

import Foundation
import Observation

// MARK: - Debug Session Simulator

/// Simulates session telemetry (strokes, distance, elapsed time) for debug mode.
/// Mirrors the firmware behaviour where a new session starts each time the
/// strokeEngine page is entered.
@Observable
class DebugSessionSimulator {
    var isEnabled: Bool = false
    var strokesPerSecond: Double = 1.5
    var distancePerSecondCm: Double = 30.0

    private(set) var isRunning: Bool = false

    private var simulationTask: Task<Void, Never>?
    private var sessionId: String = ""
    private var sessionStartDate: Date?
    private var accumulatedStrokes: Double = 0
    private var accumulatedDistanceM: Double = 0
    private weak var runtimeData: OSSMRuntimeData?

    init(runtimeData: OSSMRuntimeData) {
        self.runtimeData = runtimeData
    }

    /// Start a brand-new session, cancelling any existing one first.
    func startNewSession() {
        stopSession()
        guard isEnabled else { return }

        sessionId = UUID().uuidString
        sessionStartDate = Date()
        accumulatedStrokes = 0
        accumulatedDistanceM = 0
        isRunning = true

        simulationTask = Task { @MainActor [weak self] in
            let tickInterval: TimeInterval = 0.5
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self, !Task.isCancelled else { return }
                self.tick(interval: tickInterval)
            }
        }
    }

    /// Stop the current simulation and clear published stats.
    func stopSession() {
        simulationTask?.cancel()
        simulationTask = nil
        sessionStartDate = nil
        isRunning = false
        runtimeData?.update(sessionStats: nil)
    }

    private func tick(interval: TimeInterval) {
        guard let sessionStartDate, let runtimeData else { return }

        accumulatedStrokes += strokesPerSecond * interval
        accumulatedDistanceM += (distancePerSecondCm / 100.0) * interval

        let elapsedMs = Int(Date().timeIntervalSince(sessionStartDate) * 1000)

        let stats = OSSMSessionStats(
            sessionId: sessionId,
            elapsedMs: elapsedMs,
            strokes: Int(accumulatedStrokes),
            distanceM: accumulatedDistanceM
        )

        runtimeData.update(sessionStats: stats)
    }
}

// MARK: - Debug Mode Extension

extension OSSMBLEManager {
    func enableDebugMode() {
        isDebugMode = true
        stopScanning()
        connectionStatus = .ready
        isReady = true
        applyDebugState(.menuIdle, resetValues: true)
        refreshPatterns()
    }

    func disableDebugMode() {
        debugSessionSimulator.stopSession()
        debugSessionSimulator.isEnabled = false
        supportsSessionStats = false
        isDebugMode = false
        connectionStatus = .disconnected
        isReady = false
        applyDebugState(.idle, resetValues: true)
    }

    /// Toggle simulated session data on or off.
    /// When enabled and currently on the strokeEngine page, a session starts
    /// immediately. When disabled, the running session is stopped.
    func setDebugSessionSimulationEnabled(_ enabled: Bool) {
        debugSessionSimulator.isEnabled = enabled
        supportsSessionStats = enabled
        if enabled && currentPage == .strokeEngine {
            debugSessionSimulator.startNewSession()
        } else if !enabled {
            debugSessionSimulator.stopSession()
        }
    }

    func applyDebugState(_ status: OSSMStatus, resetValues: Bool = false) {
        DispatchQueue.main.async {
            var state = self.runtimeData.currentState
            if resetValues {
                state = OSSMState(state: status.rawValue)
            } else {
                state.state = status
            }
            self.runtimeData.update(with: state)
            self.currentRootState = status
        }
    }

    func handleDebugCommand(_ command: String, completion: ((Result<Void, Error>) -> Void)?) {
        let parts = command.split(separator: ":")
        guard let verb = parts.first else {
            completion?(.failure(OSSMError.invalidParameter("Empty command")))
            return
        }

        switch verb {
        case "go":
            guard parts.count >= 2 else {
                completion?(.failure(OSSMError.invalidParameter("Missing page")))
                return
            }
            let pageString = String(parts[1])
            guard let page = OSSMPage(rawValue: pageString) else {
                completion?(.failure(OSSMError.invalidParameter("Unknown page")))
                return
            }
            setDebugPage(page)
            completion?(.success(()))

        case "set":
            guard parts.count >= 3 else {
                completion?(.failure(OSSMError.invalidParameter("Missing parameter")))
                return
            }
            let key = String(parts[1])
            guard let value = Int(parts[2]) else {
                completion?(.failure(OSSMError.invalidParameter("Invalid value")))
                return
            }
            updateRuntimeState { state in
                switch key {
                case "speed":
                    state.speed = value
                case "stroke":
                    state.stroke = value
                case "depth":
                    state.depth = value
                case "sensation":
                    state.sensation = value
                case "pattern":
                    state.pattern = value
                default:
                    break
                }
            }
            completion?(.success(()))

        default:
            completion?(.success(()))
        }
    }

    private func updateRuntimeState(_ update: @escaping (inout OSSMState) -> Void) {
        DispatchQueue.main.async {
            var state = self.runtimeData.currentState
            update(&state)
            self.runtimeData.update(with: state)
            self.currentRootState = state.state
        }
    }

    private func setDebugPage(_ page: OSSMPage) {
        let status = debugStatus(for: page)
        updateRuntimeState { state in
            state.state = status
        }
        // Manage session simulation lifecycle: new session on strokeEngine, stop otherwise
        if page == .strokeEngine && debugSessionSimulator.isEnabled {
            debugSessionSimulator.startNewSession()
        } else {
            debugSessionSimulator.stopSession()
        }
    }

    private func debugStatus(for page: OSSMPage) -> OSSMStatus {
        switch page {
        case .menu:
            return .menuIdle
        case .simplePenetration:
            return .simplePenetrationIdle
        case .strokeEngine:
            return .strokeEngineIdle
        case .streaming:
            return .streamingIdle
        }
    }
}

//
//  OSSMBLEManager+Debug.swift
//  OSSM Control
//

import Foundation

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
        isDebugMode = false
        connectionStatus = .disconnected
        isReady = false
        applyDebugState(.idle, resetValues: true)
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

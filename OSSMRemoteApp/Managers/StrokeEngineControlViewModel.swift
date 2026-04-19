//
//  StrokeEngineControlViewModel.swift
//  OSSM Control
//

import Foundation
import Combine

@MainActor
final class StrokeEngineControlViewModel: ObservableObject {
    @Published private(set) var desiredState = OSSMPlayData()
    @Published private(set) var lastError: String?

    var debugLoggingEnabled = false

    private weak var bleManager: OSSMBLEManager?
    private var observedState = OSSMPlayData()
    private var locallyControlledParameters: Set<StrokeEngineParameter> = []
    private var acceptedCommandValues: [StrokeEngineParameter: Int] = [:]
    private var syncTask: Task<Void, Never>?

    func bind(to bleManager: OSSMBLEManager) {
        self.bleManager = bleManager
    }

    func bootstrap(from state: OSSMState) {
        receiveDeviceState(state, preferDeviceState: true)
    }

    func receiveDeviceState(_ state: OSSMState, preferDeviceState: Bool = false) {
        let incomingState = state.playData
        let previousObservedState = observedState

        observedState = incomingState

        if preferDeviceState {
            desiredState = incomingState
            locallyControlledParameters.removeAll()
            acceptedCommandValues.removeAll()
            lastError = nil
        } else {
            desiredState = mergeDesiredState(
                with: incomingState,
                previousObservedState: previousObservedState
            )
        }

        scheduleSyncIfNeeded()
    }

    func value(for parameter: StrokeEngineParameter) -> Int {
        desiredState.value(for: parameter)
    }

    func setValue(_ value: Int, for parameter: StrokeEngineParameter) {
        let clampedValue = parameter.clampedValue(value)
        guard desiredState.value(for: parameter) != clampedValue else { return }

        desiredState.setValue(clampedValue, for: parameter)
        locallyControlledParameters.insert(parameter)
        acceptedCommandValues.removeValue(forKey: parameter)
        lastError = nil
        log("Local \(parameter.commandKey) -> \(clampedValue)")
        scheduleSyncIfNeeded()
    }

    func adjustValue(for parameter: StrokeEngineParameter, by delta: Int) {
        setValue(value(for: parameter) + delta, for: parameter)
    }

    func apply(_ state: OSSMPlayData) {
        desiredState = state
        locallyControlledParameters = Set(StrokeEngineParameter.allCases)
        acceptedCommandValues.removeAll()
        lastError = nil
        log("Applying desired state \(state)")
        scheduleSyncIfNeeded()
    }

    private func mergeDesiredState(
        with incomingState: OSSMPlayData,
        previousObservedState: OSSMPlayData
    ) -> OSSMPlayData {
        var mergedState = desiredState

        for parameter in StrokeEngineParameter.allCases {
            if locallyControlledParameters.contains(parameter) {
                continue
            }

            let desiredValue = desiredState.value(for: parameter)
            let previousObservedValue = previousObservedState.value(for: parameter)
            let incomingValue = incomingState.value(for: parameter)
            let hasLocalOverride = desiredValue != previousObservedValue

            if !hasLocalOverride || desiredValue == incomingValue {
                mergedState.setValue(incomingValue, for: parameter)
            }
        }

        return mergedState
    }

    private func effectiveObservedValue(for parameter: StrokeEngineParameter) -> Int {
        acceptedCommandValues[parameter] ?? observedState.value(for: parameter)
    }

    private func nextParameterToSync() -> (parameter: StrokeEngineParameter, value: Int)? {
        for parameter in StrokeEngineParameter.syncOrder {
            let desiredValue = desiredState.value(for: parameter)
            let effectiveValue = effectiveObservedValue(for: parameter)
            if desiredValue != effectiveValue {
                return (parameter, desiredValue)
            }
        }

        return nil
    }

    private func scheduleSyncIfNeeded() {
        guard syncTask == nil else { return }
        guard nextParameterToSync() != nil else { return }

        syncTask = Task { [weak self] in
            await self?.runSyncLoop()
        }
    }

    private func runSyncLoop() async {
        defer {
            syncTask = nil
            if nextParameterToSync() != nil {
                scheduleSyncIfNeeded()
            }
        }

        while let bleManager,
              bleManager.isReady,
              bleManager.currentPage == .strokeEngine,
              let nextUpdate = nextParameterToSync() {
            do {
                try await bleManager.setStrokeEngineParameter(
                    nextUpdate.parameter,
                    value: nextUpdate.value
                )

                acceptedCommandValues[nextUpdate.parameter] = nextUpdate.value
                log("Synced \(nextUpdate.parameter.commandKey) -> \(nextUpdate.value)")
            } catch {
                acceptedCommandValues.removeValue(forKey: nextUpdate.parameter)
                lastError = error.localizedDescription
                log("Sync failed for \(nextUpdate.parameter.commandKey): \(error.localizedDescription)")
                return
            }
        }
    }

    private func log(_ message: @autoclosure () -> String) {
        guard debugLoggingEnabled else { return }
        print("[StrokeEngine][Sync] \(message())")
    }
}

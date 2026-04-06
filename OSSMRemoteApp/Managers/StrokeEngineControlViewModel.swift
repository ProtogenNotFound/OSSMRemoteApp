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
    private var pendingConfirmations: [StrokeEngineParameter: PendingConfirmation] = [:]
    private var syncTask: Task<Void, Never>?

    private let confirmationTimeout: TimeInterval = 3.0

    private struct PendingConfirmation {
        let value: Int
        let sentAt: Date
    }

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
        pruneExpiredPendingConfirmations()
        clearConfirmedPendingConfirmations(using: incomingState)

        if preferDeviceState {
            desiredState = incomingState
            pendingConfirmations.removeAll()
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
        lastError = nil
        log("Local \(parameter.commandKey) -> \(clampedValue)")
        scheduleSyncIfNeeded()
    }

    func adjustValue(for parameter: StrokeEngineParameter, by delta: Int) {
        setValue(value(for: parameter) + delta, for: parameter)
    }

    func apply(_ state: OSSMPlayData) {
        desiredState = state
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
        pruneExpiredPendingConfirmations()
        return pendingConfirmations[parameter]?.value ?? observedState.value(for: parameter)
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
        pruneExpiredPendingConfirmations()
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

                pendingConfirmations[nextUpdate.parameter] = PendingConfirmation(
                    value: nextUpdate.value,
                    sentAt: Date()
                )
                log("Synced \(nextUpdate.parameter.commandKey) -> \(nextUpdate.value)")
            } catch {
                pendingConfirmations.removeValue(forKey: nextUpdate.parameter)
                lastError = error.localizedDescription
                log("Sync failed for \(nextUpdate.parameter.commandKey): \(error.localizedDescription)")
                return
            }
        }
    }

    private func clearConfirmedPendingConfirmations(using incomingState: OSSMPlayData) {
        for parameter in StrokeEngineParameter.allCases {
            guard let pending = pendingConfirmations[parameter] else { continue }
            if pending.value == incomingState.value(for: parameter) {
                pendingConfirmations.removeValue(forKey: parameter)
            }
        }
    }

    private func pruneExpiredPendingConfirmations() {
        let now = Date()
        let expiredParameters = pendingConfirmations.compactMap { parameter, pending in
            now.timeIntervalSince(pending.sentAt) > confirmationTimeout ? parameter : nil
        }

        for parameter in expiredParameters {
            if let pending = pendingConfirmations.removeValue(forKey: parameter) {
                log("Timed out waiting for \(parameter.commandKey)=\(pending.value) confirmation")
            }
        }
    }

    private func log(_ message: @autoclosure () -> String) {
        guard debugLoggingEnabled else { return }
        print("[StrokeEngine][Sync] \(message())")
    }
}

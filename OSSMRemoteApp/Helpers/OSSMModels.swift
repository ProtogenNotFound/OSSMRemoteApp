//
//  OSSMModels.swift
//  OSSM Control
//
//  Shared data types for OSSM device control
//

import Foundation
import CoreBluetooth
import SwiftUI
import Combine

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
    case streamingPreflight = "streaming.preflight"
    case streamingIdle = "streaming.idle"
    case update = "update"
    case wifi = "wifi"
    case help = "help"
    case error = "error"
    case restart = "restart"
}

/// OSSM pages for navigation (must match firmware regex exactly)
enum OSSMPage: String, CaseIterable, Hashable {
    case menu = "menu"
    case simplePenetration = "simplePenetration"
    case strokeEngine = "strokeEngine"
    case streaming = "streaming"
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

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
import SwiftData
import AppIntents


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
    case updateChecking = "update.checking"
    case updateUpdating = "update.updating"
    case updateIdle = "update.idle"
    case wifi = "wifi"
    case wifiIdle = "wifi.idle"
    case help = "help"
    case helpIdle = "help.idle"
    case error = "error"
    case errorIdle = "error.idle"
    case errorHelp = "error.help"
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
enum KnownPattern: Int, CaseIterable, Identifiable, AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Pattern")
    }
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .simpleStroke: DisplayRepresentation(
            title: "Simple Stroke",
            subtitle: "Speeds up, coasts, and slows down on each stroke. Sensation has no effect.",
            synonyms: ["Basic Stroke"]
        ),
        .teasingPounding: DisplayRepresentation(
            title: "Teasing/Pounding",
            subtitle: "Varies inward and outward speeds. Positive Sensation speeds up inward motion. Negative speeds up outward motion.",
            synonyms: ["Teasing and Pounding", "Uneven In and Out Speed"]
        ),
        .roboStroke: DisplayRepresentation(
            title: "Robo Stroke",
            subtitle: "Positive Sensation makes strokes reach steady speed sooner. Negative makes acceleration more gradual. Zero matches Simple Stroke.",
            synonyms: ["Robotic Stroke", "Variable Acceleration"]
        ),
        .halfNHalf: DisplayRepresentation(
            title: "Half N Half",
            subtitle: "Alternates full-depth and half-depth strokes. Positive Sensation speeds up inward motion. Negative speeds up outward motion.",
            synonyms: ["Half and Half", "Alternating Full and Half Depth"]
        ),
        .deeper: DisplayRepresentation(
            title: "Deeper",
            subtitle: "Repeats a series of strokes that get progressively deeper. Sensation sets the number of strokes in each series.",
            synonyms: ["Progressively Deeper", "Increasing Depth"]
        ),
        .stopNGo: DisplayRepresentation(
            title: "Stop N Go",
            subtitle: "Pauses between groups of strokes. Sensation controls how long each pause lasts.",
            synonyms: ["Stop and Go", "Strokes with Pauses"]
        ),
        .insist: DisplayRepresentation(
            title: "Insist",
            subtitle: "Varies stroke length at the same speed. Positive Sensation shifts strokes toward the front. Negative shifts them toward the back.",
            synonyms: ["Variable Stroke Length"]
        )
    ]

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
            **>0:** Makes the in-move faster for a hard pounding sensation
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
    var sensationDescription: LocalizedStringKey?
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

/// Represents strokeEngine session telemetry broadcast by newer firmware.
struct OSSMSessionStats: Equatable {
    var sessionId: String
    var elapsedMs: Int
    var strokes: Int
    var distanceM: Double

    var elapsedSeconds: TimeInterval {
        TimeInterval(elapsedMs) / 1000
    }

    /// Parse from JSON data received from firmware
    static func fromJSON(_ data: Data) -> OSSMSessionStats? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sessionId = json["sessionId"] as? String,
              let elapsedMs = json["elapsedMs"] as? NSNumber,
              let strokes = json["strokes"] as? NSNumber,
              let distanceM = json["distanceM"] as? NSNumber else {
            return nil
        }

        return OSSMSessionStats(
            sessionId: sessionId,
            elapsedMs: elapsedMs.intValue,
            strokes: strokes.intValue,
            distanceM: distanceM.doubleValue
        )
    }
}

@Model
final class OSSMSessionStatsRecord {
    @Attribute(.unique) var sessionId: String = Foundation.UUID().uuidString
    var startDate: Date = Foundation.Date.now
    var elapsedMs: Int = 0
    var strokes: Int = 0
    var distanceM: Double = 0

    init(sessionStats: OSSMSessionStats) {
        self.sessionId = sessionStats.sessionId
        self.startDate = .now.addingTimeInterval(-max(0, sessionStats.elapsedSeconds))
        self.elapsedMs = sessionStats.elapsedMs
        self.strokes = sessionStats.strokes
        self.distanceM = sessionStats.distanceM
    }

    func update(from sessionStats: OSSMSessionStats) {
        elapsedMs = sessionStats.elapsedMs
        strokes = sessionStats.strokes
        distanceM = sessionStats.distanceM
    }
}

/// Stroke engine parameters that can be synchronized over BLE.
enum StrokeEngineParameter: CaseIterable {
    case pattern
    case speed
    case stroke
    case depth
    case sensation

    static let syncOrder: [StrokeEngineParameter] = [
        .speed,
        .stroke,
        .depth,
        .sensation,
        .pattern
    ]

    var commandKey: String {
        switch self {
        case .pattern:
            return "pattern"
        case .speed:
            return "speed"
        case .stroke:
            return "stroke"
        case .depth:
            return "depth"
        case .sensation:
            return "sensation"
        }
    }

    func clampedValue(_ value: Int) -> Int {
        switch self {
        case .pattern:
            return max(0, value)
        case .speed, .stroke, .depth, .sensation:
            return max(0, min(100, value))
        }
    }
}

/// Data structure for running stroke engine patterns.
struct OSSMPlayData: Equatable {
    var speed: Int = 0
    var stroke: Int = 0
    var depth: Int = 0
    var sensation: Int = 0
    var pattern: Int = 0

    init(
        speed: Int = 0,
        stroke: Int = 0,
        depth: Int = 0,
        sensation: Int = 0,
        pattern: Int = 0
    ) {
        self.speed = StrokeEngineParameter.speed.clampedValue(speed)
        self.stroke = StrokeEngineParameter.stroke.clampedValue(stroke)
        self.depth = StrokeEngineParameter.depth.clampedValue(depth)
        self.sensation = StrokeEngineParameter.sensation.clampedValue(sensation)
        self.pattern = StrokeEngineParameter.pattern.clampedValue(pattern)
    }

    init(state: OSSMState) {
        self.init(
            speed: state.speed,
            stroke: state.stroke,
            depth: state.depth,
            sensation: state.sensation,
            pattern: state.pattern
        )
    }

    func value(for parameter: StrokeEngineParameter) -> Int {
        switch parameter {
        case .pattern:
            return pattern
        case .speed:
            return speed
        case .stroke:
            return stroke
        case .depth:
            return depth
        case .sensation:
            return sensation
        }
    }

    mutating func setValue(_ value: Int, for parameter: StrokeEngineParameter) {
        let clampedValue = parameter.clampedValue(value)
        switch parameter {
        case .pattern:
            pattern = clampedValue
        case .speed:
            speed = clampedValue
        case .stroke:
            stroke = clampedValue
        case .depth:
            depth = clampedValue
        case .sensation:
            sensation = clampedValue
        }
    }
}

extension OSSMState {
    var playData: OSSMPlayData {
        OSSMPlayData(state: self)
    }
}

// MARK: - OSSM BLE Constants (from firmware)

enum OSSMConstants {
    static let deviceName = "OSSM"

    // Primary Service UUID
    static let primaryServiceUUID = CBUUID(string: "522b443a-4f53-534d-0001-420badbabe69")

    // Characteristic UUIDs (from firmware nimble.cpp)
    static let commandCharacteristicUUID = CBUUID(string: "522b443a-4f53-534d-1000-420badbabe69")
    static let speedKnobConfigCharacteristicUUID = CBUUID(string: "522b443a-4f53-534d-1010-420badbabe69")
    static let wifiCharacteristicUUID = CBUUID(string: "522b443a-4f53-534d-1020-420badbabe69")
    static let currentStateCharacteristicUUID = CBUUID(string: "522b443a-4f53-534d-2000-420badbabe69")
    static let sessionStatsCharacteristicUUID = CBUUID(string: "522b443a-4f53-534d-2010-420badbabe69")
    static let patternListCharacteristicUUID = CBUUID(string: "522b443a-4f53-534d-3000-420badbabe69")
    static let patternDescriptionCharacteristicUUID = CBUUID(string: "522b443a-4f53-534d-3010-420badbabe69")
    static let gpioCharacteristicUUID = CBUUID(string: "522b443a-4f53-534d-4000-420badbabe69")

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
    @Published var currentSessionStats: OSSMSessionStats?

    func update(with newState: OSSMState) {
        // Only publish if something actually changed to be safe,
        // though SwiftUI handles this well usually.
        if currentState != newState {
            currentState = newState
        }
    }

    func update(sessionStats newSessionStats: OSSMSessionStats?) {
        if currentSessionStats != newSessionStats {
            currentSessionStats = newSessionStats
        }
    }
}

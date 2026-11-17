#if DEBUG
//
//  DebugSessionHistoryModelContainer.swift
//  OSSMRemoteApp
//

import Foundation
import SwiftData

enum DebugSessionHistoryModelContainer {
    static let useDemoDatabaseKey = "debug.sessionHistory.useDemoDatabase"

    private static var liveContainer: ModelContainer?
    private static var demoContainer: ModelContainer?
    private static var demoSeedDay: String?

    static func container(useDemoDatabase: Bool) -> ModelContainer {
        if useDemoDatabase {
            return currentDemoContainer()
        }

        if let liveContainer {
            return liveContainer
        }

        let container = makeLiveContainer()
        liveContainer = container
        return container
    }

    private static func currentDemoContainer(now: Date = .now, calendar: Calendar = .current) -> ModelContainer {
        let seedDay = seedDayIdentifier(for: now, calendar: calendar)

        if let demoContainer, demoSeedDay == seedDay {
            return demoContainer
        }

        let container = makeDemoContainer(now: now, calendar: calendar)
        demoContainer = container
        demoSeedDay = seedDay
        return container
    }

    private static func makeLiveContainer() -> ModelContainer {
        do {
            return try ModelContainer(for: StrokeEnginePreset.self, OSSMSessionStatsRecord.self)
        } catch {
            fatalError("Failed to create SwiftData model container: \(error)")
        }
    }

    private static func makeDemoContainer(now: Date, calendar: Calendar) -> ModelContainer {
        do {
            let configuration = ModelConfiguration(
                for: StrokeEnginePreset.self,
                OSSMSessionStatsRecord.self,
                isStoredInMemoryOnly: true
            )
            let container = try ModelContainer(
                for: StrokeEnginePreset.self,
                OSSMSessionStatsRecord.self,
                configurations: configuration
            )
            try populateDemoSessionHistory(in: container, now: now, calendar: calendar)
            return container
        } catch {
            fatalError("Failed to create demo SwiftData model container: \(error)")
        }
    }

    private static func populateDemoSessionHistory(
        in container: ModelContainer,
        now: Date,
        calendar: Calendar
    ) throws {
        let context = ModelContext(container)
        var generator = SeededRandomNumberGenerator(seed: seedValue(for: now, calendar: calendar))

        for dayOffset in 0..<30 {
            let sessionCount = demoSessionCount(using: &generator)

            for sessionIndex in 0..<sessionCount {
                let durationSeconds = Int.random(in: 5 * 60...15 * 60, using: &generator)
                let strokesPerMinute = Double.random(in: 20...120, using: &generator)
                let travelPerStrokeM = Double.random(in: 0.10...0.60, using: &generator)
                let strokes = Int((Double(durationSeconds) / 60.0 * strokesPerMinute).rounded())
                let distanceM = Double(strokes) * travelPerStrokeM
                let startDate = demoStartDate(
                    now: now,
                    dayOffset: dayOffset,
                    durationSeconds: durationSeconds,
                    using: &generator
                )

                let stats = OSSMSessionStats(
                    sessionId: "demo-session-\(dayOffset)-\(sessionIndex)",
                    elapsedMs: durationSeconds * 1000,
                    strokes: strokes,
                    distanceM: distanceM
                )
                let record = OSSMSessionStatsRecord(sessionStats: stats)
                record.startDate = startDate
                context.insert(record)
            }
        }

        try context.save()
    }

    private static func demoSessionCount(using generator: inout SeededRandomNumberGenerator) -> Int {
        let roll = Int.random(in: 1...10, using: &generator)

        if roll == 10 {
            return 3
        }

        if roll >= 6 {
            return 2
        }

        return 1
    }

    private static func demoStartDate(
        now: Date,
        dayOffset: Int,
        durationSeconds: Int,
        using generator: inout SeededRandomNumberGenerator
    ) -> Date {
        let secondsPerDay = 24 * 60 * 60
        let latestEndPadding = 5 * 60
        let minimumAgeSeconds = durationSeconds + latestEndPadding
        let maximumAgeSeconds = secondsPerDay - latestEndPadding
        let secondsWithinDay = Int.random(in: minimumAgeSeconds...maximumAgeSeconds, using: &generator)
        let secondsAgo = dayOffset * secondsPerDay + secondsWithinDay
        return now.addingTimeInterval(-TimeInterval(secondsAgo))
    }

    private static func seedDayIdentifier(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }

    private static func seedValue(for date: Date, calendar: Calendar) -> UInt64 {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = UInt64(components.year ?? 0)
        let month = UInt64(components.month ?? 0)
        let day = UInt64(components.day ?? 0)
        return (year * 10_000) + (month * 100) + day
    }
}

private struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }
}
#endif

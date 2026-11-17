//
//  OSSMRemoteAppApp.swift
//  OSSMRemoteApp
//
//  Created by ProtogenNotFound on 24/1/26.
//

import SwiftUI
import SwiftData
import AppIntents


// Used for all services that need to be accessed by AppIntents
@MainActor
enum AppIntentShared {
    static let bleManager = OSSMBLEManager()
    static let navigationPath = OSSMNavigationPath()
    static let strokeEngineViewModel = StrokeEngineControlViewModel()
}

@main
struct OSSMRemoteAppApp: App {
    @StateObject var bleManager = AppIntentShared.bleManager
    #if DEBUG
    @AppStorage(DebugSessionHistoryModelContainer.useDemoDatabaseKey) private var useDemoSessionHistoryDatabase = false
    #endif

    var body: some Scene {
        WindowGroup {
            OSSMControlView()
                .environmentObject(bleManager)
                #if DEBUG
                .id(useDemoSessionHistoryDatabase)
                #endif
        }
        #if DEBUG
        .modelContainer(DebugSessionHistoryModelContainer.container(useDemoDatabase: useDemoSessionHistoryDatabase))
        #else
        .modelContainer(for: [StrokeEnginePreset.self, OSSMSessionStatsRecord.self])
        #endif
        #if os(visionOS)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 450, height: 600)
        #endif
    }

    init() {
        let bleMan = AppIntentShared.bleManager
        let navigationPath = AppIntentShared.navigationPath
        let strokeEngineModel = AppIntentShared.strokeEngineViewModel
        AppDependencyManager.shared.add(dependency: bleMan)
        AppDependencyManager.shared.add(dependency: navigationPath)
        AppDependencyManager.shared.add(dependency: strokeEngineModel)
    }
}

/// OSSM pages for navigation (must match firmware regex exactly)
enum OSSMPageIntentWrapper: String, CaseIterable, Hashable, AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Page")
    }
    static var caseDisplayRepresentations: [Self : DisplayRepresentation] = [
        .menu: DisplayRepresentation(title: "Menu", subtitle: "The menu page"),
        .simplePenetration: DisplayRepresentation(title: "Simple Penetration", subtitle: "Simple penetration page"),
        .strokeEngine: DisplayRepresentation(title: "Stroke Engine", subtitle: "Stroke Engine page"),
        .streaming: DisplayRepresentation(title: "Streaming", subtitle: "Streaming page")
    ]

    case menu = "menu"
    case simplePenetration = "simplePenetration"
    case strokeEngine = "strokeEngine"
    case streaming = "streaming"

    func getPage() -> OSSMPage? {
        return OSSMPage.allCases.first(where: {$0.rawValue == self.rawValue})
    }
}

@available(iOS 27.3 , *)
@AppIntent(.tool)
struct NavigateTo: AppIntent {
    static let isAssistantOnly: Bool = true

    static let title: LocalizedStringResource = "Navigate to a page"
    static let description: IntentDescription = "Navigates to or opens a page"

    @Parameter(title: "destination", description: "the name of the destination page or view")
    var destination: OSSMPageIntentWrapper

    @Dependency
    private var bleManager: OSSMBLEManager

    @Dependency
    private var navigationPath: OSSMNavigationPath

    @MainActor
    func perform() async throws -> some IntentResult {
        guard bleManager.connectionStatus == .ready else {
            throw AppIntentError(description: "OSSM is not connected")
        }
        let menuDestinations: [OSSMPageIntentWrapper] = [.strokeEngine, .streaming]

        if menuDestinations.contains(menuDestinations) {
            guard let destination = destination.getPage() else {
                throw AppIntentError(description: "Destination page doesn't exist")
            }
            navigationPath.path = [destination]
            return .result()
        }

        if destination == .menu {
            navigationPath.path = []
            return .result()
        }

        throw AppIntentError(description: "Not sure what you're trying to do, current path is \(navigationPath.path.debugDescription), destination is \(destination.localizedStringResource) ")
    }
}


//
//  OSSMRemoteAppApp.swift
//  OSSMRemoteApp
//
//  Created by ProtogenNotFound on 24/1/26.
//

import SwiftUI
import SwiftData

@main
struct OSSMRemoteAppApp: App {
    @StateObject var bleManager = OSSMBLEManager()
    var body: some Scene {
        WindowGroup {
            OSSMControlView()
                .environmentObject(bleManager)
        }
        .modelContainer(for: [StrokeEnginePreset.self])
    }
}

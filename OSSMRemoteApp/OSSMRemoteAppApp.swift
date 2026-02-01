//
//  OSSMRemoteAppApp.swift
//  OSSMRemoteApp
//
//  Created by ProtogenNotFound on 24/1/26.
//

import SwiftUI

@main
struct OSSMRemoteAppApp: App {
    @StateObject var bleManager = OSSMBLEManager()
    var body: some Scene {
        WindowGroup {
            OSSMControlView()
                .environmentObject(bleManager)
        }
    }
}

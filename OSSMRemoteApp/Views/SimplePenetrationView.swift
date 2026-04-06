//
//  SimplePenetrationView.swift
//  OSSM Control
//

import SwiftUI

struct SimplePenetrationView: PlatformSplitView {
    @EnvironmentObject var bleManager: OSSMBLEManager

    #if !os(visionOS)
    var iosBody: some View {
        Group{
            if bleManager.currentPage == .simplePenetration {
                Text("Simple Penetration")
                Button("Test"){
                    Task {
                        try? await bleManager.navigateTo(.menu)
                    }
                }
            } else {
                ProgressView()
            }
        }.navigationTitle("Simple Penetration")
    }
    #endif
}

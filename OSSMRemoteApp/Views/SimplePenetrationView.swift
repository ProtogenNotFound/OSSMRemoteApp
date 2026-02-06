//
//  SimplePenetrationView.swift
//  OSSM Control
//

import SwiftUI

struct SimplePenetrationView: View {
    @EnvironmentObject private var bleManager: OSSMBLEManager
    var body: some View {
        Group{
            if bleManager.currentPage == .simplePenetration {
                Text("Simple Penetration")
                Button("Test"){
                    bleManager.navigateTo(.menu)
                }
            } else {
                ProgressView()
            }
        }.navigationTitle("Simple Penetration")
    }
}

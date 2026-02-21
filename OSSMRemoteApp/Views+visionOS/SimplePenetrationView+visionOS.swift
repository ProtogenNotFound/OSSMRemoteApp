//
//  SimplePenetrationView+visionOS.swift
//  OSSM Control
//

import SwiftUI

#if os(visionOS)
extension SimplePenetrationView {
    var visionBody: some View {
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
#endif

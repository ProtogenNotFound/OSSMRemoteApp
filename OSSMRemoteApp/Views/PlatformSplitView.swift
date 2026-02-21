//
//  PlatformSplitView.swift
//  OSSM Control
//

import SwiftUI

#if os(visionOS)
protocol PlatformSplitView: View {
    associatedtype VisionBody: View
    @ViewBuilder var visionBody: VisionBody { get }
}

extension PlatformSplitView {
    @ViewBuilder var body: some View {
        visionBody
    }
}
#else
protocol PlatformSplitView: View {
    associatedtype IOSBody: View
    @ViewBuilder var iosBody: IOSBody { get }
}

extension PlatformSplitView {
    @ViewBuilder var body: some View {
        iosBody
    }
}
#endif

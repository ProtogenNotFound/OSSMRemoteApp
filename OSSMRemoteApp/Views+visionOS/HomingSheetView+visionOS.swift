//
//  HomingSheetView+visionOS.swift
//  OSSM Control
//

import SwiftUI

#if os(visionOS)
extension HomingProgressBar {
    var visionBody: some View {
        TimelineView(.periodic(from: .now, by: 1.0/30.0)) { _ in
            let progress: CGFloat = {
                guard duration > 0, let end = bleManager.homingEstimatedEndTime else { return 0 }
                let remaining = end.timeIntervalSinceNow
                let p = 1 - (remaining / duration)
                return CGFloat(max(0, min(1, p)))
            }()

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.quaternary)
                    Capsule()
                        .fill(.tint)
                        .frame(width: progress * geo.size.width)
                        .animation(.linear(duration: 1.0/30.0), value: progress)
                }
            }
            .frame(height: 10)
        }
    }
}

extension HomingSheetView {
    var visionBody: some View {
        let homingString = forward ? "Homing Forward" : "Homing Backward"
        let homingImage = forward ? "arrow.forward.to.line" : "arrow.backward.to.line"

        return VStack(spacing: 16) {
            let homingSeconds = forward ? homingForwardTime ?? 0 : homingBackwardTime ?? 0
            TimelineView(.periodic(from: .now, by: 1.0/30.0)) { _ in
                let progress: CGFloat = {
                    guard homingSeconds > 0, let end = bleManager.homingEstimatedEndTime else { return 0 }
                    let remaining = end.timeIntervalSinceNow
                    let p = 1 - (remaining / homingSeconds)
                    return CGFloat(max(0, min(1, p)))
                }()

                ZStack(alignment: .leading) {
                    Text(homingString)
                        .foregroundStyle(.secondary)

                    Text(homingString)
                        .contentTransition(.numericText())
                        .foregroundStyle(.white)
                        .overlay {
                            GeometryReader { geo in
                                Color.clear
                                    .frame(width: progress * geo.size.width)
                            }
                        }
                        .mask {
                            GeometryReader { geo in
                                Rectangle()
                                    .frame(width: progress * geo.size.width)
                                    .animation(.linear(duration: 1.0/30.0), value: progress)
                            }
                        }
                }
            }
            Image(systemName: homingImage)
                .symbolEffect(.drawOn.byLayer, isActive: homingPulse)
                .contentTransition(.symbolEffect(.replace))
        }
        .animation(.easeInOut, value: homingString)
        .font(.largeTitle.bold())
        .fontDesign(.rounded)
        .onAppear { onAppear() }
        .onDisappear { onDisappear() }
    }
}
#endif

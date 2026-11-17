//
//  MenuView.swift
//  OSSM Control
//

import SwiftUI
import SwiftData
import RealityKit
import AppIntents

struct MenuView: PlatformSplitView {
    @EnvironmentObject var bleManager: OSSMBLEManager
    @AppStorage("savedUUID") var savedUUID: String?
    @State var symbolSize = CGSize(.zero)
    @State private var dragOffset: CGSize = .zero
    @State private var isDragging = false

    @Query(sort: \OSSMSessionStatsRecord.startDate, order: .reverse) var sessionHistory: [OSSMSessionStatsRecord]

    #if !os(visionOS)
    let heroTransitionNamespace: Namespace.ID
    #endif

    var ossmImage: some View {
        Color.white
            .mask{
                Image("ossm")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
    }

    #if !os(visionOS)

    func menuViewCard(symbol: String, value: String, descriptor: String) -> some View {
        HStack{
            Image(systemName: symbol)
                .font(.title)
            VStack(alignment: .leading) {
                Text(value)
                Text(descriptor)
                    .font(.caption2)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect()
        .padding(4)
    }


    var iosBody: some View {
        VStack {
            OSSMPreviewRealityView()
            if !sessionHistory.isEmpty {
                let totalSessions = sessionHistory.count
                let totalTimeMs = sessionHistory.map(\.elapsedMs).reduce(0, +)
                let totalStrokes = sessionHistory.map(\.strokes).reduce(0, +)
                let totalDistanceM = sessionHistory.map(\.distanceM).reduce(0, +)
                LazyVGrid(columns: [GridItem(.flexible(minimum: 100, maximum: 400)), GridItem(.flexible(minimum: 100, maximum: 400))]) {
                    menuViewCard(symbol: "figure.pilates.circle", value: totalSessions.description, descriptor: "Sessions")
                    menuViewCard(symbol: "clock", value: Self.formattedDuration(fromMilliseconds: totalTimeMs), descriptor: "Recorded time")
                    menuViewCard(symbol: "arrow.left.arrow.right", value: totalStrokes.description, descriptor: "Strokes")
                    menuViewCard(symbol: "ruler", value: totalDistanceM.formatted(.number.precision(.fractionLength(1)))+"m", descriptor: "Distance travelled")
                }.padding(40)
            }
        }
        .toolbar{
        ToolbarItemGroup(placement: .bottomBar) {
            NavigationLink(value: OSSMPage.strokeEngine){
                VStack {
                    Text("Stroke Engine")
                        .padding(12)
                }
                    .frame(maxWidth: .infinity)

            }
            .font(.title2.bold())
            .buttonStyle(.borderedProminent)
            .matchedTransitionSource(id: "strokeEngineTitleZoom", in: heroTransitionNamespace)
            NavigationLink(value: OSSMPage.streaming){
                VStack {
                    Text("Streaming")
                        .padding(12)
                }
                    .frame(maxWidth: .infinity)

            }
            .font(.title2.bold())
            .buttonStyle(.borderedProminent)
            .matchedTransitionSource(id: "streamingTitleZoom", in: heroTransitionNamespace)

        }
    }
    }

    static func formattedDuration(fromMilliseconds milliseconds: Int) -> String {
        let totalSeconds = Int((Double(milliseconds) / 1000.0).rounded())

        guard totalSeconds > 0 else { return "0s" }

        let units: [(suffix: String, seconds: Int)] = [
            ("y", 365 * 24 * 60 * 60),
            ("d", 24 * 60 * 60),
            ("h", 60 * 60),
            ("m", 60),
            ("s", 1)
        ]

        var remainingSeconds = totalSeconds
        var components: [String] = []

        for unit in units {
            let value = remainingSeconds / unit.seconds
            guard value > 0 else { continue }
            components.append("\(value)\(unit.suffix)")
            remainingSeconds %= unit.seconds
        }

        return components.joined()
    }

    func ossmPreviewImageView() -> some View {
        let maxAngle: Double = 25
        let sensitivity: Double = 100.0

        // Combine horizontal + vertical drag into a single rotation axis + angle
        let normalizedX = dragOffset.width / sensitivity
        let normalizedY = dragOffset.height / sensitivity
        let magnitude = sqrt(normalizedX * normalizedX + normalizedY * normalizedY)
        let clampedAngle = maxAngle * (2.0 / .pi) * atan(magnitude)
        // Rotation axis is perpendicular to the drag direction
        let axis: (x: CGFloat, y: CGFloat, z: CGFloat) = magnitude > 0.001
            ? (x: CGFloat(-normalizedY / magnitude), y: CGFloat(normalizedX / magnitude), z: 0)
            : (x: 0, y: 1, z: 0)
        let angle = Angle.degrees(clampedAngle)

        // Layer Z-depth separation (only visible when dragging)
        let separation: CGFloat = isDragging ? 40 : 0
        let glowRadius: CGFloat = isDragging ? 20 + clampedAngle : 12
        let glowOpacity: Double = isDragging ? 0.5 + clampedAngle / maxAngle * 0.3 : 0.3
        let cornerRadius: CGFloat = 44

        return GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let innerSize = size * (819.0 / 1024.0)

            ZStack {
                Image("ossmImageBack")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .shadow(color: .blue.opacity(glowOpacity), radius: glowRadius)
                    .rotation3DEffect(angle, axis: axis, anchorZ: -separation, perspective: 0.4)

                Image("ossmImageMiddle")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: innerSize, height: innerSize)
                    .shadow(color: .black.opacity(isDragging ? 0.15 : 0), radius: 8, y: 2)
                    .rotation3DEffect(angle, axis: axis, anchorZ: separation * 0.15, perspective: 0.4)

                Image("ossmImageFront")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: innerSize, height: innerSize)
                    .shadow(color: .black.opacity(isDragging ? 0.25 : 0), radius: 12, y: 4)
                    .rotation3DEffect(angle, axis: axis, anchorZ: separation * 0.3, perspective: 0.4)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !isDragging {
                        withAnimation(.spring(duration: 0.4, bounce: 0.2)) {
                            isDragging = true
                        }
                    }
                    dragOffset = value.translation
                }
                .onEnded { _ in
                    withAnimation(.spring(duration: 0.5, bounce: 0.3)) {
                        isDragging = false
                        dragOffset = .zero
                    }
                }
        )
    }

    #endif
}

struct OSSMPreviewRealityView: View {
    var body: some View {
        RealityView{context in
            guard let ossm = try? await Entity(named: "ossm_model") else {print("no ossm");return}
            ossm.transform.rotation = Transform(pitch: -.pi / 2, yaw: .pi, roll: 0).rotation
            ossm.transform.scale = .init(repeating: 4)
            context.add(ossm)
        }
    }
}

#if os(visionOS)
#Preview {
    NavigationStack {
        MenuView()
    }
}
#else
private struct MenuViewPreviewWrapper: View {
    @Namespace private var heroTransitionNamespace

    var body: some View {
        NavigationStack {
            MenuView(heroTransitionNamespace: heroTransitionNamespace)
        }
    }
}

#Preview {
    MenuViewPreviewWrapper()
}
#endif

//
//  MenuView.swift
//  OSSM Control
//

import SwiftUI
import SwiftData

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
    var iosBody: some View {
        ossmPreviewImageView()
            .padding(40)


//        HStack(alignment: .bottom) {
//            NavigationLink(value: OSSMPage.strokeEngine){
//                VStack {
//                    Text("Stroke Engine")
//                        .fontDesign(.rounded)
//                        .fontWeight(.black)
//                    HStack {
//                        VStack(spacing: 0){
//                            Image(systemName: "brain.fill")
//                            ossmImage
//                                .frame(width: 42, height: 42)
//                        }
//                        .frame(maxWidth: .infinity)
//                        .padding(4)
//                        .padding(.top, 4)
//                        .background {
//                            RoundedRectangle(cornerRadius: 12)
//                                .stroke(lineWidth: 4)
//                        }
//                        VStack(spacing: 0){
//                            Image(systemName: "brain.fill").opacity(0)
//                            Image(systemName: "iphone.radiowaves.left.and.right")
//                                .symbolRenderingMode(.monochrome)
//                                .frame(width: 42, height: 42)
//                                .font(.largeTitle)
//                                .background {
//                                    GeometryReader { geo in
//                                        Rectangle()
//                                            .foregroundStyle(.clear)
//                                            .onAppear {
//                                                symbolSize = geo.size
//                                            }
//                                    }
//                                }
//                        }
//                        .frame(maxWidth: .infinity)
//                        .padding(4)
//                    }
//                    .padding(.bottom, 6)
//                }
//                    .frame(maxWidth: .infinity)
//
//            }.matchedTransitionSource(id: "strokeEngineTitleZoom", in: heroTransitionNamespace)
//            NavigationLink(value: OSSMPage.streaming){
//                VStack {
//                    Text("Streaming")
//                        .fontDesign(.rounded)
//                        .fontWeight(.black)
//                    HStack {
//                        VStack(spacing: 0){
//                            Image(systemName: "brain.fill").opacity(0)
//                            ossmImage
//                                .frame(width: 42, height: 42)
//                        }
//                        .frame(maxWidth: .infinity)
//                        .padding(4)
//                        .padding(.top, 4)
//                        
//                        VStack(spacing: 0){
//                            Image(systemName: "brain.fill")
//                            Image(systemName: "iphone.radiowaves.left.and.right")
//                                .frame(width: 42, height: 42)
//                                .font(.largeTitle)
//                                .symbolRenderingMode(.monochrome)
//                                .background {
//                                    GeometryReader { geo in
//                                        Rectangle()
//                                            .foregroundStyle(.clear)
//                                            .onAppear {
//                                                symbolSize = geo.size
//                                            }
//                                    }
//                                }
//                        }
//                        .frame(maxWidth: .infinity)
//                        .padding(4)
//                        .padding(.top, 4)
//                        .background {
//                            RoundedRectangle(cornerRadius: 12)
//                                .stroke(lineWidth: 4)
//                        }
//                    }
//                    .padding(.bottom, 6)
//                }
//                    .frame(maxWidth: .infinity)
//
//            }.matchedTransitionSource(id: "streamingTitleZoom", in: heroTransitionNamespace)
//        }
//        .buttonBorderShape(.roundedRectangle(radius: 24))
//        .buttonStyle(.glassProminent)
//        .frame(maxHeight: .infinity, alignment: .bottom)
//        .padding()
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

#Preview {
    @Previewable @Namespace var heroTransitionNamespace

    NavigationStack{
        MenuView(heroTransitionNamespace: heroTransitionNamespace)
    }
}

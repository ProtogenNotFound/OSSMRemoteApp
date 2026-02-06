//
//  StreamingView.swift
//  OSSM Control
//

import SwiftUI

private struct ControlPoint: Identifiable, Equatable {
    let id: UUID
    var x: CGFloat
    var y: CGFloat

    init(id: UUID = UUID(), x: CGFloat, y: CGFloat) {
        self.id = id
        self.x = x
        self.y = y
    }
}

struct StreamingView: View {
    @EnvironmentObject private var bleManager: OSSMBLEManager
    @State private var points: [ControlPoint] = [
        ControlPoint(x: 0.0, y: 0.5),
        ControlPoint(x: 1.0, y: 0.5)
    ]
    @State private var activeDragID: UUID?
    @State private var pendingRemovalID: UUID?

    @State private var playing: Bool = false
    @State private var playTask: Task<Void, Never>?

    @State private var playbuttonHeight: CGFloat = 0
    @State private var scrollCapsuleWidth: CGFloat = 0

    @State private var scrollValue: Double? = 0.5
    @State private var time: Double = 0.5

    private let pointRadius: CGFloat = 10
    private let canvasInset: CGFloat = 12
    private let minGap: CGFloat = 0.02
    private let removalGap: CGFloat = 0.03

    @State private var depth = 0.0
    @State private var stroke = 0.0


    var body: some View {
        VStack {
            GeometryReader { geometry in
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.gray.opacity(0.4), lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    if !playing {
                                        if activeDragID == nil {
                                            if let newID = addPoint(at: value.location, in: geometry.size) {
                                                activeDragID = newID
                                            }
                                        }
                                        if let activeID = activeDragID,
                                           let point = points.first(where: { $0.id == activeID }) {
                                            updatePoint(point, to: value.location, in: geometry.size)
                                        }
                                    }
                                }
                                .onEnded { value in
                                    if !playing {
                                        if let activeID = activeDragID,
                                           let point = points.first(where: { $0.id == activeID }) {
                                            finalizePoint(point, to: value.location, in: geometry.size)
                                        }
                                        activeDragID = nil
                                        pendingRemovalID = nil
                                    }
                                }
                        )

                    Path { path in
                        guard let first = points.first else { return }
                        path.move(to: pointToView(first, in: geometry.size))
                        for point in points.dropFirst() {
                            path.addLine(to: pointToView(point, in: geometry.size))
                        }
                    }
                    .stroke(Color.blue, lineWidth: 2)
                    .saturation(!playing ? 1.0 : 0)

                    ForEach(points) { point in
                        Circle()
                            .fill(point.id == pendingRemovalID ? Color.red.opacity(0.8) : Color.white)
                            .overlay(
                                Circle().stroke(point.id == pendingRemovalID ? Color.red : Color.blue, lineWidth: 2)
                            )
                            .frame(width: pointRadius * 2, height: pointRadius * 2)
                            .position(pointToView(point, in: geometry.size))
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        if !playing {
                                            activeDragID = point.id
                                            updatePoint(point, to: value.location, in: geometry.size)
                                        }
                                    }
                                    .onEnded { value in
                                        if !playing {
                                            finalizePoint(point, to: value.location, in: geometry.size)
                                            activeDragID = nil
                                            pendingRemovalID = nil
                                        }
                                    }
                            )
                            .saturation(!playing ? 1.0 : 0)
                    }
                }
            }
            .glassEffect(in: .rect(cornerRadius: 16))
            .aspectRatio(1.0, contentMode: .fit)
                GeometryReader { geo in
                    let size = geo.size
                    let horizontalPadding = size.width / 2
                    let spacing = 12.0
                    ScrollView(.horizontal) {
                        HStack(spacing: spacing){
                            ForEach(Array(stride(from: 0.5, to: 20, by: 0.1)), id: \.self){val in
                                let whole = floor(val) == val
                                Divider()
                                    .background(whole ? .primary : .secondary)
                                    .frame(width: 0, height: size.height - (whole ? 10 : 20), alignment: .center)
                                    .frame(maxHeight: size.height - 8)
                                    .id(val)
                            }
                        }
                        .frame(height: size.height)
                        .scrollTargetLayout()
                    }
                    .scrollIndicators(.hidden)
                    .scrollTargetBehavior(.viewAligned)
                    .scrollPosition(id: $scrollValue, anchor: .center)
                    .onChange(of: scrollValue) { _, newValue in
                        if let newValue {
                            time = newValue
                        }
                    }
                    .background(alignment: .center, content: {
                        Capsule()
                            .frame(width: 12, height: size.height)
                            .glassEffect(.clear)
                    })
                    .safeAreaPadding(.horizontal, horizontalPadding)
                }.frame(height: playbuttonHeight)
                .mask {
                    Rectangle()
                        .scaleEffect(x: 0.99, anchor: .center)
                        .blur(radius: 4)
                }
                .overlay {
                    HStack {
                        Button("Play", systemImage: playing ? "pause.fill" : "play.fill") {
                            playing.toggle()
                        }
                        .contentTransition(.symbolEffect(.replace.magic(fallback: .downUp), options: .speed(2)))
                        .background {
                            GeometryReader { geo in
                                Rectangle()
                                    .fill(.clear)
                                    .onAppear {
                                        playbuttonHeight = geo.size.height
                                    }
                            }
                        }
                        .font(.title)
                        .buttonBorderShape(.circle)
                        .buttonStyle(.glassProminent)
                        .labelStyle(.iconOnly)
                        Spacer()
                        Text("\(time, specifier: "%.1f")s")
                            .font(.callout.monospacedDigit())
                            .contentTransition(.numericText())
                            .padding(.horizontal, 16)
                            .frame(height: playbuttonHeight)
                            .glassEffect()
                            .animation(.easeInOut(duration: 0.1), value: time)
                    }
                }
            Group{
                Section("Stroke"){
                    Slider(value: $stroke, in: 0...100)
                }
                Section("Depth"){
                    Slider(value: $depth, in: 0...100)
                }
            }
        }.safeAreaPadding(16)
            .animation(.easeIn(duration: 0.1), value: playing)
            .onChange(of: playing) { _, isPlaying in
                if isPlaying {
                    startStreamingLoop()
                } else {
                    stopStreamingLoop()
                }
            }
            .onDisappear {
                stopStreamingLoop()
                playing = false
            }
    }


    private func pointToView(_ point: ControlPoint, in size: CGSize) -> CGPoint {
        let rect = canvasRect(in: size)
        return CGPoint(
            x: rect.minX + point.x * rect.width,
            y: rect.minY + (1.0 - point.y) * rect.height
        )
    }

    private func viewToPoint(_ location: CGPoint, in size: CGSize) -> ControlPoint {
        let rect = canvasRect(in: size)
        let clampedX = max(rect.minX, min(rect.maxX, location.x))
        let clampedY = max(rect.minY, min(rect.maxY, location.y))
        let x = max(0.0, min(1.0, (clampedX - rect.minX) / rect.width))
        let y = max(0.0, min(1.0, 1.0 - ((clampedY - rect.minY) / rect.height)))
        return ControlPoint(x: x, y: y)
    }

    private func canvasRect(in size: CGSize) -> CGRect {
        CGRect(
            x: canvasInset,
            y: canvasInset,
            width: max(1, size.width - canvasInset * 2),
            height: max(1, size.height - canvasInset * 2)
        )
    }

    private func addPoint(at location: CGPoint, in size: CGSize) -> UUID? {
        let newPoint = viewToPoint(location, in: size)
        let existingIndex = points.firstIndex {
            let dx = $0.x - newPoint.x
            let dy = $0.y - newPoint.y
            return hypot(dx, dy) < (pointRadius / max(size.width, 1))
        }
        if existingIndex != nil { return nil }

        var updated = points
        updated.append(newPoint)
        updated.sort { $0.x < $1.x }

        if let first = updated.first, let last = updated.last {
            if first.id == newPoint.id {
                updated[updated.count - 1].y = first.y
            } else if last.id == newPoint.id {
                updated[0].y = last.y
            }
        }

        points = updated
        return newPoint.id
    }

    private func updatePoint(_ point: ControlPoint, to location: CGPoint, in size: CGSize) {
        guard let index = points.firstIndex(of: point) else { return }
        var updated = points
        var candidate = viewToPoint(location, in: size)

        if index == 0 {
            candidate.x = 0.0
        } else if index == updated.count - 1 {
            candidate.x = 1.0
        } else {
            let minX = updated[index - 1].x + minGap
            let maxX = updated[index + 1].x - minGap
            candidate.x = max(minX, min(maxX, candidate.x))
        }

        updated[index].x = candidate.x
        updated[index].y = candidate.y

        if index == 0 {
            updated[updated.count - 1].y = candidate.y
        } else if index == updated.count - 1 {
            updated[0].y = candidate.y
        }

        points = updated

        if index != 0 && index != updated.count - 1 {
            let previous = updated[index - 1]
            let next = updated[index + 1]
            let shouldRemove = (updated[index].x - previous.x) < removalGap
                || (next.x - updated[index].x) < removalGap
            if activeDragID == updated[index].id && shouldRemove {
                pendingRemovalID = updated[index].id
            } else if pendingRemovalID == updated[index].id {
                pendingRemovalID = nil
            }
        } else if pendingRemovalID == updated[index].id {
            pendingRemovalID = nil
        }
    }

    private func finalizePoint(_ point: ControlPoint, to location: CGPoint, in size: CGSize) {
        updatePoint(point, to: location, in: size)
        guard let index = points.firstIndex(where: { $0.id == point.id }) else { return }
        guard index != 0 && index != points.count - 1 else { return }

        let previous = points[index - 1]
        let next = points[index + 1]
        if (points[index].x - previous.x) < removalGap || (next.x - points[index].x) < removalGap {
            points.remove(at: index)
        }
    }

    private func startStreamingLoop() {
        playTask?.cancel()
        playTask = Task {
            while !Task.isCancelled {
                let snapshot = await MainActor.run {
                    (points: points, time: time, stroke: stroke, depth: depth, playing: playing)
                }

                guard snapshot.playing else { return }
                guard snapshot.points.count >= 2 else {
                    try? await Task.sleep(for: .milliseconds(50))
                    continue
                }

                let loopPoints = snapshot.points
                for index in 0..<(loopPoints.count - 1) {
                    if Task.isCancelled { return }
                    let current = loopPoints[index]
                    let next = loopPoints[index + 1]
                    let segmentSeconds = max(0, Double(next.x - current.x)) * snapshot.time
                    let segmentMilliseconds = max(0, Int((segmentSeconds * 1000).rounded()))
                    let position = scaledPosition(
                        normalized: Double(next.y),
                        stroke: snapshot.stroke,
                        depth: snapshot.depth
                    )

                    bleManager.streamGoTo(position: position, time: segmentMilliseconds)

                    if segmentMilliseconds > 0 {
                        try? await Task.sleep(for: .milliseconds(segmentMilliseconds))
                    }
                }
            }
        }
    }

    private func stopStreamingLoop() {
        playTask?.cancel()
        playTask = nil
    }

    private func scaledPosition(normalized: Double, stroke: Double, depth: Double) -> Int {
        let clampedNormalized = max(0.0, min(1.0, normalized))
        let maxValue = max(0.0, min(100.0, depth))
        let minValue = max(0.0, maxValue - max(0.0, stroke))
        let scaled = minValue + clampedNormalized * (maxValue - minValue)
        return Int(round(max(0.0, min(100.0, scaled))))
    }
}


#Preview {
    StreamingView()
}

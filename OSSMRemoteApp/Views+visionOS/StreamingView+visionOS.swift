//
//  StreamingView+visionOS.swift
//  OSSM Control
//

import SwiftUI

#if os(visionOS)
extension StreamingView {
    var visionBody: some View {
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
                        .labelStyle(.iconOnly)
                        Spacer()
                        Text("\(time, specifier: "%.1f")s")
                            .font(.callout.monospacedDigit())
                            .contentTransition(.numericText())
                            .padding(.horizontal, 16)
                            .frame(height: playbuttonHeight)
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
}
#endif

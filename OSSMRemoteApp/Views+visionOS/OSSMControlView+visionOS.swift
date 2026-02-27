//
//  OSSMControlView+visionOS.swift
//  OSSM Control
//

import SwiftUI
import CoreBluetooth

#if os(visionOS)
extension OSSMControlView {
    var visionOSStatusMenu: some View {
        statusMenu
            .glassBackgroundEffect()
    }
    var visionBody: some View {
        NavigationStack (path: $path){
            Group {
                if bleManager.connectionStatus == .ready {
                    MenuView()
                        .sheet(isPresented: .constant(bleManager.homing)) {
                            HomingSheetView(
                                forward: bleManager.currentRootState.rawValue.contains("forward"),
                                homingPulse: $homingPulse,
                                onAppear: startHomingPulseLoop,
                                onDisappear: stopHomingPulseLoop
                            )
                            .interactiveDismissDisabled()
                            .presentationDetents([.medium])
                        }
                } else if savedUUID != nil {
                    savedDeviceReconnectView
                } else if !bleManager.discoveredPeripherals.isEmpty {
                    deviceListView
                } else {
                    scanningView
                }
            }
            .navigationDestination(for: OSSMPage.self) { page in
                switch page {
                case .menu:
                    MenuView()
                case .simplePenetration:
                    SimplePenetrationView()
                        .ornament(attachmentAnchor: .scene(.topTrailing)) {
                            visionOSStatusMenu
                    }
                case .strokeEngine:
                    StrokeEngineView()
                        .ornament(attachmentAnchor: .scene(.topTrailing)) {
                            visionOSStatusMenu
                        }
                case .streaming:
                    StreamingView()
                        .ornament(attachmentAnchor: .scene(.topTrailing)) {
                            visionOSStatusMenu
                        }
                }
            }
            .ornament(attachmentAnchor: .scene(.topTrailing)) {
                visionOSStatusMenu
            }
            .navigationTitle("OSSM Control")
        }
        .frame(minWidth: 510, minHeight: 680)
        .onChange(of: path, { _, newPath in
            let target = newPath.last ?? .menu
            bleManager.navigateTo(target)
        })
        .onChange(of: bleManager.discoveredPeripherals) { _, _ in
            tryConnectIfSaved()
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .onChange(of: bleManager.lastError) { _, newValue in
            if let error = newValue {
                errorMessage = error
                showError = true
            }
        }
        .onChange(of: bleManager.connectionStatus) { _, status in
            if status == .ready {
                path = []
                bleManager.navigateTo(.menu)
            }
        }
    }

    var savedDeviceReconnectView: some View {
        let found = !bleManager.discoveredPeripherals.isEmpty
        return VStack(spacing: 16) {
            Color.primary
                .frame(width: 100, height: 100)
                .mask {
                    Image("ossm")
                        .resizable()
                }
                .overlay(alignment: .topTrailing) {
                    Image(systemName: found ? "antenna.radiowaves.left.and.right.circle.fill" : "magnifyingglass.circle.fill")
                        .symbolRenderingMode(.multicolor)
                        .symbolEffect(.breathe)
                        .foregroundStyle(Color.accentColor)
                        .font(.largeTitle)
                        .offset(x: 10, y: -10)
                        .contentTransition(.symbolEffect(.replace))
                }
                .padding()
                .background(.ultraThickMaterial, in: .rect(cornerRadius: 16))
            ProgressView("\(found ? "Connecting to" : "Looking for") your OSSM")
            if let savedUUID {
                Text(savedUUID)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .animation(.easeInOut, value: found)
        .padding()
    }
}
#endif

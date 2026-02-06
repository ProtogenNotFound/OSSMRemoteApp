//
//  MenuView.swift
//  OSSM Control
//

import SwiftUI

struct MenuView: View {
    @EnvironmentObject private var bleManager: OSSMBLEManager
    @AppStorage("savedUUID") private var savedUUID: String?
    @State private var symbolSize = CGSize(.zero)

    var ossmImage: some View {
        Color.white
            .mask{
                Image("ossm")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
    }

    var body: some View {
        HStack(alignment: .bottom) {
            NavigationLink(value: OSSMPage.strokeEngine){
                VStack {
                    Text("Stroke Engine")
                        .fontDesign(.rounded)
                        .fontWeight(.black)
                    HStack {
                        VStack(spacing: 0){
                            Image(systemName: "brain.fill")
                            ossmImage
                                .frame(width: 42, height: 42)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(4)
                        .padding(.top, 4)
                        .background {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(lineWidth: 4)
                        }
                        VStack(spacing: 0){
                            Image(systemName: "brain.fill").opacity(0)
                            Image(systemName: "iphone.radiowaves.left.and.right")
                                .symbolRenderingMode(.monochrome)
                                .frame(width: 42, height: 42)
                                .font(.largeTitle)
                                .background {
                                    GeometryReader { geo in
                                        Rectangle()
                                            .foregroundStyle(.clear)
                                            .onAppear {
                                                symbolSize = geo.size
                                            }
                                    }
                                }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(4)
                    }
                    .padding(.bottom, 6)
                }
                    .frame(maxWidth: .infinity)

            }
            NavigationLink(value: OSSMPage.streaming){
                VStack {
                    Text("Streaming")
                        .fontDesign(.rounded)
                        .fontWeight(.black)
                    HStack {
                        VStack(spacing: 0){
                            Image(systemName: "brain.fill").opacity(0)
                            ossmImage
                                .frame(width: 42, height: 42)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(4)
                        .padding(.top, 4)
                        
                        VStack(spacing: 0){
                            Image(systemName: "brain.fill")
                            Image(systemName: "iphone.radiowaves.left.and.right")
                                .frame(width: 42, height: 42)
                                .font(.largeTitle)
                                .symbolRenderingMode(.monochrome)
                                .background {
                                    GeometryReader { geo in
                                        Rectangle()
                                            .foregroundStyle(.clear)
                                            .onAppear {
                                                symbolSize = geo.size
                                            }
                                    }
                                }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(4)
                        .padding(.top, 4)
                        .background {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(lineWidth: 4)
                        }
                    }
                    .padding(.bottom, 6)
                }
                    .frame(maxWidth: .infinity)

            }
        }
            .buttonBorderShape(.roundedRectangle(radius: 24))
            .buttonStyle(.glassProminent)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .padding()
    }
}

#Preview {
    NavigationStack{
        MenuView()
    }
}

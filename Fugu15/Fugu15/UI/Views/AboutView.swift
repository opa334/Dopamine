//
//  AboutView.swift
//  Evyrest
//
//  Created by Lakhan Lothiyi on 30/12/2022.
//

import SwiftUI

struct AboutView: View {
    @Environment(\.openURL) var openURL
    @AppStorage("sfw") var sfw = false
    
    let columns = [
        GridItem(.adaptive(minimum: 80))
    ]
    
    let contributors = [
        ("opa334", "http://github.com/opa334"),
        ("evelyneee", "http://github.com/evelyneee"),
        ("sourcelocation", "http://github.com/sourcelocation"),
        ("LinusHenze", "http://github.com/LinusHenze"),
        ("anotherperson", "http://github.com/opa334"),
        ("randomperson", "http://github.com/opa334"),
    ]
    
    var body: some View {
        VStack {
            VStack(spacing: 4) {
                Text("Made by by opa334, évelyne")
                Text("UI by sourcelocation\n Logo and icon by xerus")
                    .font(.footnote)
                    .opacity(0.6)
            }
            Divider()
                .background(.white)
                .padding(.horizontal, 32)
                .opacity(0.25)
            
            VStack {
                Button(action: {
                    openURL(URL(string: "https://github.com/opa334/Fugu15")!)
                }) {
                    HStack {
                        Spacer()
                        Image("github")
                        Text("Source Code")
                        Spacer()
                    }
                    .padding(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.25), lineWidth: 0.5)
                    )
                    .padding(.horizontal, 32)
                }
                Button(action: {
                    openURL(URL(string: "https://github.com/opa334/Fugu15/LICENSE")!)
                }) {
                    HStack {
                        Spacer()
                        Image(systemName: "scroll")
                        Text("License")
                        Spacer()
                    }
                    .padding(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.25), lineWidth: 0.5)
                    )
                    .padding(.horizontal, 32)
                }
            }
            .padding(.vertical)
            
            LazyVGrid(columns: columns) {
                ForEach(contributors, id: \.0) { contributor in
                    Link(destination: URL(string: contributor.1)!) {
                        HStack {
                            Text(contributor.0)
                            Image(systemName: "chevron.right")
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .font(.footnote)
            .opacity(0.6)
            .padding(.bottom)
            .padding(.horizontal, 16)
            
            
            Text("Special thanks:")
                .fixedSize()
                .font(.footnote)
                .opacity(0.6)
            
            HStack(spacing: 12) {
                Button {
                    openURL(URL(string: "https://github.com/pinauten/Fugu15")!)
                } label: {
                    Image("FuguTransparent")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 24)
                        .opacity(0.5)
                }
                
                Button {
                    openURL(URL(string: "https://pinauten.de/")!)
                } label: {
                    Image("PinautenLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 24)
                        .opacity(0.5)
                }
            }
            .padding(.bottom)
            Text("\(sfw ? "OpaA15" : "Dopamine") version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown")\n\(ProcessInfo.processInfo.operatingSystemVersionString)")
                .fixedSize()
                .font(.footnote)
                .opacity(0.6)
        }
        .foregroundColor(.white)
        .multilineTextAlignment(.center)
//        .frame(maxHeight: 600)
    }
}


struct AboutView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

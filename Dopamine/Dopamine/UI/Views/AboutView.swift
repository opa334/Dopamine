//
//  AboutView.swift
//  Evyrest
//
//  Created by Lakhan Lothiyi on 30/12/2022.
//

import SwiftUI

struct AboutView: View {
    @Environment(\.openURL) var openURL
    @State var easterEgg = false
    
    let columns = [
        GridItem(.adaptive(minimum: 100))
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
                Text("Credits_Made_By")
                Text("Credits_Made_By_Subheadline")
                    .font(.footnote)
                    .opacity(0.6)
            }
            Divider()
                .background(.white)
                .padding(.horizontal, 32)
                .opacity(0.25)
            
            VStack {
                Button(action: {
                    openURL(URL(string: "https://github.com/opa334/Dopamine")!)
                }) {
                    HStack {
                        Spacer()
                        Image("github")
                        Text("Credits_Button_Source_Code")
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
                    openURL(URL(string: "https://github.com/opa334/Dopamine/LICENSE")!)
                }) {
                    HStack {
                        Spacer()
                        Image(systemName: "scroll")
                        Text("Credits_Button_License")
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
            
            
            Text("Credits_Header_Special_Thanks")
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
            Group {
                if !easterEgg {
                    Text("Credits_Footer_Dopamine_Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown")\nOS:\(ProcessInfo.processInfo.operatingSystemVersionString)")
                } else {
                    Text(verbatim: "Wait, it's all Evyrest?\nAlways has been.")
                }
            }
            .fixedSize()
            .font(.footnote)
            .opacity(0.6)
            .onTapGesture(count: 5) {
                easterEgg.toggle()
            }
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

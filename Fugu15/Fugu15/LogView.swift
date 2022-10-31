//
//  LogView.swift
//  Fugu15
//
//  Created by Linus Henze on 2022-07-29.
//

import SwiftUI

struct LogView: View {
    @Binding var logText: String
    
    var body: some View {
        ScrollViewReader { reader in
            ZStack {
                Text("Nothing here yet...")
                    .opacity(logText.count > 0 ? 0 : 1)
                
                ScrollView{
                    Text(logText)
                        .padding([.leading, .trailing])
                        .frame(minWidth: 0,
                               maxWidth: .infinity,
                               minHeight: 0,
                               maxHeight: .infinity,
                               alignment: .topLeading)
                        .id("label")
                        .onChange(of: logText, perform: { value in
                            reader.scrollTo("label", anchor: .bottom)
                        })
                        .contextMenu {
                            Button {
                                UIPasteboard.general.string = logText
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                            }
                        }
                }
            }
        }
    }
}

struct LogView_Previews: PreviewProvider {
    @State static var logText = "Example log text\nLine 2\nLine 3"
    
    static var previews: some View {
        LogView(logText: $logText)
    }
}

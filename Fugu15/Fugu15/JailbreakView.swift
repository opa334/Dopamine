//
//  JailbreakView.swift
//  Fugu15
//
//  Created by Linus Henze on 2022-07-29.
//

import SwiftUI
import Fugu15KernelExploit

enum JBStatus {
    case notStarted
    case unsupported
    case inProgress
    case failed
    case done
    
    func text() -> String {
        switch self {
        case .notStarted:
            return "Jailbreak"
            
        case .unsupported:
            return "Unsupported"
            
        case .inProgress:
            return "Jailbreaking..."
            
        case .failed:
            return "Error!"
            
        case .done:
            return "Jailbroken"
        }
    }
    
    func color() -> Color {
        switch self {
        case .notStarted:
            return .accentColor
            
        case .unsupported:
            return .accentColor
            
        case .inProgress:
            return .accentColor
            
        case .failed:
            return .red
            
        case .done:
            return .green
        }
    }
}

struct JailbreakView: View {
    @Binding var logText: String
    
    @State var status: JBStatus = .notStarted
    @State var textStatus1      = "Status: Not running"
    @State var textStatus2      = ""
    @State var textStatus3      = ""
    @State var showSuccessMsg   = false
    
    var body: some View {
        VStack {
            Button(status.text(), action: {
                status = .inProgress
                
                DispatchQueue(label: "Fugu15").async {
                    launchExploit()
                }
            })
                .padding()
                .background(status.color())
                .cornerRadius(10)
                .foregroundColor(Color.white)
                .disabled(status != .notStarted)
            
            Text(textStatus1)
                .padding([.top, .leading, .trailing])
                .font(.headline)
            Text(textStatus2)
                .padding([.leading, .trailing])
                .font(.subheadline)
                .opacity(0.5)
            Text(textStatus3)
                .padding([.leading, .trailing])
                .font(.footnote)
                .opacity(0.4)
        }.alert(isPresented: $showSuccessMsg) {
            Alert(title: Text("Success"), message: Text("Post environment started successfully, system wide injection will only affect newly spawned processes for now!"), dismissButton: .default(Text("OK")))
        }
    }
    
    func print(_ text: String, ender: String = "\n") {
        NSLog(text)
        logText += text + ender
    }
    
    func statusUpdate(_ s: String) {
        textStatus3 = textStatus2
        textStatus2 = textStatus1
        textStatus1 = s
    }
    
    func launchExploit() {
        do {
            statusUpdate("Status: Launching kexploitd")
            
            try Fugu15.launchKernelExploit(oobPCI: Bundle.main.bundleURL.appendingPathComponent("oobPCI")) { msg in
                if status != .done {
                    DispatchQueue.main.async {
                        if msg.hasPrefix("Status: ") {
                            statusUpdate(msg)
                        }
                        
                        print(msg)
                    }
                }
            }
            
            try Fugu15.startEnvironment()
            //try Fugu15.launch_iDownload()
            
            DispatchQueue.main.async {
                statusUpdate("Status: Done!")
                status = .done
                showSuccessMsg = true
            }
        } catch {
            DispatchQueue.main.async {
                print("Fugu15 error: \(error)")
                status = .failed
            }
        }
    }
}

struct JailbreakView_Previews: PreviewProvider {
    @State static var logText = ""
    
    static var previews: some View {
        JailbreakView(logText: $logText)
    }
}

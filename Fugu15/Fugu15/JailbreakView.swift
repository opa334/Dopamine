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

enum ActiveAlert {
    case jailbroken, hidden, uninstall
}

struct JailbreakView: View {
    @Binding var logText: String
    
    @State var status: JBStatus = .notStarted
    @State var textStatus1      = "Status: Not running"
    @State var textStatus2      = ""
    @State var textStatus3      = ""
    @State var showAlert                = false
    @State var activeAlert: ActiveAlert = .jailbroken
    
    var body: some View {
        VStack {
            Button(status.text(), action: {
                status = .inProgress
                DispatchQueue(label: "Fugu15").async {
                    launchExploit()
                }
            })
            .contextMenu {
                Button(action: {
                    execCmd(args: [CommandLine.arguments[0], "hide_environment"])
                    activeAlert = .hidden
                    showAlert = true
                }, label: {
                    Label("Hide Environment", systemImage: "eye.slash")
                })
                Button(role: .destructive, action: {
                    activeAlert = .uninstall
                    showAlert = true
                }, label: {
                    Label("Uninstall Environment", systemImage: "trash")
                })
            }
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
        }.alert(isPresented: $showAlert) {
            switch activeAlert {
                case .jailbroken:
                    return  Alert(title: Text("Success"), message: Text("Jailbreak initialized. A userspace reboot is needed to finalize it!"), dismissButton: .default(Text("Userspace Reboot"), action: {
                        execCmd(args: ["/var/jb/usr/bin/launchctl", "reboot", "userspace"])
                    }))
                case .hidden:
                    return Alert(title: Text("Environment Hidden"), message: Text("Jailbreak environment fully hidden until the next rejailbreak"), dismissButton: .default(Text("OK")))
                case .uninstall:
                    return Alert(title: Text("Uninstall"),
                        message: Text("Are you sure you want to uninstall the jailbreak environment? This will delete everything about your jailbreak including packages, tweaks and apps."),
                        primaryButton: .cancel(),
                        secondaryButton: .default(Text("Uninstall Environment")) {
                            execCmd(args: [CommandLine.arguments[0], "uninstall_environment"])
                    })
            }  
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
                activeAlert = .jailbroken
                showAlert = true
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

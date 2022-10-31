//
//  RemoveFuguInstall.swift
//  Fugu15
//
//  Created by Linus Henze on 2022-07-29.
//

import SwiftUI

struct RemoveFuguInstall: View {
    static var bundleID: String? = {
        let path = Bundle.main.bundleURL
        
        guard let data = try? Data(contentsOf: path.appendingPathComponent("FuguInstall.plist")) else {
            return nil
        }
        
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return nil
        }
        
        return plist["InstalledBy"] as? String
    }()
    
    @Binding var isPresented: Bool
    
    @State var appName = "Unknown"
    @State var showSpinner = false
    
    var body: some View {
        ZStack {
            VStack {
                HStack {
                    Text("Remove “\(appName)” App?")
                        .font(.largeTitle)
                        .fontWeight(.heavy)
                        .padding()
                    Spacer()
                }
                
                HStack {
                    Text("Fugu15 was installed via the “\(appName)” App. This App is no longer needed and can therefore be removed.")
                        .padding([.leading, .trailing, .bottom])
                    Spacer()
                }
                
                Spacer()
                
                HStack {
                    Button(action: {
                        showSpinner = true
                        DispatchQueue(label: "Uninstall").async {
                            if let id = Self.bundleID {
                                let workspace = LSApplicationWorkspace.default()!
                                workspace.uninstallApplication(id, withOptions: nil, using: {})
                            }
                            
                            DispatchQueue.main.asyncAfter(deadline: .now().advanced(by: .milliseconds(500)), execute: .init(block: {
                                showSpinner = false
                                isPresented = false
                            }))
                        }
                    }) {
                        Text("Remove “\(appName)”")
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .foregroundColor(Color.white)
                            .background(Color.accentColor)
                            .cornerRadius(10)
                    }
                }.padding([.leading, .trailing])
                
                Button("Keep “\(appName)”") {
                    isPresented = false
                }
                .padding()
                    .padding(.bottom)
            }
                .padding()
                .disabled(showSpinner)
            
            if showSpinner {
                VStack() {
                    ProgressView()
                        .scaleEffect(2.0, anchor: .center)
                        .padding()
                        .padding()
                        .padding()
                        .colorInvert()
                }
                    .background(Color.primary.opacity(0.8))
                    .cornerRadius(22)
                    .ignoresSafeArea(.all)
            }
        }.onAppear {
            if let id = Self.bundleID {
                if let app = LSApplicationProxy(forIdentifier: id) {
                    if let name = app.localizedShortName {
                        appName = name
                    }
                }
            }
        }.onDisappear {
            _ = execCmd(args: [CommandLine.arguments[0], "removeFuguInstallPlist"])
        }
    }
    
    static func shouldShow() -> Bool {
        guard let id = bundleID else {
            return false
        }
        
        if let app = LSApplicationProxy(forIdentifier: id) {
            if app.isInstalled {
                return true
            }
        }
        
        return false
    }
}

struct RemoveFuguInstall_Previews: PreviewProvider {
    @State static var isPresented = true
    
    static var previews: some View {
        RemoveFuguInstall(isPresented: $isPresented)
    }
}

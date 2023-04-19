//
//  SettingsView.swift
//  Fugu15
//
//  Created by exerhythm on 02.04.2023.
//

import SwiftUI

struct SettingsView: View {
    
    @AppStorage("totalJailbreaks") var totalJailbreaks: Int = 0
    @AppStorage("successfulJailbreaks") var successfulJailbreaks: Int = 0
    
    @AppStorage("verboseLogs") var verboseLogs: Bool = false
    @AppStorage("tweakInjection") var tweakInjection: Bool = true
    @AppStorage("enableiDownload") var enableiDownload: Bool = false
    
    @State var rootPasswordChangeAlertShown = false
    @State var rootPasswordInput = "alpine"
    
    var body: some View {
        VStack {
            Text("Settings")
            Divider()
                .background(.white)
                .padding(.horizontal, 32)
                .opacity(0.25)
            
            VStack(spacing: 10) {
                Toggle("Tweak Injection", isOn: $tweakInjection)
                Toggle("iDownload", isOn: $enableiDownload)
                Toggle("Verbose Logs", isOn: $verboseLogs)
                
                VStack {
                    if isJailbroken() {
                        Button(action: {
                            rootPasswordChangeAlertShown.toggle()
                        }) {
                            HStack {
                                Image(systemName: "key")
                                Text("Set Root Password")
                                    .lineLimit(1)
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.white.opacity(0.25), lineWidth: 0.5)
                            )
                        }
                        .padding(.bottom)
                    }
                    VStack {
                        Button(action: {
                            changeEnvironmentVisibility(hidden: !isEnvironmentHidden())
                        }) {
                            HStack {
                                Image(systemName: isEnvironmentHidden() ? "eye" : "eye.slash")
                                Text("\(isEnvironmentHidden() ? "Unhide" : "Hide") Jailbreak")
                                    .lineLimit(1)
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.white.opacity(0.25), lineWidth: 0.5)
                            )
                        }
                        Button(action: {
                            rootPasswordChangeAlertShown.toggle()
                        }) {
                            HStack {
                                Image(systemName: "trash")
                                Text("Remove Jailbreak")
                                    .lineLimit(1)
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.white.opacity(0.25), lineWidth: 0.5)
                            )
                        }
                        Text("\"Hide Jailbreak\" temporarily removes jailbreak-related files until next jailbreak")
                            .font(.footnote)
                            .opacity(0.6)
                            .padding(.top, 2)
                    }
                }
                .padding(.top, 12)
            }
            .tint(.accentColor)
            .padding(.vertical, 16)
            .padding(.horizontal, 32)
            
            Divider()
                .background(.white)
                .padding(.horizontal, 32)
                .opacity(0.25)
            VStack(spacing: 6) {
                Text("Device is \(isBootstrapped() ? "" : "not ")bootstrapped")
                    .font(.footnote)
                    .opacity(0.6)
                Text("Success rate: \(successRate())% (\(successfulJailbreaks)/\(totalJailbreaks))")
                    .font(.footnote)
                    .opacity(0.6)
            }
            .padding(.top, 2)
            
            
            ZStack {}
                .textFieldAlert(isPresented: $rootPasswordChangeAlertShown) { () -> TextFieldAlert in
                    TextFieldAlert(title: "Change root password", message: "", text: Binding<String?>($rootPasswordInput))
                }
                .frame(maxHeight: 0)
            
        }
        .foregroundColor(.white)
    }
    
    func successRate() -> String {
        if totalJailbreaks == 0 {
            return "-"
        } else {
            return String(format: "%.1f", Double(successfulJailbreaks) / Double(totalJailbreaks) * 100)
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

extension View {
    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .leading,
        @ViewBuilder placeholder: () -> Content) -> some View {

        ZStack(alignment: alignment) {
            placeholder().opacity(shouldShow ? 1 : 0)
            self
        }
    }
}

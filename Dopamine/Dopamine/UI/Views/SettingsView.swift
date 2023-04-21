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
    
    @State var removeJailbreakAlertShown = false
    
    @State var isEnvironmentHiddenState = isEnvironmentHidden()
    
    var body: some View {
        VStack {
            Text("Settings_Title")
            Divider()
                .background(.white)
                .padding(.horizontal, 32)
                .opacity(0.25)
            
            VStack(spacing: 10) {
                Toggle("Options_Tweak_Injection", isOn: $tweakInjection)
                Toggle("Options_iDownload", isOn: $enableiDownload)
                Toggle("Options_Verbose_Logs", isOn: $verboseLogs)
                
                VStack {
                    if isJailbroken() {
                        Button(action: {
                            rootPasswordChangeAlertShown.toggle()
                        }) {
                            HStack {
                                Image(systemName: "key")
                                Text("Button_Set_Root_Password")
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
                            isEnvironmentHiddenState.toggle()
                            changeEnvironmentVisibility(hidden: !isEnvironmentHidden())
                        }) {
                            HStack {
                                Image(systemName: isEnvironmentHiddenState ? "eye" : "eye.slash")
                                Text(isEnvironmentHiddenState ? "Button_Unhide_Jailbreak" : "Button_Hide_Jailbreak")
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
                            removeJailbreakAlertShown = true
                        }) {
                            HStack {
                                Image(systemName: "trash")
                                Text("Button_Remove_Jailbreak")
                                    .lineLimit(1)
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.white.opacity(0.25), lineWidth: 0.5)
                            )
                        }
                        Text("Hint_Hide_Jailbreak")
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
                Text(isBootstrapped() ? "Settings_Footer_Device_Bootstrapped" :  "Settings_Footer_Device_Not_Bootstrapped")
                    .font(.footnote)
                    .opacity(0.6)
                Text("Success_Rate \(successRate())% (\(successfulJailbreaks)/\(totalJailbreaks))")
                    .font(.footnote)
                    .opacity(0.6)
            }
            .padding(.top, 2)
            
            
            ZStack {}
                .textFieldAlert(isPresented: $rootPasswordChangeAlertShown) { () -> TextFieldAlert in
                    TextFieldAlert(title: NSLocalizedString("Popup_Change_Root_Password_Title", comment: ""), message: "", text: Binding<String?>($rootPasswordInput))
                }
                .alert("Settings_Remove_Jailbreak_Alert_Title", isPresented: $removeJailbreakAlertShown, actions: {
                    Button("Settings_Remove_Jailbreak_Alert_Button_Cancel", role: .cancel) { }
                    Button("Settings_Remove_Jailbreak_Alert_Button_Uninstall", role: .destructive) {
                        removeJailbreak()
                    }
                }, message: { Text("Popup_Change_Root_Password_Body") })
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

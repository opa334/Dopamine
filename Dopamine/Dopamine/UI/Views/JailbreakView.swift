//
//  ContentView.swift
//  Fugu15
//
//  Created by sourcelocation.
//

import SwiftUI
import Fugu15KernelExploit

#if os(iOS)
import UIKit
#else
import AppKit
#endif

import Fugu15KernelExploit
import SwiftfulLoadingIndicators

struct JailbreakView: View {
    
    enum JailbreakingProgress: Equatable {
        case idle, jailbreaking, selectingPackageManager, finished
    }
    
    struct MenuOption: Identifiable, Equatable {
        
        static func == (lhs: JailbreakView.MenuOption, rhs: JailbreakView.MenuOption) -> Bool {
            lhs.id == rhs.id
        }
        
        var id = UUID()
        
        var imageName: String
        var title: String
        var view: AnyView? = nil
        var showUnjailbroken: Bool = true
        
        
        var action: (() -> ())? = nil
    }
    
    @State var optionPresentedID: UUID?
    @State var jailbreakingProgress: JailbreakingProgress = .idle
    @State var jailbreakingError: Error?
    
    @State var updateAvailable = false
    @State var showingUpdatePopup = false
    @State var updateChangelog: String? = nil
    
    @State var aprilFirstAlert = whatCouldThisVariablePossiblyEvenMean
    
    @AppStorage("verboseLogsEnabled", store: dopamineDefaults()) var advancedLogsByDefault: Bool = false
    @State var advancedLogsTemporarilyEnabled: Bool = false
    
    var isJailbreaking: Bool {
        jailbreakingProgress != .idle
    }
    
    @AppStorage("sfw", store: dopamineDefaults()) var sfw = false
    
    var menuOptions: [MenuOption] = []
    
    init() {
        menuOptions = [
            .init(imageName: "gearshape", title: NSLocalizedString("Menu_Settings_Title", comment: ""), view: AnyView(SettingsView())),
            .init(imageName: "arrow.clockwise", title: NSLocalizedString("Menu_Restart_SpringBoard_Title", comment: ""), showUnjailbroken: false, action: respring),
            .init(imageName: "arrow.clockwise.circle", title: NSLocalizedString("Menu_Reboot_Userspace_Title", comment: ""), showUnjailbroken: false, action: userspaceReboot),
            .init(imageName: "info.circle", title: NSLocalizedString("Menu_Credits_Title", comment: ""), view: AnyView(AboutView())),
        ]
    }
    
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                
                let shouldShowBackground = optionPresentedID != nil || showingUpdatePopup
                
                Image(whatCouldThisVariablePossiblyEvenMean ? "Clouds" : "Wallpaper")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .edgesIgnoringSafeArea(.all)
                    .blur(radius: 4)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                
                    .scaleEffect(shouldShowBackground ? 1.2 : 1.4)
                    .animation(.spring(), value: shouldShowBackground)
                
                VStack {
                    Spacer()
                    header
                    Spacer()
                    menu
                    if !isJailbreaking {
                        Spacer()
                        Spacer()
                    }
                    bottomSection
                    updateButton
                    if !isJailbreaking {
                        Spacer()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .blur(radius: shouldShowBackground ? 4 : 0)
                .scaleEffect(shouldShowBackground ? 0.85 : 1)
                .opacity(showingUpdatePopup ? 0 : 1)
                .animation(.spring(), value: updateAvailable)
                .animation(.spring(), value: shouldShowBackground)
                
                Color.black
                    .ignoresSafeArea()
                    .opacity(shouldShowBackground ? 0.6 : 0)
                    .animation(.spring(), value: shouldShowBackground)
                    .onTapGesture {
                        if optionPresentedID != nil {
                            optionPresentedID = nil
                        }
                    }
                ZStack {
                    ForEach(menuOptions) { option in
                        option.view?
                            .padding(.vertical)
                            .background(showingUpdatePopup ? nil : MaterialView(.systemUltraThinMaterialDark)
                                        //                    .opacity(0.8)
                                .cornerRadius(16))
                            .opacity(option.id == optionPresentedID ? 1 : 0)
                            .animation(.spring().speed(1.5), value: optionPresentedID != nil)
                    }
                    
                    UpdateDownloadingView(shown: $showingUpdatePopup, changelog: updateChangelog ?? NSLocalizedString("Changelog_Unavailable_Text", comment: "")/*"""
                                                                                                                                                                 Added support for iOS 15.0 - 15.1.
                                                                                                                                                                 Improved the app's compatibility with various iOS devices.
                                                                                                                                                                 Fixed bugs related to the installation of certain tweaks and packages.
                                                                                                                                                                 Added new options for customizing the app's interface and settings.
                                                                                                                                                                 """*/)
                    .opacity(showingUpdatePopup ? 1 : 0)
                    .animation(.spring().speed(1.5), value: showingUpdatePopup)
                }
                .frame(maxWidth: showingUpdatePopup ? .infinity : 320)
                .scaleEffect(shouldShowBackground ? 1 : 0.9)
                .opacity(shouldShowBackground ? 1 : 0)
                .animation(.spring().speed(1.5), value: shouldShowBackground)
            }
        }
        .onAppear {
            Task {
                do {
                    try await checkForUpdates()
                } catch {
                    Logger.log(error, type: .error, isStatus: false)
                }
            }
        }
        .alert("🤑 NEW SPONSORSHIP OFFER 🤑 \n\n⚠️ Hello iOS \(UIDevice.current.systemVersion) user! 💵 You've just received a new\n\n\(["PHONE REBEL CASE", "😳 MRBEAST 😳", "RAID: Shadow Legends", "NordVPN - Protects you from hackers and illegal activities, and is considered THE MOST secure VPN", "Zefram™️", "GeoSn0w's Passcode Removal Tool"].randomElement()!)\n\nsponsorship offer 💰💰💰 Would you like to accept it? 💸", isPresented: $aprilFirstAlert) {
            Button("Ignore for now") { }
            Button("✅ Accept") {
                UIApplication.shared.open(.init(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")!)
            }
        }
    }
    
    
    @ViewBuilder
    var header: some View {
        let tint = whatCouldThisVariablePossiblyEvenMean ? Color.black : .white
        HStack {
            VStack(alignment: .leading) {
                Image(whatCouldThisVariablePossiblyEvenMean ? "DopamineLogo2" : "DopamineLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 200)
                    .padding(.top)
                
                Text("Title_Supported_iOS_Versions")
                    .font(.subheadline)
                    .foregroundColor(tint)
                Text("Title_Made_By")
                    .font(.subheadline)
                    .foregroundColor(tint.opacity(0.5))
            }
            Spacer()
        }
        .padding()
        .frame(maxWidth: 340, maxHeight: nil)
        .animation(.spring(), value: isJailbreaking)
    }
    
    @ViewBuilder
    var menu: some View {
        VStack {
            ForEach(menuOptions) { option in
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    if option.view != nil {
                        optionPresentedID = option.id
                    } else if let action = option.action {
                        action()
                    }
                } label: {
                    HStack {
                        Label(title: { Text(option.title) }, icon: { Image(systemName: option.imageName) })
                            .foregroundColor(Color.white)
                        
                        Spacer()
                        
                        if option.view != nil {
                            Image(systemName: Locale.characterDirection(forLanguage: Locale.current.languageCode ?? "") == .rightToLeft ? "chevron.left" : "chevron.right")
                                .font(.body)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(16)
                    .background(Color(red: 1, green: 1, blue: 1, opacity: 0.00001))
                }
                .buttonStyle(.plain)
                .disabled(!option.showUnjailbroken && !isJailbroken())
                
                if menuOptions.last != option {
                    Divider()
                        .background(.white)
                        .opacity(0.5)
                        .padding(.horizontal)
                }
            }
        }
        .padding()
        .background(MaterialView(.systemUltraThinMaterialDark))
        .cornerRadius(16)
        .frame(maxWidth: 320, maxHeight: isJailbreaking ? 0 : nil)
        .opacity(isJailbreaking ? 0 : 1)
        .animation(.spring(), value: isJailbreaking)
    }
    
    @ViewBuilder
    var bottomSection: some View {
        VStack {
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                
                if (dopamineDefaults().array(forKey: "selectedPackageManagers") as? [String] ?? []).isEmpty && !isBootstrapped() {
                    jailbreakingProgress = .selectingPackageManager
                } else {
                    uiJailbreak()
                }
                print(jailbreakingProgress)
            } label: {
                Label(title: {
                    if isJailbroken() {
                        Text("Status_Title_Jailbroken")
                    } else {
                        switch jailbreakingProgress {
                        case .idle:
                            Text("Button_Jailbreak_Title")
                        case .jailbreaking:
                            Text("Status_Title_Jailbreaking")
                        case .selectingPackageManager:
                            Text("Status_Title_Select_Package_Managers")
                        case .finished:
                            if jailbreakingError == nil {
                                Text("Status_Title_Jailbroken")
                            } else {
                                Text("Status_Title_Unsuccessful")
                            }
                        }
                    }}, icon: {
                        ZStack {
                            switch jailbreakingProgress {
                            case .jailbreaking:
                                LoadingIndicator(animation: .doubleHelix, color: .white, size: .small)
                            case .selectingPackageManager:
                                Image(systemName: "shippingbox")
                            case .finished:
                                if jailbreakingError == nil {
                                    Image(systemName: "lock.open")
                                } else {
                                    Image(systemName: "lock.slash")
                                }
                            case .idle:
                                Image(systemName: "lock.open")
                            }
                        }
                    })
                .foregroundColor(whatCouldThisVariablePossiblyEvenMean ? .black : .white)
                .padding()
                .frame(maxWidth: isJailbreaking ? .infinity : 280)
            }
            .disabled(isJailbroken() || isJailbreaking)
            .drawingGroup()
            
            if jailbreakingProgress == .finished || jailbreakingProgress == .jailbreaking {
                Spacer()
                LogView(advancedLogsTemporarilyEnabled: $advancedLogsTemporarilyEnabled, advancedLogsByDefault: $advancedLogsByDefault)
                endButtons
            } else if jailbreakingProgress == .selectingPackageManager {
                PackageManagerSelectionView(onContinue: {
                    uiJailbreak()
                })
                .padding(.horizontal)
            }
        }
        .frame(maxWidth: isJailbreaking ? .infinity : 280, maxHeight: isJailbreaking ? UIScreen.main.bounds.height * 0.65 : nil)
        .padding(.horizontal, isJailbreaking ? 0 : 20)
        .padding(.top, isJailbreaking ? 16 : 0)
        .background(MaterialView(.systemUltraThinMaterialDark)
            .cornerRadius(isJailbreaking ? 20 : 8)
            .ignoresSafeArea(.all, edges: isJailbreaking ? .all : .top)
            .offset(y: isJailbreaking ? 16 : 0)
            .opacity(isJailbroken() ? 0.5 : 1)
        )
        .animation(.spring(), value: isJailbreaking)
    }
    
    @ViewBuilder
    var endButtons: some View {
        switch jailbreakingProgress {
        case .finished:
            //            Button {
            //                userspaceReboot()
            //            } label: {
            //                Label(title: { Text("Reboot Userspace (Finish)") }, icon: {
            //                    Image(systemName: "arrow.clockwise")
            //                })
            //                .foregroundColor(.white)
            //                .padding()
            //                .frame(maxWidth: 280, maxHeight: jailbreakingError != nil ? 0 : nil)
            //                .background(MaterialView(.light)
            //                    .opacity(0.5)
            //                    .cornerRadius(8)
            //                )
            //                .opacity(jailbreakingError != nil ? 0 : 1)
            //            }
            if !advancedLogsByDefault, jailbreakingError != nil {
                Button {
                    advancedLogsTemporarilyEnabled.toggle()
                } label: {
                    Label(title: { Text(advancedLogsTemporarilyEnabled ? "Button_Hide_Logs_Title" : "Button_Show_Logs_Title") }, icon: {
                        Image(systemName: "scroll")
                    })
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: 280, maxHeight: jailbreakingError != nil ? nil : 0)
                    .background(MaterialView(.light)
                        .opacity(0.5)
                        .cornerRadius(8)
                    )
                    .opacity(jailbreakingError != nil ? 1 : 0)
                }
            }
        case .idle:
            Group {}
        case .jailbreaking:
            Group {}
        case .selectingPackageManager:
            Group {}
        }
    }
    
    @ViewBuilder
    var updateButton: some View {
        Button {
            showingUpdatePopup = true
        } label: {
            Label(title: { Text("Button_Update_Available") }, icon: {
                ZStack {
                    if jailbreakingProgress == .jailbreaking {
                        LoadingIndicator(animation: .doubleHelix, color: .white, size: .small)
                    } else {
                        Image(systemName: "arrow.down.circle")
                    }
                }
            })
            .foregroundColor(whatCouldThisVariablePossiblyEvenMean ? .black : .white)
            .padding()
        }
        .frame(maxHeight: updateAvailable && jailbreakingProgress == .idle ? nil : 0)
        .opacity(updateAvailable && jailbreakingProgress == .idle ? 1 : 0)
        .animation(.spring(), value: updateAvailable)
    }
    
    func uiJailbreak() {
        jailbreakingProgress = .jailbreaking
        let dpDefaults = dopamineDefaults()
        dpDefaults.set(dpDefaults.integer(forKey: "totalJailbreaks") + 1, forKey: "totalJailbreaks")
        DispatchQueue(label: "Dopamine").async {
            sleep(1)
            
            jailbreak { e in
                jailbreakingProgress = .finished
                jailbreakingError = e
                
                if e == nil {
                    dpDefaults.set(dpDefaults.integer(forKey: "successfulJailbreaks") + 1, forKey: "successfulJailbreaks")
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    let tweakInjectionEnabled = dpDefaults.bool(forKey: "tweakInjectionEnabled")
                    
                    Logger.log(NSLocalizedString("Restarting Userspace", comment: ""), type: .continuous, isStatus: true)
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        if tweakInjectionEnabled {
                            userspaceReboot()
                        } else {
                            respring()
                        }
                    }
                } else {
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            }
        }
    }
    
    func checkForUpdates() async throws {
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            
            let owner = "opa334"
            let repo = "Dopamine"
            
            // Get the releases
            let releasesURL = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases")!
            let releasesRequest = URLRequest(url: releasesURL)
            let (releasesData, _) = try await URLSession.shared.data(for: releasesRequest)
            let releasesJSON = try JSONSerialization.jsonObject(with: releasesData, options: []) as! [[String: Any]]
            
            if let latestTag = releasesJSON.first?["tag_name"] as? String, latestTag != version {
                updateAvailable = true
                updateChangelog = releasesJSON.first?["body"] as? String
            }
        }
    }
}

struct JailbreakView_Previews: PreviewProvider {
    static var previews: some View {
        JailbreakView()
    }
}

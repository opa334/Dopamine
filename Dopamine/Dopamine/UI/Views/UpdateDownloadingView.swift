//
//  UpdateDownloadingView.swift
//  Fugu15
//
//  Created by sourcelocation on 12/04/2023.
//

import SwiftUI
import SwiftfulLoadingIndicators

struct UpdateDownloadingView: View {
    
    enum UpdateState {
        case changelog, downloading, updating
    }
    
    
    @State var progressDouble: Double = 0
    var downloadProgress = Progress()
    
    @Binding var shown: Bool
    @State var updateState: UpdateState = .changelog
    @State var showLogView = false
    var changelog: String
    
    var body: some View {
        ZStack {
            VStack(spacing: 16) {
                VStack(spacing: 10) {
                    Text("Title_Changelog")
                        .font(.title2)
                    
                    Divider()
                        .background(.white)
                        .padding(.horizontal, 32)
                        .opacity(0.5)
                    ScrollView {
                        Text(try! AttributedString(markdown: changelog, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                            .opacity(0.5)
                            .multilineTextAlignment(.center)
                            .padding(.vertical)
                    }
                }
                
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    updateState = .downloading
                    
                    // 💀 code
                    Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { t in
                        progressDouble = downloadProgress.fractionCompleted
                        
                        if progressDouble == 1 {
                            t.invalidate()
                        }
                    }
                    
                    Task {
                        do {
                            try await downloadUpdateAndInstall()
                            updateState = .updating
                        } catch {
                            showLogView = true
                            Logger.log("Error: \(error.localizedDescription)", type: .error)
                        }
                    }
                    
                } label: {
                    Label(title: { Text("Button_Update")  }, icon: { Image(systemName: "arrow.down") })
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: 280)
                        .background(MaterialView(.light)
                            .opacity(0.5)
                            .cornerRadius(8)
                        )
                }
                .fixedSize()
                
                
                Button {
                    shown = false
                } label: {
                    Label(title: { Text("Button_Cancel")  }, icon: { Image(systemName: "xmark") })
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: 280)
                }
                .fixedSize()
            }
            .opacity(updateState == .changelog ? 1 : 0)
            .animation(.spring(), value: updateState)
            .padding(.vertical, 64)
            
            ZStack {
                VStack(spacing: 150) {
                    VStack(spacing: 10) {
                        Spacer()
                        Text(updateState != .updating ? NSLocalizedString("Update_Status_Downloading", comment: "") : NSLocalizedString("Update_Status_Installing", comment: ""))
                            .font(.title2)
                            .multilineTextAlignment(.center)
                            .drawingGroup()
                        Text(updateState == .downloading ? NSLocalizedString("Update_Status_Subtitle_Please_Wait", comment: "") : NSLocalizedString("Update_Status_Subtitle_Restart_Soon", comment: ""))
                            .opacity(0.5)
                            .multilineTextAlignment(.center)
                            .padding(.bottom, 32)
                    }
                    .animation(.spring(), value: updateState)
                    .frame(height: 225)
                    
                    VStack {
                        if showLogView {
                            LogView(advancedLogsTemporarilyEnabled: .constant(true), advancedLogsByDefault: .constant(true))
                            Text("Update_Log_Hint_Scrollable")
                                .foregroundColor(.white.opacity(0.5))
                                .padding()
                        }
                    }
                    .opacity(showLogView ? 1 : 0)
                    .frame(height: 225)
                }
                ZStack {
                    ZStack {
                        Text("\(Int(progressDouble * 100))%")
                            .font(.title)
                            .opacity(updateState == .downloading ? 1 : 0)
                        LoadingIndicator(animation: .circleRunner, color: .white, size: .medium, speed: .normal)
                            .opacity(updateState == .updating ? 1 : 0)
                    }
                    Circle()
                        .stroke(
                            Color.white.opacity(0.1),
                            lineWidth: updateState == .downloading ? 8 : 4
                        )
                        .animation(.spring(), value: updateState)
                    Circle()
                        .trim(from: 0, to: progressDouble)
                        .stroke(
                            Color.white,
                            style: StrokeStyle(
                                lineWidth: updateState == .downloading ? 8 : 0,
                                lineCap: .round
                            )
                        )
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut, value: progressDouble)
                        .animation(.spring(), value: updateState)
                }
                .frame(height: 128)
                .padding(32)
            }
            .opacity(updateState != .changelog ? 1 : 0)
            .animation(.spring(), value: updateState)
            
        }
        .foregroundColor(.white)
        .frame(maxWidth: 280)
    }
    
    func downloadUpdateAndInstall() async throws {
        let owner = "opa334"
        let repo = "Fugu15"
        
        // Get the releases
        let releasesURL = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases")!
        let releasesRequest = URLRequest(url: releasesURL)
        let (releasesData, _) = try await URLSession.shared.data(for: releasesRequest)
        let releasesJSON = try JSONSerialization.jsonObject(with: releasesData, options: []) as! [[String: Any]]
        
        Logger.log(String(data: releasesData, encoding: .utf8) ?? "none")
        
        // Find the latest release
        guard let latestRelease = releasesJSON.first,
              let assets = latestRelease["assets"] as? [[String: Any]],
              let asset = assets.first(where: { ($0["name"] as! String).contains(".tipa") }),
              let downloadURLString = asset["browser_download_url"] as? String,
              let downloadURL = URL(string: downloadURLString) else {
            throw "Could not find download URL for ipa"
        }
        
        // Download the asset
        try await withThrowingTaskGroup(of: Void.self) { group in
            downloadProgress.totalUnitCount = 1
            group.addTask {
                let (url, _) = try await URLSession.shared.download(from: downloadURL, progress: downloadProgress)
                update(tipaURL: url)
            }
            try await group.waitForAll()
        }
    }
}

struct UpdateDownloadingView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
//            Image("Wallpaper")
//                .resizable()
//                .aspectRatio(contentMode: .fill)
//                .edgesIgnoringSafeArea(.all)
//                .blur(radius: 4)
//                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Color.black
                .opacity(1)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
            UpdateDownloadingView(shown: .constant(true), changelog:
"""
· Added support for iOS 15.0 - 15.1.
· Improved the app's compatibility with various iOS devices.
· Fixed bugs related to the installation of certain tweaks and packages.
· Added new options for customizing the app's interface and settings.
· Added support for iOS 15.0 - 15.1.
· Improved the app's compatibility with various iOS devices.
· Fixed bugs related to the installation of certain tweaks and packages.
· Added new options for customizing the app's interface and settings.
· Added support for iOS 15.0 - 15.1.
· Improved the app's compatibility with various iOS devices.
· Fixed bugs related to the installation of certain tweaks and packages.
· Added new options for customizing the app's interface and settings.
· Added support for iOS 15.0 - 15.1.
· Improved the app's compatibility with various iOS devices.
· Fixed bugs related to the installation of certain tweaks and packages.
· Added new options for customizing the app's interface and settings.
"""
            )
        }
    }
}

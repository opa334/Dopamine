//
//  PackageManagerSelectionView.swift
//  Fugu15
//
//  Created by sourcelocation on 15/04/2023.
//

import SwiftUI
import Fugu15KernelExploit
import SwiftfulLoadingIndicators

struct PackageManagerSelectionView: View {
    
    @Binding var shown: Bool
    
    @State var selectedNames: [String] = []
    
    var reinstall: Bool = false
    
    enum ReinstallStatus {
        case idle, inProgress, finished
    }
    
    @State var reinstallStatus = ReinstallStatus.idle
    
    var onContinue: () -> Void
    
    var packageManagers: [(String, String)] = [
        ("Sileo", "Sileo"),
        ("Zebra", "Zebra")
    ]
    
    var body: some View {
        VStack {
            
            if reinstallStatus == .idle {
                
                Spacer()
                
                HStack(spacing: 48) {
                    ForEach(packageManagers.indices, id: \.self) { pmI in
                        let pm = packageManagers[pmI]
                        let name = pm.0
                        let imageName = pm.1
                        
                        Button {
                            if selectedNames.contains(name) {
                                selectedNames.removeAll(where: { $0 == name })
                            } else {
                                selectedNames.append(name)
                            }
                        } label: {
                            VStack(spacing: 12) {
                                Image(imageName)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 64)
                                
                                HStack {
                                    Text(name)
                                    
                                    let isSelected = selectedNames.contains(name)
                                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(isSelected ? .white : .white.opacity(0.5))
                                }
                            }
                        }
                    }
                }
                
                Text(reinstall ? "Select_Package_Managers_Reinstall_Message" : "Select_Package_Managers_Install_Message")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.vertical)
                    .padding(.horizontal, 32)
                    .multilineTextAlignment(.center)
                
                Spacer()
            }
            
            if reinstallStatus == .idle {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    
                    if !reinstall {
                        onContinue()
                    } else {
                        reinstallStatus = .inProgress
                        
                        DispatchQueue.global(qos: .userInitiated).async {
                            let dpkgPath = rootifyPath(path: "usr/bin/dpkg")
                            if dpkgPath != nil {
                                if selectedNames.contains("Sileo") {
                                    _ = execCmd(args: [dpkgPath!, "-i", Bundle.main.bundlePath + "/sileo.deb"])
                                }
                                if selectedNames.contains("Zebra") {
                                    _ = execCmd(args: [dpkgPath!, "-i", Bundle.main.bundlePath + "/zebra.deb"])
                                }
                            }
                            
                            DispatchQueue.main.async {
                                reinstallStatus = .finished
                            }
                        }
                    }
                } label: {
                    Label(title: { Text(reinstall ? "Reinstall" : "Continue") }, icon: {
                        Image(systemName: reinstall ? "square.and.arrow.down.on.square" : "arrow.right")
                    })
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: 280)
                    .background(MaterialView(.light)
                        .opacity(0.5)
                        .cornerRadius(8)
                    )
                    .opacity(selectedNames.isEmpty ? 0.5 : 1)
                    
                }
                .disabled(selectedNames.isEmpty)
                .animation(.spring(), value: selectedNames)
            } else if reinstallStatus == .inProgress {
                LoadingIndicator(animation: .circleRunner, color: .white)
            } else if reinstallStatus == .finished {
                Text("PM_Reinstall_Done_Text")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.vertical)
                    .padding(.horizontal, 32)
                    .multilineTextAlignment(.center)
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    
                    shown = false
                    reinstallStatus = .idle
                } label: {
                    Label(title: { Text("Close") }, icon: {
                        Image(systemName: "checkmark")
                    })
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: 280)
                    .background(MaterialView(.light)
                        .opacity(0.5)
                        .cornerRadius(8)
                    )
                    .opacity(selectedNames.isEmpty ? 0.5 : 1)
                }
            }
        }
        .foregroundColor(.white)
        .onChange(of: selectedNames) { newValue in
            dopamineDefaults().set(newValue, forKey: "selectedPackageManagers")
        }
    }
}

struct PackageManagerSelectionView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Image("Wallpaper")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .edgesIgnoringSafeArea(.all)
                .blur(radius: 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Color.black
                .opacity(0.5)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
            PackageManagerSelectionView(shown: .constant(true), reinstall: true, onContinue: {
                
            })
                .frame(maxHeight: 300)
        }
    }
}

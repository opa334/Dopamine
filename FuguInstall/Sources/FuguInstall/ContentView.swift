//
//  ContentView.swift
//  jailbreakd
//
//  Created by Linus Henze.
//  Copyright © 2021/2022 Pinauten GmbH. All rights reserved.
//

import SwiftUI
import MachO

import CBindings
import ZIPFoundation

func launchApp(withIdentifier id: String) {
    typealias LaunchType = @convention(c) (_: CFString, _: Bool) -> Int32
    if let hndl = dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices", RTLD_NOW) {
        if let fn = dlsym(hndl, "SBSLaunchApplicationWithIdentifier") {
            let SBSLaunchApplicationWithIdentifier = unsafeBitCast(fn, to: LaunchType.self)
            _ = SBSLaunchApplicationWithIdentifier(id as CFString, false)
        }
    }
}

struct ContentView: View {
    @State var currentStep   = 1
    @State var description   = "Extracting Fugu15.ipa"
    @State var installFailed = false
    @State var errorDesc: String?
    @State var done = false
    @State var bundleID: String?
    
    var body: some View {
        NavigationView {
            VStack() {
                Divider()
                VStack {
                    Spacer()
                    Text(installFailed ? "Fugu15 installation failed!" : done ? "Fugu15 installation completed!" : "Installing Fugu15, please wait...").padding(.bottom)
                    if !done {
                        Text("Step \(currentStep)/8\(installFailed ? " [Failed]" : "")").padding(.top)
                        Text(description).font(.footnote).padding(.top, -5.0).padding(.bottom)
                        if let errorDesc = errorDesc {
                            Text(errorDesc).font(.footnote).padding([.leading, .trailing])
                        }
                    } else {
                        Button("Launch Fugu15") {
                            launchApp(withIdentifier: bundleID!)
                        }
                        .padding(.all)
                        .background(Color.blue)
                        .cornerRadius(10)
                        .foregroundColor(Color.white)
                    }
                    Spacer()
                }
                Spacer()
            }
            .onAppear {
                DispatchQueue(label: "FuguInstall").async {
                    self.doInstall()
                }
            }
            .navigationTitle("FuguInstall")
            .navigationBarTitleDisplayMode(.inline)
        }.navigationViewStyle(.stack)
    }
    
    func nextStep(description: String) {
        DispatchQueue.main.async {
            self.currentStep += 1
            self.description = description
        }
    }
    
    func error(description: String, err: Error? = nil) {
        DispatchQueue.main.async {
            self.description   = description
            if let err = err {
                self.errorDesc = "\(err)"
            }
            
            self.installFailed = true
        }
    }
    
    func getIPA() -> Data? {
        // Open our executable
        do {
            let exe = try Data(contentsOf: Bundle.main.executableURL!)
            let exeEnd = exe.count
            let highest = exe.withUnsafeBytes { ptr in
                let hdr = ptr.baseAddress!.assumingMemoryBound(to: fat_header.self)
                guard hdr.pointee.magic.bigEndian == FAT_MAGIC else {
                    error(description: "Invalid FAT magic!")
                    return 0
                }
                
                let archs = ptr.baseAddress!.advanced(by: MemoryLayout<fat_header>.size).assumingMemoryBound(to: fat_arch.self)
                var currentHighest: UInt32 = 0
                for i in 0..<Int(hdr.pointee.nfat_arch.bigEndian) {
                    let start = archs[i].offset.bigEndian
                    let end   = start + archs[i].size.bigEndian
                    if currentHighest < end {
                        currentHighest = end
                    }
                }
                
                return Int(currentHighest)
            }
            
            let remaining = exeEnd - highest
            guard highest != 0,
                  remaining > 0 else {
                error(description: "Failed to find ipa in FAT!")
                return nil
            }
            
            return exe.subdata(in: highest..<exeEnd)
        } catch let e {
            error(description: "Failed to read ipa!", err: e)
            return nil
        }
    }
    
    func doInstall() {
        // Extract IPA
        guard let ipaData = getIPA() else {
            return
        }
        
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let ipa = docs.appendingPathComponent("ipa")
        let dst = docs.appendingPathComponent("extracted")
        
        do {
            try ipaData.write(to: ipa)
        } catch let e {
            error(description: "Failed to write ipa to disk!", err: e)
            return
        }
        
        try? FileManager.default.removeItem(at: dst)
        try? FileManager.default.createDirectory(at: dst, withIntermediateDirectories: true)
        do {
            try FileManager.default.unzipItem(at: ipa, to: dst)
        } catch let e {
            error(description: "Failed to unzip ipa!", err: e)
            return
        }
        
        nextStep(description: "Getting App infos")
        
        var bundleID: String?
        var appPath:  URL!
        
        do {
            let payload = dst.appendingPathComponent("Payload")
            let apps = try FileManager.default.contentsOfDirectory(atPath: payload.path)
            var found = false
            for app in apps {
                if app.hasSuffix(".app") {
                    guard !found else {
                        error(description: "Attempting to install multiple Apps (not supported)!")
                        return
                    }
                    
                    let infoData = try Data(contentsOf: payload.appendingPathComponent(app).appendingPathComponent("Info.plist"))
                    guard let info = try PropertyListSerialization.propertyList(from: infoData, format: nil) as? [String: Any] else {
                        error(description: "Info.plist is not a Dictionary!")
                        return
                    }
                    
                    guard let id = info["CFBundleIdentifier"] as? String else {
                        error(description: "Info.plist has no/bad CFBundleIdentifier!")
                        return
                    }
                    
                    bundleID = id
                    appPath  = payload.appendingPathComponent(app)
                    found    = true
                }
            }
        } catch let e {
            error(description: "Failed to get App infos!", err: e)
            return
        }
        
        guard let bundleID = bundleID else {
            error(description: "Couldn't get App bundle id!")
            return
        }
        
        self.bundleID = bundleID
        
        do {
            guard let myId = Bundle.main.bundleIdentifier else {
                error(description: "Failed to get my bundle identifier!")
                return
            }
            
            let fuguInstallDict = ["InstalledBy": myId]
            let fuguInstallPlist = try PropertyListSerialization.data(fromPropertyList: fuguInstallDict, format: .xml, options: .zero)
            try fuguInstallPlist.write(to: appPath.unsafelyUnwrapped.appendingPathComponent("FuguInstall.plist"))
        } catch let e {
            error(description: "Failed to create FuguInstall.plist!", err: e)
            return
        }
        
        nextStep(description: "Removing old App (if it exists)")
        
        let workspace = LSApplicationWorkspace.default()!
        workspace.uninstallApplication(bundleID, withOptions: nil)
        
        nextStep(description: "Installing App")
        
        do {
            try workspace.installApplication(dst, withOptions: [
                LSInstallTypeKey: 1,
                "PackageType": "Placeholder"
            ]) { x, y in
                if let info = x as? [String: Any] {
                    if let state = info["Status"] as? String {
                        if let percent = info["PercentComplete"] as? Int {
                            errorDesc = "\(state) [\(percent)%]" // Not an error, just used to log
                        }
                    }
                }
            }
        } catch let e {
            error(description: "Failed to install App!", err: e)
            return
        }
        
        errorDesc = nil
        
        nextStep(description: "Getting App directory")
        
        guard let proxy = LSApplicationProxy(forIdentifier: bundleID) else {
            error(description: "Failed to get LSApplicationProxy for App!")
            return
        }
        
        nextStep(description: "Registering App")
        
        // Let's hope there are no PlugIns...
        workspace.registerApplicationDictionary([
            "ApplicationType": "System",
            "IsDeletable": 1,
            "CFBundleIdentifier": proxy.applicationIdentifier!,
            "Path": proxy.bundleURL!.path,
            "Container": proxy.containerURL!.path
        ])
        
        nextStep(description: "Fixing App permissions")
        
        try? FileManager.default.unzipItem(at: ipa, to: dst)
        
        let res = execCmd(args: [CommandLine.arguments[0], "fixAppPerm", dst.path, proxy.bundleURL!.path])
        guard res == 0 else {
            error(description: "Failed to fix App permissions!")
            return
        }
                                           
        try? FileManager.default.removeItem(at: dst)
        
        nextStep(description: "Installation completed!")
        self.done = true
        
        usleep(100000)
        
        launchApp(withIdentifier: bundleID)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

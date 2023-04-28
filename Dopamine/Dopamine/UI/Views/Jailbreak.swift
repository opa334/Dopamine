//
//  Jailbreak.swift
//  Fugu15
//
//  Created by exerhythm on 03.04.2023.
//

import UIKit
import Fugu15KernelExploit
import CBindings

var fakeRootPath: String? = nil
public func rootifyPath(path: String) -> String {
    if fakeRootPath == nil {
        fakeRootPath = Bootstrapper.locateExistingFakeRoot()
    }
    return fakeRootPath! + "/procursus/" + path
}

func getBootInfoValue(key: String) -> Any? {
    guard let bootInfo = NSDictionary(contentsOfFile: rootifyPath(path: "/basebin/boot_info.plist")) else {
        return nil
    }
    return bootInfo[key]
}

func respring() {
    _ = execCmd(args: [rootifyPath(path: "/usr/bin/sbreload")])
}

func userspaceReboot() {
    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    
    // MARK: Fade out Animation
    
    let view = UIView(frame: UIScreen.main.bounds)
    view.backgroundColor = .black
    view.alpha = 0

    for window in UIApplication.shared.connectedScenes.map({ $0 as? UIWindowScene }).compactMap({ $0 }).flatMap({ $0.windows.map { $0 } }) {
        window.addSubview(view)
        UIView.animate(withDuration: 0.2, delay: 0, animations: {
            view.alpha = 1
        })
    }
    
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: {
        _ = execCmd(args: [rootifyPath(path: "/usr/bin/launchctl"), "reboot", "userspace"])
    })
}

func reboot() {
    _ = execCmd(args: [CommandLine.arguments[0], "reboot"])
}

func isJailbroken() -> Bool {
    if isSandboxed() { return true } // ui debugging
    
    var jbdPid: pid_t = 0
    jbdGetStatus(nil, nil, &jbdPid)
    return jbdPid != 0
}

func isBootstrapped() -> Bool {
    if isSandboxed() { return true } // ui debugging
    
    return Bootstrapper.isBootstrapped()
}

func jailbreak(completion: @escaping (Error?) -> ()) {
    do {
        var wifiFixupNeeded = false
        if #available(iOS 15.4, *) {
            // No Wifi fixup needed
        }
        else {
            if wifiIsEnabled() {
                setWifiEnabled(false)
                Logger.log("Disabling Wi-Fi", isStatus: true)
                sleep(1)
            }
        }

        Logger.log("Launching kexploitd", isStatus: true)

        try Fugu15.launchKernelExploit(oobPCI: Bundle.main.bundleURL.appendingPathComponent("oobPCI")) { msg in
            DispatchQueue.main.async {
                var toPrint: String
                let verbose = !msg.hasPrefix("Status: ")
                if !verbose {
                    toPrint = String(msg.dropFirst("Status: ".count))
                }
                else {
                    toPrint = msg
                }

                Logger.log(toPrint, isStatus: !verbose)
            }
        }

        if #available(iOS 15.4, *) {
            // No Wifi fixup needed
        }
        else {
            setWifiEnabled(true)
            Logger.log("Enabling Wi-Fi", isStatus: true)
        }
        
        try Fugu15.startEnvironment()
        
        DispatchQueue.main.async {
            Logger.log(NSLocalizedString("Jailbreak_Done", comment: ""), type: .success, isStatus: true)
            completion(nil)
        }
    } catch {
        DispatchQueue.main.async {
            Logger.log("\(error.localizedDescription)", type: .error, isStatus: true)
            completion(error)
            NSLog("Fugu15 error: \(error)")
        }
    }
}

func removeJailbreak() {
    dopamineDefaults().removeObject(forKey: "selectedPackageManagers")
    _ = execCmd(args: [CommandLine.arguments[0], "uninstall_environment"])
    if isJailbroken() {
        reboot()
    }
}

func jailbrokenUpdateTweakInjectionPreference() {
    _ = execCmd(args: [CommandLine.arguments[0], "update_tweak_injection"])
}

func changeMobilePassword(newPassword: String) {
    _ = execCmd(args: [rootifyPath(path: "/usr/bin/dash"), "-c", String(format: "printf \"%%s\\n\" \"\(newPassword)\" | \(rootifyPath(path: "/usr/sbin/pw")) usermod 501 -h 0")])
}


func changeEnvironmentVisibility(hidden: Bool) {
    if hidden {
        _ = execCmd(args: [CommandLine.arguments[0], "hide_environment"])
    }
    else {
        _ = execCmd(args: [CommandLine.arguments[0], "unhide_environment"])
    }

    if isJailbroken() {
        jbdSetFakelibVisible(!hidden)
    }
}

func isEnvironmentHidden() -> Bool {
    return !FileManager.default.fileExists(atPath: "/var/jb")
}

func update(tipaURL: URL) {
    print(tipaURL)
}

func installedEnvironmentVersion() -> String {
    return getBootInfoValue(key: "basebin-version") as? String ?? "1.0"
}

func isInstalledEnvironmentVersionMismatching() -> Bool {
    return installedEnvironmentVersion() != Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
}

func updateEnvironment() {
    
}


// debugging
func isSandboxed() -> Bool {
    !FileManager.default.isWritableFile(atPath: "/var/mobile/")
}

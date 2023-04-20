//
//  Jailbreak.swift
//  Fugu15
//
//  Created by exerhythm on 03.04.2023.
//

import UIKit
import Fugu15KernelExploit


func respring() {
    
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
        let _ = execCmd(args: ["/var/jb/usr/bin/launchctl", "reboot", "userspace"])
    })
}

func isJailbroken() -> Bool {
    return false
}

func isBootstrapped() -> Bool {
    return true
}

func jailbreak(completion: @escaping (Error?) -> ()) {
    let tweakInjection = UserDefaults.standard.bool(forKey: "tweakInjection")
    let enableiDownload = UserDefaults.standard.bool(forKey: "enableiDownload")
    
    let selectedPackageManagers = UserDefaults.standard.array(forKey: "selectedPackageManagers") as? [String] ?? []
    let shouldInstallZebra = selectedPackageManagers.contains("Zebra")
    let shouldInstallSileo = selectedPackageManagers.contains("Sileo")

    do {
        Logger.log("Launching kexploitd", isUserFriendly: true)
        
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

                Logger.log(toPrint, isUserFriendly: !verbose)
            }
        }
        
        try Fugu15.startEnvironment()
        
        DispatchQueue.main.async {
            Logger.log("Done!", type: .success, isUserFriendly: true)
            completion(nil)
        }
    } catch {
        DispatchQueue.main.async {
            Logger.log("\(error.localizedDescription)", type: .error, isUserFriendly: true)
            completion(error)
            NSLog("Fugu15 error: \(error)")
        }
    }
}

func changeRootPassword(newPassword: String) {
    
}


func changeEnvironmentVisibility(hidden: Bool) {
    
}

func isEnvironmentHidden() -> Bool {
    return false
}


func update(tipaURL: URL) {
    print(tipaURL)
}

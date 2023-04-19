//
//  Jailbreak.swift
//  Fugu15
//
//  Created by exerhythm on 03.04.2023.
//

import UIKit


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
        // put implementation here
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
    
    // testing function, can be removed
    DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: {
//      completion(NSError(domain: "", code: 1))
        completion(nil)
    })
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

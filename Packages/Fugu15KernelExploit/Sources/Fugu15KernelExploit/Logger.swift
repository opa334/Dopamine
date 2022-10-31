//
//  Logger.swift
//  kexploitd
//
//  Created by Linus Henze.
//  Copyright © 2021/2022 Pinauten GmbH. All rights reserved.
//

import Foundation

class Logger {
    static var logFileHandle: FileHandle?
    
    static func print(_ s: String) {
        NSLog("%@", s)
        
        if logFileHandle != nil {
            try? logFileHandle.unsafelyUnwrapped.write(contentsOf: (s + "\n").data(using: .utf8) ?? Data())
        }
    }
    
    static func fmt(_ s: String, _ args: CVarArg...) {
        print(String(format: s, arguments: args))
    }
    
    static func status(_ s: String) {
        print("Status: \(s)")
    }
}

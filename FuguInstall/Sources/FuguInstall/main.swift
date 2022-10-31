//
//  main.swift
//  FuguInstall
//
//  Created by Linus Henze.
//  Copyright © 2022 Pinauten GmbH. All rights reserved.
//

import Foundation
import CBindings

func execCmd(args: [String], fileActions: posix_spawn_file_actions_t? = nil) -> Int32? {
    var fileActions = fileActions
    
    var attr: posix_spawnattr_t?
    posix_spawnattr_init(&attr)
    posix_spawnattr_set_persona_np(&attr, 99, 1)
    posix_spawnattr_set_persona_uid_np(&attr, 0)
    posix_spawnattr_set_persona_gid_np(&attr, 0)
    
    var pid: pid_t = 0
    var argv: [UnsafeMutablePointer<CChar>?] = []
    for arg in args {
        argv.append(strdup(arg))
    }
    
    argv.append(nil)
    
    let result = posix_spawn(&pid, argv[0], &fileActions, &attr, &argv, environ)
    let err = errno
    guard result == 0 else {
        NSLog("Failed")
        NSLog("Error: \(result) Errno: \(err)")
        
        return nil
    }
    
    var status: Int32 = 0
    waitpid(pid, &status, 0)
    
    return status
}

if CommandLine.arguments.count > 1 {
    switch CommandLine.arguments[1] {
    case "fixAppPerm":
        guard CommandLine.arguments.count == 4 else {
            exit(-1)
        }
        
        let installed = URL(fileURLWithPath: CommandLine.arguments[3])
        let orig = URL(fileURLWithPath: CommandLine.arguments[2]).appendingPathComponent("Payload").appendingPathComponent(installed.lastPathComponent)
        
        do {
            if let enumerator = FileManager.default.enumerator(atPath: orig.path) {
                for case let file as String in enumerator {
                    let origPath = orig.path + "/" + file
                    let newPath  = installed.path + "/" + file
                    if let attr = try? FileManager.default.attributesOfItem(atPath: origPath) {
                        if let perms = attr[.posixPermissions] {
                            try FileManager.default.setAttributes([.posixPermissions: perms], ofItemAtPath: newPath)
                        }
                    }
                }
            }
        } catch {
            exit(-2)
        }
        
        exit(0)
        
    default:
        exit(-1)
    }
}

FuguInstallApp.main()

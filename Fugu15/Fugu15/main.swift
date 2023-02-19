//
//  main.swift
//  Fugu15
//
//  Created by Linus Henze on 2022-07-29.
//

import Foundation
import Fugu15KernelExploit

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
    case "do-bootstrap":
        Bootstrapper.doBootstrap();
        exit(0)

    case "removeFuguInstallPlist":
        let path = Bundle.main.bundleURL
        
        let plist = path.appendingPathComponent("FuguInstall.plist")
        try? FileManager.default.removeItem(at: plist)
        
        exit(0)
        
    default:
        break
    }
}

Fugu15.mainHook()

Fugu15App.main()

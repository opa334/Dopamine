//
//  iDownloadCmds.swift
//  Fugu15KernelExploit
//
//  Created by Linus Henze.
//  Copyright © 2022 Pinauten GmbH. All rights reserved.
//

import Foundation
import iDownload

let iDownloadCmds = [
    "help": iDownload_help,
    "autorun": iDownload_autorun,
    "tcload": iDownload_tcload,
    "bootstrap": iDownload_bootstrap,
    "uninstall": iDownload_uninstall
] as [String: iDownloadCmd]

func iDownload_help(_ hndlr: iDownloadHandler, _ cmd: String, _ args: [String]) throws {
    try hndlr.sendline("tcload <path to TrustCache>: Load a TrustCache")
    try hndlr.sendline("bootstrap:                   Extract bootstrap.tar to /private/preboot/jb")
    try hndlr.sendline("uninstall:                   Remove Procursus, Sileo and /var/jb symlink")
}

func iDownload_autorun(_ hndlr: iDownloadHandler, _ cmd: String, _ args: [String]) throws {
    if access("/private/preboot/jb/TrustCache", F_OK) == 0 {
        try iDownload_tcload(hndlr, "tcload", ["/private/preboot/jb/TrustCache"])
        _ = try? hndlr.exec("/sbin/mount", args: ["-u", "/private/preboot"])
        
        if access("/var/jb/Applications/Sileo.app", F_OK) == 0 {
            _ = try? hndlr.exec("/var/jb/usr/bin/uicache", args: ["-p", "/var/jb/Applications/Sileo.app"])
        }
    }
}

func iDownload_tcload(_ hndlr: iDownloadHandler, _ cmd: String, _ args: [String]) throws {
    if args.count != 1 {
        try hndlr.sendline("Usage: tcload <path to TrustCache>")
        return
    }
    
    guard let krw = hndlr.krw else {
        throw iDownloadError.custom("No KRW support!")
    }
    
    let tcPath = hndlr.resolve(path: args[0])
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: tcPath)) else {
        throw iDownloadError.custom("Failed to read trust cache!")
    }
    
    // Make sure the trust cache is good
    guard data.count >= 0x18 else {
        throw iDownloadError.custom("Trust cache is too small!")
    }
    
    let vers = data.getGeneric(type: UInt32.self)
    guard vers == 1 else {
        throw iDownloadError.custom(String(format: "Trust cache has bad version (must be 1, is %u)!", vers))
    }
    
    let count = data.getGeneric(type: UInt32.self, offset: 0x14)
    guard data.count == 0x18 + (Int(count) * 22) else {
        throw iDownloadError.custom(String(format: "Trust cache has bad length (should be %p, is %p)!", 0x18 + (Int(count) * 22), data.count))
    }
    
    guard let pmap_image4_trust_caches = Fugu15.patchfinder?.pmap_image4_trust_caches else {
        throw iDownloadError.custom("Failed to patchfind pmap_image4_trust_caches!")
    }
    
    var mem: UInt64!
    do {
        mem = try krw.kalloc(size: UInt(data.count + 0x10))
    } catch let e {
        throw KRWError.customError(description: "Failed to allocate kernel memory for TrustCache: \(e)")
    }
    
    let next = KRWAddress(address: mem, options: [])
    let us   = KRWAddress(address: mem + 0x8, options: [])
    let tc   = KRWAddress(address: mem + 0x10, options: [])
    
    do {
        try krw.kwrite(address: us, data: Data(fromObject: mem + 0x10))
        try krw.kwrite(address: tc, data: data)
    } catch let e {
        throw KRWError.customError(description: "Failed to write to our TrustCache: \(e)")
    }
    
    let pitc = KRWAddress(address: pmap_image4_trust_caches + hndlr.slide, options: .PPL)
    
    // Read head
    guard let cur = krw.r64(pitc) else {
        throw KRWError.customError(description: "Failed to read TrustCache head!")
    }
    
    // Write into our list entry
    try krw.kwrite(address: next, data: Data(fromObject: cur))
    
    // Replace head
    try krw.kwrite(address: pitc, data: Data(fromObject: mem.unsafelyUnwrapped))
    
    try hndlr.sendline("Successfully loaded TrustCache!")
}

func iDownload_bootstrap(_ hndlr: iDownloadHandler, _ cmd: String, _ args: [String]) throws {
    let bootstrap_tar = Bundle.main.bundleURL.appendingPathComponent("bootstrap.tar").path
    let tar           = Bundle.main.bundleURL.appendingPathComponent("tar").path
    let trustCache    = Bundle.main.bundleURL.appendingPathComponent("TrustCache").path
    let sileo         = Bundle.main.bundleURL.appendingPathComponent("sileo.deb").path
    
    guard access(bootstrap_tar, F_OK) == 0 else {
        throw iDownloadError.custom("bootstrap.tar does not exist!")
    }
    
    guard access(tar, F_OK) == 0 else {
        throw iDownloadError.custom("tar does not exist!")
    }
    
    guard access(trustCache, F_OK) == 0 else {
        throw iDownloadError.custom("TrustCache for tar does not exist!")
    }
    
    try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tar)
    
    try hndlr.sendline("Re-Mounting /private/preboot...")
    do {
        let exit = try hndlr.exec("/sbin/mount", args: ["-u", "/private/preboot"])
        if exit != 0 {
            throw iDownloadError.custom("mount failed: exit status: \(exit)")
        }
    } catch iDownloadError.execError(status: let status) {
        throw iDownloadError.custom("Failed to exec mount: posix_spawn error \(status) (\(String(cString: strerror(status)))")
    } catch iDownloadError.childDied(signal: let signal) {
        throw iDownloadError.custom("mount died: Signal: \(signal)")
    }
    
    try hndlr.sendline("Loading tar TrustCache...")
    try iDownload_tcload(hndlr, "tcload", [trustCache])
    
    try hndlr.sendline("Creating bootstrap dir")
    try? FileManager.default.removeItem(atPath: "/private/preboot/jb")
    try FileManager.default.createDirectory(atPath: "/private/preboot/jb", withIntermediateDirectories: false, attributes: nil)
    
    try hndlr.sendline("Extracting bootstrap.tar...")
    do {
        let exit = try hndlr.exec(tar, args: ["-xvf", bootstrap_tar], cwd: "/private/preboot/jb")
        if exit != 0 {
            throw iDownloadError.custom("tar failed: exit status: \(exit)")
        }
    } catch iDownloadError.execError(status: let status) {
        throw iDownloadError.custom("Failed to exec tar: posix_spawn error \(status) (\(String(cString: strerror(status)))")
    } catch iDownloadError.childDied(signal: let signal) {
        throw iDownloadError.custom("tar died: Signal: \(signal)")
    }
    
    if access("/private/preboot/jb/TrustCache", F_OK) == 0 {
        try hndlr.sendline("Loading bootstrap.tar TrustCache...")
        try iDownload_tcload(hndlr, "tcload", ["/private/preboot/jb/TrustCache"])
    }
    
    try hndlr.sendline("Creating /var/jb symlink...")
    try? FileManager.default.removeItem(atPath: "/var/jb")
    try? FileManager.default.createSymbolicLink(atPath: "/var/jb", withDestinationPath: "/private/preboot/jb")
    
    try hndlr.sendline("Running bootstrap.sh...")
    var status = try hndlr.exec("/var/jb/usr/bin/sh", args: ["/var/jb/prep_bootstrap.sh"])
    
    try hndlr.sendline("prep_bootstrap.sh: \(status)")
    
    if access(sileo, F_OK) == 0 {
        try hndlr.sendline("Installing Sileo...")
        status = try hndlr.exec("/var/jb/usr/bin/dpkg", args: ["-i", sileo])
        
        try hndlr.sendline("dpkg: \(status)")
        
        status = try hndlr.exec("/var/jb/usr/bin/uicache", args: ["-p", "/var/jb/Applications/Sileo.app"])
        
        try hndlr.sendline("uicache: \(status)")
    }
    
    try hndlr.sendline("Done")
}

func iDownload_uninstall(_ hndlr: iDownloadHandler, _ cmd: String, _ args: [String]) throws {
    if access("/var/jb/Applications/Sileo.app", F_OK) == 0 {
        try hndlr.sendline("Removing Sileo...")
        _ = try? hndlr.exec("/var/jb/usr/bin/uicache", args: ["-u", "/var/jb/Applications/Sileo.app"])
    }
    
    if access("/private/preboot/jb", F_OK) == 0 {
        try hndlr.sendline("Removing bootstrap...")
        try? FileManager.default.removeItem(atPath: "/private/preboot/jb")
    }
    
    try hndlr.sendline("Removing /var/jb symlink...")
    try? FileManager.default.removeItem(atPath: "/var/jb")
    
    try hndlr.sendline("Done")
}

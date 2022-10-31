//
//  main.swift
//  Exe2Driver
//
//  Created by Linus Henze.
//  Copyright © 2022 Pinauten GmbH. All rights reserved.
//

import Foundation
import Darwin
import SwiftUtils
import SwiftMachO
import MachO

func fail(_ msg: String, _ args: CVarArg...) -> Never {
    print(String(format: msg, arguments: args))
    exit(-1)
}

guard CommandLine.arguments.count >= 3 else {
    fail("Usage: Exe2Driver <path to exe> <driver output path>")
}

// We use the MachO module just to parse FAT files
// Unfortunately, it does not support editing MachO files right now
var machO: Data!
do {
    machO = try MachO(fromFile: CommandLine.arguments[1]).data
} catch {
    fail("Failed to read MachO file at '\(CommandLine.arguments[1])'!")
}

guard let hdr = machO.tryGetGeneric(type: mach_header_64.self) else {
    fail("Bad file size!")
}

guard hdr.magic == MH_MAGIC_64 else {
    fail("Not a MachO!")
}

// Iterate over all load commands to find LC_BUILD_VERSION and LC_MAIN

var foundBuildVersion = false, foundMain = false

guard let ncmds = machO.tryGetGeneric(type: UInt32.self, offset: 0x10) else {
    fail("Bad file size!")
}

guard let cmds_size = machO.tryGetGeneric(type: UInt32.self, offset: 0x14) else {
    fail("Bad file size!")
}

guard (cmds_size + 0x20) <= machO.count else {
    fail("Bad file size!")
}

var pos = 0x20
for _ in 0..<ncmds {
    guard let cmd = machO.tryGetGeneric(type: load_command.self, offset: UInt(pos)) else {
        fail("Bad file (size)!")
    }
    
    if cmd.cmd == LC_BUILD_VERSION,
       cmd.cmdsize >= MemoryLayout<build_version_command>.size {
        // Modify the command
        // Set platform to driverkit
        machO.withUnsafeMutableBytes { (ptr: UnsafeMutableRawBufferPointer) in
            let bvc = ptr.baseAddress!.advanced(by: pos).assumingMemoryBound(to: build_version_command.self)
            bvc.pointee.platform = UInt32(PLATFORM_DRIVERKIT)
        }
        
        foundBuildVersion = true
    } else if cmd.cmd == LC_MAIN,
              cmd.cmdsize >= MemoryLayout<entry_point_command>.size {
        // "Hide" the command by changing it's type
        machO.withUnsafeMutableBytes { (ptr: UnsafeMutableRawBufferPointer) in
            let epc = ptr.baseAddress!.advanced(by: pos).assumingMemoryBound(to: entry_point_command.self)
            epc.pointee.cmd = 0x13371337
        }
        
        foundMain = true
    }
    
    if foundBuildVersion && foundMain {
        break
    }
    
    pos += Int(cmd.cmdsize)
}

if !foundBuildVersion {
    fail("MachO does not contain the required LC_BUILD_VERSION load command!")
}

if !foundMain {
    fail("MachO does not contain the required LC_MAIN load command!")
}

do {
    try machO.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
} catch {
    fail("Failed to write patched driver to '\(CommandLine.arguments[2])'!")
}

print("Successfully patched executable!")
print("Wrote driver to '\(CommandLine.arguments[2])'.")

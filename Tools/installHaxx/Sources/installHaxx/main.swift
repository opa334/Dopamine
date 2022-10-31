//
//  main.swift
//  installHaxx
//
//  Created by Linus Henze.
//  Copyright © 2021/2022 Pinauten GmbH. All rights reserved.
//

import Foundation
import SwiftUtils
import SwiftMachO

let cpuTypeModify = UInt32(bitPattern: CPU_TYPE_ARM64)
let cpuTypeInject = UInt32(bitPattern: CPU_TYPE_ARM64)

let cpuSubtypeModify = UInt32(bitPattern: CPU_SUBTYPE_ARM64E)
let cpuSubtypeInject = UInt32(bitPattern: CPU_SUBTYPE_ARM64_V8)

do {
    if CommandLine.arguments.count < 4 {
        print("Usage: installHaxx <program to modify> <program to inject> <output> <optional extra data>")
        print("Specify - for one of the input files to read it from stdin")
        print("Specify - for the the output file to write it to stdout")
        exit(-1)
    }
    
    guard CommandLine.arguments[1] != "-" || CommandLine.arguments[2] != "-" else {
        print("You can only specify - for one of the input files!")
        exit(-1)
    }
    
    var modify: Data!
    if CommandLine.arguments[1] != "-" {
        modify = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
    } else {
        // Read from stdin
        modify = Data()
        
        var chr = getc(stdin)
        while chr != EOF {
            modify.append(UInt8(chr))
            
            chr = getc(stdin)
        }
    }
    
    var inject: Data!
    if CommandLine.arguments[2] != "-" {
        inject = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
    } else {
        // Read from stdin
        inject = Data()
        
        var chr = getc(stdin)
        while chr != EOF {
            inject.append(UInt8(chr))
            
            chr = getc(stdin)
        }
    }
    
    var extraData: Data!
    if CommandLine.arguments.count >= 5 {
        extraData = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[4]))
    } else {
        extraData = Data()
    }
    
    // Parse as MachO
    let injectMachO = try MachO(fromData: inject, okToLoadFAT: false)
    
    // In our fat, the program we modify has to come first
    // It must be set as an arm64e application in the FAT header
    // It's subtype must be 2, which is invalid
    
    // The program we inject has to come afterwards
    // It must be an arm64e application
    
    guard injectMachO.cpuType == CPU_TYPE_ARM64 else {
        print("The program to inject is not an arm64e application!")
        exit(-1)
    }
    
    guard injectMachO.cpuSubType == cpuSubtypeInject else {
        print("The program to inject is not an arm64e application!")
        exit(-1)
    }
    
    // Ok, build the FAT
    // Header
    var fat = Data(fromObject: FAT_MAGIC.bigEndian)   // FAT magic
    fat.appendGeneric(value: (2 as UInt32).bigEndian) // Number of archs
    
    // Arch 0, the program we modify
    fat.appendGeneric(value: cpuTypeModify.bigEndian)        // CPU Type
    fat.appendGeneric(value: cpuSubtypeModify.bigEndian)     // CPU Subtype
    fat.appendGeneric(value: (0x4000 as UInt32).bigEndian)   // Offset, page-aligned
    fat.appendGeneric(value: UInt32(modify.count).bigEndian) // Size
    fat.appendGeneric(value: (0xE as UInt32).bigEndian)      // Alignment, power of 2
    
    var modifyAlignedSize = UInt32(modify.count)
    if (modifyAlignedSize % 0x4000) != 0 {
        let off = 0x4000 - (modifyAlignedSize & 0x3FFF)
        modifyAlignedSize += off
        modify.append(Data(count: Int(off)))
    }
    
    // Arch 1, the program we inject
    fat.appendGeneric(value: cpuTypeInject.bigEndian)                // CPU Type
    fat.appendGeneric(value: cpuSubtypeInject.bigEndian)             // CPU Subtype
    fat.appendGeneric(value: (0x4000 + modifyAlignedSize).bigEndian) // Offset, page-aligned
    fat.appendGeneric(value: UInt32(inject.count).bigEndian)         // Size
    fat.appendGeneric(value: (0xE as UInt32).bigEndian)              // Alignment, power of 2
    
    // Alignment, fill with zeros
    fat.append(Data(count: 0x4000 - fat.count))
    
    // Append binaries
    fat.append(modify)
    fat.append(inject)
    
    // Extra data comes right after the injected executable
    // No padding
    fat.append(extraData)
    
    // Return that stuff
    if CommandLine.arguments[3] != "-" {
        try fat.write(to: URL(fileURLWithPath: CommandLine.arguments[3]))
    } else {
        // Write to stdout
        fat.withUnsafeBytes { ptr in
            _ = fwrite(ptr.baseAddress!, 1, ptr.count, stdout)
        }
    }
} catch let e {
    print("An exception occurred: \(e)")
    exit(-1)
}

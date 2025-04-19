//
//  main.swift
//  MachOMerger
//
//  Created by Linus Henze.
//

import Foundation
import SwiftMachO
import MachO

typealias SegRelocInfo = [(String, [(isB: Bool, origCommand: Segment64LoadCommand, data: Data, offset: UInt64)])]

let pageSize: UInt64    = 0x4000
let pageMaskOff: UInt64 = pageSize - 1
let pageMask: UInt64    = ~pageMaskOff

guard CommandLine.arguments.count == 4 else {
    print("Usage: MachOMerger <a> <b> <out>")
    exit(-1)
}

let a = try MachO(fromFile: CommandLine.arguments[1], okToLoadFAT: false)
let b = try MachO(fromFile: CommandLine.arguments[2], okToLoadFAT: false)

var newMachO = Data()

struct MachOMergeData {
    var segments: [(Segment64LoadCommand, Data)] = []
    var linkedit: Data?
    var dylibs: [String] = []
    var chainedFixups: Data?
    var unixthread: [(flavor: UInt32, state: Data)]?
    var exportsTrie: Data?
    var symtab: (symbols: Data, strings: Data)?
    var dysymtab: (localStart: Int, localCount: Int, externalStart: Int, externalCount: Int, undefStart: Int, undefCount: Int, indirect: Data)?
    var splitInfo: Data?
    var functionStarts: Data?
    var dataInCode: Data?
    var otherCommands: [LoadCommand] = []
}

func collectData(fromMachO machO: MachO) -> MachOMergeData {
    // Iterate over all load commands
    var result = MachOMergeData()
    for cmd in machO.cmds {
        if let seg = cmd as? Segment64LoadCommand {
            let start = Int(seg.fileOffset)
            let end   = start + Int(seg.fileSize)
            guard let data = machO.data.trySubdata(in: start..<end) else {
                print("Failed to get segment \(seg.name) of a!")
                exit(-1)
            }
            
            if seg.name == "__LINKEDIT" {
                result.linkedit = data
            } else {
                result.segments.append((seg, data))
            }
        }
    }
    
    func extract(_ data: Data, _ off: Int, _ size: Int) -> Data {
        if size == 0 {
            return Data()
        }
        
        guard let res = data.trySubdata(in: off..<(off + size)) else {
            print("extract: Failed to get data!")
            exit(-1)
        }
        
        return res
    }
    
    func machOExtract(_ off: Int, _ size: Int) -> Data {
        extract(machO.data, off, size)
    }
    
    func getLECmdData(_ cmd: LoadCommand, name: String) -> Data {
        guard let cmdRaw = cmd as? OpaqueLoadCommand else {
            print("XXX: Not compatible with this version of SwiftMachO!")
            exit(-1)
        }
        
        guard let off = cmdRaw.data.tryGetGeneric(type: UInt32.self, offset: 0) else {
            print("\(name): Couldn't get offset!")
            exit(-1)
        }
        
        guard let size = cmdRaw.data.tryGetGeneric(type: UInt32.self, offset: 4) else {
            print("\(name): Couldn't get size!")
            exit(-1)
        }
        
        return machOExtract(Int(off), Int(size))
    }
    
    for cmd in machO.cmds {
        let cmdNum = cmd.type.rawValue
        if cmdNum == LC_SEGMENT_64 {
            // Already parsed
        } else if let chainLC = cmd as? ChainedFixupsLoadCommand {
            result.chainedFixups = machOExtract(Int(chainLC.fixupOffset), Int(chainLC.fixupSize))
        } else if cmdNum == LC_DYLD_EXPORTS_TRIE {
            result.exportsTrie = getLECmdData(cmd, name: "LC_DYLD_EXPORTS_TRIE")
        } else if let symtab = cmd as? SymTabLoadCommand {
            let dataSym = machOExtract(Int(symtab.symOff), 16 * Int(symtab.symCount))
            let dataStr = machOExtract(Int(symtab.strOff), Int(symtab.strSize))
            
            result.symtab = (symbols: dataSym, strings: dataStr)
        } else if cmd is DSymTabLoadCommand {
            // Will be handled later
        } else if let unixthread = cmd as? UnixThreadLoadCommand {
            result.unixthread = unixthread.threadStates
        } else if cmdNum == LC_SEGMENT_SPLIT_INFO {
            result.splitInfo = getLECmdData(cmd, name: "LC_SEGMENT_SPLIT_INFO")
        } else if cmdNum == LC_FUNCTION_STARTS {
            result.functionStarts = getLECmdData(cmd, name: "LC_FUNCTION_STARTS")
        } else if cmdNum == LC_DATA_IN_CODE {
            result.dataInCode = getLECmdData(cmd, name: "LC_DATA_IN_CODE")
        } else if cmdNum == LC_LOAD_DYLIB {
            // Handle this
        } else if cmdNum == LC_ID_DYLIB || cmdNum == LC_UUID || cmdNum == LC_ID_DYLINKER || cmdNum == LC_BUILD_VERSION || cmdNum == LC_SOURCE_VERSION {
            result.otherCommands.append(cmd)
        } else if cmdNum == LC_CODE_SIGNATURE || cmdNum == LC_ENCRYPTION_INFO_64 {
        } else {
            print("Unhandled command \(cmd.type)")
            exit(-1)
        }
    }
    
    for cmd in machO.cmds {
        if let dysym = cmd as? DSymTabLoadCommand {
            guard result.symtab != nil else {
                print("DYSYMTAB without SYMTAB!")
                exit(-1)
            }
            
            let `indirect` = machOExtract(Int(dysym.indirectOff), 4 * Int(dysym.indirectCount))
            
            guard dysym.tocCount == 0 else {
                print("DYSYMTAB: TOC not supported!")
                exit(-1)
            }
            
            guard dysym.moduleTblCount == 0 else {
                print("DYSYMTAB: Module Tables not supported!")
                exit(-1)
            }
            
            guard dysym.extSymTblCount == 0 else {
                print("DYSYMTAB: External symbol tables not supported!")
                exit(-1)
            }
            
            guard dysym.extRelCount == 0 else {
                print("DYSYMTAB: External relocation not supported!")
                exit(-1)
            }
            
            guard dysym.localRelCount == 0 else {
                print("DYSYMTAB: Local relocation not supported!")
                exit(-1)
            }
            
            result.dysymtab = (localStart: Int(dysym.localSymOff), localCount: Int(dysym.localSymCount), externalStart: Int(dysym.externalSymOff), externalCount: Int(dysym.externalSymCount), undefStart: Int(dysym.undefSymOff), undefCount: Int(dysym.undefSymCount), indirect: `indirect`)
            
            break
        }
    }
    
    return result
}

// Collect data from both MachOs
var dataA = collectData(fromMachO: a)
var dataB = collectData(fromMachO: b)

// Patch out magic of both MachOs
// Fixes issues with some third party software (e.g. Frida) finding the wrong place and mistaking it for the header
// Of course the root issue is in third party software, but I guess we can make their life easier
let magicReplacement = UInt32(0xd0d0d0d0)

/*
 * Now comes the real magic: Merging the MachOs.
 * To do this, the following steps have to be performed:
 * 1. Merge all the segments and generate appropriate reloc information
 *    Relocation information will simply be section -> offset
 */

// Segments with the same name will be merged
// We will output segments in the following order: r-x r-- rw-

var segments: [(String, [(isB: Bool, origCommand: Segment64LoadCommand, data: Data, offset: UInt64)])] = []
for seg in dataA.segments {
    guard !segments.contains(where: { $0.0 == seg.0.name }) else {
        print("Found duplicate segment! [A]")
        exit(-1)
    }

    var data = seg.1

    if seg.0.name == "__TEXT" {
        data = Data(fromObject:magicReplacement) + data.subdata(in: 4..<data.count)
    }
    
    segments.append((seg.0.name, [(isB: false, origCommand: seg.0, data: data, offset: 0)]))
}

var sortingRequired = false

for seg in dataB.segments {
    var data = seg.1

    if seg.0.name == "__TEXT" {
        data = Data(fromObject:magicReplacement) + data.subdata(in: 4..<data.count)
    }

    let newEntry = [(isB: true, origCommand: seg.0, data: data, offset: 0 as UInt64)]
    
    var found = false
    var new: [(String, [(isB: Bool, origCommand: Segment64LoadCommand, data: Data, offset: UInt64)])] = []
    for s in segments {
        if s.0 == seg.0.name {
            new.append((s.0, s.1 + newEntry))
            found = true
        } else {
            new.append(s)
        }
    }
    
    if !found {
        new.append((seg.0.name, newEntry))
        sortingRequired = true
    }
    
    segments = new
}

func compareProt(_ a: VMProt, b: VMProt) -> Bool? {
    if a.rawValue == b.rawValue {
        return nil
    } else if a.rawValue == (VM_PROT_READ | VM_PROT_EXECUTE) {
        return true
    } else if a.rawValue == VM_PROT_READ && b.rawValue == (VM_PROT_READ | VM_PROT_WRITE) {
        return true
    }
    
    return false
}

guard !sortingRequired else {
    print("FIXME: sortingRequired not implemented!")
    exit(-1)
}

// Relocate segments
var curReloc: UInt64 = 0x4000 // Reserve some space for our new header
var nSegments: [(String, [(isB: Bool, origCommand: Segment64LoadCommand, data: Data, offset: UInt64)])] = []
for var seg in segments {
    let origVM = seg.1[0].origCommand.vmAddr
    seg.1[0].offset = curReloc &- origVM
    
    curReloc += seg.1[0].origCommand.vmSize
    curReloc = (curReloc + pageMaskOff) & pageMask
    
    if seg.1.count == 2 {
        let origVM = seg.1[1].origCommand.vmAddr
        seg.1[1].offset = curReloc &- origVM
        
        curReloc += seg.1[1].origCommand.vmSize
        curReloc = (curReloc + pageMaskOff) & pageMask
    }
    
    nSegments.append(seg)
}

let relocInfo = RelocInfo(segRel: nSegments)

// Okay, we've relocated the segments
// Now we'll need to fix them
fixupViaSplitInfo(infoA: dataA, infoB: dataB, relocInfo: relocInfo)

// The segments themselfes are fixed now
// What's left is essentially chained fixups and a few others
let newChainedFixups = mergeChainedFixups(infoA: dataA, infoB: dataB, relocInfo: relocInfo, machOA: a, machOB: b)

// Generate trampolines
if let symsB = try? b.getSymbolTable(),
   let symsA = try? a.getSymbolTable() {
    for sym in symsB.symbols {
        if sym.name.starts(with: "_MACHOMERGER_TRAMPOLINE_") {
            let dstName = sym.name.replacingOccurrences(of: "_MACHOMERGER_TRAMPOLINE", with: "")
            
            var dstAddr: UInt64!
            if let d = getMagicSymbolVal(dstName) {
                dstAddr = d.0
            } else if let d = symsA.symbol(forName: dstName) {
                dstAddr = d.value
            }
            
            guard dstAddr != nil else {
                print("Cannot resolve symbol \(dstName)")
                exit(-1)
            }
            
            // Generate instruction
            let at = relocInfo.translate(address: sym.value, isB: true)
            let to = relocInfo.translate(address: dstAddr, isB: false)
            
            let delta = Int64(bitPattern: to &- at)
            let deltaSh = delta >> 2
            guard deltaSh <= 0x3FFFFFF && deltaSh >= -0x3FFFFFF else {
                print("Cannot generate trampoline: Delta too large!")
                exit(-1)
            }
            
            let instr = 0x14000000 | UInt32(deltaSh & 0x03FFFFFF)
            
            // Write it
            let seg = relocInfo.segment(forOrigAddress: sym.value, isB: true)!
            let off = Int(seg.3)
            var data = seg.1
            data = data.subdata(in: 0..<off) + Data(fromObject: instr) + data.subdata(in: (off + 4)..<data.count)
            relocInfo.replaceSegment(name: seg.0, isB: true, data: data)
        } else if sym.name.starts(with: "_MACHOMERGER_HOOKTRAMPOLINE_") {
            let dstName = sym.name.replacingOccurrences(of: "_MACHOMERGER_HOOKTRAMPOLINE", with: "")
            
            var dstAddr: UInt64!
            if let d = getMagicSymbolVal(dstName) {
                dstAddr = d.0
            } else if let d = symsA.symbol(forName: dstName) {
                dstAddr = d.value
            }
            
            guard dstAddr != nil else {
                print("Cannot resolve symbol \(dstName)")
                exit(-1)
            }
            
            // Generate instruction
            let at = relocInfo.translate(address: sym.value, isB: true)
            let to = relocInfo.translate(address: dstAddr, isB: false) + 4
            
            let delta = Int64(bitPattern: to &- at)
            let deltaSh = delta >> 2
            guard deltaSh <= 0x3FFFFFF && deltaSh >= -0x3FFFFFF else {
                print("Cannot generate trampoline: Delta too large!")
                exit(-1)
            }
            
            let instr = 0x14000000 | UInt32(deltaSh & 0x03FFFFFF)
            
            // Write it
            let seg = relocInfo.segment(forOrigAddress: sym.value, isB: true)!
            let off = Int(seg.3)
            var data = seg.1
            data = data.subdata(in: 0..<off) + Data(fromObject: instr) + data.subdata(in: (off + 4)..<data.count)
            relocInfo.replaceSegment(name: seg.0, isB: true, data: data)
        } else if sym.name.starts(with: "_MACHOMERGER_HOOK_") {
            let dstName = sym.name.replacingOccurrences(of: "_MACHOMERGER_HOOK", with: "")
            let origName = "_MACHOMERGER_ORIG" + dstName
            
            var dstAddr: UInt64!
            if let d = getMagicSymbolVal(dstName) {
                dstAddr = d.0
            } else if let d = symsA.symbol(forName: dstName) {
                dstAddr = d.value
            }

            var origAddr: UInt64!
            if let o = symsB.symbol(forName: origName) {
                origAddr = o.value
            }
            
            guard dstAddr != nil else {
                print("Cannot resolve symbol \(dstName)")
                exit(-1)
            }
            
            // Generate instruction
            let to = relocInfo.translate(address: sym.value, isB: true)
            let at = relocInfo.translate(address: dstAddr, isB: false)
            
            let delta = Int64(bitPattern: to &- at)
            let deltaSh = delta >> 2
            guard deltaSh <= 0x3FFFFFF && deltaSh >= -0x3FFFFFF else {
                print("Cannot generate trampoline: Delta too large!")
                exit(-1)
            }
            
            let instr = 0x14000000 | UInt32(deltaSh & 0x03FFFFFF)
            
            // Write it
            let seg = relocInfo.segment(forOrigAddress: dstAddr, isB: false)!
            let off = Int(seg.3)
            var data = seg.1
            let origInsn = data.subdata(in: off..<off+4).withUnsafeBytes { $0.load(as: UInt32.self) }
            data = data.subdata(in: 0..<off) + Data(fromObject: instr) + data.subdata(in: (off + 4)..<data.count)
            relocInfo.replaceSegment(name: seg.0, isB: false, data: data)

            if origAddr != nil {
                // Copy original first instruction to _MACHOMERGER_ORIG_* first instruction
                // Obviously this mechanism does not work if said instruction is pc-relative, so we have to just assume it's not
                let origSeg = relocInfo.segment(forOrigAddress: origAddr, isB: true)!
                let origOff = Int(origSeg.3)
                var origData = origSeg.1

                origData = origData.subdata(in: 0..<origOff) + Data(fromObject: origInsn) + origData.subdata(in: (origOff + 4)..<origData.count)
                relocInfo.replaceSegment(name: origSeg.0, isB: true, data: origData)
            }
        }
    }
}

// Generate most of the MachO content, except header
var machOData = Data()

for seg in relocInfo.segRel {
    machOData += seg.1[0].data
    
    if seg.1.count == 2 {
        machOData += seg.1[1].data
    }
}

// Generate the MachO itself
var machOHdr = Data()
var loadCommandsSLC = Data()
var loadCommands = Data()
var loadCommandsCount = 0

// Generate segment load commands
let (slcCount, slcs) = generateSegmentLoadCommands(infoA: dataA, infoB: dataB, relocInfo: relocInfo)
loadCommandsSLC.append(slcs)
loadCommandsCount += slcCount

var linkedit = Data()
func emitLinkeditCommand(type: UInt32, data: Data) {
    var res = Data(fromObject: type)
    res.appendGeneric(value: 0x10 as UInt32)
    res.appendGeneric(value: UInt32(linkedit.count + machOData.count + 0x4000))
    res.appendGeneric(value: UInt32(data.count))
    loadCommands.append(res)
    loadCommandsCount += 1
    
    linkedit.append(data)
}

emitLinkeditCommand(type: LC_DYLD_CHAINED_FIXUPS, data: newChainedFixups)

let (symCmdCount, symCmdData) = emitSymtabDysymtab(infoA: dataA, infoB: dataB, relocInfo: relocInfo, linkedit: &linkedit, linkeditStart: machOData.count + 0x4000)
loadCommandsCount += symCmdCount
loadCommands += symCmdData

if dataA.unixthread != nil {
    let (count, cmd) = emitUnixthread(info: dataA, relocInfo: relocInfo, isB: false)
    loadCommandsCount += count
    loadCommands += cmd
} else if dataB.unixthread != nil {
    let (count, cmd) = emitUnixthread(info: dataB, relocInfo: relocInfo, isB: true)
    loadCommandsCount += count
    loadCommands += cmd
}

for other in dataA.otherCommands {
    if let opaque = other as? OpaqueLoadCommand {
        let cmd = opaque.type.rawValue
        loadCommands += Data(fromObject: cmd) + Data(fromObject: UInt32(opaque.data.count) + 8) + opaque.data
        loadCommandsCount += 1
    }
    else if let uuidCmd = other as? UUIDLoadCommand {
        let cmd = uuidCmd.type.rawValue
        loadCommands += Data(fromObject: cmd) + Data(fromObject: uuidCmd.cmdSize) + Data(fromObject: uuidCmd.uuid)
        loadCommandsCount += 1
    }
}

let lastSegments = relocInfo.segRel.last!
let lastSegment = (lastSegments.1.count == 1) ? lastSegments.1[0] : lastSegments.1[1]
var linkeditLC = segment_command_64()
linkeditLC.cmd = UInt32(LC_SEGMENT_64)
linkeditLC.cmdsize = UInt32(MemoryLayout<segment_command_64>.size)
_ = withUnsafeMutableBytes(of: &linkeditLC.segname) { ptr in
    strcpy(ptr.baseAddress!, "__LINKEDIT")
}
linkeditLC.vmaddr = lastSegment.origCommand.vmAddr + lastSegment.offset + lastSegment.origCommand.vmSize
linkeditLC.vmsize = UInt64(linkedit.count)
linkeditLC.fileoff = lastSegment.origCommand.fileOffset + lastSegment.offset + lastSegment.origCommand.fileSize
linkeditLC.filesize = UInt64(linkedit.count)
linkeditLC.maxprot = VM_PROT_READ
linkeditLC.initprot = VM_PROT_READ
linkeditLC.nsects = 0
linkeditLC.flags = 0
loadCommandsSLC.appendGeneric(value: linkeditLC)
loadCommandsCount += 1

var hdr = mach_header_64()
hdr.magic = MH_MAGIC_64
hdr.cputype = CPU_TYPE_ARM64
hdr.cpusubtype = Int32(bitPattern: a.cpuSubType)
hdr.filetype = UInt32(MH_DYLINKER)
hdr.ncmds = UInt32(loadCommandsCount)
hdr.sizeofcmds = UInt32(loadCommands.count + loadCommandsSLC.count)

machOHdr.appendGeneric(value: hdr)
machOHdr.append(loadCommandsSLC)
machOHdr.append(loadCommands)

guard machOHdr.count < 0x4000 else {
    print("Generated MachO header too large!")
    exit(-1)
}

machOHdr.append(Data(repeating: 0, count: 0x4000 - machOHdr.count))

var out = machOHdr + machOData + linkedit

try out.write(to: URL(fileURLWithPath: CommandLine.arguments[3]))

/*let resMachO = try MachO(out)

let testCF = try resMachO.getChainedFixups()
try testCF.forEachFixup { location, vAddr, content in
    print("\(pStr(location)) -> \(pStr(vAddr))")
}*/

print("Done!")

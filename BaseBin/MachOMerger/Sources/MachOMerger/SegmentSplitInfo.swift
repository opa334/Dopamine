//
//  SegmentSplitInfo.swift
//  MachOMerger
//
//  Created by Linus Henze on 2023-03-15.
//

import Foundation
import PatchfinderUtils
import SwiftMachO
import MachO

func pStr(_ p: UInt64) -> String {
    String(format: "%p", p)
}

func ssiFixAdrp(adrp: UInt32, at: UInt64, to: UInt64) -> UInt32 {
    guard (adrp & 0x9F000000) == 0x90000000 else {
        // Not an adrp - Warn but don't touch
        print("WARNING: ssiFixAdrp: Encountered non-adrp instruction at \(at) - Leaving as-is")
        return adrp
    }
    
    let atPage = (at & ~0xFFF) >> 12
    let toPage = (to & ~0xFFF) >> 12
    let pageDistance = Int64(bitPattern: toPage &- atPage)
    guard pageDistance < 0x200000 && pageDistance > -0x200000 else {
        print("ssiFixAdrp: Cannot fixup adrp: Distance too large!")
        exit(-1)
    }
    
    let instruction = (adrp & 0x9F00001F) | UInt32((pageDistance & 0x1FFFFC) << 3) | UInt32((pageDistance & 0x3) << 29)
    
    guard AArch64Instr.Emulate.adrp(instruction, pc: at) == (to & ~0xFFF) else {
        print("ssiFixAdrp: Generated wrong adrp!")
        exit(-1)
    }
    
    return instruction
}

func ssiFixOff12(instr: UInt32, at: UInt64, to: UInt64, toOld: UInt64) -> UInt32 {
    guard (to & 0xFFF) == (toOld & 0xFFF) else {
        print("ssiFixOff12: Not implemented!")
        exit(-1)
    }
    
    // As long as the lowest 12 bits stay the same, there is nothing to do
    return instr
}

func ssiFixBr26(instr: UInt32, at: UInt64, atOld: UInt64, to: UInt64, toOld: UInt64) -> UInt32 {
    let delta = Int64(bitPattern: to &- at)
    let deltaSh = delta >> 2
    guard deltaSh <= 0x3FFFFFF && deltaSh >= -0x3FFFFFF else {
        print("ssiFixBr26: Delta too large!")
        exit(-1)
    }
    
    let new = (instr & 0xFC000000) | UInt32(deltaSh & 0x03FFFFFF)
    if delta == Int64(bitPattern: toOld &- atOld) {
        guard instr == new else {
            print("ssiFixBr26: Instruction generation bug!")
            exit(-1)
        }
    }
    
    return new
}

func ssiFixImgOff32(val: UInt32, at: UInt64, to: UInt64) -> UInt32 {
    // This should simply point to the new address
    guard to <= UInt32.max else {
        print("ssiFixImgOff32: Cannot fixup: Distance too large!")
        exit(-1)
    }
    
    return UInt32(to)
}

func ssiFixThP64(val: UInt64, at: UInt64, to: UInt64) -> UInt64 {
    let cf = ChainedFixups.ChainedStartsInSegment.ChainTarget(rawValue: val, bindsAre24Bit: false)
    
    switch cf {
    case .authRebase(target: _, diversity: let diversity, addrDiv: let addrDiv, key: let key, next: let next):
        guard to <= UInt32.max else {
            print("ssiFixThP64: Cannot fixup: Distance too large! [authRebase]")
            exit(-1)
        }
        
        return ChainedFixups.ChainedStartsInSegment.ChainTarget.authRebase(target: UInt32(to), diversity: diversity, addrDiv: addrDiv, key: key, next: next).rawValue
        
    case .authBind(ordinal: _, diversity: _, addrDiv: _, key: _, next: _):
        print("ssiFixThP64: authBind shouldn't exist!")
        exit(-1)
        
    case .rebase(target: _, high8: let high8, next: let next):
        guard to <= 0x7FFFFFFFFFF else {
            print("ssiFixThP64: Cannot fixup: Distance too large! [rebase]")
            exit(-1)
        }
        
        return ChainedFixups.ChainedStartsInSegment.ChainTarget.rebase(target: to, high8: high8, next: next).rawValue
        
    case .bind(ordinal: _, addend: _, next: _):
        print("ssiFixThP64: bind shouldn't exist!")
        exit(-1)
    }
}

func processSplitInfo(_ reader: ULEB128Reader, relocInfo: RelocInfo, isB: Bool) {
    let version = reader.read()
    guard version == 0x7F else {
        print("Only DYLD_CACHE_ADJ_V2_FORMAT is supported!")
        exit(-1)
    }
    
    let sectionCount = reader.read()
    for _ in 0..<sectionCount {
        let fromSectionIndex = reader.read()
        let toSectionIndex = reader.read()
        let toOffsetCount = reader.read()
        
        guard fromSectionIndex != 0 else {
            print("Invalid from section index in LC_SEGMENT_SPLIT_INFO - Cannot be zero!")
            exit(-1)
        }
        
        // https://forums.swift.org/t/mixing-var-and-let-in-tuple-destructuring/32459/5
        // Swift, WTF?!
        guard case (var fromSection, let fromSectionOldAddr, let fromSectionNewAddr)? = relocInfo.section(forIndex: Int(fromSectionIndex), isB: isB) else {
            print("Invalid from section index in LC_SEGMENT_SPLIT_INFO!")
            exit(-1)
        }
        
        guard let (_, toSectionOldAddr, toSectionNewAddr) = relocInfo.section(forIndex: Int(toSectionIndex), isB: isB) else {
            print("Invalid to section index in LC_SEGMENT_SPLIT_INFO!")
            exit(-1)
        }
        
        var toSectionOffset: UInt64 = 0
        for _ in 0..<toOffsetCount {
            let toSectionDelta = reader.read()
            let fromOffsetCount = reader.read()
            toSectionOffset += toSectionDelta
            
            for _ in 0..<fromOffsetCount {
                let kind = reader.read()
                
                let fromSectDeltaCount = reader.read()
                var fromSectionOffset: UInt64 = 0
                for _ in 0..<fromSectDeltaCount {
                    let delta = reader.read()
                    fromSectionOffset += delta
                    
                    // We will fix whatever is in fromSection at fromSectionOffset
                    // to point to toSection + toSectionOffset
                    let fromAddr = fromSectionNewAddr + fromSectionOffset
                    let toAddr   = toSectionNewAddr   + toSectionOffset
                    
                    let fromAddrOld = fromSectionOldAddr + fromSectionOffset
                    let toAddrOld   = toSectionOldAddr   + toSectionOffset
                    
                    //print("Fixing up \(pStr(fromAddr)) -> \(pStr(toAddr)) [orig: \(pStr(fromAddrOld)) -> \(pStr(toAddrOld))]")
                    
                    switch kind {
                    case 2:
                        let loc = fromSection.getGeneric(type: UInt32.self, offset: UInt(fromSectionOffset))
                        let new = loc + UInt32(toAddr - toAddrOld)
                        fromSection = fromSection[0..<Int(fromSectionOffset)] + Data(fromObject: new) + fromSection[Int(fromSectionOffset + 4)...]
                        break

                    case 5:
                        let adrp = fromSection.getGeneric(type: UInt32.self, offset: UInt(fromSectionOffset))
                        let new = ssiFixAdrp(adrp: adrp, at: fromAddr, to: toAddr)
                        fromSection = fromSection.subdata(in: 0..<Int(fromSectionOffset)) + Data(fromObject: new) + fromSection.subdata(in: Int(fromSectionOffset + 4)..<fromSection.count)
                        
                    case 6:
                        let instr = fromSection.getGeneric(type: UInt32.self, offset: UInt(fromSectionOffset))
                        let new = ssiFixOff12(instr: instr, at: fromAddr, to: toAddr, toOld: toAddrOld)
                        fromSection = fromSection[0..<Int(fromSectionOffset)] + Data(fromObject: new) + fromSection[Int(fromSectionOffset + 4)...]
                        
                    case 7:
                        let instr = fromSection.getGeneric(type: UInt32.self, offset: UInt(fromSectionOffset))
                        let new = ssiFixBr26(instr: instr, at: fromAddr, atOld: fromAddrOld, to: toAddr, toOld: toAddrOld)
                        fromSection = fromSection[0..<Int(fromSectionOffset)] + Data(fromObject: new) + fromSection[Int(fromSectionOffset + 4)...]
                        
                    case 12:
                        let val = fromSection.getGeneric(type: UInt32.self, offset: UInt(fromSectionOffset))
                        let new = ssiFixImgOff32(val: val, at: fromAddr, to: toAddr)
                        fromSection = fromSection[0..<Int(fromSectionOffset)] + Data(fromObject: new) + fromSection[Int(fromSectionOffset + 4)...]
                        
                    case 13:
                        let val = fromSection.getGeneric(type: UInt64.self, offset: UInt(fromSectionOffset))
                        let new = ssiFixThP64(val: val, at: fromAddr, to: toAddr)
                        fromSection = fromSection[0..<Int(fromSectionOffset)] + Data(fromObject: new) + fromSection[Int(fromSectionOffset + 8)...]
                        
                    default:
                        print("Unknow kind \(kind) in LC_SEGMENT_SPLIT_INFO!")
                        exit(-1)
                    }
                }
            }
        }
        
        // Write updated sections
        relocInfo.replaceSection(forIndex: Int(fromSectionIndex), isB: isB, data: fromSection)
    }
}

func fixupViaSplitInfo(infoA: MachOMergeData, infoB: MachOMergeData, relocInfo: RelocInfo) {
    guard let splitInfoA = infoA.splitInfo else {
        print("No LC_SEGMENT_SPLIT_INFO in A!")
        exit(-1)
    }
    
    guard let splitInfoB = infoB.splitInfo else {
        print("No LC_SEGMENT_SPLIT_INFO in A!")
        exit(-1)
    }
    
    let readerA = ULEB128Reader(data: splitInfoA)
    let readerB = ULEB128Reader(data: splitInfoB)
    
    processSplitInfo(readerA, relocInfo: relocInfo, isB: false)
    processSplitInfo(readerB, relocInfo: relocInfo, isB: true)
}

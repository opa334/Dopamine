//
//  ChainedFixups.swift
//  MachOMerger
//
//  Created by Linus Henze.
//

import Foundation
import SwiftMachO
import MachO

func mergeChainedFixups(infoA: MachOMergeData, infoB: MachOMergeData, relocInfo: RelocInfo, machOA: MachO, machOB: MachO) -> Data {
    guard let cfA = infoA.chainedFixups else {
        print("No chained fixups! [A]")
        exit(-1)
    }
    
    let versionA = cfA.getGeneric(type: UInt32.self, offset: 0)
    guard versionA == 0 else {
        print("Can only support version 0 chained fixups! [A]")
        exit(-1)
    }
    
    let startsOffA     = cfA.getGeneric(type: UInt32.self, offset: 4)
    //let importsOffA    = cfA.getGeneric(type: UInt32.self, offset: 8)
    //let symsOffA       = cfA.getGeneric(type: UInt32.self, offset: 12)
    let importsCountA  = cfA.getGeneric(type: UInt32.self, offset: 16)
    let importsFormatA = cfA.getGeneric(type: UInt32.self, offset: 20)
    let symsFormatA    = cfA.getGeneric(type: UInt32.self, offset: 24)
    guard symsFormatA == 0 else {
        print("Can only support symbol format 0 for chained fixups!")
        exit(-1)
    }
    
    guard let cfB = infoB.chainedFixups else {
        print("No chained fixups! [B]")
        exit(-1)
    }
    
    let versionB = cfB.getGeneric(type: UInt32.self, offset: 0)
    guard versionB == 0 else {
        print("Can only support version 0 chained fixups! [A]")
        exit(-1)
    }
    
    let startsOffB     = cfB.getGeneric(type: UInt32.self, offset: 4)
    //let importsOffB    = cfB.getGeneric(type: UInt32.self, offset: 8)
    //let symsOffB       = cfB.getGeneric(type: UInt32.self, offset: 12)
    let importsCountB  = cfB.getGeneric(type: UInt32.self, offset: 16)
    let importsFormatB = cfB.getGeneric(type: UInt32.self, offset: 20)
    let symsFormatB    = cfB.getGeneric(type: UInt32.self, offset: 24)
    guard symsFormatB == 0 else {
        print("Can only support symbol format 0 for chained fixups!")
        exit(-1)
    }
    
    guard importsFormatA == importsFormatB else {
        print("Chained fixups imports format must be the same for both binaries!")
        exit(-1)
    }
    
    // For our limited usecase, assume these binaries imports nothing
    /*guard importsCountA == 0 && importsCountB == 0 else {
        print("XXX: Can only support zero imports right now!")
        exit(-1)
    }*/
    
    // If there are any imports, resolve them now
    guard importsCountA == 0 else {
        print("XXX: Can only support zero imports for A right now!")
        exit(-1)
    }
    
    if importsCountB != 0 {
        // Need to walk chain
        let cf = try! b.getChainedFixups()
        let symTable = try! a.getSymbolTable()
        try! cf.forEachFixup({ location, vAddr, content in
            if case .authBind(ordinal: _, diversity: let diversity, addrDiv: let addrDiv, key: let key, next: let next) = content {
                let segment = relocInfo.segment(forOrigAddress: location, isB: true)!
                let off = Int(segment.3)
                var data = segment.1
                let dat = data.getGeneric(type: UInt64.self, offset: UInt(segment.3))
                guard dat == content.rawValue else {
                    print("XXX: ChainedFixups .authBind err!")
                    exit(-1)
                }
                
                guard let sym = cf.symbol(forFixup: content) else {
                    print("Couldn't find symbol in imports table!")
                    exit(-1)
                }
                
                var isB = false
                var dst: UInt64!
                if let d = getMagicSymbolVal(sym) {
                    dst = d.0
                    isB = d.1
                } else if let d = symTable.symbol(forName: sym) {
                    dst = d.value
                }
                
                guard dst != nil else {
                    print("Cannot resolve symbol \(sym)!")
                    exit(-1)
                }
                
                let new = ChainedFixups.ChainedStartsInSegment.ChainTarget.authRebase(target: UInt32(relocInfo.translate(address: dst, isB: isB)), diversity: diversity, addrDiv: addrDiv, key: key, next: next)
                data = data.subdata(in: 0..<off) + Data(fromObject: new.rawValue) + data.subdata(in: (off+8)..<data.count)
                relocInfo.replaceSegment(name: segment.0, isB: true, data: data)
            } else if case .bind(ordinal: _, addend: _, next: let next) = content {
                let segment = relocInfo.segment(forOrigAddress: location, isB: true)!
                let off = Int(segment.3)
                var data = segment.1
                let dat = data.getGeneric(type: UInt64.self, offset: UInt(segment.3))
                guard dat == content.rawValue else {
                    print("XXX: ChainedFixups .bind err!")
                    exit(-1)
                }
                
                let sym = cf.symbol(forFixup: content)!
                
                var isB = false
                var dst: UInt64!
                if let d = getMagicSymbolVal(sym) {
                    dst = d.0
                    isB = d.1
                } else if let d = symTable.symbol(forName: sym) {
                    dst = d.value
                }
                
                guard dst != nil else {
                    print("Cannot resolve symbol \(sym)!")
                    exit(-1)
                }
                
                let new = ChainedFixups.ChainedStartsInSegment.ChainTarget.rebase(target: relocInfo.translate(address: dst, isB: isB), high8: 0, next: next)
                data = data.subdata(in: 0..<off) + Data(fromObject: new.rawValue) + data.subdata(in: (off+8)..<data.count)
                relocInfo.replaceSegment(name: segment.0, isB: true, data: data)
            }
        })
    }
    
    // Okay, we only have to fix the starts
    let startsA = cfA.advanced(by: Int(startsOffA))
    let startsB = cfB.advanced(by: Int(startsOffB))
    
    let segCountA = startsA.getGeneric(type: UInt32.self)
    let segCountB = startsB.getGeneric(type: UInt32.self)
    
    var segsA: [Data?] = []
    var segsB: [Data?] = []
    
    for i in 0..<UInt(segCountA) {
        let off  = Int(startsA.getGeneric(type: UInt32.self, offset: 4 + (4 * i))) + 4
        if off == 4 {
            segsA.append(nil)
            continue
        }
        
        let size = Int(startsA.getGeneric(type: UInt32.self, offset: UInt(off - 4)))
        
        var data = startsA.subdata(in: off..<(off + size))
        
        // Get matching segment
        let seg = relocInfo.segment(forIndex: Int(i), isB: false)
        
        // Change segment offset
        let segmentOff = data.getGeneric(type: UInt64.self, offset: 0x4)
        
        data = data.subdata(in: 0..<4) + Data(fromObject: segmentOff &+ seg.2) + data.subdata(in: 12..<data.count)
        
        segsA.append(data)
    }
    
    for i in 0..<UInt(segCountB) {
        let off = Int(startsB.getGeneric(type: UInt32.self, offset: 4 + (4 * i))) + 4
        if off == 4 {
            segsB.append(nil)
            continue
        }
        
        let size = Int(startsB.getGeneric(type: UInt32.self, offset: UInt(off - 4)))
        
        var data = startsB.subdata(in: off..<(off + size))
        
        // Get matching segment
        let seg = relocInfo.segment(forIndex: Int(i), isB: true)
        
        // Change segment offset
        let segmentOff = data.getGeneric(type: UInt64.self, offset: 0x4)
        
        data = data.subdata(in: 0..<4) + Data(fromObject: segmentOff &+ seg.2) + data.subdata(in: 12..<data.count)
        
        segsB.append(data)
    }
    
    // Now merge them
    var segsMerged: [Data?] = []
    var curA = 0
    var curB = 0
    for seg in relocInfo.segRel {
        if !seg.1[0].isB && seg.1.count == 1 {
            // Only A
            segsMerged.append(segsA[curA])
            curA += 1
        } else if seg.1[0].isB {
            // Only B
            segsMerged.append(segsB[curB])
            curB += 1
        } else {
            // Merge
            if let a = segsA[curA],
               let b = segsB[curB] {
                let offA = a.getGeneric(type: UInt64.self, offset: 0x4)
                let offB = b.getGeneric(type: UInt64.self, offset: 0x4)
                
                let pgSizeA = a.getGeneric(type: UInt16.self, offset: 0x0)
                let pgSizeB = b.getGeneric(type: UInt16.self, offset: 0x0)
                guard pgSizeA == pgSizeB else {
                    print("mergeChainedFixups: Page Size not equal!")
                    exit(-1)
                }
                
                let pageOffMask = UInt64(pgSizeA) - 1
                let diff = offB - offA
                guard diff & pageOffMask == 0 else {
                    print("mergeChainedFixups: Distance not multiple of page size!")
                    exit(-1)
                }
                
                let pageDiff = diff / UInt64(pgSizeA)
                guard pageDiff < UInt16.max else {
                    print("mergeChainedFixups: Distance too large!")
                    exit(-1)
                }
                
                // Emit A with additional pages
                let countA = a.getGeneric(type: UInt16.self, offset: 0x10)
                let countB = b.getGeneric(type: UInt16.self, offset: 0x10)
                var offs = Data()
                for _ in 0..<UInt(pageDiff - UInt64(countA)) {
                    offs += Data(fromObject: UInt16(0xFFFF))
                }
                
                for i in 0..<UInt(countB) {
                    offs += Data(fromObject: b.getGeneric(type: UInt16.self, offset: 0x12 + (2 * i)))
                }
                
                let data = a.subdata(in: 0..<0x10) + Data(fromObject: countA + countB + (UInt16(pageDiff) - countA)) + a.subdata(in: 0x12..<(0x12 + (2 * Int(countA)))) + offs
                segsMerged.append(data)
            } else if segsB[curB] == nil {
                // Effectively only A (maybe)
                segsMerged.append(segsA[curA])
            } else {
                // Effectively only B (maybe)
                segsMerged.append(segsB[curB])
            }
            
            curA += 1
            curB += 1
        }
    }
    
    // Generate the starts header
    var starts  = Data()
    var segData = Data()
    starts.appendGeneric(value: UInt32(segsMerged.count + 1))
    
    let needsAdjust = segsMerged.count & 1 == 1
    let theOff = segsMerged.count + 1 + (needsAdjust ? 1 : 0)
    for i in 0..<segsMerged.count {
        if let s = segsMerged[i] {
            let off = 4 + (4 * theOff) + segData.count
            starts.appendGeneric(value: UInt32(off))
            
            let toAppend = Data(fromObject: UInt32(s.count) + 4) + s
            segData += toAppend
        } else {
            starts.appendGeneric(value: 0 as UInt32)
        }
    }
    
    starts.appendGeneric(value: 0 as UInt32) // LINKEDIT
    
    // Is this needed?
    if needsAdjust {
        starts.appendGeneric(value: 0 as UInt32)
    }
    
    let startsSegData = starts + segData
    
    var newChainedFixups = Data()
    
    // Emit header
    newChainedFixups.appendGeneric(value:  0 as UInt32)                     // ???
    newChainedFixups.appendGeneric(value: 32 as UInt32)                     // startsOff
    newChainedFixups.appendGeneric(value: UInt32(32 + startsSegData.count)) // importsOff
    newChainedFixups.appendGeneric(value: UInt32(32 + startsSegData.count)) // symsOff
    newChainedFixups.appendGeneric(value: 0 as UInt32)                      // importsCount
    newChainedFixups.appendGeneric(value: importsFormatA)                   // importsFormat
    newChainedFixups.appendGeneric(value: symsFormatA)                      // symsFormat
    newChainedFixups.appendGeneric(value: 0 as UInt32)                      // pad
    
    // Emit data
    newChainedFixups.append(startsSegData)
    
    return newChainedFixups
}

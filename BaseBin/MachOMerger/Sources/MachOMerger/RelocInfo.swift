//
//  RelocInfo.swift
//  MachOMerger
//
//  Created by Linus Henze on 2023-03-15.
//

import Foundation
import SwiftMachO

class RelocInfo {
    public private(set) var segRel: SegRelocInfo
    
    init(segRel: SegRelocInfo) {
        self.segRel = segRel
    }
    
    public func segment(forOrigAddress addr: UInt64, isB: Bool) -> (String, Data, UInt64, UInt64)? {
        for seg in segRel {
            if !isB {
                let s = seg.1[0]
                guard !s.isB else { continue }
                
                let base = s.origCommand.vmAddr
                if addr >= base {
                    if addr < (base + s.origCommand.vmSize) {
                        return (seg.0, s.data, s.offset, addr - base)
                    }
                }
            } else {
                let s = (seg.1.count == 2) ? seg.1[1] : seg.1[0]
                guard s.isB else { continue }
                
                let base = s.origCommand.vmAddr
                if addr >= base {
                    if addr < (base + s.origCommand.vmSize) {
                        return (seg.0, s.data, s.offset, addr - base)
                    }
                }
            }
        }
        
        return nil
    }
    
    public func segment(forName name: String, isB: Bool) -> (Data, UInt64)? {
        for seg in segRel {
            guard seg.0 == name else { continue }
            
            if !isB {
                let s = seg.1[0]
                guard !s.isB else {
                    return nil
                }
                
                return (s.data, s.offset)
            } else {
                let s = (seg.1.count == 2) ? seg.1[1] : seg.1[0]
                guard s.isB else {
                    return nil
                }
                
                return (s.data, s.offset)
            }
        }
        
        return nil
    }
    
    public func segment(forIndex index: Int, isB: Bool) -> (Segment64LoadCommand, Data, UInt64) {
        var currentIndex = 0
        for seg in segRel {
            if !isB {
                let s = seg.1[0]
                guard !s.isB else { continue }
                
                if currentIndex == index {
                    return (s.origCommand, s.data, s.offset)
                }
                
                currentIndex += 1
            } else {
                let s = (seg.1.count == 2) ? seg.1[1] : seg.1[0]
                guard s.isB else { continue }
                
                if currentIndex == index {
                    return (s.origCommand, s.data, s.offset)
                }
                
                currentIndex += 1
            }
        }
        
        print("Invalid segment index \(index)")
        exit(-1)
    }
    
    public func replaceSegment(name: String, isB: Bool, data: Data) {
        for i in 0..<segRel.count {
            guard segRel[i].0 == name else { continue }
            
            if !isB {
                guard !segRel[i].1[0].isB else {
                    print("A does not have segment \(name)")
                    exit(-1)
                }
                
                segRel[i].1[0].data = data
                return
            } else {
                let which = (segRel[i].1.count == 2) ? 1 : 0
                guard segRel[i].1[which].isB else {
                    print("B does not have segment \(name)")
                    exit(-1)
                }
                
                segRel[i].1[which].data = data
                return
            }
        }
        
        print("Bad segment name \(name)")
        exit(-1)
    }
    
    public func section(forIndex: Int, isB: Bool) -> (Data, UInt64, UInt64)? {
        if forIndex == 0 {
            // mach header
            // Should point to the new one
            if !isB {
                return (Data(), segRel[0].1[0].origCommand.vmAddr, 0)
            } else {
                return (Data(), segRel[0].1[1].origCommand.vmAddr, 0)
            }
        }
        
        var currentIndex = 1
        for seg in segRel {
            var s: (isB: Bool, origCommand: Segment64LoadCommand, data: Data, offset: UInt64)!
            if !isB {
                s = seg.1[0]
                guard !s.isB else {
                    continue
                }
            } else {
                s = (seg.1.count == 2) ? seg.1[1] : seg.1[0]
                guard s.isB else {
                    continue
                }
            }
            
            for sect in s!.origCommand.sections {
                if currentIndex == forIndex {
                    // This is what we want
                    let off  = Int(sect.address) - Int(s!.origCommand.vmAddr)
                    let size = Int(sect.size)
                    
                    // Zero-fill sections have no file data; return empty
                    let sectionType = sect.flags.rawValue & 0xFF
                    if sectionType == 0x1 /* S_ZEROFILL */ || sectionType == 0xC /* S_GB_ZEROFILL */ {
                        return (Data(count: size), sect.address, sect.address &+ s!.offset)
                    }
                    
                    // Also guard against off-disk BSS-like sections
                    guard off + size <= s!.data.count else {
                        // Clamp to what's on disk, pad the rest
                        let available = max(0, s!.data.count - off)
                        let fileData = available > 0 ? s!.data.subdata(in: off..<(off + available)) : Data()
                        return (fileData + Data(count: size - available), sect.address, sect.address &+ s!.offset)
                    }
                    
                    let data = s!.data.subdata(in: off..<(off + size))
                    return (data, sect.address, sect.address &+ s!.offset)
                }
                currentIndex += 1
            }
        }
        
        return nil
    }
    
    public func replaceSection(forIndex: Int, isB: Bool, data: Data) {
        guard forIndex != 0 else {
            print("Cannot replace mach header!")
            exit(-1)
        }
        
        var currentIndex = 1
        for i in 0..<segRel.count {
            var which = 0
            if !isB {
                guard !segRel[i].1[0].isB else {
                    continue
                }
            } else {
                which = (segRel[i].1.count == 2) ? 1 : 0
                guard segRel[i].1[which].isB else {
                    continue
                }
            }
            
            for sect in segRel[i].1[which].origCommand.sections {
                if currentIndex == forIndex {
                    // This is what we want
                    let off  = Int(sect.address) - Int(segRel[i].1[which].origCommand.vmAddr)
                    let size = Int(sect.size)
                    
                    let before = segRel[i].1[which].data.subdata(in: 0..<off)
                    let after  = segRel[i].1[which].data.subdata(in: (off + size)..<segRel[i].1[which].data.count)
                    let data = before + data + after
                    
                    assert(data.count == segRel[i].1[which].data.count)
                    
                    segRel[i].1[which].data = data
                    
                    return
                }
                
                currentIndex += 1
            }
        }
        
        print("Bad section index \(forIndex)")
        exit(-1)
    }
    
    public func translate(address: UInt64, isB: Bool) -> UInt64 {
        address + segment(forOrigAddress: address, isB: isB)!.2
    }
}

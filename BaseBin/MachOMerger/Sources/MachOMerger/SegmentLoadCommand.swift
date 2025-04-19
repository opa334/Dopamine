//
//  SegmentLoadCommand.swift
//  MachOMerger
//
//  Created by Linus Henze on 2023-03-16.
//

import Foundation
import MachO

func generateSegmentLoadCommands(infoA: MachOMergeData, infoB: MachOMergeData, relocInfo: RelocInfo) -> (Int, Data) {
    var result = Data()
    for i in 0..<relocInfo.segRel.count {
        let seg = relocInfo.segRel[i]
        
        // Emit it
        let base = seg.1[0].origCommand.vmAddr &+ seg.1[0].offset
        
        var sects = seg.1[0].origCommand.sections.count
        if seg.1.count > 1 {
            sects += seg.1[1].origCommand.sections.count
        }
        
        var slc = segment_command_64()
        slc.cmd = UInt32(LC_SEGMENT_64)
        slc.cmdsize = UInt32(MemoryLayout<segment_command_64>.size + (MemoryLayout<section_64>.size * sects))
        _ = withUnsafeMutableBytes(of: &slc.segname) { ptr in
            strcpy(ptr.baseAddress!, seg.0)
        }
        
        if i == 0 {
            slc.vmaddr = 0
            if seg.1.count == 1 {
                slc.vmsize = seg.1[0].origCommand.vmSize + 0x4000
                slc.filesize = seg.1[0].origCommand.fileSize + 0x4000
            } else {
                slc.vmsize = seg.1[0].origCommand.vmSize + seg.1[1].origCommand.vmSize + 0x4000
                slc.filesize = seg.1[0].origCommand.fileSize + seg.1[1].origCommand.fileSize + 0x4000
            }
            
            slc.fileoff = 0
            slc.maxprot = VM_PROT_READ | VM_PROT_EXECUTE
            slc.initprot = VM_PROT_READ | VM_PROT_EXECUTE
        } else {
            slc.vmaddr = base
            if seg.1.count == 1 {
                slc.vmsize = seg.1[0].origCommand.vmSize
                slc.filesize = seg.1[0].origCommand.fileSize
            } else {
                slc.vmsize = seg.1[0].origCommand.vmSize + seg.1[1].origCommand.vmSize
                slc.filesize = seg.1[0].origCommand.fileSize + seg.1[1].origCommand.fileSize
            }
            
            slc.fileoff = seg.1[0].origCommand.fileOffset + seg.1[0].offset
            slc.maxprot = Int32(bitPattern: seg.1[0].origCommand.maximumProt.rawValue)
            slc.initprot = Int32(bitPattern: seg.1[0].origCommand.protection.rawValue)
        }
        
        slc.nsects = UInt32(sects)
        slc.flags = seg.1[0].origCommand.flags
        
        var sectsData = Data()
        for sect in seg.1[0].origCommand.sections {
            var sectLC = section_64()
            _ = withUnsafeMutableBytes(of: &sectLC.sectname) { ptr in
                strcpy(ptr.baseAddress!, sect.section)
            }
            _ = withUnsafeMutableBytes(of: &sectLC.segname) { ptr in
                strcpy(ptr.baseAddress!, seg.0)
            }
            
            sectLC.addr = sect.address + seg.1[0].offset
            sectLC.size = sect.size
            sectLC.offset = sect.offset + UInt32(seg.1[0].offset)
            sectLC.align = sect.alignment
            sectLC.flags = sect.flags.rawValue
            sectLC.reserved1 = sect.reserved1
            sectLC.reserved2 = sect.reserved2
            sectLC.reserved3 = sect.reserved3
            
            sectsData.appendGeneric(value: sectLC)
        }
        
        if seg.1.count > 1 {
            for sect in seg.1[1].origCommand.sections {
                var sectLC = section_64()
                _ = withUnsafeMutableBytes(of: &sectLC.sectname) { ptr in
                    if sect.section != "__jbinfo" {
                        // Special case, "__DATA:__jbinfo" section should not be appended with "_2"
                        // Ideally I would have added a check here to only add _2 if the section already exists in file a
                        // But then again this is Swift
                        strcpy(ptr.baseAddress!, sect.section + "_2")
                    }
                    else {
                        strcpy(ptr.baseAddress!, sect.section)
                    }
                }
                _ = withUnsafeMutableBytes(of: &sectLC.segname) { ptr in
                    strcpy(ptr.baseAddress!, seg.0)
                }
                
                sectLC.addr = sect.address + seg.1[1].offset
                sectLC.size = sect.size
                sectLC.offset = sect.offset + UInt32(seg.1[1].offset)
                sectLC.align = sect.alignment
                sectLC.flags = sect.flags.rawValue
                sectLC.reserved1 = sect.reserved1
                sectLC.reserved2 = sect.reserved2
                sectLC.reserved3 = sect.reserved3
                
                sectsData.appendGeneric(value: sectLC)
            }
        }
        
        result.appendGeneric(value: slc)
        result.append(sectsData)
    }
    
    return (relocInfo.segRel.count, result)
}

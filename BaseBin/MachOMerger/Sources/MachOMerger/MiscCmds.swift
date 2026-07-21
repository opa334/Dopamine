//
//  MiscCmds.swift
//  MachOMerger
//
//  Created by Linus Henze on 2023-03-16.
//

import Foundation
import MachO

func emitUUIDCmd() -> (Int, Data) {
    let cmd = uuid_command(cmd: UInt32(LC_UUID), cmdsize: UInt32(MemoryLayout<uuid_command>.size), uuid: UUID().uuid)
    
    return (1, Data(fromObject: cmd))
}

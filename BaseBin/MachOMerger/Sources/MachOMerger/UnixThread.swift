//
//  UnixThread.swift
//  MachOMerger
//
//  Created by Linus Henze on 2023-03-16.
//

import Foundation
import MachO

func emitUnixthread(info: MachOMergeData, relocInfo: RelocInfo, isB: Bool) -> (Int, Data) {
    let ths = info.unixthread!
    guard ths.count == 1 else {
        print("More than one UnixThread?!")
        exit(-1)
    }
    
    let th = ths[0]
    guard th.flavor == ARM_THREAD_STATE64 && th.state.count == MemoryLayout<arm_thread_state64_t>.size else {
        print("Can only support ARM64 threads!")
        exit(-1)
    }
    
    var thA64 = th.state.getGeneric(type: arm_thread_state64_t.self)
    
    thA64.__pc = relocInfo.translate(address: thA64.__pc, isB: isB)
    if let st = try? b.getSymbolTable() {
        if let newStart = st.symbol(forName: "_MACHOMERGER_START_HOOK") {
            thA64.__pc = relocInfo.translate(address: newStart.value, isB: true)
        }
    }
    
    var result = Data()
    result.appendGeneric(value: UInt32(LC_UNIXTHREAD))
    result.appendGeneric(value: UInt32(16 + MemoryLayout<arm_thread_state64_t>.size))
    result.appendGeneric(value: UInt32(ARM_THREAD_STATE64))
    result.appendGeneric(value: UInt32(MemoryLayout<arm_thread_state64_t>.size / 4))
    result.appendGeneric(value: thA64)
    
    return (1, result)
}

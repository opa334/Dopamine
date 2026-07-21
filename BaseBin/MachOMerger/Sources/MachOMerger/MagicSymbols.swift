//
//  MagicSymbols.swift
//  MachOMerger
//
//  Created by Linus Henze on 2023-03-16.
//

import Foundation

func getMagicSymbolVal(_ sym: String) -> (UInt64, Bool)? {
    switch sym {
    case "_MACHOMERGER_REAL_START":
        guard let ths = dataA.unixthread else {
            print("Cannot get real start: A has no unixthread")
            exit(-1)
        }
        
        guard ths.count == 1 else {
            print("More than one UnixThread?!")
            exit(-1)
        }
        
        let th = ths[0]
        guard th.flavor == ARM_THREAD_STATE64 && th.state.count == MemoryLayout<arm_thread_state64_t>.size else {
            print("Can only support ARM64 threads!")
            exit(-1)
        }
        
        let thA64 = th.state.getGeneric(type: arm_thread_state64_t.self)
        return (thA64.__pc, false)
        
    default:
        return nil
    }
}

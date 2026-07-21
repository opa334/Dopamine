//
//  ULEB128Reader.swift
//  MachOMerger
//
//  Created by Linus Henze on 2023-03-15.
//

import Foundation

class ULEB128Reader {
    private let data: Data
    private var pos: Int = 0
    
    init(data: Data) {
        self.data = data
    }
    
    func read() -> UInt64 {
        var result: UInt64 = 0
        var shift = 0
        while true {
            let dec = data[pos]
            pos += 1
            
            let tmp = UInt64(dec & 0x7F)
            let val = tmp << shift
            if (val >> shift) != tmp {
                // Overflow
                print("ULEB128Reader: Overflow")
                exit(-1)
            }
            
            shift += 7
            
            result |= val
            
            if (dec >> 7) == 0 {
                return result
            }
        }
    }
}

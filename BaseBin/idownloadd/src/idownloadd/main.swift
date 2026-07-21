//
//  main.swift
//  idownloadd
//
//  Created by Lars Fröder on 08.06.23.
//

import Foundation
import iDownload

jbclient_initialize_primitives()

do {
    try iDownload.launch_iDownload(krw: iDownloadKRW(), otherCmds: iDownloadCmds)
} catch let e {
    NSLog("Failed to launch iDownload: \(e)")
    exit(1)
}

RunLoop.main.run()

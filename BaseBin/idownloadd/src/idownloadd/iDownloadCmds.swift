//
//  iDownloadCMDs.swift
//  idownloadd
//
//  Created by Lars Fröder on 08.06.23.
//

import Foundation
import iDownload

let iDownloadCmds = [
    "help": iDownload_help
] as [String: iDownloadCmd]

func iDownload_help(_ hndlr: iDownloadHandler, _ cmd: String, _ args: [String]) throws {
    try hndlr.sendline("")
}

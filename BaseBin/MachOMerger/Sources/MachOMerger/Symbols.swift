//
//  Symbols.swift
//  MachOMerger
//
//  Created by Linus Henze on 2023-03-16.
//

import Foundation
import MachO

func extractSymbols(info: MachOMergeData) -> ([nlist_64]) {
    let syms = info.symtab?.symbols
    return (syms?.withUnsafeBytes({ ptr in
        [nlist_64](ptr.assumingMemoryBound(to: nlist_64.self))
    }))!
}

func fixup(symbols: [nlist_64], start: Int, count: Int, strOff: Int, relocInfo: RelocInfo, isB: Bool) -> Data {
    var syms = Data()
    let end  = start + count
    for i in start..<end {
        var sym = symbols[i]
        
        // Fix it up
        sym.n_un.n_strx += UInt32(strOff)
        sym.n_value = relocInfo.translate(address: sym.n_value, isB: isB)
        syms.appendGeneric(value: sym)
    }
    
    return syms
}

func emitSymtabDysymtab(infoA: MachOMergeData, infoB: MachOMergeData, relocInfo: RelocInfo, linkedit: inout Data, linkeditStart: Int) -> (Int, Data) {
    let symsA = extractSymbols(info: infoA)
    let symsB = extractSymbols(info: infoB)
    
    let dsymA = infoA.dysymtab!
    let dsymB = infoB.dysymtab!
    guard dsymA.localCount + dsymA.externalCount + dsymA.undefCount == symsA.count else {
        print("DSYMTAB is wrong! [A]")
        exit(-1)
    }
    
    guard dsymB.localCount + dsymB.externalCount + dsymB.undefCount == symsB.count else {
        print("DSYMTAB is wrong! [B]")
        exit(-1)
    }
    
    // Generate the new one
    var syms = Data()
    syms += fixup(symbols: symsA, start: dsymA.localStart, count: dsymA.localCount, strOff: 0, relocInfo: relocInfo, isB: false)
    syms += fixup(symbols: symsB, start: dsymB.localStart, count: dsymB.localCount, strOff: infoA.symtab!.strings.count, relocInfo: relocInfo, isB: true)
    
    let eSymsOff = syms.count / MemoryLayout<nlist_64>.size
    syms += fixup(symbols: symsA, start: dsymA.externalStart, count: dsymA.externalCount, strOff: 0, relocInfo: relocInfo, isB: false)
    syms += fixup(symbols: symsB, start: dsymB.externalStart, count: dsymB.externalCount, strOff: infoA.symtab!.strings.count, relocInfo: relocInfo, isB: true)
    
    let uSymsOff = syms.count / MemoryLayout<nlist_64>.size
    syms += fixup(symbols: symsA, start: dsymA.undefStart, count: dsymA.undefCount, strOff: 0, relocInfo: relocInfo, isB: false)
    syms += fixup(symbols: symsB, start: dsymB.undefStart, count: dsymB.undefCount, strOff: infoA.symtab!.strings.count, relocInfo: relocInfo, isB: true)
    
    let symtabOff = linkeditStart + linkedit.count
    linkedit += syms
    
    let strtabOff = linkeditStart + linkedit.count
    linkedit += infoA.symtab!.strings + infoB.symtab!.strings
    
    var symtab = symtab_command()
    symtab.cmd = UInt32(LC_SYMTAB)
    symtab.cmdsize = UInt32(MemoryLayout<symtab_command>.size)
    symtab.symoff = UInt32(symtabOff)
    symtab.nsyms = UInt32(symsA.count + symsB.count)
    symtab.stroff = UInt32(strtabOff)
    symtab.strsize = UInt32(infoA.symtab!.strings.count + infoB.symtab!.strings.count)
    
    var dysym = dysymtab_command()
    dysym.cmd = UInt32(LC_DYSYMTAB)
    dysym.cmdsize = UInt32(MemoryLayout<dysymtab_command>.size)
    dysym.ilocalsym = 0
    dysym.nlocalsym = UInt32(dsymA.localCount + dsymB.localCount)
    dysym.iextdefsym = UInt32(eSymsOff)
    dysym.nextdefsym = UInt32(dsymA.externalCount + dsymB.externalCount)
    dysym.iundefsym = UInt32(uSymsOff)
    dysym.nundefsym = UInt32(dsymA.undefCount + dsymB.undefCount)
    
    return (2, Data(fromObject: symtab) + Data(fromObject: dysym))
}

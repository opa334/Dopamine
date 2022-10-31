//
//  main.swift
//  fastPathSign
//
//  Created by Linus Henze.
//  Copyright © 2022 Pinauten GmbH. All rights reserved.
//

import Foundation
import Security
import Security_Codesign

if CommandLine.arguments.count < 2 {
    print("Usage: fastPathSign <MachO path> <optional team identifier>")
    exit(-1)
}

let path = CommandLine.arguments[1]

var teamID = "Pinauten"
if CommandLine.arguments.count >= 3 {
    teamID = CommandLine.arguments[2]
}

var staticCode: SecStaticCode!
var err = SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &staticCode)
guard err == kOSReturnSuccess,
      staticCode != nil else {
    print("SecStaticCodeCreateWithPath failed!")
    exit(-1)
}

var props: CFDictionary!
err = SecCodeCopySigningInformation(staticCode, [], &props)
guard err == kOSReturnSuccess,
      props != nil else {
    print("SecCodeCopySigningInformation failed!")
    exit(-1)
}

guard let sProps = props as? [String: Any] else {
    print("SecCodeCopySigningInformation returned bad props!")
    exit(-1)
}

var identityCF: CFTypeRef?
err = SecItemCopyMatching([kSecMatchLimit: kSecMatchLimitAll, kSecClass: kSecClassIdentity, kSecReturnRef: true] as CFDictionary, &identityCF)
guard err == kOSReturnSuccess,
      identityCF != nil else {
    print("SecItemCopyMatching failed!!")
    exit(-1)
}

guard CFGetTypeID(identityCF) == CFArrayGetTypeID() else {
    print("SecItemCopyMatching returned bad data!")
    exit(-1)
}

let identities = identityCF as! CFArray as [AnyObject]
guard identities.count != 0 else {
    print("SecItemCopyMatching returned empty array!")
    print("Make sure to import Exploits/fastPath/arm.pfx!")
    exit(-1)
}

var identity: SecIdentity!
for id in identities {
    guard CFGetTypeID(id) == SecIdentityGetTypeID() else {
        continue
    }
    
    var cert: SecCertificate?
    var name: CFString?
    SecIdentityCopyCertificate(id as! SecIdentity, &cert)
    guard cert != nil else {
        continue
    }
    
    SecCertificateCopyCommonName(cert.unsafelyUnwrapped, &name)
    guard name != nil else {
        continue
    }
    
    if String(name.unsafelyUnwrapped) == "Pinauten PWN Cert" {
        identity = (id as! SecIdentity)
        break
    }
}

guard let identity = identity else {
    print("Couldn't find identity!")
    print("Make sure to import Exploits/fastPath/arm.pfx!")
    exit(-1)
}

var signerProps = [
    kSecCodeSignerIdentity!: identity,
    kSecCodeSignerPlatformIdentifier!: 13,
    kSecCodeSignerTeamIdentifier!: teamID
] as [CFString: Any]

func copyIfPossible(_ name: CFString, as: CFString) {
    if let value = sProps[name as String] {
        signerProps[`as`] = value
    }
}

copyIfPossible(kSecCodeInfoRequirementData, as: kSecCodeSignerRequirements)
copyIfPossible(kSecCodeInfoEntitlements, as: kSecCodeSignerEntitlements)
copyIfPossible(kSecCodeInfoIdentifier, as: kSecCodeSignerIdentifier)
copyIfPossible(kSecCodeInfoResourceDirectory, as: kSecCodeSignerResourceRules)

var signer: SecCodeSignerRef?
err = SecCodeSignerCreate(signerProps as CFDictionary, [], &signer)
guard err == kOSReturnSuccess,
      signer != nil else {
    print("SecCodeSignerCreate failed!")
    exit(-1)
}

// Now sign
var cfError: Unmanaged<CFError>?
err = SecCodeSignerAddSignatureWithErrors(signer, staticCode, [], &cfError)
guard err == kOSReturnSuccess else {
    print("SecCodeSignerAddSignatureWithErrors failed!")
    if cfError != nil {
        print(cfError!.takeRetainedValue().localizedDescription)
    } else {
        print("<no error description>")
    }
    exit(-1)
}

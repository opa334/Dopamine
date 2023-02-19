import CBindings;

class Bootstrapper {

    static func remountPrebootPartition(writable: Bool) -> Int32? {
        if writable {
            return execCmd(args: ["/sbin/mount", "-u", "-w", "/private/preboot"])
        } else {
            return execCmd(args: ["/sbin/mount", "-u", "/private/preboot"])
        }
	}
    
    static func untar(tarPath: String, target: String) -> Int32? {
        let tarBinary = Bundle.main.bundlePath + "/tar"
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tarBinary)
        return execCmd(args: [tarBinary, "-xpkf", tarPath, "-C", target]);
    }

	static func generateFakeRootPath() -> String {
		let letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
		var result = ""
		for _ in 0..<6 {
			let randomIndex = Int(arc4random_uniform(UInt32(letters.count)))
			let randomCharacter = letters[letters.index(letters.startIndex, offsetBy: randomIndex)]
			result += String(randomCharacter)
		}
		return "/private/preboot/jb-" + result
	}

	static func locateExistingFakeRoot() -> String? {
        let ppURL = URL(fileURLWithPath: "/private/preboot")
        guard let candidateURLs = try? FileManager.default.contentsOfDirectory(at: ppURL , includingPropertiesForKeys: nil, options: []) else { return nil }
		for candidateURL in candidateURLs {
			if candidateURL.lastPathComponent.hasPrefix("jb-") {
				return candidateURL.path
			}
		}
		return nil
	}

    static func doBootstrap() {
        let jbPath = "/var/jb"

        if remountPrebootPartition(writable: true) != 0 {
            NSLog("Failed to remount /private/preboot partition as writable")
            return
        }
        
        // Remove existing /var/jb symlink if it exists (will be recreated later)
        
        do {
            if FileManager.default.fileExists(atPath: jbPath) {
                try FileManager.default.removeItem(atPath: jbPath)
            }
        } catch let error as NSError {
            NSLog("Failed to delete existing /var/jb symlink: \(error)")
            return
        }
        
        // Ensure fake root directory inside /private/preboot exists
        
        var fakeRootPath = locateExistingFakeRoot()
        if fakeRootPath == nil {
            fakeRootPath = generateFakeRootPath()
            do {
                try FileManager.default.createDirectory(atPath: fakeRootPath!, withIntermediateDirectories: true)
            } catch let error as NSError {
                NSLog("Failed to create \(fakeRootPath!): \(error)")
                return
            }
        }
        
        // Extract Procursus Bootstrap if neccessary
        
        var bootstrapNeedsExtract = false
        var procursusPath = fakeRootPath! + "/procursus"
        var installedPath = procursusPath + "/.installed_fugu15max"

        if FileManager.default.fileExists(atPath: procursusPath) {
            if !FileManager.default.fileExists(atPath: installedPath) {
                NSLog("Wiping existing bootstrap because installed file not found")
                do {
                    chflags(fakeRootPath, UInt32(0))
                    try FileManager.default.removeItem(atPath: procursusPath)
                } catch let error as NSError {
                    NSLog("Failed to delete existing Procursus directory: \(error)")
                    return
                }
            }
        }

        if !FileManager.default.fileExists(atPath: procursusPath) {
            do {
                try FileManager.default.createDirectory(atPath: procursusPath, withIntermediateDirectories: true)
            } catch let error as NSError {
                NSLog("Failed to create Procursus directory: \(error)")
                return
            }
            
            bootstrapNeedsExtract = true
        }
        
        // Protect /private/preboot/jb-<UUID> from being deleted when searching for software updates
        // This unfortunately also prevents creating any other file in that folder, so we do it after creating the procursus folder
        chflags(fakeRootPath, UInt32(SF_IMMUTABLE))
        
        // Update basebin (should be done every rejailbreak)
        
        var basebinTarPath = Bundle.main.bundlePath + "/basebin.tar"
        var basebinPath = procursusPath + "/basebin"
        if FileManager.default.fileExists(atPath: basebinPath) {
            do {
                try FileManager.default.removeItem(atPath: basebinPath)
            } catch let error as NSError {
                NSLog("Failed to delete existing basebin: \(error)")
            }
        }
        let untarRet = untar(tarPath: basebinTarPath, target: procursusPath)
        if untarRet != 0 {
            NSLog("Failed to untar Basebin: \(String(describing: untarRet))")
            return
        }

        // Create /var/jb symlink
        do {
            try FileManager.default.createSymbolicLink(atPath: jbPath, withDestinationPath: procursusPath)
        } catch let error as NSError {
            NSLog("Failed to create /var/jb symlink: \(error)")
            return
        }

        if bootstrapNeedsExtract {
            let procursusTarPath = Bundle.main.bundlePath + "/bootstrap.tar"
            let untarRet = untar(tarPath: procursusTarPath, target: "/")
            if untarRet != 0 {
                NSLog("Failed to untar Procursus: \(String(describing: untarRet))")
                return
            }
            do {
                try "".write(toFile: installedPath, atomically: true, encoding: String.Encoding.utf8)
            } catch { }
        }
    }

	static func doHide() {
        // Remove existing /var/jb symlink if it exists (will be recreated on next jb)
        // This is the only thing that apps could detect when the device is not actually jailbroken
        // Except for apps that check for random preferences and shit on /var (something no app should ever do because of way to many false positives, feel free to send this comment to your manager)
        
        let jbPath = "/var/jb"

        if remountPrebootPartition(writable: true) != 0 {
            NSLog("Failed to remount /private/preboot partition as writable")
            return
        }
        
        do {
            if FileManager.default.fileExists(atPath: jbPath) {
                try FileManager.default.removeItem(atPath: jbPath)
            }
        } catch let error as NSError {
            NSLog("Failed to delete /var/jb symlink: \(error)")
            return
        }
        
        if remountPrebootPartition(writable: false) != 0 {
            NSLog("Failed to remount /private/preboot partition as non-writable")
            return
        }
	}

	static func doUninstall() {
        let jbPath = "/var/jb"
        
        if remountPrebootPartition(writable: true) != 0 {
            NSLog("Failed to remount /private/preboot partition as writable")
            return
        }
        
        // Delete /var/jb symlink
        do {
            if FileManager.default.fileExists(atPath: jbPath) {
                try FileManager.default.removeItem(atPath: jbPath)
            }
        } catch let error as NSError {
            NSLog("Failed to delete /var/jb symlink: \(error)")
            return
        }
        
        // Delete fake root
        let fakeRootPath = locateExistingFakeRoot()
        chflags(fakeRootPath, 0)
        if fakeRootPath != nil {
            do {
                try FileManager.default.removeItem(atPath: fakeRootPath!)
            }
            catch let error as NSError {
                NSLog("Failed to delete fake root: \(error)")
                return
            }
        }
        
        if remountPrebootPartition(writable: false) != 0 {
            NSLog("Failed to remount /private/preboot partition as non-writable")
            return
        }

        // TODO: reload icon cache (?)
	}

	static func isBootstrapped() -> Bool {
        return locateExistingFakeRoot() != nil
	}
}

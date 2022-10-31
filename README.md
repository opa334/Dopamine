# Fugu15
Fugu15 is a semi-untethered permasigned jailbreak for iOS 15.  
It contains a code-signing bypass, kernel exploit, kernel PAC bypass and PPL bypass.  
Additionally, it can be installed via Safari, i.e. a computer is not required, except for a Web Server that hosts Fugu15.  
Please note that Fugu15 does not support tweaks (no tweak injection library).

# Tested Devices and iOS Versions
- iPhone Xs Max: iOS 15.4.1
- iPhone 11 (SRD): iOS 15.4.1
- iPhone 12 (SRD): iOS 15.4.1
- iPhone 12 Pro Max: iOS 15.4.1
- iPhone 13: iOS 15.1 (offline edition - see bugs below [WiFi bug])

Other devices are probably supported as well.  
Non-arm64e devices are not supported.

# Building
Prerequisites:  
1. Make sure you have Xcode ~~13/14~~ 14.1 installed
2. Import the fastPath arm certificate (`Exploits/fastPath/arm.pfx`) into your Keychain (double click on the file). The password is "password" (without quotes)
3. You need a validly signed copy of Apple's Developer App from the AppStore (with DRM!). Copy the IPA to `Server/orig.ipa`. Note that if you would like to use a different AppStore App you will need to get it's Team ID and add `TEAMID=<the App's Team ID>` to all `make` commands

Now you can simply run `make` to build Fugu15 (internet connection required to download dependencies).  
Please note that you will be asked to grant "fastPathSign" access to the Keychain item "privateKey" (the private key of the fastPath certificate). Enter your password and select "Always allow".

## Building Tools
Building Fugu15 requires multiple Tools which can be found in the `Tools` directory. Building them is entirely optional because I've already compiled them.  
If you want to build them yourself, simply run `make` in the `Tools` directory.

# Installing
There are two ways to install Fugu15 on your device: Via Safari or via USB

## Installing via Safari
To install Fugu15 via Safari, do the following (requires you to own a domain):  
1. Make sure your device is connected to the same network as your computer
2. Change the DNS A record for a domain you own to the local IP-Address of your computer
3. Obtain a certificate for your domain (e.g. via Let's Encrypt) and copy it to `Server/serverCert/fullchain.cer` (the certificate itself) and `Server/serverCert/server.key` (private key)
4. Make sure you have Flask installed (`pip3 install Flask`)
5. Change `serverUrl` in `Server/server.py` to your domain
6. Run `python3 server.py` in the `Server` directory
7. Visit `https://<your domain>` on your iPhone and follow the instructions

## Installing via USB
1. Install `Fugu15_Developer.ipa`, e.g. via `ideviceinstaller -i Fugu15_Developer.ipa`. Alternatively, install Fugu15/Fugu15.ipa via TrollStore.
2. Open the newly installed "Developer" App (or whatever AppStore App you used) on your iPhone

# iDownload
Like all Fugu jailbreaks, Fugu15 ships with iDownload. The iDownload shell can be accessed on port 1337 (run `iproxy 1337 1337 &` and then `nc 127.1 1337` to connect to iDownload).  
Type `help` to see a list of supported commands.  
The following commands are especially useful:
- `r64/r32/r16/r8 <address>`: Read a 64/32/16/8 bit integer at the given kernel address. Add the `@S` suffix to slide the given address or `@P` to read from a physical address.
- `w64/w32/w16/w8 <address> <value>`: Write the given 64/32/16/8 bit integer to the given kernel address. Also supports the suffixes described above and additionally `@PPL` to write to a PPL protected address (see `krwhelp`).
- `kcall <address> <up to 8 arguments>`: Call the kernel function at the given address, passing up to 8 64-Bit integer arguments.
- `tcload <path to TrustCache>`: Load the given TrustCache into the kernel

# Procursus Bootstrap and Sileo
Fugu15 also ships with the procursus bootstrap and Sileo. Run the `bootstrap` command in iDownload to install both. Afterwards, you might have to respring to force Sileo to show up on the Home Screen (`uicache -r`).

Procursus is installed into the `/private/preboot/jb` directory and `/var/jb` is a symlink to it.

# Known Issues/Bugs
1. If oobPCI (the process exploiting the kernel) exits, the system might be left in an inconsistent state and panic at some point. This usually occurs about 5 seconds after running the `exit_full` command in iDownload.  
Workaround: Don't quit oobPCI or make sure to do it as fast as possible to reduce the chance of a kernel panic. The reason for this panic is currently unknown.
2. When not connected to power, entering deep sleep will cause a kernel panic due to a bug in DriverKit (also happened with Fugu14). Unfortunately, the fix from Fugu14 does not work on iOS 15.  
Workaround: This bug will not occur when quitting oobPCI. However, the bug described above may occur when oobPCI exits.
3. Some iOS versions (at least iOS 15.1 and below, maybe 15.2 and 15.3 too) have a DriverKit bug which causes bus mastering to be disabled for the WiFi chip when running oobPCI, causing a kernel panic when WiFi is used. This bug can be fixed but a fix is not included in Fugu15 at the moment.  
Workaround: Disable WiFi.

# FAQ
Q: I'm an end user. Is Fugu15 useful to me?  
A: No.  

Q: My iOS version/device is not supported by Fugu15, will you add support for it?  
A: No. (I'm done with iOS 15)  

Q: Will you ever add support for tweak injection?  
A: No.  

Q: Do you provide official support for Fugu15? Are any updates planned?  
A: No.  

Q: I installed/updated something through Sileo but it won't launch. How can I fix that?  
A: Fugu15 uses TrustCache injection to bypass code signing. Therefore, if you install or update something, it's code signature must be in a TrustCache. You can load additional TrustCaches from the iDownload shell via the `tcload` command.  

Q: Wen eta Fugu16??????  
A: ...  

# Credits
The following open-source software is used by Fugu15:
- [Procursus Bootstrap](https://github.com/ProcursusTeam/Procursus): The bootstrap used by Fugu15. License: [BSD 0-Clause](https://github.com/ProcursusTeam/Procursus/blob/main/LICENSE). The tools included in the bootstrap are released under many different licenses, please see the procursus repo for more information
- [Sileo](https://github.com/Sileo/Sileo): The package manager included in Fugu15. License: [BSD 4-Clause](https://github.com/Sileo/Sileo/blob/stable/LICENSE)
- [ZIPFoundation](https://github.com/weichsel/ZIPFoundation): Swift library for working with ZIP archives. Used in FuguInstall to install the Fugu15 App. License: [MIT](https://github.com/weichsel/ZIPFoundation/blob/development/LICENSE)

# License
MIT. See the `LICENSE` file.

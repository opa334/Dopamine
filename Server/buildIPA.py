import zipfile
import io
import plistlib
import subprocess

def buildIPA(appStoreIPA, fuguInstall, otherIPA, installHaxx="../Tools/installHaxx/installHaxx"):
    with open(appStoreIPA, "rb") as f:
        ipa = io.BytesIO(b"")
        ipaNewZip = zipfile.ZipFile(ipa, "w")
        ipaZip = zipfile.ZipFile(f, "r")

        # Get data from Info.plist
        payload = list(zipfile.Path(ipaZip, "Payload/").iterdir())
        if len(payload) != 1:
            print("Invalid IPA file!")
            exit(-1)
            
        theApp = payload[0]
        infoPlist = plistlib.loads(theApp.joinpath("Info.plist").read_bytes())

        bundleId      = infoPlist["CFBundleIdentifier"]
        bundleVersion = infoPlist["CFBundleVersion"]
        bundleName    = infoPlist["CFBundleDisplayName"]

        appBinaryPath = infoPlist["CFBundleExecutable"]
        appBinaryPath = theApp.joinpath(appBinaryPath)
        appBinary     = appBinaryPath.read_bytes()

        patchedBinary = subprocess.check_output([installHaxx, "-", fuguInstall, "-", otherIPA], input=appBinary)
        
        for item in ipaZip.infolist():
            buffer = ipaZip.read(item.filename)
            if item.filename == appBinaryPath.at:
                ipaNewZip.writestr(item, patchedBinary)
            else:
                ipaNewZip.writestr(item, buffer)
            
        ipaNewZip.comment = ipaZip.comment

        ipaZip.close()
        ipaNewZip.close()
        
        ipa.seek(0)
        return ipa.read()

if __name__ == "__main__":
    import sys
    import os
    
    if len(sys.argv) < 3:
        print("Usage: buildIPA.py <path to other IPA> <output path> <optional path to AppStore IPA> <optional path to FuguInstall> <optional path to installHaxx binary>")
        exit(-1)
    
    base = os.path.dirname(sys.argv[0])
    if base == '':
        base = '.'
        
    otherIPA    = sys.argv[1]
    output      = sys.argv[2]
    appStoreIPA = sys.argv[3] if len(sys.argv) >= 4 else (base + "/orig.ipa")
    fuguInstall = sys.argv[4] if len(sys.argv) >= 5 else (base + "/FuguInstall")
    installHaxx = sys.argv[5] if len(sys.argv) >= 6 else (base + "/../Tools/installHaxx/installHaxx")

    with open(output, "wb+") as f:
        f.write(buildIPA(appStoreIPA, fuguInstall, otherIPA, installHaxx))

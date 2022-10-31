from flask import Flask, request, render_template, make_response, after_this_request, Response
import uuid
import zipfile
import io
import plistlib
import subprocess

serverUrl = "jbme.pinauten.de"

with open("orig.ipa", "rb") as f:
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

    patchedBinary = subprocess.check_output(["../Tools/installHaxx/installHaxx", "-", "FuguInstall", "-", "Fugu15.ipa"], input=appBinary)
    
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
ipaData = ipa.read()
with open("Fugu.ipa", "wb+") as f:
    f.write(ipaData)

app = Flask(__name__)

ipaDownloadStarted = []
ipaDownloadDone    = []

@app.route("/")
def main_site():
    key = str(uuid.uuid4())
    return render_template("index.html", key=key, server=serverUrl, appName=bundleName)
    
@app.route("/didStartIPADownload")
def didStartIPADownload():
    key = request.args.get("key", None)
    if key is None:
        return {"error": "No key given"}

    return {"result": key in ipaDownloadStarted}

@app.route("/didDownloadIPA")
def didDownloadIPA():
    key = request.args.get("key", None)
    if key is None:
        return {"error": "No key given"}

    return {"result": key in ipaDownloadDone}

@app.route("/<key>/manifest.plist")
def getInfoPlist(key):
    response = make_response(render_template("manifest.plist", key=key, server=serverUrl, bundleId=bundleId, bundleVersion=bundleVersion, title="TotallyLegitDeveloperApp"))
    response.headers["Content-Type"] = "text/xml"
    return response

@app.route("/<key>/app.ipa")
def getIPA(key):
    global ipaDownloadStarted
    ipaDownloadStarted += [key]
    
    def generate():
        global ipaDownloadDone
        yield ipaData
        ipaDownloadDone += [key]
    
    return Response(generate(), content_type="application/octet-stream")

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=443, debug=False, ssl_context=("serverCert/fullchain.cer", "serverCert/server.key"))

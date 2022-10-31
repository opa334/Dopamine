# fastPathSign

fastPathSign is a tool to re-sign MachO's with the fastPath exploit cert.

# Prerequisites

Make sure you imported the fastPath exploit certificate into your Keychain (Exploits/fastPath/arm.pfx, password: "password").  
The certificate must be named "Pinauten PWN Cert".

# Usage

First ad-hoc sign the MachO, including the entitlements you need.  
Then run `fastPathSign <path to your MachO>` to re-sign your MachO. This will keep the entitlements, identifier, etc.

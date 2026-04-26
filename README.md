<img src="https://github.com/opa334/Dopamine/assets/52459150/ed04dd3e-d879-456d-9aa3-d4ed44819c7e" width="64" />

# Dopamine

A rootless semi-untethered jailbreak for iOS 15.0 - 16.5.1 (arm64e) and iOS 15.0 - 15.8.6 / 16.0 - 16.6.1 (arm64).

Please note that all issues related to version support will be deleted without response.

Official website / download: https://ellekit.space/dopamine/

---

## Device & iOS Compatibility

| Architecture | iOS Versions Supported |
|---|---|
| arm64e (A12–A16, M1–M2) | iOS 15.0 – 16.5.1 |
| arm64 (A9–A11) | iOS 15.0 – 15.8.6 / 16.0 – 16.6.1 |

> **Note:** Support for iOS 15.8.7 and 16.7–16.7.x is available in public beta only and may be unstable.

---

## Features

- Rootless jailbreak (does not modify the root filesystem)
- Semi-untethered (re-run the app after each reboot)
- Tweak injection via [ElleKit](https://github.com/tealbathingsuit/ellekit)
- Sileo and Zebra as default package managers
- Supports toggling tweak injection, verbose logs, and iDownload
- Ability to hide or remove the jailbreak

---

## Installation

1. Download the latest `.ipa` from the [official website](https://ellekit.space/dopamine/) or [GitHub Releases](https://github.com/opa334/Dopamine/releases).
2. Install via [TrollStore](https://github.com/opa334/TrollStore) (recommended, permanent) or a signing service/Sideloadly.
3. Open the Dopamine app and tap **Jailbreak**.
4. After jailbreaking, open Sileo → Sources → ElleKit repo → install **ElleKit**.
5. Search for and install **PreferenceLoader** from the Search tab.
6. Respring/reboot and rejailbreak as needed.

> **Note for iOS 15.0–15.3.1:** Wi-Fi must be disabled before jailbreaking, but can be re-enabled afterward.

---

## Building from Source

Requirements:
- Xcode 14+
- `make`

```bash
git clone --recursive https://github.com/opa334/Dopamine
cd Dopamine
make
```
## Credits & Acknowledgements

- **opa334** – Lead developer
- **Linus Henze** – Original Fugu15 proof of concept
- All contributors listed in the [contributors graph](https://github.com/opa334/Dopamine/graphs/contributors)

---
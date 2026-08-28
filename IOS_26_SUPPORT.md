# iOS 26.2 support status

Dopamine does **not** advertise or support iOS 26.2 on iPhone 12/A14 in this tree.

The existing iOS 26.x metadata ends at iOS 26.0.1. Some shared kernel-structure code handles later 26.x releases, but that does not establish a working exploit path. This is a source-audit result, not physical-device validation:

- `momentarius` explicitly supports only A12/A13 and ends at build range iOS 26.0.1.
- `DarkSword` and `ClearSword` advertise iOS 26.0–26.0.1 and do not declare A14 support in their iOS 26 metadata.
- `Titan` contains A14 exploit code, but its declared support range is iOS 16.1–17.3.1; it is not an iOS 26.2 exploit path.
- `dmaFail` contains A14-related code but its metadata remains limited to older iOS releases and cannot be treated as iOS 26.2 support.

Do not expand `DPSupportedRanges`, add iOS 26.2 build identifiers, or update the normal support string until a compatible exploit and complete device flow are validated on the target build.

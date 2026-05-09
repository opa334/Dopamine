<img src="https://github.com/opa334/Dopamine/assets/52459150/ed04dd3e-d879-456d-9aa3-d4ed44819c7e" width="64" />

# Dopamine

Dopamine is a rootless, semi-untethered jailbreak for supported iOS and iPadOS 15 and 16 devices.

Official website and download: https://ellekit.space/dopamine/

Upstream repository: https://github.com/opa334/Dopamine

## Supported Versions

Dopamine support depends on both the device hardware and the installed firmware version.

The latest stable 2.x releases support the following version ranges:

| Device family | Architecture | Supported iOS/iPadOS versions |
| --- | --- | --- |
| A8-A11 devices | arm64 | 15.0-15.8.6 and 16.0-16.6.1 |
| A12-A14 and M1 devices | arm64e | 15.0-16.5.1 |
| A15-A16 and M2 devices | arm64e | 15.0-16.5 |

Current Dopamine 2.5 beta releases add experimental DarkSword support for additional arm64 versions:

| Device family | Architecture | Beta-supported iOS/iPadOS versions |
| --- | --- | --- |
| A9-A10 devices | arm64 | 15.8.7 |
| A11 and earlier devices | arm64 | 16.7-16.7.15 |

Notes:

- A12 and newer devices are still limited to iOS/iPadOS 16.5.1 and below. Newer iOS/iPadOS 16 versions lack the required PPL bypass for these chips.
- Extended support for iOS/iPadOS 15.8.7 on A9-A10 devices and iOS/iPadOS 16.7-16.7.15 on arm64 devices is available only in current Dopamine 2.5 beta releases using the DarkSword exploit.
- DarkSword currently has known issues on A8/A8X devices. Check the latest release notes before testing on those devices.
- DarkSword may not work reliably on A9X devices.
- Beta iOS/iPadOS versions may require installation through TrollStore.

## Supported Devices

### iPhone

| Chip | Devices |
| --- | --- |
| A9 | iPhone 6s, iPhone 6s Plus, iPhone SE 1st generation |
| A10 | iPhone 7, iPhone 7 Plus |
| A11 | iPhone 8, iPhone 8 Plus, iPhone X |
| A12 | iPhone XS, iPhone XS Max, iPhone XR |
| A13 | iPhone 11, iPhone 11 Pro, iPhone 11 Pro Max, iPhone SE 2nd generation |
| A14 | iPhone 12, iPhone 12 mini, iPhone 12 Pro, iPhone 12 Pro Max |
| A15 | iPhone 13, iPhone 13 mini, iPhone 13 Pro, iPhone 13 Pro Max, iPhone SE 3rd generation, iPhone 14, iPhone 14 Plus |
| A16 | iPhone 14 Pro, iPhone 14 Pro Max |

### iPad

| Chip | Devices |
| --- | --- |
| A8/A8X | iPad mini 4, iPad Air 2 |
| A9/A9X | iPad 5th generation, iPad Pro 9.7-inch, iPad Pro 12.9-inch 1st generation |
| A10/A10X | iPad 6th generation, iPad 7th generation, iPad Pro 10.5-inch, iPad Pro 12.9-inch 2nd generation |
| A12/A12X/A12Z | iPad 8th generation, iPad mini 5th generation, iPad Air 3rd generation, iPad Pro 11-inch 1st generation, iPad Pro 11-inch 2nd generation, iPad Pro 12.9-inch 3rd generation, iPad Pro 12.9-inch 4th generation |
| A13 | iPad 9th generation |
| A14 | iPad 10th generation, iPad Air 4th generation |
| A15 | iPad mini 6th generation |
| M1 | iPad Air 5th generation, iPad Pro 11-inch 3rd generation, iPad Pro 12.9-inch 5th generation |
| M2 | iPad Pro 11-inch 4th generation, iPad Pro 12.9-inch 6th generation |

### iPod touch

| Chip | Devices |
| --- | --- |
| A10 | iPod touch 7th generation |

## Project Layout

| Path | Purpose |
| --- | --- |
| `Application/` | Dopamine iOS application, UI, jailbreak flow, exploit selection, and Xcode project |
| `BaseBin/` | Lower-level jailbreak components, bootstrap integration, and native support code |
| `Packages/` | Package assets and packaging-related files |
| `.github/workflows/` | Continuous integration workflows |
| `Makefile` | Top-level build entry point |

## Contributing

Contributions are welcome when they are focused, tested, and aligned with the existing codebase.

Good areas to contribute include:

- Fixing reproducible crashes or reliability issues.
- Improving localization coverage and correcting existing translations.
- Cleaning up UI bugs, layout issues, or accessibility problems.
- Improving build scripts, CI, packaging, or developer documentation.
- Refactoring small, well-contained areas without changing behavior.
- Updating compatibility checks when upstream support changes.

Before opening a pull request:

1. Search existing issues and pull requests to avoid duplicate work.
2. Keep the change focused on one problem.
3. Follow the existing Objective-C, C, C++, Swift, and Makefile style used in the repository.
4. Test on a supported device and firmware version when the change affects runtime behavior.
5. Include clear reproduction steps for bug fixes.
6. Explain the user-visible impact of the change.

Issues requesting support for unsupported versions or devices may be closed without response. Check the current support matrix before filing a compatibility issue.

## Building

This project is intended to be built on macOS with Xcode and the required iOS development toolchain installed.

Clone the repository with submodules:

```sh
git clone --recursive https://github.com/opa334/Dopamine.git
cd Dopamine
```

If the repository was cloned without submodules, initialize them before building:

```sh
git submodule update --init --recursive
```

Build targets and signing requirements may change between releases. Check the current `Makefile`, Xcode project settings, and CI configuration before submitting build-related changes.

## License

Dopamine is released under the MIT License. See `LICENSE.md` for details.

<img src="https://github.com/opa334/Dopamine/assets/52459150/ed04dd3e-d879-456d-9aa3-d4ed44819c7e" width="64" />

# Dopamine + RootHide (3.x)

Fork RootHide của **Dopamine rootless 3.x**. Jailbreak vẫn rootless + semi-untethered. Lớp ẩn lấy từ Dopamine2-roothide (`.jbroot-<16hex>`, không `/var/jb`). Tweak đích là **RootHide**, không phải rootless (`THEOS_PACKAGE_SCHEME=rootless` / `/var/jb`).

## Nguồn

| Vai trò | Repo | Ghi chú |
|---|---|---|
| Base | [opa334/Dopamine](https://github.com/opa334/Dopamine) default branch, tag **3.0.7** (commit `38f3240`) | Giữ exploit 3.x (ClearSword/DarkSword/Titan/momentarius), hookd, dopamine daemon, dyldhook iOS 16–18+ |
| Hide engine | [roothide/Dopamine2-roothide](https://github.com/roothide/Dopamine2-roothide) | Nguồn chính. Không viết hide engine mới |
| Tham khảo glue | [P013onEr/RootHide](https://github.com/P013onEr/RootHide) | Chỉ tham khảo. Domain 5 giữ `JBS_DOMAIN_DOPAMINE`; RootHide = domain **6** |

Bảng map file: [ROOTHIDE-MAP.md](ROOTHIDE-MAP.md)

## iOS

Giống upstream 3.x:

- arm64e: 15.0 – 17.3.1
- A12/A13: 15.0 – 18.7.1 và 26.0 – 26.0.1
- arm64: 15.0 – 18.7.1

Thiết bị test mục tiêu: iPhone 11 Pro Max (A13) iOS 18.6.2, sideload IPA qua eSign. Nằm trong A12/A13 15.0–18.7.1.

## IPA vs TIPA

Cùng binary, khác entitlements lúc đóng gói. Jailbreak **không** phụ thuộc TrollStore: kernel exploit chạy trên IPA sideload (eSign / AltStore / Sideloadly). TrollStore detect runtime (`_TrollStore`), không `#ifdef`.

| Artifact | Entitlements | Dùng khi |
|---|---|---|
| `Application/Dopamine.ipa` | `Dopamine.entitlements` (không platform-application / no-sandbox / persona-mgmt / proc_info-allow) | eSign, chứng chỉ, sideload |
| `Application/Dopamine.tipa` | `Dopamine-TrollStore.entitlements` (full TrollStore set) | TrollStore |

`make` trong `Application/` emit **cả hai**. GitHub Actions upload cả `.ipa` và `.tipa`.

Không nhúng cert, không forge signature.

## Tweak: RootHide, không rootless

- Bootstrap: `/var/containers/Bundle/Application/.jbroot-<16hex>` + AppGroup secondary. **Không** tạo `/var/jb`.
- Hook: `roothidehooks.dylib`, không `rootlesshooks`.
- TweakLoader: `JBROOT_PATH("/usr/lib/TweakLoader.dylib")`.
- `libroot` lấy prefix từ `jbclient_get_jbroot()` (randomized), không hardcode `/var/jb`.
- App RootHide (`roothideapp.deb`) cài trong `finalizeBootstrap` — blacklist app.
- Build tweak: `THEOS_PACKAGE_SCHEME = roothide` (theos fork [roothide/theos](https://github.com/roothide/theos)). Tweak rootless (`/var/jb`) **không** phải ABI đích.

## Build (REQUIRES_MACOS)

Host Windows không produce `.ipa` / `.tipa`. Cần macOS + Xcode + ldid + trustcache + [roothide/theos](https://github.com/roothide/theos).

```sh
# vendor bootstraps RootHide (đã copy sẵn). Không curl Procursus stock — tar đó tạo /var/jb.
ls Application/Dopamine/Resources/bootstrap_1800.tar.zst
ls Application/Dopamine/Resources/bootstrap_1900.tar.zst   # iOS 16+ gồm 18.6.2

export THEOS=/path/to/roothide-theos
gmake -j$(sysctl -n hw.logicalcpu)
# → Application/Dopamine.ipa
# → Application/Dopamine.tipa
```

CI: `.github/workflows/main.yml` cài `roothide/theos`, verify vendor bootstrap, upload IPA+TIPA.

## Giới hạn đã giữ

- Rootless, không rootful
- Semi-untethered
- Không đổi kernel exploit 3.x
- palera1n exploit không port; palehide hook giữ

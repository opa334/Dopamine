# Map RootHide file → fork 3.x

Hide source: `references/Dopamine2-roothide` (roothide/Dopamine2-roothide).
Base: opa334/Dopamine 3.0.7. Glue domain: `JBS_DOMAIN_DOPAMINE=5` giữ; `JBS_DOMAIN_ROOTHIDE=6`.

## Copy nguyên (hide engine)

| RootHide 2.x | Fork 3.x |
|---|---|
| `BaseBin/libjailbreak/src/roothider/` | `BaseBin/libjailbreak/src/roothider/` (kalloc_pt copy lại; 3.x đã xóa) |
| `BaseBin/libjailbreak/src/jbclient_roothide.c` | cùng path |
| `BaseBin/libjailbreak/src/roothider.h` | cùng path |
| `BaseBin/roothidehooks/` | `BaseBin/roothidehooks/` (thay rootlesshooks) |
| `BaseBin/jailbreakd/` | `BaseBin/jailbreakd/` |
| `BaseBin/bootstrapper/` | `BaseBin/bootstrapper/` |
| `BaseBin/launchdhook/src/jbserver/jbdomain_roothide.c` | cùng path |
| `BaseBin/launchdhook/src/roothider.m` | cùng path |
| `BaseBin/systemhook/src/roothider.h` | include retarget `common/private.h` |
| `BaseBin/systemhook/src/roothider_common.c` | cùng path |
| `BaseBin/systemhook/src/roothider_main.c` | include retarget `common/` |
| `BaseBin/dyldhook/src/roothider.c` `.S` | cùng path (`@loader_path/.jbroot`) |
| `BaseBin/_external/include/roothide.h` | cùng path |
| `Application/Dopamine/Resources/roothideapp.deb` | cùng path |
| `Application/Dopamine/Resources/bootstrap_{1800,1900}.tar.zst` | vendor RootHide, không Procursus stock |

## Glue 3.x (không thay hide engine)

| File | Việc |
|---|---|
| `BaseBin/libjailbreak/src/jbserver_domains.h` | `JBS_DOMAIN_ROOTHIDE 6` + enum action |
| `BaseBin/launchdhook/src/jbserver/jbserver_global.c` | `&gRootHideDomain` sau dopamine |
| `BaseBin/libjailbreak/src/jbclient_xpc.h` | append client API RootHide, giữ 3.x `forceCSAdhoc` / dopamine domain |
| `BaseBin/libjailbreak/src/libjailbreak.h` | `#include "roothider.h"` |
| `BaseBin/libjailbreak/src/info.h` | `jbrand`, `palera1n`, `dyld_patch_enabled` |
| `BaseBin/libjailbreak/Makefile` | `src/roothider/*`, `-lc++` |
| `BaseBin/systemhook/Makefile` | `jailbreakd.c` client |
| `BaseBin/systemhook/src/common/common.h` | `HOOK_DYLIB_PATH` → `extern const char*` |
| `BaseBin/systemhook/src/main.c` | prehook/posthook RootHide, TweakLoader `JBROOT_PATH`, `roothidehooks.dylib` |
| `BaseBin/launchdhook/Makefile` | `-lellekit`, `roothider_common.c` |
| `BaseBin/launchdhook/src/spawn_hook.c` | `roothide_launchd___posix_spawn_*` (litehook giữ) |
| `BaseBin/launchdhook/src/main.m` | `roothide_launchd_preinit/postinit`, spinlock `vm.shared_region_pivot` |
| `BaseBin/Makefile` | drop `rootlesshooks`; add `roothidehooks jailbreakd bootstrapper`; giữ `hookd dopamine` |
| `Application/.../DOBootstrapper.m` | overlay RH2: `InstallBootstrap` vào `.jbroot-`, xóa `/var/jb`, `roothideapp.deb` |
| `Application/.../DOEnvironmentManager.m` | `locateJailbreakRoot` = `find_jbroot` (cả IPA, không chỉ TrollStore); không tạo `/var/jb` |
| `Application/.../DOJailbreaker.m` + `main.m` | `PATH` `/rootfs/...`; checkin khi hide |
| `Application/.../DOSettingsController.m` | dyld patch specifier |
| `BaseBin/dopamine/src/main.m` | launchctl/SHELL qua `JBROOT_PATH`; không `/var/jb` |
| `Application/Makefile` | emit IPA + TIPA, marker `Dopamine.roothide`, copy `*.deb` |
| `Dopamine.entitlements` | IPA (bỏ TrollStore-only keys) |
| `Dopamine-TrollStore.entitlements` | TIPA full set |
| `.github/workflows/main.yml` | `roothide/theos`; upload `.ipa` + `.tipa` |

## 3.x giữ, không drop

ClearSword, DarkSword, Titan, momentarius, hookd, dopamine daemon, TXM/trustcache_fs/stock_fixes, PERSONA_FIX, `DOBootstrapper+zstd`, clock_alarm, Standalone, systemhook `src/common/`, dyldhook iOS 16–17 và iOS 18+.

## Không port

- palera1n exploit (hide hook palera1n.x trong roothidehooks giữ)
- P013onEr thay domain 5 = RootHide (sẽ đè dopamine 3.x)
- rootlesshooks trong `all`
- invent hide engine

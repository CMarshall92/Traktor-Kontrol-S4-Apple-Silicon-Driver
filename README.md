# Traktor Kontrol S4 — Apple Silicon driver

[![License: GPL-2.0-only](https://img.shields.io/badge/license-GPL--2.0--only-blue.svg)](LICENSE)

Native Instruments never shipped an arm64 driver for the S4 MK1, and the original
2.8.0 installer cannot be repackaged: its kernel extension and MIDI plug-in are
x86_64 binaries. This project builds a replacement from the open-source
[s4mk1-revival-macos](https://github.com/almoretti/s4mk1-revival-macos) driver and
packages it as a normal macOS installer.

It is not affiliated with or endorsed by Native Instruments.

## What you get

| Component | What it does | Needs the security change? |
|---|---|---|
| **S4 MK1 Audio Driver** | arm64 CoreAudio HAL plug-in. Exposes the S4 as a CoreAudio device named **Traktor Kontrol S4**. | No |
| **Traktor Controller Integration** | arm64e identity shim kernel extension. Makes Traktor Pro 4 recognise the S4 as a controller. | Yes, one time |

Audio works without the kernel extension. Traktor will not see the controller
without it. Both are selected by default; you can uncheck the kext in the
installer's **Customize** pane if you only want audio.

## Requirements

- An Apple Silicon Mac (M1 or later), macOS 11 or later.
- Administrator password.
- The S4 MK1 and a USB cable.
- About 15 minutes for the first install, including one recovery-mode trip.

## Phase 1 — One-time security change (recoveryOS)

**Only needed for the kernel extension.** If you only want the audio device, skip
this phase and uncheck **Traktor Controller Integration** in Phase 2.

1. Shut down completely.
2. Press and **hold** the power button until **Loading startup options** appears,
   then click **Options → Continue** and log in. Holding the power button is what
   enters One True Recovery (1TR), which `bputil` requires.
3. Menu bar: **Utilities → Startup Security Utility**. Select your startup disk,
   choose **Reduced Security**, tick **Allow user management of kernel extensions
   from identified developers**, and click **OK**.
4. Menu bar: **Utilities → Terminal**, then run these one line at a time:

   ```sh
   bputil -n -k
   csrutil enable --without kext
   reboot
   ```

5. `bputil` asks for your admin user name and password. When it finishes, the Mac
   restarts.

**What these do**

- `bputil -n -k` recreates the boot policy with third-party kext loading enabled.
  This is Permissive Security, the configuration the shim is tested with. Pass both
  flags in **one** invocation: `-n` rebuilds the policy from scratch and keeps only
  the options named in that same command.
- `csrutil enable --without kext` keeps System Integrity Protection on but disables
  kext signature checking, which the ad-hoc-signed shim needs.

To stay on **Reduced Security** instead of Permissive, run `bputil -k` instead of
`bputil -n -k` (the GUI step above already sets this). If the kext is later refused
with a signature error, redo this phase with the exact pair above, or fall back to
`csrutil disable`.

Optional confirmation before leaving recovery:

```sh
bputil -d
csrutil status
```

## Phase 2 — Install

1. Open the DMG. Download it from the repository's **Releases** page, or from this
   repository build it with `./build-installer.sh` and open:

   ```
   dist/Traktor Kontrol S4 2.8.0 (Apple Silicon).dmg
   ```

2. Double-click **Traktor Kontrol S4 2.8.0 (Apple Silicon).pkg**.
3. Read the Introduction, then **Continue → Install**, and authenticate.
4. In **Customize**, leave both checked:
   - **S4 MK1 Audio Driver** — the CoreAudio device.
   - **Traktor Controller Integration** — the kext Traktor needs.
5. Let it finish. The installer removes the old x86_64 NI kext, MIDI plug-in and
   preference pane, installs and ad-hoc-signs the arm64 driver and kext, and tries
   to load the kext.

The post-install step will usually report that the extension is **waiting for
approval**. That is expected; continue to Phase 3.

## Phase 3 — Approve the extension and restart

1. Open **System Settings → Privacy & Security** and scroll to **Security**. Click
   **Allow** next to the blocked **CaiaqS4Shim** message (authenticate).
2. If no button appears, re-trigger the prompt from Terminal:

   ```sh
   sudo kmutil load -p /Library/Extensions/CaiaqS4Shim.kext
   ```

3. **Restart.** Booting with the S4 unplugged is fine and recommended for the first
   boot after installing.
4. After login, plug in the S4.

## Phase 4 — Verify

Run these and compare:

```sh
# 1. Kext loaded?
kmutil showloaded --bundle-identifier cc.moretti.s4native.CaiaqS4Shim

# 2. Did it match the S4?
ioreg -r -c com_caiaq_driver_TraktorKontrolS4_NIUSBUserClient -d 1 | grep -E 'Caiaq'

# 3. Audio device present?
system_profiler SPAudioDataType | grep -A6 -i 'S4'

# 4. Driver log (Ctrl-C to stop)
log stream --predicate 'subsystem == "cc.moretti.s4"'
```

**Expected**

- `kmutil showloaded` lists `cc.moretti.s4native.CaiaqS4Shim`.
- `ioreg` shows `CaiaqArmedMask` (goes non-zero once Traktor connects) and a rising
  `CaiaqDelivered`.
- `system_profiler` shows **Traktor Kontrol S4**.
- The log shows `device open, fw …`, then `kext connected`, then a
  `reports digital … analog …` line every ~5 seconds.
- If the kext is not loaded, the log says `kext not available … streaming without
  it` and the reports line ends with `(no kext)`; audio still works.

Then open **Traktor Pro 4 → Preferences → Controller Manager**. It should list
**Traktor Kontrol S4**, not "Generic MIDI". Set **Traktor Kontrol S4** as the audio
device in Traktor's **Audio Setup** if it is not selected automatically.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| Installer says **Not an Apple Silicon Mac** | You are on an Intel Mac. This installer is arm64-only; use the Native Instruments 2.8.0 installer there. |
| **Bad code signature** / extension refused | Redo Phase 1 with `csrutil disable` instead of `csrutil enable --without kext`, then restart. |
| Kext installed but not loaded | Approve it in **Privacy & Security**, run `sudo kmutil load -p /Library/Extensions/CaiaqS4Shim.kext`, then restart. |
| No audio device in Audio MIDI Setup | Run `sudo killall coreaudiod`, replug the S4, and check `log stream` for `cc.moretti.s4`. |
| Audio works, Traktor does not see the controller | The kext is not loaded or approved. Audio and controller support are independent. |
| Mac loops at boot with the S4 attached | Observed only with an early panicking kext build. Unplug the S4, boot, log in, then plug it in. If it recurs, uninstall the kext. |
| No sound from MAIN or PHONES | Select **Traktor Kontrol S4** as the output device. Output is 44.1 kHz only; inputs and multi-channel routing are not implemented yet. |
| `ioreg` shows the kext but `CaiaqArmedMask` stays 0 | Traktor is not connected to the controller yet. Open Traktor and check **Controller Manager**. |

## Uninstall / restore security

Double-click **Uninstall Traktor Kontrol S4 Driver.command** in:

```
/Applications/Native Instruments/Traktor Kontrol S4 Driver/Documentation/
```

Or do it manually:

```sh
sudo kmutil unload -b cc.moretti.s4native.CaiaqS4Shim
sudo rm -rf /Library/Extensions/CaiaqS4Shim.kext
sudo rm -rf "/Library/Audio/Plug-Ins/HAL/S4MK1.driver"
sudo kmutil clear-staging
sudo killall coreaudiod
```

Then restore security: shut down, hold the power button, **Options → Continue**,
**Utilities → Startup Security Utility → Full Security**, and in recovery Terminal:

```sh
csrutil enable
reboot
```

> **Note:** `man bputil` documents a one-way door. Full Security performs an online
> check, and on a Mac that is not fully up to date it may not be possible to set
> Full Security again. **Reduced Security plus `csrutil enable`** is the realistic
> restore point in that case. Decide before doing Phase 1.

## Rebuild from source

```sh
./build-installer.sh
```

Requires Xcode command line tools and an Apple Silicon Mac. The script clones the
upstream project at a pinned commit, builds the kext and the HAL plug-in, then
assembles and verifies the package and the DMG. It also writes
`dist/s4mk1-revival-macos-<commit>.tar.gz`, the corresponding source for the
compiled binaries.

Repository layout:

```
build-installer.sh   build script (pkg + dmg + source tarball)
src/                 installer scripts, Distribution.xml, Read Me, uninstaller
dist/                build output (not tracked)
```

## Licence

[GPL-2.0-only](LICENSE).

The arm64 driver and kernel extension are
[almoretti/s4mk1-revival-macos](https://github.com/almoretti/s4mk1-revival-macos),
GPL-2.0-only, commit `2b0e9875384a9e3658e1c066d175ddc80bbb84c0`. The packaging in
this repository (build script, installer scripts, Distribution.xml and
documentation) is released under the same licence, so the whole project is
GPL-2.0-only. Nothing from Native Instruments is redistributed; the installer only
deletes their obsolete x86_64 files.

- `LICENSE` — the full GNU General Public License v2 text. GitHub detects this as
  **GPL-2.0**.
- `NOTICE` — upstream attribution, the pinned commit, the ad-hoc signing note and
  the trademark disclaimer.

### Corresponding source for released binaries

Each release includes `s4mk1-revival-macos-<commit>.tar.gz` next to the DMG.
That tarball is the complete corresponding source for the driver and kernel
extension in the DMG; `build-installer.sh` generates it with `git archive` from
the pinned upstream commit. The packaging source is the release tag itself.

Traktor, Traktor Kontrol and Native Instruments are trademarks of Native
Instruments GmbH. This project is not affiliated with or endorsed by Native
Instruments.

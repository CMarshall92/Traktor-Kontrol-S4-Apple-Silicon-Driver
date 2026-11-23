#!/bin/bash
# Build "Traktor Kontrol S4 2.8.0 (Apple Silicon).pkg" and the distribution DMG.
#
#   ./build-installer.sh
#
# The arm64 payload is built from almoretti/s4mk1-revival-macos (GPL-2.0) at a
# pinned commit, then packaged as a product archive with two selectable
# components: the CoreAudio HAL driver and the identity shim kernel extension.
#
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
BUILD="$HERE/build"
SRC="$HERE/src"
DIST="$HERE/dist"
UPSTREAM="$BUILD/upstream"
COMMIT="2b0e9875384a9e3658e1c066d175ddc80bbb84c0"   # almoretti/s4mk1-revival-macos
REPO="https://github.com/almoretti/s4mk1-revival-macos.git"
VERSION="2.8.0"
KEXT_ID="cc.moretti.s4native.CaiaqS4Shim"
HAL_ID="com.caiaq.s4.applesilicon.hal"

say() { printf '\n== %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

[[ "$(uname -m)" == "arm64" ]] || die "build on Apple Silicon (the kext is arm64e)"

say "toolchain"
xcrun --sdk macosx --show-sdk-path >/dev/null || die "Xcode command line tools missing"
clang --version | head -1

say "upstream source ($COMMIT)"
mkdir -p "$BUILD" "$DIST"
if [[ ! -d "$UPSTREAM/.git" ]]; then
    git clone "$REPO" "$UPSTREAM"
fi
git -C "$UPSTREAM" fetch --all --quiet || true
git -C "$UPSTREAM" checkout --quiet "$COMMIT"

say "build kext (arm64e) and HAL plug-in (arm64)"
make -C "$UPSTREAM/kext" clean >/dev/null
make -C "$UPSTREAM/kext"
make -C "$UPSTREAM/audio" clean >/dev/null 2>&1 || true
make -C "$UPSTREAM/audio" plugin

KEXT_SRC="$UPSTREAM/kext/build/CaiaqS4Shim.kext"
HAL_SRC="$UPSTREAM/audio/S4MK1.driver"
[[ -d "$KEXT_SRC" ]] || die "kext build missing"
[[ -d "$HAL_SRC" ]] || die "plugin build missing"

say "assemble payload roots"
rm -rf "$BUILD/root-hal" "$BUILD/root-kext"
DOC="$BUILD/root-hal/Applications/Native Instruments/Traktor Kontrol S4 Driver/Documentation"
mkdir -p "$DOC"
mkdir -p "$BUILD/root-hal/Library/Audio/Plug-Ins/HAL"
mkdir -p "$BUILD/root-kext/Library/Extensions"

ditto --noextattr --noacl --noqtn "$HAL_SRC" "$BUILD/root-hal/Library/Audio/Plug-Ins/HAL/S4MK1.driver"
ditto --noextattr --noacl --noqtn "$KEXT_SRC" "$BUILD/root-kext/Library/Extensions/CaiaqS4Shim.kext"

cp "$SRC/resources/ReadMe.html" "$DOC/Read Me.html"
cp "$SRC/resources/Uninstall Traktor Kontrol S4 Driver.command" "$DOC/"
chmod 755 "$DOC/Uninstall Traktor Kontrol S4 Driver.command"
cp "$HERE/LICENSE" "$DOC/LICENSE-GPL-2.0.txt"
cp "$HERE/NOTICE" "$DOC/NOTICE.txt"

# No extended attributes anywhere in the payload: pkgbuild turns them into AppleDouble
# "._" entries, and codesign refuses a bundle carrying them.
xattr -cr "$BUILD/root-hal" "$BUILD/root-kext"
find "$BUILD/root-hal" "$BUILD/root-kext" -name '._*' -delete

# The Read Me is also visible from the Installer's Introduction pane.
mkdir -p "$BUILD/resources"
cp "$SRC/resources/ReadMe.html" "$BUILD/resources/ReadMe.html"

say "component packages"
rm -rf "$BUILD/scripts-hal" "$BUILD/scripts-kext" "$BUILD/pkgs"
mkdir -p "$BUILD/scripts-hal" "$BUILD/scripts-kext" "$BUILD/pkgs"
cp "$SRC/scripts/hal-preinstall"  "$BUILD/scripts-hal/preinstall"
cp "$SRC/scripts/hal-postinstall" "$BUILD/scripts-hal/postinstall"
cp "$SRC/scripts/kext-preinstall"  "$BUILD/scripts-kext/preinstall"
cp "$SRC/scripts/kext-postinstall" "$BUILD/scripts-kext/postinstall"
chmod 755 "$BUILD"/scripts-*/*

for f in "$BUILD"/scripts-*/*; do bash -n "$f" || die "syntax error in $f"; done

pkgbuild --root "$BUILD/root-hal" \
         --scripts "$BUILD/scripts-hal" \
         --identifier "$HAL_ID" \
         --version "$VERSION" \
         --install-location "/" \
         --ownership recommended \
         "$BUILD/pkgs/hal.pkg"

pkgbuild --root "$BUILD/root-kext" \
         --scripts "$BUILD/scripts-kext" \
         --identifier "$KEXT_ID" \
         --version "1.0.0" \
         --install-location "/" \
         --ownership recommended \
         "$BUILD/pkgs/kext.pkg"

say "product archive"
rm -f "$BUILD/Traktor Kontrol S4 2.8.0 (Apple Silicon).pkg"
productbuild --distribution "$SRC/Distribution.xml" \
             --resources "$BUILD/resources" \
             --package-path "$BUILD/pkgs" \
             "$BUILD/Traktor Kontrol S4 2.8.0 (Apple Silicon).pkg"

say "distribution DMG"
rm -rf "$BUILD/dmgroot"
mkdir -p "$BUILD/dmgroot"
cp "$BUILD/Traktor Kontrol S4 2.8.0 (Apple Silicon).pkg" "$BUILD/dmgroot/"
cat > "$BUILD/dmgroot/READ ME FIRST.txt" <<'TXT'
Traktor Kontrol S4 MK1 - Apple Silicon driver
=============================================

1. Open "Traktor Kontrol S4 2.8.0 (Apple Silicon).pkg".
2. If you want controller support inside Traktor, do the one-time recovery-mode
   step printed in the installer's Read Me BEFORE installing. Audio works
   without it.
3. After installing, approve "CaiaqS4Shim" in System Settings > Privacy &
   Security if asked, then restart with the S4 plugged in.

Full instructions are in the installer Read Me and in
/Applications/Native Instruments/Traktor Kontrol S4 Driver/Documentation/.

Uninstall: double-click "Uninstall Traktor Kontrol S4 Driver.command" in that
documentation folder.
TXT
rm -f "$DIST/Traktor Kontrol S4 2.8.0 (Apple Silicon).dmg"
hdiutil create -quiet -volname "Traktor Kontrol S4 2.8.0 (Apple Silicon)" \
    -srcfolder "$BUILD/dmgroot" -fs HFS+ -format UDZO \
    "$DIST/Traktor Kontrol S4 2.8.0 (Apple Silicon).dmg"

# GPL-2.0 corresponding source for the binaries in the DMG. Upload this next to the
# DMG on every release; the source in this repository alone does not include the
# upstream project, which is cloned into build/ and not tracked.
say "corresponding source (GPL-2.0)"
rm -f "$DIST/s4mk1-revival-macos-$COMMIT.tar.gz"
git -C "$UPSTREAM" archive --format=tar.gz \
    --prefix="s4mk1-revival-macos-$COMMIT/" "$COMMIT" \
    > "$DIST/s4mk1-revival-macos-$COMMIT.tar.gz"

say "verify"
echo "-- kext architecture"
lipo -info "$BUILD/root-kext/Library/Extensions/CaiaqS4Shim.kext/Contents/MacOS/CaiaqS4Shim"
echo "-- HAL architecture"
lipo -info "$BUILD/root-hal/Library/Audio/Plug-Ins/HAL/S4MK1.driver/Contents/MacOS/S4MK1"
echo "-- signatures"
codesign -dv "$BUILD/root-kext/Library/Extensions/CaiaqS4Shim.kext" 2>&1 | head -5
codesign -dv "$BUILD/root-hal/Library/Audio/Plug-Ins/HAL/S4MK1.driver" 2>&1 | head -5
echo "-- flat package"
pkgutil --check-signature "$BUILD/Traktor Kontrol S4 2.8.0 (Apple Silicon).pkg" || true
echo "-- image"
hdiutil imageinfo "$DIST/Traktor Kontrol S4 2.8.0 (Apple Silicon).dmg" \
    | grep -E "Format Description|Total Bytes|Compressed Ratio" || true

say "done"
ls -lh "$DIST"/*.dmg "$DIST"/*.tar.gz "$BUILD/Traktor Kontrol S4 2.8.0 (Apple Silicon).pkg"

#!/bin/bash
# Uninstall the Traktor Kontrol S4 MK1 Apple Silicon driver.
# Double-click this file in Finder, or run it in Terminal.
# SPDX-License-Identifier: GPL-2.0-only
set -u

echo "Traktor Kontrol S4 MK1 driver - uninstall"
echo

osascript <<'APPLESCRIPT'
do shell script "pkill -x s4hostd 2>/dev/null; pkill -x s4stream 2>/dev/null; kmutil unload -b cc.moretti.s4native.CaiaqS4Shim 2>/dev/null; rm -rf /Library/Extensions/CaiaqS4Shim.kext; rm -rf '/Library/Audio/Plug-Ins/HAL/S4MK1.driver'; kmutil clear-staging 2>/dev/null; killall coreaudiod 2>/dev/null; true" with administrator privileges with prompt "Remove the Traktor Kontrol S4 MK1 Apple Silicon driver?"
APPLESCRIPT

echo "Removed the driver and the kernel extension."
echo
echo "To restore Full Security on Apple Silicon:"
echo "  1. Shut down, hold the power button until Loading startup options appears."
echo "  2. Options > Continue > Utilities > Startup Security Utility > Full Security."
echo "  3. Utilities > Terminal:  csrutil enable  then  reboot"
echo
read -r -p "Press Return to close this window." _

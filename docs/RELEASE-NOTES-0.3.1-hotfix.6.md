# MechOS 0.3.1 Hotfix 6

Hotfix 6 fixes the case where MechScope is running on a legacy-GPU compatibility path but the Plasma desktop remains visible on top of it.

## Root cause

The GT 730/non-Vulkan fallback correctly switched from Gamescope to Plasma, but the old session launched the MechScope supervisor before `startplasma-wayland` finished creating the user's real Wayland session. The background supervisor could therefore launch MechScope without the final Plasma/KWin display environment, or Plasma could finish startup after MechScope and cover the fullscreen window.

## Fix

- fallback now writes an explicit Gaming Mode fallback request
- Plasma starts normally first
- a KDE XDG autostart entry launches the MechScope fallback supervisor from the real Plasma session
- the supervisor waits for the Wayland socket/display environment
- duplicate MechScope owners are rejected through the existing lock
- the source-owned MechScope runtime reasserts fullscreen and activation during the first five seconds of startup
- existing crash-loop protection and intentional Desktop/Creator mode transitions are preserved

## Update Center isolation

Hotfix 6 is the first release built under the frozen updater policy. Before packaging, all Update Center/helper/transaction/A-B engine/recovery/reboot/signing-key infrastructure is removed from the stage. CI validates the final archive and fails the release if any protected updater path is present.

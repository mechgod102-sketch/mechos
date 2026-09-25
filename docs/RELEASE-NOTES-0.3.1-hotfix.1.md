# MechOS 0.3.1 Hotfix 1

MechOS 0.3.1 Hotfix 1 is an additive compatibility and reliability update on top of MechOS 0.3.1.

## Legacy GPU integration

The existing modern GPU stack remains authoritative.

- modern NVIDIA keeps the existing `nvidia-open` + NVIDIA userspace package path
- modern AMD keeps the existing AMDGPU + Mesa/RADV path
- Intel keeps the existing Mesa/Vulkan Intel path and Hotfix 36 Intel UMA integration
- legacy NVIDIA detection is added for common 580xx, 470xx, 390xx and 340xx proprietary branches
- MechOS does not auto-install AUR legacy NVIDIA drivers as root; it exposes the matching branch and preserves a safe Nouveau/Mesa path
- legacy Radeon systems using the `radeon` kernel driver keep Mesa/OpenGL and use Gamescope only when Vulkan preflight succeeds
- MechScope now sets proprietary NVIDIA GBM variables only when the loaded kernel driver is actually `nvidia`
- Nouveau explicitly avoids proprietary NVIDIA environment variables
- missing or failing Vulkan preflight falls back to the existing supervised Plasma path rather than crash-looping
- legacy GPU diagnostics are integrated into the existing MechOS GPU Compatibility view

## Update Center reliability

- fixes the v37 `dir: unbound variable` signed-manifest crash
- raises Update Center status timeout from 8 seconds to 30 seconds
- preserves signed-manifest verification and transactional install behavior
- blocks downgrade candidates in both Update Center and the backend helper
- an installed 0.3.1 or newer system will never treat a 0.3.0 hotfix as an upgrade

## Integration policy

This hotfix does not replace the 0.3.1 GPU architecture. It patches the cumulative 0.3.1 GPU setup, MechScope session and GPU Compatibility UI in place and adds legacy branches only where detected.

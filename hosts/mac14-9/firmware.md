# Firmware

Firmware reference for `Mac14,9` (Apple Silicon, M2 Pro). The boot and security architecture differs fundamentally from Intel Macs: there is no EFI/UEFI, no SMC reset procedure, and no NVRAM reset shortcut. Boot is handled by the SoC's Boot ROM and a chain of signed bootloaders, with security policy stored per-volume.

## Boot Chain

| Stage | Component | Source | Notes |
|-------|-----------|--------|-------|
| 1 | Boot ROM | SoC mask ROM | Immutable, fused at manufacture. Trust anchor. |
| 2 | LLB (Low Level Bootloader) | NOR flash | Verified by Boot ROM. |
| 3 | iBoot | NOR flash / OS container | Verified by LLB. Loads kernel cache. |
| 4 | XNU kernel | Sealed System Volume (SSV) | Verified by iBoot via signed kernelcache. |
| — | sepOS | Secure Enclave | Independent SoC running its own signed OS for key storage / biometric matching. |

Each macOS install on disk has its own **LocalPolicy** describing its boot/security configuration. Multiple installs (incl. external volumes) coexist with independent policies.

## Inspecting Firmware State

```sh
# System firmware / OS loader version
system_profiler SPHardwareDataType | grep -E 'Firmware|Loader'

# Boot policy of the current system volume
sudo bputil -d

# All available system extensions, kext loadability, etc.
systemextensionsctl list
kmutil showloaded | head

# Current macOS / kernel
sw_vers
uname -a
```

## Recovery and Boot Modes

| Mode | How to Enter | Purpose |
|------|--------------|---------|
| Normal Boot | Press power, release | Standard startup. |
| 1TR (One True Recovery / recoveryOS) | Press and **hold** power until "Loading startup options" appears, then choose "Options" | Recovery shell, Startup Security Utility, Disk Utility, Terminal, reinstall. |
| Fallback recoveryOS | Press power twice rapidly, hold on second press | Used when primary recoveryOS is broken. |
| Safe Mode | From Startup Options, hold Shift while clicking the volume | Loads minimal kexts, runs FS checks. |
| Startup Disk Picker | Same as 1TR; pick a volume in "Options" screen | Choose alternate macOS install / external volume. |
| Share Disk | recoveryOS → Utilities → Share Disk | Modern replacement for Target Disk Mode (over USB-C / Thunderbolt). |
| DFU | Power off; hold power + connect USB-C from another Mac running Apple Configurator 2; specific key sequence per model | Restore firmware / unbrick. Requires host Mac. |

## What Does *Not* Apply (vs. Intel Macs)

- **No `Option + Command + P + R` (NVRAM reset)** — Apple removed the shortcut on Apple Silicon. NVRAM exists but is managed by macOS; a reset has no equivalent user gesture and is not generally needed.
- **No SMC reset** — Power management is integrated into the SoC. Stuck states are resolved by a forced shutdown (hold power ~10s) and reboot.
- **No T2 chip** — Its responsibilities (Secure Enclave, SSD controller, image signal processor) are absorbed into the M-series SoC.
- **No standalone firmware password** — Replaced by the per-volume **LocalPolicy** + login password chain. `firmwarepasswd` is not supported.
- **No `bless`-based EFI boot variable manipulation** — `bless` still exists for setting the active system but operates on LocalPolicy rather than EFI NVRAM.
- **No Boot Camp / legacy BIOS / CSM** — Apple Silicon does not support Windows natively via Boot Camp; virtualization (Parallels, VMware, UTM) is the path.

## Security Policy

Apple Silicon defines three security postures per macOS install, set via **Startup Security Utility** in recoveryOS (or via `bputil` for advanced cases):

| Policy | Effect |
|--------|--------|
| Full Security (default) | Only the current signed OS or one for which Apple still vouches will boot. Kernel extensions disabled unless explicitly approved + reboot. |
| Reduced Security | Allows running any signed-by-Apple OS version (incl. older). Required for: third-party kernel extensions, custom kernels, asr-based restores, certain DTrace usage. |
| Permissive Security | Reduced Security + allows non-Apple-signed kernels (e.g. for OS research, Asahi Linux installer). Not exposed in the GUI; set via `bputil -k -u <admin>`. |

Inspect with:

```sh
sudo bputil -d -v <volume-group-uuid>   # specific volume
sudo bputil -d                          # current system
```

## NVRAM

NVRAM is still present and used by macOS for things like `boot-args` and the chosen startup disk. There is no boot-time key combo to clear it; use the CLI from a booted system:

```sh
nvram -p                 # list
sudo nvram boot-args="-v"
sudo nvram -d boot-args  # delete one
sudo nvram -c            # clear all (use with caution)
```

`csr-active-config` (SIP) is **not** managed via `csrutil` alone on Apple Silicon for some operations — major SIP changes route through the LocalPolicy and require recoveryOS.

## Asahi Linux Considerations

This generation (M2 Pro) is supported by Asahi Linux to varying degrees. The installer creates an additional APFS container, writes a Permissive Security LocalPolicy for that install only (other installs keep Full Security), and chain-loads m1n1 → U-Boot → Linux. The Apple Boot ROM and Apple-signed bootloaders are never replaced.

## References

- Apple — Boot process for a Mac with Apple silicon: <https://support.apple.com/guide/security/sec5d0fab7c6/web>
- Apple — Startup Security Utility on Mac with Apple silicon: <https://support.apple.com/guide/mac-help/mchl768f7291/mac>
- Apple — Use Apple Configurator to revive or restore a Mac: <https://support.apple.com/en-us/108900>
- `man bputil`, `man nvram`, `man kmutil`, `man bless`
- Asahi Linux: <https://asahilinux.org/>

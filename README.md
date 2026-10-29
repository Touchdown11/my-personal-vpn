# ⚡ VeloVPN — Personal WireGuard VPN (Android + Windows)

Cross-platform personal WireGuard VPN app with a built-in free Cloudflare WARP
profile and support for imported country `.conf` profiles.

## Features

- **⚡ Built-in free WARP profile:** generates Curve25519 keys on-device and
  registers a personal WireGuard profile with Cloudflare's edge.
- **📊 Live telemetry:** download/upload speed, session data, duration, and an
  endpoint TCP probe. The TCP probe is **not** ICMP ping and does not measure
  latency through the WireGuard UDP tunnel.
- **🛡️ DNS modes:** Cloudflare Gaming DNS, AdGuard Ad/Tracker DNS, Cloudflare
  Malware DNS, or keep the imported profile's DNS.
- **🔥 WARP UDP port selection:** UDP 2408, 500, or 4500.
- **🌍 Imported `.conf` manager:** paste WireGuard profiles such as Proton VPN
  Free USA / Japan / NL configs.
- **📱 Android split-tunnel exclusions:** comma-separated package names.
- **🧭 Full-tunnel routing override:** forces imported profiles to use
  `0.0.0.0/0, ::/0`. The built-in WARP profile always uses full-tunnel routing.

## Important security note

This app configures WireGuard routing. It does **not** implement an OS-level
kill switch. For leak protection when the tunnel drops, enable your operating
system's always-on / lockdown VPN or firewall rules:

- **Android:** Settings → Network & internet → VPN → Always-on VPN / Block
  connections without VPN (wording varies by device).
- **Windows:** use Windows Firewall or a WireGuard client/firewall policy that
  blocks untunneled traffic.

The previous "Strict Kill Switch" label was misleading and has been replaced
with an accurate full-tunnel routing control.

## Build in GitHub Actions

The workflow pins Flutter **3.38.10**, runs analysis/tests, then builds:

- Android APK: `VeloVPN-Personal-Android-APK`
- Windows app folder: `VeloVPN-Personal-Windows-EXE`

Push to `main`, `master`, or an `arena/**` branch, or run the workflow manually
from the **Actions** tab.

## Build locally on Windows 10/11

Install Flutter **3.38.10** and Visual Studio's C++ desktop workload, then run:

```powershell
powershell -ExecutionPolicy Bypass -File .\build-on-windows.ps1
```

The script recreates missing platform scaffolding, prepares Android desugaring
and permissions, runs `flutter analyze` / `flutter test`, and builds the Windows
app. Run the resulting Windows executable as administrator so it can create the
WireGuard tunnel service.

## Vendored WireGuard plugin

`third_party/wireguard_flutter_plus` is a trimmed, patched copy of upstream
`wireguard_flutter_plus` 1.0.9. See `third_party/wireguard_flutter_plus/VELO_PATCHES.md`
for the exact changes. The override keeps native build fixes reproducible instead
of mutating the global pub cache during CI.

## Tests

```bash
flutter pub get
flutter analyze
flutter test
```

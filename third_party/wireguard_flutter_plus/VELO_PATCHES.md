# VeloVPN vendoring notes

This directory contains a trimmed copy of `wireguard_flutter_plus` 1.0.9 from
https://github.com/aakashch0179/wireguard_flutter_plus (tag `1.0.9`, commit
`622b12d7f674f1247be50b2afc23baeadb1f9705`).

Only the Dart, Android, Windows, and Linux-facing plugin files needed by this
app are kept. The upstream license is preserved in `LICENSE`.

## Local patches

- `pubspec.yaml`: marked `publish_to: none`, version `1.0.9+velo.1`, and limited
  plugin platform declarations to the platforms this repository builds.
- `android/build.gradle`: removed the obsolete embedded AGP/Kotlin buildscript,
  raised compile SDK to 36, set Java/Kotlin target to 17, raised min SDK to 24,
  enabled core-library desugaring, and updated AndroidX/coroutines/desugaring
  dependencies for Flutter 3.38.x.

The Windows native sources are currently unmodified from upstream. If CI exposes
a Windows-specific compiler issue, patch it here and document the change in this
file rather than editing the pub cache during builds.

import 'dart:io';

/// Prepares the generated Android scaffolding for the vendored WireGuard plugin.
///
/// Run after `flutter create . --platforms=android ...` and before
/// `flutter pub get` / `flutter build apk`. The script is idempotent.
void main(List<String> args) {
  final root = args.isEmpty ? Directory.current.path : args.first;
  final pluginClass = File(
    '$root/third_party/wireguard_flutter_plus/android/src/main/kotlin/'
    'orban/group/wireguard_flutter/WireguardFlutterPlugin.kt',
  );
  if (!pluginClass.existsSync()) {
    stderr.writeln(
      'Vendored WireGuard Android plugin class is missing: ${pluginClass.path}. '
      'Check that third_party/wireguard_flutter_plus/android is tracked by Git.',
    );
    exitCode = 1;
    return;
  }

  final appDir = Directory('$root/android/app');
  if (!appDir.existsSync()) {
    stderr.writeln('Android scaffolding is missing. Run flutter create first.');
    exitCode = 1;
    return;
  }

  final kts = File('${appDir.path}/build.gradle.kts');
  final groovy = File('${appDir.path}/build.gradle');
  final gradleFile = kts.existsSync() ? kts : groovy;
  if (!gradleFile.existsSync()) {
    stderr.writeln('Could not find android/app/build.gradle(.kts).');
    exitCode = 1;
    return;
  }

  var gradle = gradleFile.readAsStringSync();
  final isKts = gradleFile.path.endsWith('.kts');
  const desugarVersion = '2.1.5';

  if (!gradle.contains('coreLibraryDesugaringEnabled') &&
      !gradle.contains('isCoreLibraryDesugaringEnabled')) {
    final compileOptions = RegExp(r'compileOptions\s*\{');
    final match = compileOptions.firstMatch(gradle);
    if (match == null) {
      stderr.writeln('Could not find compileOptions in ${gradleFile.path}.');
      exitCode = 1;
      return;
    }
    final flag = isKts
        ? '\n        isCoreLibraryDesugaringEnabled = true'
        : '\n        coreLibraryDesugaringEnabled true';
    gradle = gradle.replaceRange(match.end, match.end, flag);
  }

  if (!gradle.contains('desugar_jdk_libs')) {
    final dependency = isKts
        ? 'coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:$desugarVersion")'
        : "coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:$desugarVersion'";
    final dependencies = RegExp(r'dependencies\s*\{');
    final match = dependencies.firstMatch(gradle);
    if (match == null) {
      // Flutter 3.38.x app templates can omit the dependencies block entirely.
      gradle = '${gradle.trimRight()}\n\ndependencies {\n    $dependency\n}\n';
    } else {
      gradle = gradle.replaceRange(match.end, match.end, '\n    $dependency');
    }
  }

  gradleFile.writeAsStringSync(gradle);

  final manifest = File('${appDir.path}/src/main/AndroidManifest.xml');
  if (!manifest.existsSync()) {
    stderr.writeln('Could not find AndroidManifest.xml.');
    exitCode = 1;
    return;
  }
  var manifestText = manifest.readAsStringSync();
  if (!manifestText.contains('android.permission.INTERNET')) {
    final manifestTag = RegExp(r'<manifest[^>]*>').firstMatch(manifestText);
    if (manifestTag == null) {
      stderr.writeln('Could not find <manifest> tag.');
      exitCode = 1;
      return;
    }
    const permission =
        '\n    <uses-permission android:name="android.permission.INTERNET"/>';
    manifestText =
        manifestText.replaceRange(manifestTag.end, manifestTag.end, permission);
    manifest.writeAsStringSync(manifestText);
  }

  stdout.writeln('Android scaffolding is ready for the vendored WireGuard plugin.');
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('vendored WireGuard plugin includes required native platform sources', () {
    const pluginRoot = 'third_party/wireguard_flutter_plus';
    final requiredFiles = <String>[
      '$pluginRoot/android/build.gradle',
      '$pluginRoot/android/src/main/AndroidManifest.xml',
      '$pluginRoot/android/src/main/kotlin/orban/group/wireguard_flutter/WireguardFlutterPlugin.kt',
      '$pluginRoot/windows/CMakeLists.txt',
      '$pluginRoot/windows/wireguard_flutter_plugin.cpp',
      '$pluginRoot/windows/wireguard_flutter_plugin_c_api.cpp',
      '$pluginRoot/lib/linux/wireguard_flutter_linux.dart',
    ];

    for (final path in requiredFiles) {
      expect(File(path).existsSync(), isTrue, reason: 'Missing vendored plugin file: $path');
    }
  });
}

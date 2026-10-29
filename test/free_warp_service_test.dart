import 'package:flutter_test/flutter_test.dart';
import 'package:velo_personal_vpn/models/vpn_profile.dart';
import 'package:velo_personal_vpn/services/free_warp_service.dart';

void main() {
  const imported = '''[Interface]
PrivateKey = key
Address = 10.2.0.2/32

[Peer]
PublicKey = peer
AllowedIPs = 0.0.0.0/0
Endpoint = proton.example:51820
''';

  test('AdGuard mode adds DNS even when the profile has no DNS line', () {
    final result = FreeWarpService.customizeImportedConfig(
      rawConf: imported,
      dnsMode: DnsShieldMode.adAndTrackerBlock,
      forceFullTunnel: false,
    );

    expect(result, contains('DNS = 94.140.14.14, 94.140.15.15'));
  });

  test('keep-profile mode does not invent a DNS override', () {
    final result = FreeWarpService.customizeImportedConfig(
      rawConf: imported,
      dnsMode: DnsShieldMode.keepProfileDefault,
      forceFullTunnel: false,
    );

    expect(result, imported);
  });

  test('full-tunnel override includes IPv6 instead of dropping it', () {
    final result = FreeWarpService.customizeImportedConfig(
      rawConf: imported,
      dnsMode: DnsShieldMode.keepProfileDefault,
      forceFullTunnel: true,
    );

    expect(result, contains('AllowedIPs = 0.0.0.0/0, ::/0'));
    expect(result, isNot(contains('0.0.0.0/1, 128.0.0.0/1')));
  });
}

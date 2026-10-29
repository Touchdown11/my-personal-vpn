import 'package:flutter_test/flutter_test.dart';
import 'package:velo_personal_vpn/models/vpn_profile.dart';

void main() {
  CustomVpnProfile profile(String endpoint) => CustomVpnProfile(
        id: 'id',
        name: 'name',
        countryFlag: '🌍',
        endpoint: endpoint,
        rawWgConfig: '',
      );

  test('hostOnly strips ports from hostnames and IPv4', () {
    expect(profile('example.com:51820').hostOnly, 'example.com');
    expect(profile('192.0.2.1:51820').hostOnly, '192.0.2.1');
  });

  test('hostOnly preserves bracketed IPv6 hosts without the port', () {
    expect(profile('[2001:db8::1]:51820').hostOnly, '2001:db8::1');
  });
}

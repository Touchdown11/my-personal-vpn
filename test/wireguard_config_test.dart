import 'package:flutter_test/flutter_test.dart';
import 'package:velo_personal_vpn/services/wireguard_config.dart';

void main() {
  const basic = '''[Interface]
PrivateKey = private-key
Address = 10.0.0.2/32

[Peer]
PublicKey = public-key
AllowedIPs = 0.0.0.0/0
Endpoint = example.com:51820
''';

  group('customizeImported', () {
    test('adds DNS when the imported profile has no DNS line', () {
      final result = WireGuardConfigEditor.customizeImported(
        rawConf: basic,
        dnsServers: '94.140.14.14, 94.140.15.15',
        forceFullTunnel: false,
      );

      expect(result, contains('DNS = 94.140.14.14, 94.140.15.15'));
      expect(result, contains('Endpoint = example.com:51820'));
      expect(result, contains('AllowedIPs = 0.0.0.0/0'));
    });

    test('replaces existing DNS case-insensitively and preserves CRLF', () {
      const raw = '[Interface]\r\nPrivateKey = key\r\ndns = 1.1.1.1\r\n\r\n[Peer]\r\nPublicKey = peer\r\nEndpoint = example.com:51820\r\n';
      final result = WireGuardConfigEditor.customizeImported(
        rawConf: raw,
        dnsServers: '9.9.9.9',
        forceFullTunnel: false,
      );

      expect(result, contains('dns = 9.9.9.9'));
      expect(result, isNot(contains('1.1.1.1')));
      expect(result, contains('\r\n'));
      expect(result, isNot(contains('\n\n')));
    });

    test('keeps profile DNS when dnsServers is null or empty', () {
      final result = WireGuardConfigEditor.customizeImported(
        rawConf: basic,
        dnsServers: null,
        forceFullTunnel: false,
      );
      expect(result, basic);
    });

    test('forces IPv4 and IPv6 full-tunnel routes on every peer', () {
      const raw = '''[Interface]
PrivateKey = key

[Peer]
PublicKey = peer-1
AllowedIPs = 10.0.0.0/8
Endpoint = one.example:51820

[Peer]
PublicKey = peer-2
Endpoint = two.example:51820
''';
      final result = WireGuardConfigEditor.customizeImported(
        rawConf: raw,
        forceFullTunnel: true,
      );

      expect('AllowedIPs = 0.0.0.0/0, ::/0'.allMatches(result).length, 2);
      expect(result, isNot(contains('10.0.0.0/8')));
    });

    test('does not rewrite commented-out keys or other sections', () {
      const raw = '''# DNS = comment
[Interface]
PrivateKey = key
# DNS = still-comment

[Peer]
PublicKey = peer
# AllowedIPs = comment
AllowedIPs = 192.168.0.0/16
Endpoint = example.com:51820
''';
      final result = WireGuardConfigEditor.customizeImported(
        rawConf: raw,
        dnsServers: '9.9.9.9',
        forceFullTunnel: true,
      );

      expect(result, contains('# DNS = comment'));
      expect(result, contains('# DNS = still-comment'));
      expect(result, contains('# AllowedIPs = comment'));
      expect(result, contains('DNS = 9.9.9.9'));
      expect(result, contains('AllowedIPs = 0.0.0.0/0, ::/0'));
      expect(result, isNot(contains('192.168.0.0/16')));
    });

    test('rejects configs without a peer section', () {
      expect(
        () => WireGuardConfigEditor.customizeImported(
          rawConf: '[Interface]\nPrivateKey = key\n',
          forceFullTunnel: true,
        ),
        throwsFormatException,
      );
    });
  });

  group('validateAndExtractEndpoint', () {
    test('extracts the endpoint from the peer section', () {
      expect(
        WireGuardConfigEditor.validateAndExtractEndpoint(basic),
        'example.com:51820',
      );
    });

    test('supports bracketed IPv6 endpoints', () {
      const raw = '''[Interface]
PrivateKey = key

[Peer]
PublicKey = peer
Endpoint = [2001:db8::1]:51820
''';
      expect(
        WireGuardConfigEditor.validateAndExtractEndpoint(raw),
        '[2001:db8::1]:51820',
      );
    });

    test('ignores commented endpoints and requires a real one', () {
      const raw = '''[Interface]
PrivateKey = key

[Peer]
PublicKey = peer
# Endpoint = commented.example:51820
''';
      expect(
        () => WireGuardConfigEditor.validateAndExtractEndpoint(raw),
        throwsFormatException,
      );
    });

    test('requires interface private key and peer public key', () {
      expect(
        () => WireGuardConfigEditor.validateAndExtractEndpoint(
          '[Interface]\n[Peer]\nEndpoint = example.com:51820\n',
        ),
        throwsFormatException,
      );
      expect(
        () => WireGuardConfigEditor.validateAndExtractEndpoint(
          '[Interface]\nPrivateKey = key\n[Peer]\nEndpoint = example.com:51820\n',
        ),
        throwsFormatException,
      );
    });

    test('rejects endpoints without a valid port', () {
      for (final endpoint in ['example.com', 'example.com:0', 'example.com:99999']) {
        final raw = '[Interface]\nPrivateKey = key\n[Peer]\nPublicKey = peer\nEndpoint = $endpoint\n';
        expect(
          () => WireGuardConfigEditor.validateAndExtractEndpoint(raw),
          throwsFormatException,
        );
      }
    });
  });
}

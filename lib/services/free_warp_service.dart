import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/vpn_profile.dart';

/// 100% Free Serverless WireGuard Engine ($0 Server Cost, No Account Needed)
class FreeWarpService {
  static const _privKeyPref = 'velo_warp_priv_key';
  static const _pubKeyPref = 'velo_warp_pub_key';
  static const _v4Pref = 'velo_warp_ipv4';
  static const _v6Pref = 'velo_warp_ipv6';
  static const _peerPubPref = 'velo_warp_peer_pub';

  /// Generates RFC-7748 clamped Curve25519 WireGuard keys on-device
  /// and registers a free personal tunnel with Cloudflare's global UDP edge.
  static Future<void> ensureRegistered({bool forceRefresh = false}) async {
    final prefs = await SharedPreferences.getInstance();
    if (!forceRefresh &&
        prefs.getString(_privKeyPref) != null &&
        prefs.getString(_v4Pref) != null &&
        prefs.getString(_peerPubPref) != null) {
      return;
    }

    final rng = Random.secure();
    final seed = Uint8List.fromList(List<int>.generate(32, (_) => rng.nextInt(256)));
    // Strict WireGuard Curve25519 scalar clamping
    seed[0] &= 248;
    seed[31] &= 127;
    seed[31] |= 64;

    final algorithm = X25519();
    final keyPair = await algorithm.newKeyPairFromSeed(seed);
    final privBytes = await keyPair.extractPrivateKeyBytes();
    final pubKey = await keyPair.extractPublicKey();

    final privB64 = base64Encode(privBytes);
    final pubB64 = base64Encode(pubKey.bytes);

    final res = await http.post(
      Uri.parse('https://api.cloudflareclient.com/v0a2158/reg'),
      headers: {
        'Content-Type': 'application/json',
        'CF-Client-Version': 'a-6.11-2223',
      },
      body: jsonEncode({
        'key': pubB64,
        'install_id': '',
        'fcm_token': '',
        'tos': DateTime.now().toUtc().toIso8601String(),
        'model': 'VeloPersonalVPN',
        'locale': 'en_US',
      }),
    );

    if (res.statusCode != 200) {
      throw Exception('Free tunnel registration returned HTTP ${res.statusCode}');
    }

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final cfg = body['config'] as Map<String, dynamic>;
    final peer = (cfg['peers'] as List<dynamic>).first as Map<String, dynamic>;
    final addrs =
        (cfg['interface'] as Map<String, dynamic>)['addresses'] as Map<String, dynamic>;

    await prefs.setString(_privKeyPref, privB64);
    await prefs.setString(_pubKeyPref, pubB64);
    await prefs.setString(_v4Pref, addrs['v4'] as String);
    await prefs.setString(_v6Pref, addrs['v6'] as String);
    await prefs.setString(_peerPubPref, peer['public_key'] as String);
  }

  /// Builds the WireGuard Quick Config dynamically applying user's chosen
  /// Firewall Bypass UDP Port, DNS Ad-Blocker Mode, and Kill Switch!
  static Future<String> buildFreeWarpConfig({
    required int udpPort,
    required DnsShieldMode dnsMode,
    required bool killSwitch,
  }) async {
    await ensureRegistered();
    final prefs = await SharedPreferences.getInstance();

    final priv = prefs.getString(_privKeyPref)!;
    final v4 = prefs.getString(_v4Pref)!;
    final v6 = prefs.getString(_v6Pref)!;
    final peerPub = prefs.getString(_peerPubPref)!;

    final dns = dnsMode.dnsServers.isNotEmpty ? dnsMode.dnsServers : '1.1.1.1, 1.0.0.1';
    final allowedIps = killSwitch ? '0.0.0.0/0, ::/0' : '0.0.0.0/1, 128.0.0.0/1';

    return '''[Interface]
PrivateKey = $priv
Address = $v4/32, $v6/128
DNS = $dns
MTU = 1280

[Peer]
PublicKey = $peerPub
AllowedIPs = $allowedIps
Endpoint = engage.cloudflareclient.com:$udpPort
PersistentKeepalive = 20
''';
  }

  /// Applies optional DNS AdBlocker & Kill Switch overrides to imported .conf files
  static String customizeImportedConfig({
    required String rawConf,
    required DnsShieldMode dnsMode,
    required bool killSwitch,
  }) {
    var updated = rawConf;

    if (dnsMode != DnsShieldMode.keepProfileDefault && dnsMode.dnsServers.isNotEmpty) {
      if (RegExp(r'^DNS\s*=', multiLine: true).hasMatch(updated)) {
        updated = updated.replaceFirst(
          RegExp(r'^DNS\s*=.*$', multiLine: true),
          'DNS = ${dnsMode.dnsServers}',
        );
      }
    }

    if (!killSwitch) {
      updated = updated.replaceFirst(
        RegExp(r'^AllowedIPs\s*=.*$', multiLine: true),
        'AllowedIPs = 0.0.0.0/1, 128.0.0.0/1',
      );
    }

    return updated;
  }
}

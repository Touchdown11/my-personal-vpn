import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/vpn_profile.dart';
import 'wireguard_config.dart';

/// 100% Free Serverless WireGuard Engine ($0 Server Cost, No Account Needed)
class FreeWarpService {
  static const _privKeyPref = 'velo_warp_priv_key';
  static const _pubKeyPref = 'velo_warp_pub_key';
  static const _v4Pref = 'velo_warp_ipv4';
  static const _v6Pref = 'velo_warp_ipv6';
  static const _peerPubPref = 'velo_warp_peer_pub';
  static const _registrationTimeout = Duration(seconds: 20);

  static Future<void>? _registrationInFlight;

  /// Generates RFC-7748 clamped Curve25519 WireGuard keys on-device
  /// and registers a free personal tunnel with Cloudflare's global UDP edge.
  static Future<void> ensureRegistered({bool forceRefresh = false}) {
    final existing = _registrationInFlight;
    if (existing != null) return existing;

    final future = _register(forceRefresh: forceRefresh).whenComplete(() {
      _registrationInFlight = null;
    });
    _registrationInFlight = future;
    return future;
  }

  static Future<void> _register({required bool forceRefresh}) async {
    final prefs = await SharedPreferences.getInstance();
    if (!forceRefresh &&
        prefs.getString(_privKeyPref) != null &&
        prefs.getString(_v4Pref) != null &&
        prefs.getString(_v6Pref) != null &&
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

    final http.Response res;
    try {
      res = await http
          .post(
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
          )
          .timeout(_registrationTimeout);
    } on TimeoutException {
      throw Exception('Free tunnel registration timed out. Check your internet connection and try again.');
    }

    if (res.statusCode != 200) {
      throw Exception('Free tunnel registration returned HTTP ${res.statusCode}');
    }

    final String v4;
    final String v6;
    final String peerPub;
    try {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final cfg = body['config'] as Map<String, dynamic>;
      final peers = cfg['peers'] as List<dynamic>;
      if (peers.isEmpty) {
        throw const FormatException('Registration response contained no peers.');
      }
      final peer = peers.first as Map<String, dynamic>;
      final addrs =
          (cfg['interface'] as Map<String, dynamic>)['addresses'] as Map<String, dynamic>;
      v4 = _requireString(addrs['v4'], 'IPv4 address');
      v6 = _requireString(addrs['v6'], 'IPv6 address');
      peerPub = _requireString(peer['public_key'], 'peer public key');
    } on Object catch (e) {
      throw Exception('Free tunnel registration returned an invalid response: $e');
    }

    // Only persist a complete, validated identity.
    await prefs.setString(_privKeyPref, privB64);
    await prefs.setString(_pubKeyPref, pubB64);
    await prefs.setString(_v4Pref, v4);
    await prefs.setString(_v6Pref, v6);
    await prefs.setString(_peerPubPref, peerPub);
  }

  static String _requireString(Object? value, String label) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
    throw FormatException('Registration response is missing $label.');
  }

  /// Builds the built-in Cloudflare WARP config.
  ///
  /// The built-in profile always routes both IPv4 and IPv6 through the tunnel.
  /// This is routing, not an OS-level kill switch; the UI must not claim that it
  /// blocks traffic when the tunnel is down.
  static Future<String> buildFreeWarpConfig({
    required int udpPort,
    required DnsShieldMode dnsMode,
  }) async {
    await ensureRegistered();
    final prefs = await SharedPreferences.getInstance();

    final priv = prefs.getString(_privKeyPref)!;
    final v4 = prefs.getString(_v4Pref)!;
    final v6 = prefs.getString(_v6Pref)!;
    final peerPub = prefs.getString(_peerPubPref)!;

    final dns = dnsMode.dnsServers.isNotEmpty ? dnsMode.dnsServers : '1.1.1.1, 1.0.0.1';

    return '''[Interface]
PrivateKey = $priv
Address = $v4/32, $v6/128
DNS = $dns
MTU = 1280

[Peer]
PublicKey = $peerPub
AllowedIPs = ${WireGuardConfigEditor.fullTunnelAllowedIps}
Endpoint = engage.cloudflareclient.com:$udpPort
PersistentKeepalive = 20
''';
  }

  /// Applies optional DNS and full-tunnel routing overrides to imported configs.
  static String customizeImportedConfig({
    required String rawConf,
    required DnsShieldMode dnsMode,
    required bool forceFullTunnel,
  }) {
    return WireGuardConfigEditor.customizeImported(
      rawConf: rawConf,
      dnsServers: dnsMode == DnsShieldMode.keepProfileDefault ? null : dnsMode.dnsServers,
      forceFullTunnel: forceFullTunnel,
    );
  }
}

class CustomVpnProfile {
  final String id;
  final String name;
  final String countryFlag;
  final String endpoint;
  final String rawWgConfig;

  const CustomVpnProfile({
    required this.id,
    required this.name,
    required this.countryFlag,
    required this.endpoint,
    required this.rawWgConfig,
  });

  String get hostOnly {
    final clean = endpoint.trim();
    if (clean.startsWith('[')) {
      final endBracket = clean.indexOf(']');
      if (endBracket != -1) return clean.substring(1, endBracket);
    }
    return clean.split(':').first;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'countryFlag': countryFlag,
        'endpoint': endpoint,
        'rawWgConfig': rawWgConfig,
      };

  factory CustomVpnProfile.fromJson(Map<String, dynamic> json) {
    return CustomVpnProfile(
      id: json['id'] as String,
      name: json['name'] as String,
      countryFlag: (json['countryFlag'] as String?) ?? '🌍',
      endpoint: json['endpoint'] as String,
      rawWgConfig: json['rawWgConfig'] as String,
    );
  }
}

/// DNS Shield Modes (Gaming Low-Ping vs AdBlock vs Malware Protection)
enum DnsShieldMode {
  gamingFastest(
    label: '⚡ Gaming Fastest (Cloudflare 1.1.1.1)',
    subtitle: 'Lowest DNS lookup latency (~8ms) — no filtering',
    dnsServers: '1.1.1.1, 1.0.0.1',
  ),
  adAndTrackerBlock(
    label: '🛡️ Ad + Tracker + Malware Blocker',
    subtitle: 'Blocks ads, popups & trackers across apps (AdGuard DNS)',
    dnsServers: '94.140.14.14, 94.140.15.15',
  ),
  malwareShield(
    label: '🔒 Malware & Phishing Shield',
    subtitle: 'Blocks malicious & phishing domains (Cloudflare 1.1.1.2)',
    dnsServers: '1.1.1.2, 1.0.0.2',
  ),
  keepProfileDefault(
    label: '📄 Keep Profile Default DNS',
    subtitle: 'Recommended when using Proton VPN country configs (10.2.0.1)',
    dnsServers: '',
  );

  final String label;
  final String subtitle;
  final String dnsServers;

  const DnsShieldMode({
    required this.label,
    required this.subtitle,
    required this.dnsServers,
  });
}

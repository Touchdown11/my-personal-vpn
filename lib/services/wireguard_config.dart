/// Small, dependency-free WireGuard Quick config editor.
///
/// WireGuard configs are INI-like: keys are only meaningful inside the correct
/// section, and a config may contain multiple [Peer] sections. The helpers here
/// intentionally avoid global regex replacement so comments, other sections, and
/// unrelated keys are preserved.
class WireGuardConfigEditor {
  static const fullTunnelAllowedIps = '0.0.0.0/0, ::/0';

  static final _sectionPattern = RegExp(r'^\s*\[([^\]]+)\]\s*(?:#.*)?$');
  static final _keyPattern = RegExp(r'^(\s*)([A-Za-z0-9_-]+)(\s*=\s*)(.*?)(\s*)$');

  /// Applies DNS and routing overrides to an imported config.
  ///
  /// [dnsServers] of `null` or an empty string means "keep the profile DNS".
  /// When [forceFullTunnel] is true, every peer is routed through the tunnel for
  /// both IPv4 and IPv6. When false, the imported profile's own routes are kept.
  static String customizeImported({
    required String rawConf,
    String? dnsServers,
    required bool forceFullTunnel,
  }) {
    final document = _Document.parse(rawConf);
    final interface = document.firstSection('Interface');
    if (interface == null) {
      throw const FormatException('WireGuard config is missing [Interface].');
    }
    final peers = document.sectionsNamed('Peer');
    if (peers.isEmpty) {
      throw const FormatException('WireGuard config is missing [Peer].');
    }

    if (dnsServers != null && dnsServers.trim().isNotEmpty) {
      interface.setKey('DNS', dnsServers.trim());
    }

    if (forceFullTunnel) {
      for (final peer in peers) {
        peer.setKey('AllowedIPs', fullTunnelAllowedIps);
      }
    }

    return document.render();
  }

  /// Validates the minimum fields needed before handing a config to the native
  /// WireGuard backend, and returns the first peer endpoint.
  static String validateAndExtractEndpoint(String rawConf) {
    final document = _Document.parse(rawConf);
    final interface = document.firstSection('Interface');
    if (interface == null) {
      throw const FormatException('WireGuard config is missing [Interface].');
    }
    if (interface.valueFor('PrivateKey')?.isNotEmpty != true) {
      throw const FormatException('[Interface] must contain PrivateKey.');
    }

    final peer = document.firstSection('Peer');
    if (peer == null) {
      throw const FormatException('WireGuard config is missing [Peer].');
    }
    if (peer.valueFor('PublicKey')?.isNotEmpty != true) {
      throw const FormatException('[Peer] must contain PublicKey.');
    }

    final endpoint = peer.valueFor('Endpoint');
    if (endpoint == null || endpoint.isEmpty) {
      throw const FormatException('[Peer] must contain Endpoint = host:port.');
    }
    _validateEndpoint(endpoint);
    return endpoint;
  }

  static void _validateEndpoint(String endpoint) {
    if (endpoint.contains(RegExp(r'\s'))) {
      throw const FormatException('Endpoint must not contain whitespace.');
    }
    final uri = Uri.tryParse('//$endpoint');
    if (uri == null || uri.host.isEmpty || !uri.hasPort) {
      throw const FormatException('Endpoint must be host:port or [IPv6]:port.');
    }
    final port = uri.port;
    if (port < 1 || port > 65535) {
      throw const FormatException('Endpoint port must be between 1 and 65535.');
    }
  }
}

class _Document {
  _Document(this.preamble, this.sections, this.lineEnding, this.trailingNewline);

  final List<String> preamble;
  final List<_Section> sections;
  final String lineEnding;
  final bool trailingNewline;

  factory _Document.parse(String raw) {
    final lineEnding = raw.contains('\r\n') ? '\r\n' : '\n';
    final normalized = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final trailingNewline = normalized.endsWith('\n');
    final lines = normalized.split('\n');
    if (trailingNewline && lines.isNotEmpty && lines.last.isEmpty) {
      lines.removeLast();
    }

    final preamble = <String>[];
    final sections = <_Section>[];
    _Section? current;
    for (final line in lines) {
      final match = WireGuardConfigEditor._sectionPattern.firstMatch(line);
      if (match != null) {
        current = _Section(match.group(1)!, line);
        sections.add(current);
      } else if (current == null) {
        preamble.add(line);
      } else {
        current.body.add(line);
      }
    }
    return _Document(preamble, sections, lineEnding, trailingNewline);
  }

  _Section? firstSection(String name) {
    for (final section in sections) {
      if (section.name.toLowerCase() == name.toLowerCase()) return section;
    }
    return null;
  }

  List<_Section> sectionsNamed(String name) => sections
      .where((section) => section.name.toLowerCase() == name.toLowerCase())
      .toList();

  String render() {
    final lines = <String>[
      ...preamble,
      for (final section in sections) ...[section.header, ...section.body],
    ];
    final rendered = lines.join(lineEnding);
    return trailingNewline ? '$rendered$lineEnding' : rendered;
  }
}

class _Section {
  _Section(this.name, this.header);

  final String name;
  final String header;
  final List<String> body = [];

  String? valueFor(String key) {
    for (final line in body) {
      final match = WireGuardConfigEditor._keyPattern.firstMatch(line);
      if (match != null && match.group(2)!.toLowerCase() == key.toLowerCase()) {
        return _stripComment(match.group(4)!).trim();
      }
    }
    return null;
  }

  void setKey(String key, String value) {
    var replaced = false;
    final updated = <String>[];
    for (final line in body) {
      final match = WireGuardConfigEditor._keyPattern.firstMatch(line);
      if (match != null && match.group(2)!.toLowerCase() == key.toLowerCase()) {
        if (!replaced) {
          updated.add('${match.group(1)}${match.group(2)}${match.group(3)}$value');
          replaced = true;
        }
        // Drop duplicate keys so the native parser does not see conflicting
        // DNS or AllowedIPs values.
        continue;
      }
      updated.add(line);
    }
    if (!replaced) {
      updated.add('$key = $value');
    }
    body
      ..clear()
      ..addAll(updated);
  }

  static String _stripComment(String value) {
    final index = value.indexOf('#');
    return index == -1 ? value : value.substring(0, index);
  }
}

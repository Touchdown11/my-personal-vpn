import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wireguard_flutter_plus/wireguard_flutter_plus.dart';

import 'models/vpn_profile.dart';
import 'services/free_warp_service.dart';
import 'services/ping_service.dart';
import 'services/wireguard_config.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const VeloUltimatePersonalApp());
}

class VeloUltimatePersonalApp extends StatelessWidget {
  const VeloUltimatePersonalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VeloVPN Personal',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF070A12),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E5A3),
          secondary: Color(0xFF3B82F6),
          surface: Color(0xFF101728),
        ),
      ),
      home: const UltimateVpnHome(),
    );
  }
}

class UltimateVpnHome extends StatefulWidget {
  const UltimateVpnHome({super.key});

  @override
  State<UltimateVpnHome> createState() => _UltimateVpnHomeState();
}

class _UltimateVpnHomeState extends State<UltimateVpnHome> {
  static const _profilesPrefKey = 'velo_saved_country_profiles_v1';
  static const _excludedAppsPrefKey = 'velo_excluded_android_apps_v1';

  final _wireguard = WireGuardFlutter.instance;

  int _navIndex = 0;
  String _selectedProfileId = 'builtin_free_warp';
  List<CustomVpnProfile> _profiles = [];

  // Connection & Live Telemetry
  bool _engineReady = false;
  String? _engineError;
  StreamSubscription<VpnStage>? _stageSubscription;
  StreamSubscription<Map<String, dynamic>>? _trafficSubscription;
  bool _isConnected = false;
  bool _isBusy = false;
  String _stageText = 'DISCONNECTED';
  String _downSpeed = '0 KB/s';
  String _upSpeed = '0 KB/s';
  String _totalData = '0 MB';
  String _duration = '00:00:00';

  // Live Ping Meter
  PingResult? _latestPing;
  bool _isPinging = false;

  // Ultimate Controls
  int _udpPort = 2408; // 2408 | 500 | 4500
  DnsShieldMode _dnsMode = DnsShieldMode.gamingFastest;
  bool _forceFullTunnel = true;
  final TextEditingController _excludedAppsCtrl = TextEditingController();
  String _lastBuiltConfig = '# Tap Connect or Preview to generate your WireGuard config';

  @override
  void initState() {
    super.initState();
    _initEngine();
    _loadSavedData();
  }

  @override
  void dispose() {
    _stageSubscription?.cancel();
    _trafficSubscription?.cancel();
    _excludedAppsCtrl.dispose();
    super.dispose();
  }

  Future<void> _initEngine() async {
    try {
      await _wireguard.initialize(
        interfaceName: 'wg0',
        vpnName: 'VeloVPN Personal',
      );
      _engineReady = true;
      _engineError = null;
    } catch (e) {
      _engineReady = false;
      final message = 'VPN engine initialization failed: $e';
      _engineError = message;
      if (mounted) {
        setState(() => _stageText = 'ENGINE ERROR');
        WidgetsBinding.instance.addPostFrameCallback((_) => _showError(message));
      }
      return;
    }

    await _stageSubscription?.cancel();
    _stageSubscription = _wireguard.vpnStageSnapshot.listen((event) {
      if (!mounted) return;
      final name = event.toString().split('.').last.toLowerCase();
      setState(() {
        _isConnected = name == 'connected';
        _isBusy = name == 'connecting' ||
            name == 'authenticating' ||
            name == 'disconnecting' ||
            name == 'reconnect';
        _stageText = name.toUpperCase();
      });
    }, onError: (Object e) {
      if (mounted) _showError('VPN status stream failed: $e');
    });

    await _trafficSubscription?.cancel();
    _trafficSubscription = _wireguard.trafficSnapshot.listen((data) {
      if (!mounted) return;
      setState(() {
        _downSpeed = _formatRate(data['downloadSpeed']);
        _upSpeed = _formatRate(data['uploadSpeed']);
        _totalData = _formatBytes(
          _toNum(data['totalDownload']) + _toNum(data['totalUpload']),
        );
        if (data['duration'] != null) {
          _duration = data['duration'].toString();
        }
      });
    }, onError: (Object e) {
      if (mounted) _showError('VPN telemetry stream failed: $e');
    });
  }

  void _showError(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      SnackBar(backgroundColor: Colors.redAccent, content: Text(message)),
    );
  }

  double _toNum(dynamic val) {
    if (val is num) return val.toDouble();
    if (val is String) return double.tryParse(val) ?? 0;
    return 0;
  }

  String _formatRate(dynamic raw) {
    if (raw is String && raw.contains('/s')) return raw;
    final bytesPerSec = _toNum(raw);
    if (bytesPerSec <= 0) return '0 KB/s';
    if (bytesPerSec >= 1024 * 1024) {
      return '${(bytesPerSec / (1024 * 1024)).toStringAsFixed(1)} MB/s';
    }
    return '${(bytesPerSec / 1024).toStringAsFixed(0)} KB/s';
  }

  String _formatBytes(double bytes) {
    if (bytes <= 0) return '0 MB';
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _loadSavedData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawList = prefs.getString(_profilesPrefKey);
      if (rawList != null) {
        final decoded = jsonDecode(rawList) as List<dynamic>;
        _profiles = decoded
            .map((e) => CustomVpnProfile.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      _excludedAppsCtrl.text = prefs.getString(_excludedAppsPrefKey) ?? '';
    } catch (e) {
      _profiles = [];
      if (mounted) _showError('Saved VPN profiles could not be loaded: $e');
    }
    if (mounted) setState(() {});
    await _runPingTest();
  }

  Future<void> _saveProfiles() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _profilesPrefKey,
      jsonEncode(_profiles.map((p) => p.toJson()).toList()),
    );
  }

  Future<void> _runPingTest() async {
    if (_isPinging || !mounted) return;
    setState(() => _isPinging = true);

    String host = 'engage.cloudflareclient.com';
    if (_selectedProfileId != 'builtin_free_warp') {
      final found = _profiles.where((p) => p.id == _selectedProfileId);
      if (found.isNotEmpty) host = found.first.hostOnly;
    }

    try {
      final result = await PingService.measureHost(host);
      if (mounted) setState(() => _latestPing = result);
    } catch (e) {
      if (mounted) _showError('Endpoint TCP probe failed: $e');
    } finally {
      if (mounted) setState(() => _isPinging = false);
    }
  }

  Future<(String endpoint, String config)> _prepareActiveTunnel() async {
    if (_selectedProfileId == 'builtin_free_warp') {
      final cfg = await FreeWarpService.buildFreeWarpConfig(
        udpPort: _udpPort,
        dnsMode: _dnsMode,
      );
      return ('engage.cloudflareclient.com:$_udpPort', cfg);
    }

    final profile = _profiles.firstWhere((p) => p.id == _selectedProfileId);
    final cfg = FreeWarpService.customizeImportedConfig(
      rawConf: profile.rawWgConfig,
      dnsMode: _dnsMode,
      forceFullTunnel: _forceFullTunnel,
    );
    return (profile.endpoint, cfg);
  }

  Future<void> _toggleConnect() async {
    if (_isBusy) return;
    setState(() => _isBusy = true);
    try {
      if (_isConnected) {
        await _wireguard.stopVpn();
      } else {
        if (!_engineReady) {
          await _initEngine();
          if (!_engineReady) {
            throw Exception(_engineError ?? 'VPN engine is not initialized.');
          }
        }

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_excludedAppsPrefKey, _excludedAppsCtrl.text.trim());

        final (endpoint, wgConf) = await _prepareActiveTunnel();
        setState(() => _lastBuiltConfig = wgConf);

        final excludedApps = Platform.isAndroid
            ? _excludedAppsCtrl.text
                .split(',')
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .toList()
            : <String>[];

        await _wireguard.startVpn(
          serverAddress: endpoint,
          wgQuickConfig: wgConf,
          providerBundleIdentifier: 'com.personal.velovpn.WGExtension',
          excludedApps: excludedApps,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text('VPN Error: $e'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _openImportModal() async {
    final nameCtrl = TextEditingController(text: 'USA Free (Proton)');
    final flagCtrl = TextEditingController(text: '🇺🇸');
    final confCtrl = TextEditingController();

    try {
      await showDialog<void>(
        context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF101728),
        title: const Text('Import Country WireGuard .conf'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Tip: Download free USA / Japan / NL .conf files from account.protonvpn.com → Downloads → WireGuard configuration and paste below!',
                  style: TextStyle(fontSize: 12, color: Colors.white70),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    SizedBox(
                      width: 64,
                      child: TextField(
                        controller: flagCtrl,
                        decoration: const InputDecoration(labelText: 'Flag'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(labelText: 'Server Label'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: confCtrl,
                  maxLines: 8,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  decoration: const InputDecoration(
                    labelText: 'Paste [Interface] & [Peer] config',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final raw = confCtrl.text.trim();
              final String endpoint;
              try {
                endpoint = WireGuardConfigEditor.validateAndExtractEndpoint(raw);
              } on FormatException catch (e) {
                _showError('Invalid .conf: ${e.message}');
                return;
              }
              final newProfile = CustomVpnProfile(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                name: nameCtrl.text.trim().isEmpty ? 'Custom Country' : nameCtrl.text.trim(),
                countryFlag: flagCtrl.text.trim().isEmpty ? '🌍' : flagCtrl.text.trim(),
                endpoint: endpoint,
                rawWgConfig: raw,
              );
              setState(() {
                _profiles.add(newProfile);
                _selectedProfileId = newProfile.id;
                // Keep Proton internal DNS by default so country routing works smoothly
                _dnsMode = DnsShieldMode.keepProfileDefault;
              });
              await _saveProfiles();
              if (ctx.mounted) Navigator.pop(ctx);
              _runPingTest();
            },
            child: const Text('Save Country'),
          ),
        ],
        ),
      );
    } finally {
      nameCtrl.dispose();
      flagCtrl.dispose();
      confCtrl.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B101E),
        title: const Row(
          children: [
            Icon(Icons.bolt_rounded, color: Color(0xFF00E5A3)),
            SizedBox(width: 6),
            Text('VeloVPN', style: TextStyle(fontWeight: FontWeight.w800)),
            SizedBox(width: 8),
            Text(
              'PERSONAL FREE',
              style: TextStyle(fontSize: 11, color: Color(0xFF00E5A3)),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _isConnected
                      ? const Color(0x2800E5A3)
                      : const Color(0x28EF4444),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(
                    color: _isConnected
                        ? const Color(0xFF00E5A3)
                        : const Color(0xFFEF4444),
                  ),
                ),
                child: Text(
                  _stageText,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: _isConnected
                        ? const Color(0xFF00E5A3)
                        : const Color(0xFFFCA5A5),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: IndexedStack(
            index: _navIndex,
            children: [
              _buildConnectTab(),
              _buildShieldAndGamingTab(),
              _buildToolsTab(),
            ],
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: const Color(0xFF0B101E),
        selectedIndex: _navIndex,
        onDestinationSelected: (idx) async {
          setState(() => _navIndex = idx);
          if (idx == 2) {
            try {
              final (_, cfg) = await _prepareActiveTunnel();
              if (mounted) setState(() => _lastBuiltConfig = cfg);
            } catch (_) {}
          }
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.power_settings_new), label: 'Connect'),
          NavigationDestination(icon: Icon(Icons.shield_outlined), label: 'Shield & Gaming'),
          NavigationDestination(icon: Icon(Icons.code_rounded), label: 'Config Tools'),
        ],
      ),
    );
  }

  Widget _buildConnectTab() {
    final pingLabel = _isPinging
        ? 'Testing...'
        : (_latestPing == null || !_latestPing!.reachable
            ? '-- ms'
            : '${_latestPing!.avgMs} ms (±${_latestPing!.jitterMs})');

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Big Neon Connect Ring
        Center(
          child: GestureDetector(
            onTap: _isBusy ? null : _toggleConnect,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 240),
              width: 156,
              height: 156,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isConnected
                    ? const Color(0xFF0B352D)
                    : const Color(0xFF111A2E),
                border: Border.all(
                  color: _isBusy
                      ? const Color(0xFFF59E0B)
                      : (_isConnected
                          ? const Color(0xFF00E5A3)
                          : const Color(0xFF2B3B63)),
                  width: 3.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _isConnected
                        ? const Color(0x4400E5A3)
                        : const Color(0x44000000),
                    blurRadius: 28,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.power_settings_new_rounded,
                    size: 46,
                    color: _isConnected ? const Color(0xFF00E5A3) : Colors.white,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _isBusy
                        ? 'WORKING...'
                        : (_isConnected ? 'TAP STOP' : 'TAP CONNECT'),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _duration,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: Colors.white60,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 22),

        // 4-Box Live Telemetry Grid
        Row(
          children: [
            _metricTile('TCP PROBE', pingLabel, onTap: _runPingTest),
            const SizedBox(width: 8),
            _metricTile('DOWNLOAD', _downSpeed),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _metricTile('UPLOAD', _upSpeed),
            const SizedBox(width: 8),
            _metricTile('SESSION DATA', _totalData),
          ],
        ),
        const SizedBox(height: 22),

        // Server / Country Selector Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'SELECT FREE TUNNEL',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.white60,
              ),
            ),
            TextButton.icon(
              onPressed: _openImportModal,
              icon: const Icon(Icons.add_circle_outline, size: 18),
              label: const Text('Add Country .conf'),
            ),
          ],
        ),

        // Built-in Free Turbo/Gaming WARP Card
        _profileCard(
          id: 'builtin_free_warp',
          flag: '⚡',
          title: 'Auto Turbo & Gaming UDP (Free WARP)',
          subtitle: 'Port $_udpPort • ${_dnsMode.label.split(" ").take(2).join(" ")} • $0 Forever',
        ),

        // Imported Country Profiles
        ..._profiles.map(
          (p) => _profileCard(
            id: p.id,
            flag: p.countryFlag,
            title: p.name,
            subtitle: p.endpoint,
            onDelete: () async {
              setState(() {
                _profiles.removeWhere((item) => item.id == p.id);
                if (_selectedProfileId == p.id) {
                  _selectedProfileId = 'builtin_free_warp';
                }
              });
              await _saveProfiles();
            },
          ),
        ),
      ],
    );
  }

  Widget _metricTile(String label, String value, {VoidCallback? onTap}) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF101728),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF22304F)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    label,
                    style: const TextStyle(fontSize: 10, color: Colors.white54),
                  ),
                  if (onTap != null)
                    const Icon(Icons.refresh, size: 13, color: Color(0xFF00E5A3)),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _profileCard({
    required String id,
    required String flag,
    required String title,
    required String subtitle,
    VoidCallback? onDelete,
  }) {
    final selected = _selectedProfileId == id;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: selected ? const Color(0xFF112A2A) : const Color(0xFF101728),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? const Color(0xFF00E5A3) : const Color(0xFF22304F),
        ),
      ),
      child: ListTile(
        leading: Text(flag, style: const TextStyle(fontSize: 24)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.white60)),
        trailing: onDelete != null
            ? IconButton(
                icon: const Icon(Icons.delete_outline, size: 20, color: Colors.white54),
                onPressed: onDelete,
              )
            : (selected
                ? const Icon(Icons.check_circle, color: Color(0xFF00E5A3))
                : null),
        onTap: () {
          setState(() => _selectedProfileId = id);
          _runPingTest();
        },
      ),
    );
  }

  Widget _buildShieldAndGamingTab() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'DNS AD-BLOCKER & GAMING RESOLVER',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white60),
        ),
        const SizedBox(height: 8),
        ...DnsShieldMode.values.map(
          (mode) => RadioListTile<DnsShieldMode>(
            value: mode,
            groupValue: _dnsMode,
            activeColor: const Color(0xFF00E5A3),
            title: Text(mode.label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            subtitle: Text(mode.subtitle, style: const TextStyle(fontSize: 12)),
            onChanged: (v) {
              if (v != null) setState(() => _dnsMode = v);
            },
          ),
        ),
        const Divider(height: 28),
        const Text(
          'FIREWALL PORT BYPASS (FREE WARP TUNNEL)',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white60),
        ),
        const SizedBox(height: 8),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 2408, label: Text('UDP 2408 (Fast)')),
            ButtonSegment(value: 500, label: Text('UDP 500 (Wi-Fi)')),
            ButtonSegment(value: 4500, label: Text('UDP 4500 (NAT)')),
          ],
          selected: {_udpPort},
          onSelectionChanged: (s) => setState(() => _udpPort = s.first),
        ),
        const SizedBox(height: 20),
        SwitchListTile(
          title: const Text('Force full-tunnel routing'),
          subtitle: const Text(
            'Overrides imported profiles with IPv4 + IPv6 routes. Built-in WARP always uses full-tunnel routing. '
            'This is not an OS-level kill switch; enable always-on/lockdown VPN in your device settings for leak protection.',
          ),
          value: _forceFullTunnel,
          activeColor: const Color(0xFF00E5A3),
          onChanged: (v) => setState(() => _forceFullTunnel = v),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _excludedAppsCtrl,
          decoration: const InputDecoration(
            labelText: 'Android Split-Tunnel Excluded Apps (Optional)',
            hintText: 'com.whatsapp, com.discord',
            helperText: 'Comma-separated Android package names that bypass the VPN',
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }

  Widget _buildToolsTab() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        FilledButton.tonalIcon(
          onPressed: () async {
            setState(() => _isBusy = true);
            try {
              await FreeWarpService.ensureRegistered(forceRefresh: true);
              final (_, cfg) = await _prepareActiveTunnel();
              setState(() => _lastBuiltConfig = cfg);
              if (mounted) {
                final message = _selectedProfileId == 'builtin_free_warp'
                    ? 'Generated a brand-new free WARP keypair.'
                    : 'Regenerated the free WARP identity. The selected imported profile is unchanged.';
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(message)),
                );
              }
            } catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error: $e')),
                );
              }
            } finally {
              if (mounted) setState(() => _isBusy = false);
            }
          },
          icon: const Icon(Icons.autorenew),
          label: const Text('Regenerate Free WARP Identity (New Keypair)'),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'ACTIVE WIREGUARD CONFIG (.CONF)',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white60),
            ),
            TextButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _lastBuiltConfig));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Copied .conf to clipboard!')),
                );
              },
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('Copy .conf'),
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF0B101E),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF22304F)),
          ),
          child: SelectableText(
            _lastBuiltConfig,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.5),
          ),
        ),
      ],
    );
  }
}

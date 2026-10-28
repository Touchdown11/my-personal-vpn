import 'dart:io';
import 'dart:math';

class PingResult {
  final int avgMs;
  final int jitterMs;
  final bool reachable;

  const PingResult({
    required this.avgMs,
    required this.jitterMs,
    required this.reachable,
  });
}

/// Measures real round-trip latency & gaming jitter from your Windows PC / Android phone
class PingService {
  static Future<PingResult> measureHost(String host) async {
    final samples = <int>[];
    final targetHost = host == 'engage.cloudflareclient.com' ? '1.1.1.1' : host;

    for (var i = 0; i < 3; i++) {
      final sw = Stopwatch()..start();
      Socket? socket;
      try {
        socket = await Socket.connect(
          targetHost,
          443,
          timeout: const Duration(milliseconds: 1400),
        );
        sw.stop();
        samples.add(sw.elapsedMilliseconds);
      } catch (_) {
        // Fallback probe on port 53 if 443 is closed on a raw WireGuard host
        try {
          final sw2 = Stopwatch()..start();
          socket = await Socket.connect(
            targetHost,
            53,
            timeout: const Duration(milliseconds: 1200),
          );
          sw2.stop();
          samples.add(sw2.elapsedMilliseconds);
        } catch (_) {}
      } finally {
        socket?.destroy();
      }
    }

    if (samples.isEmpty) {
      return const PingResult(avgMs: 0, jitterMs: 0, reachable: false);
    }

    final sum = samples.reduce((a, b) => a + b);
    final avg = (sum / samples.length).round();
    final maxPing = samples.reduce(max);
    final minPing = samples.reduce(min);

    return PingResult(
      avgMs: avg,
      jitterMs: maxPing - minPing,
      reachable: true,
    );
  }
}

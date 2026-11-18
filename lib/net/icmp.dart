import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:teccheck_native/teccheck_native.dart';

class PingStats {
  final String target;
  final int sent;
  final int received;
  final List<double> rtts;

  PingStats(this.target, this.sent, this.received, this.rtts);

  double get lossPct => sent == 0 ? 0 : (sent - received) * 100 / sent;
  double? get min => rtts.isEmpty ? null : rtts.reduce((a, b) => a < b ? a : b);
  double? get max => rtts.isEmpty ? null : rtts.reduce((a, b) => a > b ? a : b);
  double? get avg => rtts.isEmpty ? null : rtts.reduce((a, b) => a + b) / rtts.length;

  /// Jitter = média da diferença entre amostras consecutivas.
  double? get jitter {
    if (rtts.length < 2) return null;
    var s = 0.0;
    for (var i = 1; i < rtts.length; i++) {
      s += (rtts[i] - rtts[i - 1]).abs();
    }
    return s / (rtts.length - 1);
  }
}

class Hop {
  final int ttl;
  final String? ip;
  final String? host;
  final double? rttMs;
  final bool reached;

  Hop(this.ttl, this.ip, this.host, this.rttMs, this.reached);
}

/// Ping e traceroute sobre o ICMP nativo (Android: /system/bin/ping, iOS: socket ICMP).
class IcmpTools {
  bool _stop = false;

  void stop() => _stop = true;

  static Future<String> resolve(String host) async {
    final ip = InternetAddress.tryParse(host);
    if (ip != null) return ip.address;
    final list = await InternetAddress.lookup(host, type: InternetAddressType.IPv4);
    if (list.isEmpty) throw Exception('Host desconhecido: $host');
    return list.first.address;
  }

  Future<PingStats> ping(
    String host, {
    required int count,
    required int size,
    required bool dontFragment,
    required void Function(String line) onLine,
    required void Function(PingStats partial) onProgress,
  }) async {
    _stop = false;
    final ip = await resolve(host);
    onLine('PING $host ($ip) $size bytes${dontFragment ? ' [DF]' : ''}');
    final rtts = <double>[];
    var sent = 0;
    for (var seq = 1; seq <= count && !_stop; seq++) {
      final t0 = DateTime.now();
      final r = await TecCheckNative.icmpEcho(ip, size: size, dontFragment: dontFragment, timeoutMs: 2000);
      sent++;
      switch (r.status) {
        case 'reply':
          final ms = r.rttMs ?? DateTime.now().difference(t0).inMicroseconds / 1000;
          rtts.add(ms);
          onLine('resposta de ${r.from ?? ip}: seq=$seq tempo=${ms.toStringAsFixed(1)} ms');
        case 'fragneeded':
          onLine('seq=$seq: pacote grande demais (fragmentação necessária) — MTU menor que ${size + 28}');
        case 'unreachable':
          onLine('seq=$seq: destino inalcançável${r.from != null ? ' (de ${r.from})' : ''}');
        case 'ttl':
          onLine('seq=$seq: TTL excedido em ${r.from}');
        case 'error':
          onLine('seq=$seq: erro — ${r.message}');
        default:
          onLine('seq=$seq: sem resposta (timeout)');
      }
      onProgress(PingStats(host, sent, rtts.length, List.of(rtts)));
      final wait = 500 - DateTime.now().difference(t0).inMilliseconds;
      if (seq < count && wait > 0 && !_stop) await Future.delayed(Duration(milliseconds: wait));
    }
    final st = PingStats(host, sent, rtts.length, rtts);
    onLine('--- $sent enviados, ${st.received} recebidos, ${st.lossPct.toStringAsFixed(0)}% perda ---');
    return st;
  }

  Future<void> traceroute(String host, {int maxHops = 30, required void Function(Hop) onHop}) async {
    _stop = false;
    final target = await resolve(host);
    for (var ttl = 1; ttl <= maxHops && !_stop; ttl++) {
      // até 2 tentativas por salto, como o traceroute tradicional faz com 3
      IcmpReply r = const IcmpReply('timeout');
      for (var attempt = 0; attempt < 2 && !r.isReply && r.status != 'ttl'; attempt++) {
        r = await TecCheckNative.icmpEcho(target, ttl: ttl, timeoutMs: 1500, size: 32);
        if (_stop) return;
      }
      final reached = r.isReply || (r.status == 'unreachable' && r.from == target);
      var rtt = r.rttMs;
      // No Android o ping não mede o tempo do salto intermediário: mede com um ping direto.
      if (r.from != null && rtt == null) {
        final p = await TecCheckNative.icmpEcho(r.from!, timeoutMs: 1000, size: 32);
        rtt = p.rttMs;
      }
      final name = r.from == null ? null : await _reverse(r.from!);
      onHop(Hop(ttl, r.from, name, rtt, reached));
      if (reached) return;
    }
  }

  static Future<String?> _reverse(String ip) async {
    try {
      final a = await InternetAddress(ip).reverse().timeout(const Duration(milliseconds: 1500));
      return a.host == ip ? null : a.host;
    } catch (_) {
      return null;
    }
  }

  /// Mantém a lista de RTT de um ping curta para o gráfico.
  static List<double> tail(List<double> v, [int n = 300]) => v.sublist(max(0, v.length - n));
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'speed_server.dart';

class SpeedResult {
  final double? pingMs;
  final double? jitterMs;
  final double? downMbps;
  final double? upMbps;
  final String server;
  final String clientIp;
  final String isp;
  final DateTime time;

  SpeedResult({
    this.pingMs,
    this.jitterMs,
    this.downMbps,
    this.upMbps,
    this.server = '',
    this.clientIp = '',
    this.isp = '',
    DateTime? time,
  }) : time = time ?? DateTime.now();

  bool get complete => downMbps != null && upMbps != null;

  SpeedResult copyWith({
    double? pingMs,
    double? jitterMs,
    double? downMbps,
    double? upMbps,
    String? server,
    String? clientIp,
    String? isp,
  }) =>
      SpeedResult(
        pingMs: pingMs ?? this.pingMs,
        jitterMs: jitterMs ?? this.jitterMs,
        downMbps: downMbps ?? this.downMbps,
        upMbps: upMbps ?? this.upMbps,
        server: server ?? this.server,
        clientIp: clientIp ?? this.clientIp,
        isp: isp ?? this.isp,
      );
}

typedef SpeedListener = void Function(String phase, double live, double progress, SpeedResult partial);

/// Teste de velocidade: 6 conexões paralelas, 10 s por fase, descartando 1,5 s
/// iniciais (slow start do TCP).
///
/// Servidores suportados:
///  - Cloudflare: /__down?bytes=N e /__up
///  - Ookla (servidor do provedor no speedtest.net):
///      daemon atual: /hello, /download?size=N, /upload
///      legado:       /speedtest/latency.txt, /speedtest/random4000x4000.jpg, /speedtest/upload.php
class SpeedTester {
  static const _cfBase = 'https://speed.cloudflare.com';
  final SpeedServer server;
  SpeedTester([this.server = SpeedServer.cloudflare]);

  late String _latencyUrl;
  late String Function() _downloadUrl;
  late String _uploadUrl;
  static const _parallel = 6;
  static const _phase = Duration(seconds: 10);
  static const _warmup = Duration(milliseconds: 1500);

  final _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 5)
    ..idleTimeout = const Duration(seconds: 5)
    ..maxConnectionsPerHost = 8
    ..userAgent = 'TecCheck/2.0';

  final Uint8List _payload = () {
    final rnd = Random();
    return Uint8List.fromList(List.generate(256 * 1024, (_) => rnd.nextInt(256)));
  }();
  bool _cancelled = false;

  void cancel() {
    _cancelled = true;
    _client.close(force: true);
  }

  Future<SpeedResult> run(SpeedListener on) async {
    var r = SpeedResult();
    on('Localizando servidor', 0, 0, r);
    // IP público e operadora (ASN) vêm da Cloudflare em qualquer caso.
    try {
      final m = jsonDecode(await _getText('$_cfBase/meta').timeout(const Duration(seconds: 5))) as Map<String, dynamic>;
      final srv = [m['colo'], m['city']].whereType<String>().where((s) => s.isNotEmpty).join(' · ');
      r = r.copyWith(
        server: srv.isEmpty ? 'Cloudflare' : 'Cloudflare $srv',
        clientIp: m['clientIp'] as String? ?? '',
        isp: m['asOrganization'] as String? ?? '',
      );
    } catch (_) {
      r = r.copyWith(server: 'Cloudflare');
    }
    if (!server.isCloudflare) {
      on('Conectando em ${server.sponsor}', 0, 0, r);
      await _prepareOokla();
      final city = server.city.isEmpty ? '' : ' (${server.city})';
      r = r.copyWith(server: 'Ookla · ${server.sponsor}$city · ${server.host}');
    } else {
      _latencyUrl = '$_cfBase/__down?bytes=0';
      _downloadUrl = () => '$_cfBase/__down?bytes=50000000';
      _uploadUrl = '$_cfBase/__up';
    }

    // ---- latência ----
    final samples = <double>[];
    const n = 16;
    for (var i = 0; i < n; i++) {
      _check();
      final sw = Stopwatch()..start();
      final req = await _client.getUrl(Uri.parse(_nocache(_latencyUrl)));
      final res = await req.close();
      await res.drain<void>();
      final ms = sw.elapsedMicroseconds / 1000;
      if (i > 0) samples.add(ms); // 1ª inclui TLS
      on('Latência', ms, (i + 1) / n, r);
    }
    final sorted = [...samples]..sort();
    final ping = sorted[sorted.length ~/ 2];
    var jit = 0.0;
    for (var i = 1; i < samples.length; i++) {
      jit += (samples[i] - samples[i - 1]).abs();
    }
    r = r.copyWith(pingMs: ping, jitterMs: jit / (samples.length - 1));

    final down = await _measure('Download', r, on, _downloadWorker);
    r = r.copyWith(downMbps: down);
    on('Download', down, 1, r);

    final up = await _measure('Upload', r, on, _uploadWorker);
    r = r.copyWith(upMbps: up);
    on('Concluído', up, 1, r);
    _client.close();
    return r;
  }

  void _check() {
    if (_cancelled) throw const _Cancelled();
  }

  Future<double> _measure(
    String phase,
    SpeedResult r,
    SpeedListener on,
    Future<void> Function(_Counter, DateTime) worker,
  ) async {
    final total = _Counter();
    final start = DateTime.now();
    final deadline = start.add(_phase);

    final workers = List.generate(_parallel, (_) async {
      while (!_cancelled && DateTime.now().isBefore(deadline)) {
        try {
          await worker(total, deadline).timeout(_phase + const Duration(seconds: 3));
        } catch (_) {
          if (DateTime.now().isBefore(deadline)) await Future.delayed(const Duration(milliseconds: 200));
        }
      }
    });

    var lastBytes = 0;
    var lastT = start;
    int? warmBytes;
    var warmT = start;
    while (DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(milliseconds: 250));
      _check();
      final now = DateTime.now();
      final b = total.value;
      if (warmBytes == null && now.difference(start) >= _warmup) {
        warmBytes = b;
        warmT = now;
      }
      final inst = _mbps(b - lastBytes, now.difference(lastT));
      lastBytes = b;
      lastT = now;
      on(phase, inst, (now.difference(start).inMilliseconds / _phase.inMilliseconds).clamp(0.0, 1.0), r);
    }
    final end = DateTime.now();
    final result = _mbps(total.value - (warmBytes ?? 0), end.difference(warmT));
    await Future.wait(workers).timeout(const Duration(seconds: 4), onTimeout: () => []);
    return result;
  }

  double _mbps(int bytes, Duration d) => bytes * 8 / (max(d.inMilliseconds, 1) / 1000) / 1e6;

  Future<void> _downloadWorker(_Counter total, DateTime deadline) async {
    final req = await _client.getUrl(Uri.parse(_nocache(_downloadUrl())));
    final res = await req.close();
    await for (final chunk in res) {
      total.value += chunk.length;
      if (_cancelled || DateTime.now().isAfter(deadline)) break; // cancela a assinatura e fecha
    }
  }

  Future<void> _uploadWorker(_Counter total, DateTime deadline) async {
    const size = 8 * 1024 * 1024;
    final req = await _client.postUrl(Uri.parse(_nocache(_uploadUrl)));
    req.contentLength = size;
    req.headers.contentType = ContentType('application', 'octet-stream');
    var sent = 0;
    while (sent < size) {
      final chunk = min(_payload.length, size - sent);
      req.add(chunk == _payload.length ? _payload : Uint8List.sublistView(_payload, 0, chunk));
      await req.flush();
      sent += chunk;
      total.value += chunk;
      if (_cancelled || DateTime.now().isAfter(deadline)) {
        req.abort();
        return;
      }
    }
    final res = await req.close();
    await res.drain<void>();
  }

  static int _seq = 0;
  String _nocache(String url) =>
      '$url${url.contains('?') ? '&' : '?'}nocache=${DateTime.now().microsecondsSinceEpoch}${_seq++}';

  Future<bool> _ok(String url) async {
    try {
      final req = await _client.getUrl(Uri.parse(_nocache(url))).timeout(const Duration(seconds: 5));
      final res = await req.close().timeout(const Duration(seconds: 5));
      await res.drain<void>();
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  /// Descobre qual API o servidor Ookla fala (daemon atual ou legado) e se aceita HTTPS.
  Future<void> _prepareOokla() async {
    final schemes = server.https ? ['https', 'http'] : ['http', 'https'];
    for (final sc in schemes) {
      final base = '$sc://${server.host}';
      if (await _ok('$base/hello')) {
        _latencyUrl = '$base/hello';
        _downloadUrl = () => '$base/download?size=25000000';
        _uploadUrl = '$base/upload';
        return;
      }
      if (await _ok('$base/speedtest/latency.txt')) {
        _latencyUrl = '$base/speedtest/latency.txt';
        _downloadUrl = () => '$base/speedtest/random4000x4000.jpg';
        _uploadUrl = '$base/speedtest/upload.php';
        return;
      }
      _check();
    }
    throw Exception('O servidor ${server.host} não respondeu. Confira o endereço/porta ou escolha outro servidor.');
  }

  Future<String> _getText(String url) async {
    final req = await _client.getUrl(Uri.parse(url));
    final res = await req.close();
    return res.transform(utf8.decoder).join();
  }
}

class _Counter {
  int value = 0;
}

class _Cancelled implements Exception {
  const _Cancelled();
  @override
  String toString() => 'Cancelado';
}

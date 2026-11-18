import 'package:flutter/services.dart';

/// Resposta de um único ICMP echo.
class IcmpReply {
  /// reply | ttl | unreachable | fragneeded | timeout | error
  final String status;
  final String? from;
  final double? rttMs;
  final String? message;

  const IcmpReply(this.status, {this.from, this.rttMs, this.message});

  bool get isReply => status == 'reply';

  factory IcmpReply.fromMap(Map<dynamic, dynamic>? m) {
    if (m == null) return const IcmpReply('error', message: 'sem resposta do nativo');
    return IcmpReply(
      m['status'] as String? ?? 'error',
      from: m['from'] as String?,
      rttMs: (m['rttMs'] as num?)?.toDouble(),
      message: m['message'] as String?,
    );
  }
}

class TecCheckNative {
  static const _ch = MethodChannel('teccheck_native');

  /// Android: localização + dispositivos Wi-Fi próximos. iOS: localização (para o SSID).
  static Future<bool> requestPermissions() async =>
      await _ch.invokeMethod<bool>('requestPermissions') ?? false;

  /// Só Android (no iOS retorna null).
  static Future<Map<dynamic, dynamic>?> netInfo() => _ch.invokeMethod<Map<dynamic, dynamic>>('netInfo');

  /// Só Android (no iOS retorna null).
  static Future<Map<dynamic, dynamic>?> wifiScan() => _ch.invokeMethod<Map<dynamic, dynamic>>('wifiScan');

  static Future<IcmpReply> icmpEcho(
    String host, {
    int ttl = 64,
    int timeoutMs = 2000,
    int size = 56,
    bool dontFragment = false,
  }) async {
    try {
      final m = await _ch.invokeMethod<Map<dynamic, dynamic>>('icmpEcho', {
        'host': host,
        'ttl': ttl,
        'timeoutMs': timeoutMs,
        'size': size,
        'df': dontFragment,
      });
      return IcmpReply.fromMap(m);
    } on PlatformException catch (e) {
      return IcmpReply('error', message: e.message);
    }
  }

  static Future<bool> reachable(String ip, {int timeoutMs = 400}) async {
    try {
      return await _ch.invokeMethod<bool>('reachable', {'ip': ip, 'timeoutMs': timeoutMs}) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Abre o app Speedtest (Ookla). Retorna false se não estiver instalado.
  static Future<bool> openOokla() async {
    try {
      return await _ch.invokeMethod<bool>('openOokla') ?? false;
    } catch (_) {
      return false;
    }
  }
}

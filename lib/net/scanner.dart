import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:teccheck_native/teccheck_native.dart';

import 'net_info.dart';

class Device {
  final String ip;
  final String? hostname;
  final String? mac;
  final List<int> openPorts;
  final int? rttMs;
  final bool isGateway;
  final bool isSelf;
  final String type;

  Device({
    required this.ip,
    this.hostname,
    this.mac,
    this.openPorts = const [],
    this.rttMs,
    this.isGateway = false,
    this.isSelf = false,
    this.type = 'Dispositivo',
  });

  String? get webUrl {
    if (openPorts.contains(80)) return 'http://$ip';
    if (openPorts.contains(443)) return 'https://$ip';
    if (openPorts.contains(8080)) return 'http://$ip:8080';
    if (openPorts.contains(8443)) return 'https://$ip:8443';
    return null;
  }
}

enum _Port { open, closed, filtered }

/// Varredura da LAN em Dart puro + ICMP nativo.
/// "Connection refused" (RST) também prova que o host existe.
class NetworkScanner {
  static const discoveryPorts = [80, 443, 22, 445, 8080, 62078, 554, 7547];
  static const servicePorts = [
    21, 22, 23, 53, 80, 139, 443, 445, 554, 631, 1883, 5000, 7547, //
    8000, 8008, 8009, 8080, 8291, 8443, 8728, 9100, 34567, 37777, 62078,
  ];
  static const portNames = {
    21: 'FTP', 22: 'SSH', 23: 'Telnet', 53: 'DNS', 80: 'HTTP', 139: 'NetBIOS', 443: 'HTTPS',
    445: 'SMB', 554: 'RTSP', 631: 'IPP', 1883: 'MQTT', 5000: 'UPnP/NAS', 7547: 'TR-069',
    8000: 'HTTP-alt', 8008: 'Cast', 8009: 'Cast', 8080: 'HTTP-alt', 8291: 'Winbox',
    8443: 'HTTPS-alt', 8728: 'API MikroTik', 9100: 'Impressora', 34567: 'DVR XM',
    37777: 'DVR Dahua', 62078: 'iOS sync',
  };

  bool _stop = false;
  void stop() => _stop = true;

  Future<List<Device>> scan(
    NetInfo info, {
    required void Function(int done, int total) onProgress,
    required void Function(Device) onFound,
  }) async {
    _stop = false;
    final ip = info.ip;
    if (ip == null) return [];
    final hosts = hostRange(ip, info.prefix);
    final found = <Device>[];
    var next = 0;
    var done = 0;

    Future<void> worker() async {
      while (!_stop) {
        if (next >= hosts.length) return;
        final h = hosts[next++];
        Device? d;
        try {
          d = await _probe(h, info);
        } catch (_) {}
        done++;
        onProgress(done, hosts.length);
        if (d != null) {
          found.add(d);
          onFound(d);
        }
      }
    }

    await Future.wait(List.generate(48, (_) => worker()));
    found.sort((a, b) => ipToInt(a.ip).compareTo(ipToInt(b.ip)));
    return found;
  }

  Future<Device?> _probe(String ip, NetInfo info) async {
    final isSelf = ip == info.ip;
    final isGw = ip == info.gateway;
    final sw = Stopwatch()..start();
    var alive = isSelf || await TecCheckNative.reachable(ip, timeoutMs: 450);
    final rtt = (alive && !isSelf) ? sw.elapsedMilliseconds : null;

    if (!alive) {
      for (final p in discoveryPorts) {
        if (_stop) return null;
        if (await _tcp(ip, p, 220) != _Port.filtered) {
          alive = true;
          break;
        }
      }
    }
    if (!alive) return null;

    final open = <int>[];
    if (!isSelf) {
      final states = await Future.wait(servicePorts.map((p) => _tcp(ip, p, 350)));
      for (var i = 0; i < servicePorts.length; i++) {
        if (states[i] == _Port.open) open.add(servicePorts[i]);
      }
    }

    final nb = await _netbios(ip);
    String? rdns;
    try {
      final r = await InternetAddress(ip).reverse().timeout(const Duration(milliseconds: 1500));
      if (r.host != ip) rdns = r.host;
    } catch (_) {}

    final d = Device(
      ip: ip,
      hostname: nb?.$1 ?? rdns,
      mac: nb?.$2,
      openPorts: open,
      rttMs: rtt,
      isGateway: isGw,
      isSelf: isSelf,
    );
    return Device(
      ip: d.ip,
      hostname: d.hostname,
      mac: d.mac,
      openPorts: d.openPorts,
      rttMs: d.rttMs,
      isGateway: d.isGateway,
      isSelf: d.isSelf,
      type: _guessType(d),
    );
  }

  static String _guessType(Device d) {
    final h = (d.hostname ?? '').toLowerCase();
    final p = d.openPorts;
    if (d.isSelf) return 'Este aparelho';
    if (d.isGateway) return 'Roteador / Gateway';
    if (p.contains(8291) || p.contains(8728)) return 'MikroTik';
    if (p.contains(7547)) return 'CPE / ONU (TR-069)';
    if (p.contains(62078) || h.contains('iphone') || h.contains('ipad')) return 'iPhone / iPad';
    if (p.contains(9100) || p.contains(631)) return 'Impressora';
    if (p.contains(554) || p.contains(37777) || p.contains(34567)) return 'Câmera / DVR';
    if (p.contains(8008) || p.contains(8009) || h.contains('chromecast')) return 'Chromecast / Smart TV';
    if (h.contains('tv') || h.contains('roku')) return 'Smart TV';
    if (h.contains('android') || h.contains('galaxy') || h.contains('redmi') || h.contains('moto')) {
      return 'Celular Android';
    }
    if (p.contains(445) || p.contains(139)) return 'Computador (Windows/SMB)';
    if (p.contains(22)) return 'Linux / Equip. de rede';
    if (d.webUrl != null) return 'Dispositivo com painel web';
    return 'Dispositivo';
  }

  static Future<_Port> _tcp(String ip, int port, int timeoutMs) async {
    try {
      final s = await Socket.connect(ip, port, timeout: Duration(milliseconds: timeoutMs));
      s.destroy();
      return _Port.open;
    } on SocketException catch (e) {
      final code = e.osError?.errorCode;
      // ECONNREFUSED: 111 no Linux/Android, 61 no iOS
      if (code == 111 || code == 61 || (e.osError?.message.toLowerCase().contains('refused') ?? false)) {
        return _Port.closed;
      }
      return _Port.filtered;
    } catch (_) {
      return _Port.filtered;
    }
  }

  /// NBSTAT (UDP 137): nome NetBIOS e MAC de máquinas Windows/Samba.
  static Future<(String, String?)?> _netbios(String ip) async {
    RawDatagramSocket? s;
    try {
      s = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      final q = Uint8List(50);
      q[0] = 0x13;
      q[1] = 0x37;
      q[5] = 1;
      q[12] = 0x20;
      q[13] = 0x43; // 'C'
      q[14] = 0x4B; // 'K'  -> "*"
      for (var i = 15; i < 45; i++) {
        q[i] = 0x41; // 'A'
      }
      q[47] = 0x21; // NBSTAT
      q[49] = 0x01; // IN
      s.send(q, InternetAddress(ip), 137);

      final completer = Completer<Uint8List?>();
      final sub = s.listen((ev) {
        if (ev == RawSocketEvent.read) {
          final dg = s!.receive();
          if (dg != null && !completer.isCompleted) completer.complete(dg.data);
        }
      });
      final data = await completer.future.timeout(const Duration(milliseconds: 600), onTimeout: () => null);
      await sub.cancel();
      if (data == null || data.length < 57) return null;

      final count = data[56];
      String? name;
      for (var i = 0; i < count; i++) {
        final off = 57 + i * 18;
        if (off + 18 > data.length) break;
        final nm = String.fromCharCodes(data.sublist(off, off + 15)).trim();
        final suffix = data[off + 15];
        final group = (data[off + 16] & 0x80) != 0;
        if (name == null && suffix == 0 && !group && nm.isNotEmpty) name = nm;
      }
      final macOff = 57 + count * 18;
      String? mac;
      if (macOff + 6 <= data.length) {
        mac = List.generate(6, (i) => data[macOff + i].toRadixString(16).padLeft(2, '0').toUpperCase()).join(':');
        if (mac == '00:00:00:00:00:00') mac = null;
      }
      return name == null ? null : (name, mac);
    } catch (_) {
      return null;
    } finally {
      s?.close();
    }
  }

  static int ipToInt(String ip) => ip.split('.').fold(0, (acc, s) => (acc << 8) | (int.tryParse(s) ?? 0));

  static String _intToIp(int v) => '${(v >> 24) & 255}.${(v >> 16) & 255}.${(v >> 8) & 255}.${v & 255}';

  /// Limita a varredura a no máximo um /24 em volta do IP do aparelho.
  static List<String> hostRange(String ip, int prefix) {
    final p = prefix.clamp(24, 30);
    final mask = (0xFFFFFFFF << (32 - p)) & 0xFFFFFFFF;
    final net = ipToInt(ip) & mask;
    final bcast = net | (~mask & 0xFFFFFFFF);
    return [for (var v = net + 1; v < bcast; v++) _intToIp(v)];
  }
}

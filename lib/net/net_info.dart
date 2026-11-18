import 'dart:io';

import 'package:network_info_plus/network_info_plus.dart';
import 'package:teccheck_native/teccheck_native.dart';

class WifiUtil {
  static int channel(int freq) {
    if (freq == 2484) return 14;
    if (freq >= 2412 && freq <= 2472) return (freq - 2407) ~/ 5;
    if (freq >= 5000 && freq <= 5900) return (freq - 5000) ~/ 5;
    if (freq >= 5925 && freq <= 7125) return (freq - 5950) ~/ 5;
    return 0;
  }

  static String band(int freq) => freq < 3000 ? '2.4 GHz' : (freq < 5925 ? '5 GHz' : '6 GHz');

  static String? standardName(int? code) => switch (code) {
        1 => 'Wi-Fi legado (a/b/g)',
        4 => 'Wi-Fi 4 (802.11n)',
        5 => 'Wi-Fi 5 (802.11ac)',
        6 => 'Wi-Fi 6 (802.11ax)',
        7 => '802.11ad',
        8 => 'Wi-Fi 7 (802.11be)',
        _ => null,
      };

  static String quality(int? rssi) {
    if (rssi == null) return '—';
    if (rssi >= -55) return 'Excelente';
    if (rssi >= -67) return 'Bom';
    if (rssi >= -75) return 'Regular';
    return 'Fraco';
  }
}

class NetInfo {
  final bool connected;
  final String transport;
  final String? ip;
  final int prefix;
  final String? gateway;
  final List<String> dns;
  final List<String> ipv6;
  final String? ssid;
  final String? bssid;
  final int? rssi;
  final int? linkSpeed;
  final int? txSpeed;
  final int? rxSpeed;
  final int? frequency;
  final String? wifiStandard;

  const NetInfo({
    this.connected = false,
    this.transport = '—',
    this.ip,
    this.prefix = 24,
    this.gateway,
    this.dns = const [],
    this.ipv6 = const [],
    this.ssid,
    this.bssid,
    this.rssi,
    this.linkSpeed,
    this.txSpeed,
    this.rxSpeed,
    this.frequency,
    this.wifiStandard,
  });

  int? get channel => frequency == null ? null : WifiUtil.channel(frequency!);
  String? get band => frequency == null ? null : WifiUtil.band(frequency!);
  bool get isWifi => transport == 'Wi-Fi';

  static Future<NetInfo> read() async {
    if (Platform.isAndroid) {
      final m = await TecCheckNative.netInfo();
      if (m == null || m['connected'] != true) return const NetInfo();
      return NetInfo(
        connected: true,
        transport: m['transport'] as String? ?? '—',
        ip: m['ip'] as String?,
        prefix: (m['prefix'] as int?) ?? 24,
        gateway: m['gateway'] as String?,
        dns: (m['dns'] as List?)?.cast<String>() ?? const [],
        ipv6: (m['ipv6'] as List?)?.cast<String>() ?? const [],
        ssid: m['ssid'] as String?,
        bssid: m['bssid'] as String?,
        rssi: m['rssi'] as int?,
        linkSpeed: m['linkSpeed'] as int?,
        txSpeed: m['txSpeed'] as int?,
        rxSpeed: m['rxSpeed'] as int?,
        frequency: m['frequency'] as int?,
        wifiStandard: WifiUtil.standardName(m['wifiStandard'] as int?),
      );
    }
    return _readIos();
  }

  /// iOS: SSID/BSSID exigem permissão de localização e o entitlement
  /// "Access WiFi Information". Sinal (dBm), canal e link não são expostos pela Apple.
  static Future<NetInfo> _readIos() async {
    final ni = NetworkInfo();
    String? wifiIp, mask, gw, ssid, bssid;
    try {
      wifiIp = await ni.getWifiIP();
      mask = await ni.getWifiSubmask();
      gw = await ni.getWifiGatewayIP();
      ssid = (await ni.getWifiName())?.replaceAll('"', '');
      bssid = (await ni.getWifiBSSID())?.toUpperCase();
    } catch (_) {}

    final v6 = <String>[];
    String? anyV4;
    try {
      for (final itf in await NetworkInterface.list(includeLinkLocal: false)) {
        for (final a in itf.addresses) {
          if (a.type == InternetAddressType.IPv6 && !a.isLinkLocal && itf.name.startsWith('en')) {
            v6.add(a.address);
          }
          if (a.type == InternetAddressType.IPv4 && !a.isLoopback) anyV4 ??= a.address;
        }
      }
    } catch (_) {}

    final hasWifi = wifiIp != null && wifiIp.isNotEmpty;
    final ip = hasWifi ? wifiIp : anyV4;
    if (ip == null) return const NetInfo();
    return NetInfo(
      connected: true,
      transport: hasWifi ? 'Wi-Fi' : 'Dados móveis',
      ip: ip,
      prefix: _maskToPrefix(mask),
      gateway: (gw == null || gw.isEmpty || gw == '0.0.0.0') ? null : gw,
      ipv6: v6,
      ssid: (ssid == null || ssid.isEmpty) ? null : ssid,
      bssid: bssid == '02:00:00:00:00:00' ? null : bssid,
    );
  }

  static int _maskToPrefix(String? mask) {
    if (mask == null) return 24;
    final parts = mask.split('.').map(int.tryParse).toList();
    if (parts.length != 4 || parts.contains(null)) return 24;
    var bits = 0;
    for (final p in parts) {
      var v = p!;
      while (v > 0) {
        bits += v & 1;
        v >>= 1;
      }
    }
    return bits == 0 ? 24 : bits;
  }
}

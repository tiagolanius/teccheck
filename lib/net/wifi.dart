import 'dart:io';

import 'package:teccheck_native/teccheck_native.dart';

import 'net_info.dart';

class WifiNet {
  final String ssid;
  final String bssid;
  final int rssi;
  final int freq;
  final int widthMhz;
  final String security;
  final String? standard;

  WifiNet(this.ssid, this.bssid, this.rssi, this.freq, this.widthMhz, this.security, this.standard);

  int get channel => WifiUtil.channel(freq);
  String get band => WifiUtil.band(freq);
}

class ChannelAdvice {
  final String band;
  final int best;
  final int? current;
  final String note;
  ChannelAdvice(this.band, this.best, this.current, this.note);
}

class WifiScanResult {
  final List<WifiNet> nets;
  final bool fresh;
  final bool supported;
  WifiScanResult(this.nets, this.fresh, this.supported);
}

class WifiAnalyzer {
  /// Só Android. A Apple não permite que apps listem redes Wi-Fi no iOS.
  static bool get supported => Platform.isAndroid;

  static Future<WifiScanResult> scan() async {
    if (!supported) return WifiScanResult([], false, false);
    final m = await TecCheckNative.wifiScan();
    final raw = (m?['nets'] as List?) ?? const [];
    final nets = raw.map((e) {
      final r = e as Map;
      final caps = r['caps'] as String? ?? '';
      final sec = caps.contains('SAE') || caps.contains('WPA3')
          ? 'WPA3'
          : caps.contains('RSN') || caps.contains('WPA2')
              ? 'WPA2'
              : caps.contains('WPA')
                  ? 'WPA'
                  : caps.contains('WEP')
                      ? 'WEP'
                      : 'Aberta';
      return WifiNet(
        r['ssid'] as String? ?? '(rede oculta)',
        r['bssid'] as String? ?? '',
        r['rssi'] as int? ?? -100,
        r['freq'] as int? ?? 0,
        r['width'] as int? ?? 20,
        sec,
        WifiUtil.standardName(r['standard'] as int?),
      );
    }).toList()
      ..sort((a, b) => b.rssi.compareTo(a.rssi));
    return WifiScanResult(nets, m?['fresh'] == true, true);
  }

  static const _ch24 = [1, 6, 11];
  static const _ch5 = [
    36, 40, 44, 48, 52, 56, 60, 64, 100, 104, 108, 112, 116, 120, 124, 128, 132, 136, 140, //
    149, 153, 157, 161, 165,
  ];

  /// Pontuação = soma de (rssi+100) das redes que se sobrepõem ao canal. Menor = mais limpo.
  static List<ChannelAdvice> advise(List<WifiNet> nets, String? myBssid, int? currentFreq) {
    final others = nets.where((n) => n.bssid != myBssid).toList();
    int score(List<WifiNet> l, int c, int Function(WifiNet) reach) => l
        .where((n) => (n.channel - c).abs() < reach(n))
        .fold(0, (s, n) => s + (n.rssi + 100).clamp(0, 100));

    final n24 = others.where((n) => n.band == '2.4 GHz').toList();
    final best24 = _ch24.reduce((a, b) => score(n24, a, (_) => 5) <= score(n24, b, (_) => 5) ? a : b);
    final cur24 = (currentFreq != null && currentFreq < 3000) ? WifiUtil.channel(currentFreq) : null;

    final n5 = others.where((n) => n.band == '5 GHz').toList();
    int reach5(WifiNet n) => (n.widthMhz ~/ 5).clamp(4, 64);
    final best5 = _ch5.reduce((a, b) => score(n5, a, reach5) <= score(n5, b, reach5) ? a : b);
    final cur5 = (currentFreq != null && currentFreq >= 5000 && currentFreq <= 5900)
        ? WifiUtil.channel(currentFreq)
        : null;

    return [
      ChannelAdvice('2.4 GHz', best24, cur24, '${n24.length} redes vizinhas. Use só 1, 6 ou 11 com 20 MHz.'),
      ChannelAdvice('5 GHz', best5, cur5,
          '${n5.length} redes vizinhas. Canais 52–144 são DFS (podem mudar sozinhos com radar).'),
    ];
  }
}

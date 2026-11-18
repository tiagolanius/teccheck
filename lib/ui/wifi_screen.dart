import 'package:flutter/material.dart';

import '../net/net_info.dart';
import '../net/wifi.dart';
import '../state.dart';
import 'widgets.dart';

class WifiScreen extends StatefulWidget {
  const WifiScreen({super.key});
  @override
  State<WifiScreen> createState() => _WifiScreenState();
}

class _WifiScreenState extends State<WifiScreen> {
  final s = VisitState.I;

  @override
  void initState() {
    super.initState();
    if (WifiAnalyzer.supported && s.wifiNets.isEmpty) s.scanWifi();
    if (!WifiAnalyzer.supported) s.refreshNet();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Análise Wi-Fi')),
      body: ListenableBuilder(
        listenable: s,
        builder: (context, _) {
          final n = s.net;
          final nets = s.wifiNets;
          final advice = nets.isEmpty ? <ChannelAdvice>[] : WifiAnalyzer.advise(nets, n.bssid, n.frequency);
          final n5 = nets.where((x) => x.band == '5 GHz').toList();
          return ListView(padding: const EdgeInsets.all(16), children: [
            SectionCard(title: 'Conexão Wi-Fi do aparelho', children: [
              if (!n.isWifi)
                const Text('O aparelho não está no Wi-Fi agora.', style: TextStyle(color: Tec.warn))
              else ...[
                InfoRow('SSID', n.ssid ?? '(permita a Localização)'),
                InfoRow('BSSID', n.bssid),
                if (n.rssi != null) InfoRow('Sinal', '${n.rssi} dBm · ${WifiUtil.quality(n.rssi)}', color: Tec.rssi(n.rssi)),
                if (n.frequency != null) InfoRow('Banda', '${n.band} · canal ${n.channel} · ${n.frequency} MHz'),
                if (n.linkSpeed != null) InfoRow('Link', '${n.linkSpeed} Mbps'),
                if (n.txSpeed != null) InfoRow('TX / RX', '${n.txSpeed} / ${n.rxSpeed ?? '—'} Mbps'),
                if (n.wifiStandard != null) InfoRow('Padrão', n.wifiStandard),
                if (n.rssi != null && n.rssi! < -70)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text('Sinal fraco neste ponto. Considere reposicionar o roteador ou instalar repetidor/mesh.',
                        style: TextStyle(color: Tec.warn, fontSize: 12)),
                  ),
              ],
            ]),
            const SizedBox(height: 12),
            if (!WifiAnalyzer.supported)
              const SectionCard(title: 'Limitação do iPhone', children: [
                Text(
                  'A Apple não permite que apps leiam o sinal (dBm), o canal ou as redes vizinhas. '
                  'Para análise de canais e interferência, use um aparelho Android.',
                  style: TextStyle(color: Tec.muted, fontSize: 13),
                ),
              ])
            else ...[
              BigButton(Icons.search, s.wifiRunning ? 'Varrendo…' : 'Varrer redes Wi-Fi', s.wifiRunning ? null : s.scanWifi),
              if (s.wifiMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(s.wifiMessage!, style: const TextStyle(color: Tec.warn, fontSize: 12)),
                ),
              if (advice.isNotEmpty) ...[
                const SizedBox(height: 12),
                SectionCard(title: 'Recomendação de canal', children: [
                  for (final a in advice) ...[
                    Row(children: [
                      SizedBox(width: 70, child: Text(a.band, style: const TextStyle(fontWeight: FontWeight.bold))),
                      Text(
                        '${a.current != null ? 'atual ${a.current} → ' : ''}melhor: ${a.best}',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          color: (a.current == null || a.current == a.best) ? Tec.good : Tec.warn,
                        ),
                      ),
                    ]),
                    Text(a.note, style: const TextStyle(color: Tec.muted, fontSize: 11)),
                    const SizedBox(height: 6),
                  ],
                ]),
                const SizedBox(height: 12),
                SectionCard(title: 'Ocupação 2.4 GHz', children: [
                  _ChannelChart(nets.where((x) => x.band == '2.4 GHz').toList(), List.generate(13, (i) => i + 1), n.bssid),
                ]),
                if (n5.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  SectionCard(title: 'Ocupação 5 GHz', children: [
                    _ChannelChart(n5, (n5.map((x) => x.channel).toSet().toList()..sort()), n.bssid),
                  ]),
                ],
                const SizedBox(height: 12),
                Text('${nets.length} redes detectadas', style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
              const SizedBox(height: 8),
              for (final w in nets) ...[_WifiRow(w, w.bssid == n.bssid), const SizedBox(height: 8)],
            ],
          ]);
        },
      ),
    );
  }
}

class _ChannelChart extends StatelessWidget {
  final List<WifiNet> nets;
  final List<int> channels;
  final String? mine;
  const _ChannelChart(this.nets, this.channels, this.mine);

  @override
  Widget build(BuildContext context) {
    final by = <int, List<WifiNet>>{};
    for (final w in nets) {
      by.putIfAbsent(w.channel, () => []).add(w);
    }
    return Column(children: [
      SizedBox(
        height: 110,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (final ch in channels)
            Expanded(
              child: Builder(builder: (_) {
                final l = by[ch] ?? const <WifiNet>[];
                if (l.isEmpty) return const SizedBox();
                final strongest = l.map((e) => e.rssi).reduce((a, b) => a > b ? a : b);
                final h = ((strongest + 100).clamp(0, 70) / 70) * 110;
                final color = l.any((e) => e.bssid == mine)
                    ? Tec.good
                    : l.length >= 4
                        ? Tec.bad
                        : l.length >= 2
                            ? Tec.warn
                            : Tec.cyan;
                return Container(
                  height: h,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.85),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                  ),
                );
              }),
            ),
        ]),
      ),
      const SizedBox(height: 4),
      Row(children: [
        for (final ch in channels)
          Expanded(
            child: Text('$ch\n${by[ch]?.length ?? 0}',
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 9, color: Tec.muted, height: 1.1)),
          ),
      ]),
      const SizedBox(height: 4),
      const Text('canal / nº de redes · altura = sinal mais forte', style: TextStyle(fontSize: 10, color: Tec.muted)),
    ]);
  }
}

class _WifiRow extends StatelessWidget {
  final WifiNet w;
  final bool mine;
  const _WifiRow(this.w, this.mine);

  @override
  Widget build(BuildContext context) {
    final open = w.security == 'Aberta' || w.security == 'WEP';
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Icon(w.security == 'Aberta' ? Icons.lock_open : Icons.lock, color: open ? Tec.bad : Tec.muted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${w.ssid}${mine ? '  (conectado)' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.bold, color: mine ? Tec.good : Tec.text)),
              Text(
                '${w.band} · ch ${w.channel} · ${w.widthMhz} MHz · ${w.security}${w.standard != null ? ' · ${w.standard}' : ''}',
                style: const TextStyle(color: Tec.muted, fontSize: 11),
              ),
              Text(w.bssid, style: const TextStyle(fontFamily: 'monospace', color: Tec.muted, fontSize: 10)),
            ]),
          ),
          Text('${w.rssi}', style: TextStyle(color: Tec.rssi(w.rssi), fontWeight: FontWeight.bold, fontSize: 18)),
          const Text(' dBm', style: TextStyle(color: Tec.muted, fontSize: 10)),
        ]),
      ),
    );
  }
}

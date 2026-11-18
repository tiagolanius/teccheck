import 'package:flutter/material.dart';

import '../main.dart';
import '../net/scanner.dart';
import '../state.dart';
import 'web_screen.dart';
import 'widgets.dart';

class ScanScreen extends StatelessWidget {
  const ScanScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = VisitState.I;
    return Scaffold(
      appBar: AppBar(title: const Text('Dispositivos na rede')),
      body: ListenableBuilder(
        listenable: s,
        builder: (context, _) {
          final n = s.net;
          final range = n.ip == null
              ? null
              : '${n.ip!.substring(0, n.ip!.lastIndexOf('.'))}.0/${n.prefix.clamp(24, 30)}'
                  '${n.prefix < 24 ? ' (limitado a /24)' : ''}';
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SectionCard(title: 'Varredura da rede local', children: [
                InfoRow('Faixa', range),
                InfoRow('Encontrados', '${s.devices.length}'),
                const SizedBox(height: 8),
                if (s.scanRunning) ...[
                  LinearProgressIndicator(value: s.scanTotal == 0 ? null : s.scanDone / s.scanTotal),
                  const SizedBox(height: 4),
                  Text('${s.scanDone}/${s.scanTotal} endereços verificados',
                      style: const TextStyle(color: Tec.muted, fontSize: 12)),
                  const SizedBox(height: 8),
                  BigButton(Icons.stop, 'Parar', s.stopScan, outlined: true),
                ] else
                  BigButton(Icons.search, s.scanFinished ? 'Varrer novamente' : 'Iniciar varredura', s.startScan),
                if (s.scanFinished && n.ip == null)
                  const Text('Sem IPv4 na rede atual.', style: TextStyle(color: Tec.bad)),
                const SizedBox(height: 8),
                const Text(
                  'O sistema não libera o MAC dos vizinhos; ele aparece só quando o aparelho responde NetBIOS. '
                  'No iPhone, permita "Rede local" quando for solicitado.',
                  style: TextStyle(color: Tec.muted, fontSize: 11),
                ),
              ]),
              const SizedBox(height: 10),
              for (final d in s.devices) ...[_DeviceCard(d), const SizedBox(height: 10)],
            ],
          );
        },
      ),
    );
  }
}

IconData _icon(Device d) {
  final t = d.type;
  if (d.isGateway || t.contains('MikroTik') || t.contains('ONU') || t.contains('rede')) return Icons.router;
  if (d.isSelf || t.contains('iPhone') || t.contains('Celular')) return Icons.smartphone;
  if (t.contains('Impressora')) return Icons.print;
  if (t.contains('Câmera')) return Icons.videocam;
  if (t.contains('TV') || t.contains('Chromecast')) return Icons.tv;
  if (t.contains('Computador')) return Icons.computer;
  return Icons.devices_other;
}

class _DeviceCard extends StatelessWidget {
  final Device d;
  const _DeviceCard(this.d);

  @override
  Widget build(BuildContext context) {
    final url = d.isSelf ? null : d.webUrl;
    return Card(
      color: d.isGateway ? Tec.cardHi : Tec.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: url == null ? null : () => go(context, WebScreen(url, title: d.ip)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(_icon(d), color: d.isGateway ? Tec.good : Tec.cyan, size: 30),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(d.ip, style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold)),
                  const Spacer(),
                  if (d.rttMs != null) Text('${d.rttMs} ms', style: const TextStyle(color: Tec.muted, fontSize: 12)),
                ]),
                Text(d.type, style: const TextStyle(color: Tec.cyan, fontSize: 13)),
                if (d.hostname != null) Text(d.hostname!, style: const TextStyle(fontSize: 13)),
                if (d.mac != null)
                  Text(d.mac!, style: const TextStyle(fontFamily: 'monospace', color: Tec.muted, fontSize: 12)),
                if (d.openPorts.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    for (final p in d.openPorts)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: Tec.bg, borderRadius: BorderRadius.circular(6)),
                        child: Text('$p ${NetworkScanner.portNames[p] ?? ''}'.trim(), style: const TextStyle(fontSize: 11)),
                      ),
                  ]),
                ],
                if (url != null)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text('Toque para abrir o painel web', style: TextStyle(color: Tec.good, fontSize: 11)),
                  ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

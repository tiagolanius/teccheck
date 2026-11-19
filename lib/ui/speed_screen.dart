import 'package:flutter/material.dart';
import 'package:teccheck_native/teccheck_native.dart';

import '../main.dart';
import '../state.dart';
import 'server_picker.dart';
import 'web_screen.dart';
import 'widgets.dart';

class SpeedScreen extends StatelessWidget {
  const SpeedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = VisitState.I;
    return Scaffold(
      appBar: AppBar(title: const Text('Teste de velocidade')),
      body: ListenableBuilder(
        listenable: s,
        builder: (context, _) {
          final r = s.speed;
          final plan = s.planoMbps;
          final latency = s.speedPhase == 'Latência';
          final live = s.speedRunning ? s.speedLive : (r?.downMbps ?? 0);
          final scale = latency ? 200.0 : [100.0, 300.0, 500.0, 1000.0, 2500.0].firstWhere((m) => m >= live, orElse: () => 10000.0);
          final link = s.net.linkSpeed;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _ServerCard(s),
              const SizedBox(height: 4),
              Center(
                child: Gauge(
                  value: live,
                  max: scale,
                  label: s.speedRunning ? s.speedPhase : ((r?.complete ?? false) ? 'Download' : 'Pronto'),
                  unit: latency ? 'ms' : 'Mbps',
                ),
              ),
              if (s.speedRunning) LinearProgressIndicator(value: s.speedProgress),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: StatTile('Ping', fmt(r?.pingMs, 0), 'ms', Tec.latency(r?.pingMs))),
                const SizedBox(width: 8),
                Expanded(child: StatTile('Jitter', fmt(r?.jitterMs), 'ms', Tec.cyan)),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: StatTile('Download', fmt(r?.downMbps), 'Mbps', Tec.cyan)),
                const SizedBox(width: 8),
                Expanded(child: StatTile('Upload', fmt(r?.upMbps), 'Mbps', Tec.violet)),
              ]),
              if (plan != null && r?.downMbps != null && !s.speedRunning) ...[
                const SizedBox(height: 10),
                Builder(builder: (_) {
                  final pct = r!.downMbps! / plan * 100;
                  final c = pct >= 80 ? Tec.good : (pct >= 60 ? Tec.warn : Tec.bad);
                  return Text('Entregou ${fmt(pct, 0)}% do plano de ${fmt(plan, 0)} Mbps',
                      textAlign: TextAlign.center, style: TextStyle(color: c, fontSize: 14));
                }),
              ],
              if (s.speedError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(s.speedError!, style: const TextStyle(color: Tec.bad)),
                ),
              const SizedBox(height: 14),
              s.speedRunning
                  ? BigButton(Icons.stop, 'Cancelar', s.cancelSpeed, outlined: true)
                  : BigButton(Icons.play_arrow, r == null ? 'Iniciar teste' : 'Testar novamente', s.startSpeed),
              const SizedBox(height: 10),
              BigButton(Icons.open_in_new, 'Abrir Speedtest (Ookla)', () async {
                final ok = await TecCheckNative.openOokla();
                if (!ok && context.mounted) go(context, const WebScreen('https://www.speedtest.net', title: 'Speedtest'));
              }, outlined: true),
              if (r != null) ...[
                const SizedBox(height: 12),
                SectionCard(title: 'Servidor e operadora', children: [
                  InfoRow('Servidor', r.server),
                  InfoRow('Operadora', r.isp),
                  InfoRow('IP público', r.clientIp),
                  InfoRow('Conexão', '${s.net.transport}${link != null ? ' · link $link Mbps' : ''}'),
                  if (s.net.isWifi && link != null && plan != null && link < plan)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'O link Wi-Fi do aparelho ($link Mbps) é menor que o plano. '
                        'Teste no 5 GHz, mais perto do roteador ou via cabo.',
                        style: const TextStyle(color: Tec.warn, fontSize: 12),
                      ),
                    ),
                ]),
              ],
              const SizedBox(height: 12),
              SectionCard(title: 'Resultado do Speedtest Ookla (opcional)', children: [
                const Text('Anote aqui para sair no relatório.', style: TextStyle(color: Tec.muted, fontSize: 12)),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: NumField('↓ Mbps', controller: s.ooklaDown)),
                  const SizedBox(width: 8),
                  Expanded(child: NumField('↑ Mbps', controller: s.ooklaUp)),
                  const SizedBox(width: 8),
                  Expanded(child: NumField('Ping ms', controller: s.ooklaPing)),
                ]),
                const SizedBox(height: 10),
                NumField('Plano contratado (Mbps)', controller: s.plano, onChanged: (_) => s.touch()),
              ]),
              const SizedBox(height: 10),
              const Text('6 conexões paralelas, 10 s por fase. IP público e operadora identificados pela Cloudflare.',
                  style: TextStyle(color: Tec.muted, fontSize: 11)),
            ],
          );
        },
      ),
    );
  }
}

class _ServerCard extends StatelessWidget {
  final VisitState s;
  const _ServerCard(this.s);

  @override
  Widget build(BuildContext context) {
    final sv = s.server;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: s.speedRunning ? null : () => go(context, const ServerPickerScreen()),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(children: [
            Icon(sv.isCloudflare ? Icons.cloud : Icons.dns, color: Tec.cyan),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Servidor de teste', style: TextStyle(color: Tec.muted, fontSize: 11)),
                Text(sv.title, style: const TextStyle(fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(sv.subtitle, style: const TextStyle(color: Tec.muted, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
            ),
            Text('Trocar', style: TextStyle(color: s.speedRunning ? Tec.muted : Tec.cyan, fontWeight: FontWeight.bold)),
          ]),
        ),
      ),
    );
  }
}

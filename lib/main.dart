import 'package:flutter/material.dart';
import 'package:teccheck_native/teccheck_native.dart';

import 'net/net_info.dart';
import 'state.dart';
import 'ui/ping_screen.dart';
import 'ui/report_screen.dart';
import 'ui/scan_screen.dart';
import 'ui/speed_screen.dart';
import 'ui/web_screen.dart';
import 'ui/widgets.dart';
import 'ui/wifi_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TecCheckApp());
}

class TecCheckApp extends StatelessWidget {
  const TecCheckApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TecCheck',
      debugShowCheckedModeBanner: false,
      theme: Tec.theme(),
      home: const HomeScreen(),
    );
  }
}

void go(BuildContext context, Widget screen) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final s = VisitState.I;

  @override
  void initState() {
    super.initState();
    TecCheckNative.requestPermissions().catchError((_) => false).whenComplete(s.refreshNet);
    s.loadServer();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('TecCheck', style: TextStyle(fontWeight: FontWeight.bold))),
      body: ListenableBuilder(
        listenable: s,
        builder: (context, _) {
          final sp = (s.speed?.complete ?? false) ? s.speed : null;
          final tools = [
            _Tool('Velocidade', Icons.speed, sp != null,
                sp != null ? '↓ ${fmt(sp.downMbps, 0)}  ↑ ${fmt(sp.upMbps, 0)} Mbps' : 'Download, upload, latência',
                const SpeedScreen()),
            _Tool('Dispositivos', Icons.devices, s.scanFinished && s.devices.isNotEmpty,
                s.devices.isNotEmpty ? '${s.devices.length} encontrados' : 'Varredura da rede local', const ScanScreen()),
            _Tool('Ping / Trace', Icons.network_ping, s.pingStats != null || s.hops.isNotEmpty,
                s.pingStats != null
                    ? '${fmt(s.pingStats!.avg, 0)} ms · ${fmt(s.pingStats!.lossPct, 0)}% perda'
                    : 'Latência e rota',
                const PingScreen()),
            _Tool('Wi-Fi', Icons.wifi, s.wifiNets.isNotEmpty,
                s.wifiNets.isNotEmpty ? '${s.wifiNets.length} redes · canais' : 'Sinal e canais', const WifiScreen()),
          ];
          return RefreshIndicator(
            onRefresh: s.refreshNet,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _ConnectionCard(s.net, s.refreshNet),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => go(context, const GatewayScreen()),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(60),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.router),
                    const SizedBox(width: 12),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Acessar roteador', style: TextStyle(fontWeight: FontWeight.bold)),
                      Text(s.net.gateway != null ? 'http://${s.net.gateway}' : 'gateway não detectado',
                          style: const TextStyle(fontSize: 12)),
                    ]),
                  ]),
                ),
                const SizedBox(height: 16),
                const Text('Checklist da visita', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.45,
                  children: [for (final t in tools) _ToolCard(t)],
                ),
                const SizedBox(height: 12),
                BigButton(Icons.picture_as_pdf, 'Gerar relatório da visita (PDF)',
                    () => go(context, const ReportScreen()),
                    color: Tec.violet),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Tool {
  final String title;
  final IconData icon;
  final bool done;
  final String summary;
  final Widget screen;
  _Tool(this.title, this.icon, this.done, this.summary, this.screen);
}

class _ToolCard extends StatelessWidget {
  final _Tool t;
  const _ToolCard(this.t);

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => go(context, t.screen),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(t.icon, color: Tec.cyan, size: 28),
              const Spacer(),
              if (t.done) const Icon(Icons.check_circle, color: Tec.good, size: 20),
            ]),
            const Spacer(),
            Text(t.title, style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(t.summary, style: const TextStyle(color: Tec.muted, fontSize: 12), maxLines: 2),
          ]),
        ),
      ),
    );
  }
}

class _ConnectionCard extends StatelessWidget {
  final NetInfo n;
  final Future<void> Function() onRefresh;
  const _ConnectionCard(this.n, this.onRefresh);

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Conexão atual',
      trailing: IconButton(onPressed: onRefresh, icon: const Icon(Icons.refresh, color: Tec.cyan)),
      children: !n.connected
          ? [const Text('Sem conexão de rede.', style: TextStyle(color: Tec.bad))]
          : [
              InfoRow('Tipo', n.transport),
              if (n.isWifi) ...[
                InfoRow('SSID', n.ssid ?? '(permita a Localização)'),
                if (n.rssi != null) InfoRow('Sinal', '${n.rssi} dBm · ${WifiUtil.quality(n.rssi)}', color: Tec.rssi(n.rssi)),
                if (n.frequency != null) InfoRow('Banda/canal', '${n.band} · ch ${n.channel}'),
                if (n.linkSpeed != null)
                  InfoRow('Link', '${n.linkSpeed} Mbps${n.wifiStandard != null ? ' · ${n.wifiStandard}' : ''}'),
              ],
              InfoRow('IP', n.ip != null ? '${n.ip}/${n.prefix}' : null),
              InfoRow('Gateway', n.gateway),
              if (n.dns.isNotEmpty) InfoRow('DNS', n.dns.join(', ')),
              if (n.ipv6.isNotEmpty) InfoRow('IPv6', n.ipv6.first, color: Tec.good),
              if (n.transport == 'Dados móveis')
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text('Atenção: conecte no Wi-Fi ou cabo do cliente para testar a rede dele.',
                      style: TextStyle(color: Tec.warn, fontSize: 12)),
                ),
            ],
    );
  }
}

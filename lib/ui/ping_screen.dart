import 'package:flutter/material.dart';

import '../net/icmp.dart';
import '../state.dart';
import 'widgets.dart';

class PingScreen extends StatefulWidget {
  const PingScreen({super.key});
  @override
  State<PingScreen> createState() => _PingScreenState();
}

class _PingScreenState extends State<PingScreen> {
  final s = VisitState.I;
  late final host = TextEditingController(text: s.net.gateway ?? '8.8.8.8');
  final count = TextEditingController(text: '20');
  final size = TextEditingController(text: '56');
  bool df = false;

  @override
  Widget build(BuildContext context) {
    final presets = <(String, String)>[
      if (s.net.gateway != null) ('Gateway', s.net.gateway!),
      ('Google DNS', '8.8.8.8'),
      ('Cloudflare', '1.1.1.1'),
      ('google.com', 'google.com'),
      ('Valve (CS2)', 'valve.net'),
      ('Riot (LoL)', 'riotgames.com'),
    ];
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Ping e Traceroute'),
          bottom: const TabBar(tabs: [Tab(text: 'Ping'), Tab(text: 'Traceroute')]),
        ),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(children: [
              TextField(
                controller: host,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'Destino (IP ou domínio)'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 42,
                child: ListView(scrollDirection: Axis.horizontal, children: [
                  for (final (label, value) in presets)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        label: Text(label),
                        selected: host.text == value,
                        onSelected: (_) => setState(() => host.text = value),
                      ),
                    ),
                ]),
              ),
            ]),
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: s,
              builder: (context, _) => TabBarView(children: [_pingTab(), _traceTab()]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _pingTab() {
    final st = s.pingStats;
    final rtts = st?.rtts ?? const <double>[];
    return ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [
        Expanded(child: NumField('Pacotes', controller: count)),
        const SizedBox(width: 8),
        Expanded(child: NumField('Tamanho (bytes)', controller: size)),
      ]),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: df,
        onChanged: (v) => setState(() => df = v),
        title: const Text('Não fragmentar (teste de MTU)'),
        subtitle: const Text('Ex.: 1472 bytes + DF = MTU 1500. Se falhar, reduza até passar.',
            style: TextStyle(fontSize: 11, color: Tec.muted)),
      ),
      s.pingRunning
          ? BigButton(Icons.stop, 'Parar', s.stopPing, outlined: true)
          : BigButton(Icons.play_arrow, 'Iniciar ping', () {
              FocusScope.of(context).unfocus();
              s.startPing(
                host.text,
                (int.tryParse(count.text) ?? 20).clamp(1, 1000),
                (int.tryParse(size.text) ?? 56).clamp(8, 65000),
                df,
              );
            }),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: StatTile('Média', fmt(st?.avg), 'ms', Tec.latency(st?.avg))),
        const SizedBox(width: 8),
        Expanded(child: StatTile('Mín/Máx', st?.min == null ? '—' : '${fmt(st!.min, 0)}/${fmt(st.max, 0)}', 'ms', Tec.cyan)),
        const SizedBox(width: 8),
        Expanded(child: StatTile('Perda', st == null ? '—' : fmt(st.lossPct, 0), '%', Tec.loss(st?.lossPct))),
      ]),
      if (st != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            '${st.jitter != null ? 'Jitter: ${fmt(st.jitter)} ms · ' : ''}${st.received}/${st.sent} respostas',
            style: const TextStyle(color: Tec.muted, fontSize: 12),
          ),
        ),
      if (rtts.length >= 2) ...[
        const SizedBox(height: 10),
        SectionCard(title: 'Latência por pacote', children: [Sparkline(IcmpTools.tail(rtts))]),
      ],
      if (s.pingLines.isNotEmpty) ...[
        const SizedBox(height: 10),
        SectionCard(title: 'Saída', children: [
          SelectableText(
            s.pingLines.skip(s.pingLines.length > 40 ? s.pingLines.length - 40 : 0).join('\n'),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11, height: 1.3),
          ),
        ]),
      ],
    ]);
  }

  Widget _traceTab() {
    return ListView(padding: const EdgeInsets.all(16), children: [
      s.traceRunning
          ? BigButton(Icons.stop, 'Parar', s.stopTrace, outlined: true)
          : BigButton(Icons.play_arrow, 'Iniciar traceroute', () {
              FocusScope.of(context).unfocus();
              s.startTrace(host.text);
            }),
      if (s.traceError != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(s.traceError!, style: const TextStyle(color: Tec.bad)),
        ),
      if (s.hops.isNotEmpty || s.traceRunning) ...[
        const SizedBox(height: 12),
        SectionCard(title: 'Rota até ${s.traceTarget}', children: [
          for (final h in s.hops)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                  width: 28,
                  child: Text('${h.ttl}', style: const TextStyle(fontFamily: 'monospace', color: Tec.muted)),
                ),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      h.ip ?? '* * *',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        fontWeight: h.reached ? FontWeight.bold : FontWeight.normal,
                        color: h.reached ? Tec.good : (h.ip == null ? Tec.muted : Tec.text),
                      ),
                    ),
                    if (h.host != null)
                      Text(h.host!, style: const TextStyle(color: Tec.muted, fontSize: 11), maxLines: 1),
                  ]),
                ),
                Text(h.rttMs == null ? '*' : '${fmt(h.rttMs)} ms',
                    style: TextStyle(fontFamily: 'monospace', fontSize: 13, color: Tec.latency(h.rttMs))),
              ]),
            ),
          if (s.traceRunning)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('Rastreando…', style: TextStyle(color: Tec.cyan, fontSize: 12)),
            )
          else if (s.hops.isNotEmpty && !s.hops.last.reached)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('Destino não respondeu dentro de 30 saltos.', style: TextStyle(color: Tec.warn, fontSize: 12)),
            ),
        ]),
      ],
    ]);
  }
}

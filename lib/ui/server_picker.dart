import 'dart:async';

import 'package:flutter/material.dart';

import '../net/speed_server.dart';
import '../state.dart';
import 'widgets.dart';

/// Escolha do servidor de teste: Cloudflare, servidores Ookla (busca no speedtest.net)
/// ou um servidor digitado à mão (host:porta). A escolha fica salva como padrão.
class ServerPickerScreen extends StatefulWidget {
  const ServerPickerScreen({super.key});
  @override
  State<ServerPickerScreen> createState() => _ServerPickerScreenState();
}

class _ServerPickerScreenState extends State<ServerPickerScreen> {
  final s = VisitState.I;
  final search = TextEditingController();
  List<SpeedServer> results = [];
  List<SpeedServer> recent = [];
  bool loading = false;
  String? error;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    ServerStore.loadRecent().then((r) {
      if (mounted) setState(() => recent = r);
    });
    _search('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _search(String q) async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final r = await OoklaDirectory.search(q);
      if (!mounted || q != search.text) return;
      setState(() => results = r);
    } catch (e) {
      if (mounted) setState(() => error = 'Não foi possível buscar no speedtest.net: $e');
    }
    if (mounted) setState(() => loading = false);
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () => _search(q));
  }

  Future<void> _pick(SpeedServer sv) async {
    await s.selectServer(sv);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _manual() async {
    final host = TextEditingController();
    final name = TextEditingController();
    final sv = await showDialog<SpeedServer>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Servidor Ookla manual'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: host,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Endereço',
              hintText: 'speedtest.provedor.com.br:8080',
            ),
          ),
          const SizedBox(height: 10),
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Nome (opcional)')),
          const SizedBox(height: 8),
          const Text('Sem porta, usa 8080 (padrão do servidor Ookla).', style: TextStyle(color: Tec.muted, fontSize: 11)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(
              ctx,
              SpeedServer.manual(host.text, sponsor: name.text.trim().isEmpty ? 'Servidor manual' : name.text.trim()),
            ),
            child: const Text('Usar'),
          ),
        ],
      ),
    );
    if (sv != null) await _pick(sv);
  }

  Widget _tile(SpeedServer sv) {
    final selected = sv == s.server;
    return Card(
      color: selected ? Tec.cardHi : Tec.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: selected ? const BorderSide(color: Tec.cyan) : BorderSide.none,
      ),
      child: ListTile(
        onTap: () => _pick(sv),
        leading: Icon(sv.isCloudflare ? Icons.cloud : Icons.dns, color: selected ? Tec.cyan : Tec.muted),
        title: Text(sv.title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(sv.subtitle, style: const TextStyle(fontSize: 12, color: Tec.muted)),
        trailing: selected ? const Icon(Icons.check_circle, color: Tec.good) : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Servidor de teste'),
        actions: [IconButton(tooltip: 'Digitar servidor', onPressed: _manual, icon: const Icon(Icons.add))],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(
          controller: search,
          onChanged: _onChanged,
          textInputAction: TextInputAction.search,
          onSubmitted: _search,
          decoration: InputDecoration(
            labelText: 'Buscar provedor ou cidade (speedtest.net)',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: loading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : null,
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _manual,
          icon: const Icon(Icons.edit),
          label: const Text('Digitar endereço do servidor (host:porta)'),
        ),
        const SizedBox(height: 14),
        _tile(SpeedServer.cloudflare),
        if (recent.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text('Usados recentemente', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          for (final r in recent) _tile(r),
        ],
        const SizedBox(height: 12),
        Text(search.text.isEmpty ? 'Servidores Ookla mais próximos' : 'Resultados da busca',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        if (error != null) Text(error!, style: const TextStyle(color: Tec.bad, fontSize: 12)),
        if (!loading && error == null && results.isEmpty)
          const Text('Nenhum servidor encontrado. Tente outro nome ou digite o endereço.',
              style: TextStyle(color: Tec.muted, fontSize: 12)),
        for (final r in results) _tile(r),
      ]),
    );
  }
}

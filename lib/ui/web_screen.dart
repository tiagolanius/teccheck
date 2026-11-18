import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../state.dart';
import 'widgets.dart';

/// Botão "Acessar roteador": gateway detectado + atalhos de IPs comuns de ONU/roteador.
class GatewayScreen extends StatefulWidget {
  const GatewayScreen({super.key});
  @override
  State<GatewayScreen> createState() => _GatewayScreenState();
}

class _GatewayScreenState extends State<GatewayScreen> {
  final s = VisitState.I;
  late final address = TextEditingController(text: 'http://${s.net.gateway ?? '192.168.1.1'}');
  late String url = address.text;
  final _key = GlobalKey<_BrowserState>();

  void _go(String a) {
    final u = a.startsWith('http://') || a.startsWith('https://') ? a : 'http://$a';
    setState(() {
      address.text = u;
      url = u;
    });
    _key.currentState?.load(u);
  }

  @override
  Widget build(BuildContext context) {
    final gw = s.net.gateway;
    final presets = <(String, String)>[
      if (gw != null) ('Gateway $gw', gw),
      ('192.168.1.1', '192.168.1.1'),
      ('192.168.0.1', '192.168.0.1'),
      ('ONU 192.168.100.1', '192.168.100.1'),
      ('10.0.0.1', '10.0.0.1'),
      ('MikroTik 192.168.88.1', '192.168.88.1'),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Acesso ao roteador'),
        actions: [
          IconButton(
            tooltip: 'Abrir no navegador',
            icon: const Icon(Icons.open_in_browser),
            onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
          ),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: address,
                keyboardType: TextInputType.url,
                autocorrect: false,
                textInputAction: TextInputAction.go,
                onSubmitted: _go,
              ),
            ),
            IconButton(onPressed: () => _go(address.text), icon: const Icon(Icons.arrow_forward, color: Tec.cyan)),
          ]),
        ),
        SizedBox(
          height: 48,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            scrollDirection: Axis.horizontal,
            children: [
              for (final (label, ip) in presets)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(label: Text(label), selected: url == 'http://$ip', onSelected: (_) => _go(ip)),
                ),
            ],
          ),
        ),
        Expanded(child: _Browser(url, key: _key)),
      ]),
    );
  }
}

class WebScreen extends StatelessWidget {
  final String url;
  final String title;
  const WebScreen(this.url, {super.key, this.title = 'Navegador'});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_browser),
            onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
          ),
        ],
      ),
      body: _Browser(url),
    );
  }
}

class _Browser extends StatefulWidget {
  final String initialUrl;
  const _Browser(this.initialUrl, {super.key});
  @override
  State<_Browser> createState() => _BrowserState();
}

class _BrowserState extends State<_Browser> {
  late final WebViewController c;
  int progress = 0;
  String? error;

  @override
  void initState() {
    super.initState();
    c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) {
          if (mounted) setState(() => progress = p);
        },
        onPageStarted: (_) {
          if (mounted) setState(() => error = null);
        },
        onWebResourceError: (e) {
          if ((e.isForMainFrame ?? true) && mounted) {
            setState(() => error = 'Não foi possível abrir: ${e.description}');
          }
        },
        onHttpAuthRequest: _auth,
      ));
    load(widget.initialUrl);
  }

  void load(String u) {
    if (u.isEmpty) return;
    c.loadRequest(Uri.parse(u));
  }

  Future<void> _auth(HttpAuthRequest req) async {
    final user = TextEditingController(text: 'admin');
    final pass = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Login do equipamento'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(req.host, style: const TextStyle(color: Tec.muted, fontSize: 12)),
          const SizedBox(height: 8),
          TextField(controller: user, decoration: const InputDecoration(labelText: 'Usuário')),
          const SizedBox(height: 8),
          TextField(controller: pass, obscureText: true, decoration: const InputDecoration(labelText: 'Senha')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Entrar')),
        ],
      ),
    );
    if (ok == true) {
      req.onProceed(WebViewCredential(user: user.text, password: pass.text));
    } else {
      req.onCancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      if (progress > 0 && progress < 100) LinearProgressIndicator(value: progress / 100),
      if (error != null)
        Container(
          color: Tec.cardHi,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(children: [
            Expanded(child: Text(error!, style: const TextStyle(color: Tec.bad, fontSize: 12))),
            IconButton(onPressed: () => c.reload(), icon: const Icon(Icons.refresh)),
          ]),
        ),
      Expanded(child: WebViewWidget(controller: c)),
      Container(
        color: Tec.bg,
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 18),
            onPressed: () async {
              if (await c.canGoBack()) c.goBack();
            },
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: () => c.reload()),
          IconButton(
            icon: const Icon(Icons.arrow_forward_ios, size: 18),
            onPressed: () async {
              if (await c.canGoForward()) c.goForward();
            },
          ),
        ]),
      ),
    ]);
  }
}

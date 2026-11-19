import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

enum ServerKind { cloudflare, ookla }

/// Servidor de teste de velocidade: Cloudflare (padrão) ou um servidor Ookla
/// (normalmente o do próprio provedor, que aparece na lista do speedtest.net).
class SpeedServer {
  final ServerKind kind;
  final String sponsor; // provedor dono do servidor
  final String city;
  final String host; // host:porta
  final bool https;
  final String? id;
  final double? distanceKm;

  const SpeedServer({
    required this.kind,
    required this.sponsor,
    required this.city,
    required this.host,
    this.https = false,
    this.id,
    this.distanceKm,
  });

  static const cloudflare = SpeedServer(
    kind: ServerKind.cloudflare,
    sponsor: 'Cloudflare',
    city: 'mais próximo',
    host: 'speed.cloudflare.com',
    https: true,
  );

  bool get isCloudflare => kind == ServerKind.cloudflare;
  String get title => isCloudflare ? 'Cloudflare (automático)' : sponsor;
  String get subtitle => isCloudflare
      ? 'speed.cloudflare.com'
      : [if (city.isNotEmpty) city, host, if (distanceKm != null) '${distanceKm!.toStringAsFixed(0)} km'].join(' · ');

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'sponsor': sponsor,
        'city': city,
        'host': host,
        'https': https,
        'id': id,
      };

  factory SpeedServer.fromJson(Map<String, dynamic> j) => SpeedServer(
        kind: j['kind'] == 'ookla' ? ServerKind.ookla : ServerKind.cloudflare,
        sponsor: j['sponsor'] as String? ?? '',
        city: j['city'] as String? ?? '',
        host: j['host'] as String? ?? '',
        https: j['https'] as bool? ?? false,
        id: j['id'] as String?,
      );

  /// Servidor digitado à mão: "speedtest.provedor.com.br:8080" ou URL completa.
  static SpeedServer? manual(String input, {String sponsor = 'Servidor manual'}) {
    var s = input.trim();
    if (s.isEmpty) return null;
    var https = false;
    if (s.startsWith('https://')) {
      https = true;
      s = s.substring(8);
    } else if (s.startsWith('http://')) {
      s = s.substring(7);
    }
    s = s.split('/').first;
    if (!s.contains(':')) s = '$s:8080';
    return SpeedServer(kind: ServerKind.ookla, sponsor: sponsor, city: '', host: s, https: https);
  }

  @override
  bool operator ==(Object other) => other is SpeedServer && other.kind == kind && other.host == host;

  @override
  int get hashCode => Object.hash(kind, host);
}

class ServerStore {
  static const _key = 'speed_server';
  static const _recentKey = 'speed_server_recent';

  static Future<SpeedServer> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_key);
      if (raw != null) return SpeedServer.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {}
    return SpeedServer.cloudflare;
  }

  static Future<void> save(SpeedServer s) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, jsonEncode(s.toJson()));
    if (!s.isCloudflare) {
      final recent = await loadRecent();
      recent.removeWhere((r) => r == s);
      recent.insert(0, s);
      await p.setString(_recentKey, jsonEncode(recent.take(8).map((e) => e.toJson()).toList()));
    }
  }

  static Future<List<SpeedServer>> loadRecent() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_recentKey);
      if (raw == null) return [];
      return (jsonDecode(raw) as List).map((e) => SpeedServer.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }
}

/// Lista pública de servidores do speedtest.net.
/// Sem busca, retorna os mais próximos do IP; com busca, filtra por provedor/cidade.
class OoklaDirectory {
  static Future<List<SpeedServer>> search(String query) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      ..userAgent = 'Mozilla/5.0 (Linux; Android) TecCheck/2.1';
    try {
      final uri = Uri.https('www.speedtest.net', '/api/js/servers', {
        'engine': 'js',
        'limit': '30',
        if (query.trim().isNotEmpty) 'search': query.trim(),
      });
      final req = await client.getUrl(uri);
      final res = await req.close().timeout(const Duration(seconds: 10));
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode != 200) throw HttpException('speedtest.net respondeu ${res.statusCode}');
      final list = jsonDecode(body) as List;
      return list.map((e) {
        final m = e as Map<String, dynamic>;
        var host = (m['host'] as String?) ?? '';
        if (host.isEmpty) {
          final u = Uri.tryParse(m['url'] as String? ?? '');
          if (u != null) host = '${u.host}:${u.hasPort ? u.port : 8080}';
        }
        final httpsOk = m['https_functional'];
        return SpeedServer(
          kind: ServerKind.ookla,
          sponsor: (m['sponsor'] as String?) ?? 'Servidor Ookla',
          city: [(m['name'] as String?) ?? '', (m['cc'] as String?) ?? ''].where((s) => s.isNotEmpty).join(' - '),
          host: host,
          https: httpsOk == true || httpsOk == 1 || httpsOk == '1',
          id: m['id']?.toString(),
          distanceKm: (m['distance'] as num?)?.toDouble(),
        );
      }).where((s) => s.host.isNotEmpty).toList();
    } finally {
      client.close(force: true);
    }
  }
}

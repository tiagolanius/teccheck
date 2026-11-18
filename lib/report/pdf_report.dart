import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../net/icmp.dart';
import '../net/net_info.dart';
import '../net/scanner.dart';
import '../net/speed_test.dart';
import '../net/wifi.dart';

class ReportData {
  final String cliente, contrato, endereco, tecnico, ooklaDown, ooklaUp, ooklaPing, observacoes;
  final double? planoMbps;
  final NetInfo net;
  final SpeedResult? speed;
  final List<Device> devices;
  final PingStats? ping;
  final String traceTarget;
  final List<Hop> hops;
  final List<WifiNet> wifi;
  final Uint8List? signaturePng;

  ReportData({
    required this.cliente,
    required this.contrato,
    required this.endereco,
    required this.tecnico,
    required this.planoMbps,
    required this.ooklaDown,
    required this.ooklaUp,
    required this.ooklaPing,
    required this.observacoes,
    required this.net,
    required this.speed,
    required this.devices,
    required this.ping,
    required this.traceTarget,
    required this.hops,
    required this.wifi,
    required this.signaturePng,
  });
}

class PdfReport {
  static final _navy = PdfColor.fromInt(0xFF0A0F1A);
  static final _accent = PdfColor.fromInt(0xFF00A0C8);
  static final _gray = PdfColor.fromInt(0xFF646E7D);
  static final _zebra = PdfColor.fromInt(0xFFF2F5F9);

  /// A fonte padrão (Helvetica) só cobre Latin-1: troca o resto para não quebrar o PDF.
  static String t(String s) => String.fromCharCodes(s.runes.map((r) {
        if (r == 0x2014 || r == 0x2013) return 0x2D; // travessão -> hífen
        if (r == 0x2026) return 0x2E; // reticências
        return r <= 0xFF ? r : 0x3F;
      }));

  static String n(double? v, [int d = 1]) => v == null ? '-' : v.toStringAsFixed(d).replaceAll('.', ',');

  static Future<Uint8List> build(ReportData d) async {
    final doc = pw.Document(title: 'Relatório de visita técnica', author: 'TecCheck');
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final date = '${two(now.day)}/${two(now.month)}/${now.year} às ${two(now.hour)}:${two(now.minute)}';

    pw.Widget section(String title) => pw.Container(
          margin: const pw.EdgeInsets.only(top: 14, bottom: 6),
          padding: const pw.EdgeInsets.only(left: 8, bottom: 3),
          decoration: pw.BoxDecoration(
            border: pw.Border(
              left: pw.BorderSide(color: _accent, width: 3),
              bottom: pw.BorderSide(color: PdfColor.fromInt(0xFFDCE1E8), width: 0.8),
            ),
          ),
          child: pw.Text(t(title), style: pw.TextStyle(fontSize: 12.5, fontWeight: pw.FontWeight.bold, color: _navy)),
        );

    pw.Widget kv(String k, String v) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
          child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.SizedBox(width: 130, child: pw.Text(t(k), style: pw.TextStyle(fontSize: 9.5, color: _gray))),
            pw.Expanded(child: pw.Text(t(v.isEmpty ? '-' : v), style: const pw.TextStyle(fontSize: 9.5))),
          ]),
        );

    pw.Widget table(List<String> headers, List<List<String>> rows, Map<int, double> flex) =>
        pw.TableHelper.fromTextArray(
          headers: headers.map(t).toList(),
          data: rows.map((r) => r.map(t).toList()).toList(),
          headerStyle: pw.TextStyle(fontSize: 8.5, color: PdfColors.white, fontWeight: pw.FontWeight.bold),
          headerDecoration: pw.BoxDecoration(color: _navy),
          cellStyle: const pw.TextStyle(fontSize: 8.5),
          cellAlignment: pw.Alignment.centerLeft,
          headerAlignment: pw.Alignment.centerLeft,
          oddRowDecoration: pw.BoxDecoration(color: _zebra),
          border: null,
          cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          columnWidths: flex.map((k, v) => MapEntry(k, pw.FlexColumnWidth(v))),
        );

    String pct(double? v) {
      final p = d.planoMbps;
      if (v == null || p == null || p <= 0) return '';
      return '  (${(v / p * 100).toStringAsFixed(0)}% do plano)';
    }

    final net = d.net;
    final body = <pw.Widget>[
      // ---- Cliente ----
      section('Cliente'),
      kv('Nome', d.cliente),
      kv('Contrato / código', d.contrato),
      kv('Endereço', d.endereco),
      kv('Plano contratado', d.planoMbps == null ? '' : '${n(d.planoMbps, 0)} Mbps'),
      kv('Técnico', d.tecnico),

      // ---- Conexão ----
      section('Conexão do aparelho de teste'),
      kv('Tipo', net.transport),
      if (net.ssid != null) kv('Rede Wi-Fi (SSID)', net.ssid!),
      kv('IP local', net.ip == null ? '' : '${net.ip}/${net.prefix}'),
      kv('Gateway', net.gateway ?? ''),
      if (net.dns.isNotEmpty) kv('DNS', net.dns.join(', ')),
      if (net.ipv6.isNotEmpty) kv('IPv6', net.ipv6.join(', ')),
      if (net.rssi != null) kv('Sinal Wi-Fi', '${net.rssi} dBm (${WifiUtil.quality(net.rssi)})'),
      if (net.frequency != null) kv('Frequência / canal', '${net.band} · canal ${net.channel} (${net.frequency} MHz)'),
      if (net.linkSpeed != null)
        kv('Velocidade de link',
            '${net.linkSpeed} Mbps${net.txSpeed != null ? ' · TX ${net.txSpeed} / RX ${net.rxSpeed ?? '-'} Mbps' : ''}'),
      if (net.wifiStandard != null) kv('Padrão', net.wifiStandard!),
    ];

    // ---- Velocidade ----
    final ookla = double.tryParse(d.ooklaDown.replaceAll(',', '.'));
    if (d.speed != null || ookla != null) {
      body.add(section('Teste de velocidade'));
      final s = d.speed;
      if (s != null) {
        body.addAll([
          kv('Servidor', s.server),
          if (s.isp.isNotEmpty) kv('Operadora (ASN)', s.isp),
          if (s.clientIp.isNotEmpty) kv('IP público', s.clientIp),
          kv('Download', '${n(s.downMbps)} Mbps${pct(s.downMbps)}'),
          kv('Upload', '${n(s.upMbps)} Mbps'),
          kv('Latência / jitter', '${n(s.pingMs, 0)} ms / ${n(s.jitterMs)} ms'),
        ]);
      }
      if (ookla != null) {
        body.add(kv('Speedtest (Ookla)',
            'Down ${d.ooklaDown} Mbps · Up ${d.ooklaUp.isEmpty ? '-' : d.ooklaUp} Mbps · Ping ${d.ooklaPing.isEmpty ? '-' : d.ooklaPing} ms${pct(ookla)}'));
      }
      if (net.isWifi) {
        body.add(pw.Text(t('Teste feito via Wi-Fi: o resultado depende do sinal e da velocidade de link do aparelho.'),
            style: pw.TextStyle(fontSize: 8.5, color: _gray, fontStyle: pw.FontStyle.italic)));
      }
    }

    // ---- Wi-Fi ----
    if (d.wifi.isNotEmpty) {
      body.add(section('Análise Wi-Fi'));
      for (final a in WifiAnalyzer.advise(d.wifi, net.bssid, net.frequency)) {
        body.add(kv('Canal ${a.band}', '${a.current != null ? 'atual: ${a.current} · ' : ''}recomendado: ${a.best}'));
      }
      body.add(kv('Redes detectadas', '${d.wifi.length}'));
      body.add(pw.SizedBox(height: 4));
      body.add(table(
        ['SSID', 'Sinal', 'Banda', 'Canal', 'Largura', 'Segurança'],
        d.wifi.take(15).map((w) => [w.ssid, '${w.rssi} dBm', w.band, '${w.channel}', '${w.widthMhz} MHz', w.security]).toList(),
        {0: 3, 1: 1.1, 2: 1.1, 3: 0.9, 4: 1.1, 5: 1.2},
      ));
    }

    // ---- Dispositivos ----
    if (d.devices.isNotEmpty) {
      body.add(section('Dispositivos na rede (${d.devices.length})'));
      body.add(table(
        ['IP', 'Nome', 'Tipo', 'Portas abertas'],
        d.devices
            .map((x) => [x.ip, x.hostname ?? '-', x.type, x.openPorts.isEmpty ? '-' : x.openPorts.join(', ')])
            .toList(),
        {0: 1.6, 1: 2.4, 2: 2.4, 3: 2.6},
      ));
    }

    // ---- Ping ----
    final p = d.ping;
    if (p != null) {
      body.add(section('Ping - ${p.target}'));
      body.add(kv('Pacotes', '${p.sent} enviados · ${p.received} recebidos · ${n(p.lossPct, 0)}% perda'));
      if (p.avg != null) {
        body.add(kv('Latência', 'mín ${n(p.min)} · méd ${n(p.avg)} · máx ${n(p.max)} · jitter ${n(p.jitter)} ms'));
      }
    }

    // ---- Traceroute ----
    if (d.hops.isNotEmpty) {
      body.add(section('Traceroute - ${d.traceTarget}'));
      body.add(table(
        ['Salto', 'IP', 'Nome', 'Latência'],
        d.hops.map((h) => ['${h.ttl}', h.ip ?? '*', h.host ?? '', h.rttMs == null ? '*' : '${n(h.rttMs)} ms']).toList(),
        {0: 0.7, 1: 1.8, 2: 4.2, 3: 1.2},
      ));
    }

    // ---- Observações ----
    if (d.observacoes.trim().isNotEmpty) {
      body.add(section('Observações do técnico'));
      body.add(pw.Text(t(d.observacoes), style: const pw.TextStyle(fontSize: 9.5)));
    }

    // ---- Assinaturas ----
    body.add(pw.SizedBox(height: 28));
    body.add(pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
      pw.Expanded(
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.SizedBox(
            height: 70,
            child: d.signaturePng == null ? pw.SizedBox() : pw.Image(pw.MemoryImage(d.signaturePng!), fit: pw.BoxFit.contain),
          ),
          pw.Divider(thickness: 0.8, color: _gray),
          pw.Text(t('Cliente: ${d.cliente}'), style: pw.TextStyle(fontSize: 9, color: _gray)),
        ]),
      ),
      pw.SizedBox(width: 30),
      pw.Expanded(
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.SizedBox(height: 70),
          pw.Divider(thickness: 0.8, color: _gray),
          pw.Text(t('Técnico: ${d.tecnico}'), style: pw.TextStyle(fontSize: 9, color: _gray)),
        ]),
      ),
    ]));

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(32, 28, 32, 28),
      header: (ctx) => ctx.pageNumber == 1
          ? pw.Container(
              padding: const pw.EdgeInsets.all(14),
              margin: const pw.EdgeInsets.only(bottom: 6),
              decoration: pw.BoxDecoration(
                color: _navy,
                border: pw.Border(bottom: pw.BorderSide(color: _accent, width: 3)),
              ),
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text(t('Relatório de Visita Técnica'),
                    style: pw.TextStyle(fontSize: 19, color: PdfColors.white, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 3),
                pw.Text(t(date), style: pw.TextStyle(fontSize: 10, color: PdfColor.fromInt(0xFFAAC8DC))),
              ]),
            )
          : pw.SizedBox(),
      footer: (ctx) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(t('TecCheck · página ${ctx.pageNumber} de ${ctx.pagesCount}'),
            style: pw.TextStyle(fontSize: 8, color: _gray)),
      ),
      build: (ctx) => body,
    ));
    return doc.save();
  }
}

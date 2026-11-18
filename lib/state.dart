import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'net/icmp.dart';
import 'net/net_info.dart';
import 'net/scanner.dart';
import 'net/speed_test.dart';
import 'net/wifi.dart';
import 'report/pdf_report.dart';

/// Estado único da visita: tudo que foi testado vai para o relatório.
class VisitState extends ChangeNotifier {
  VisitState._();
  static final VisitState I = VisitState._();

  // ---------- Rede ----------
  NetInfo net = const NetInfo();

  Future<void> refreshNet() async {
    try {
      net = await NetInfo.read();
    } catch (_) {
      net = const NetInfo();
    }
    notifyListeners();
  }

  // ---------- Velocidade ----------
  bool speedRunning = false;
  String speedPhase = '';
  double speedLive = 0;
  double speedProgress = 0;
  SpeedResult? speed;
  String? speedError;
  SpeedTester? _tester;

  Future<void> startSpeed() async {
    if (speedRunning) return;
    speedRunning = true;
    speedError = null;
    speedPhase = 'Preparando';
    speed = null;
    notifyListeners();
    final t = _tester = SpeedTester();
    try {
      speed = await t.run((phase, live, progress, partial) {
        speedPhase = phase;
        speedLive = live;
        speedProgress = progress;
        speed = partial;
        notifyListeners();
      });
      speedPhase = 'Concluído';
    } catch (e) {
      speedPhase = 'Interrompido';
      if (e.toString() != 'Cancelado') speedError = 'Falha no teste: $e';
    }
    speedRunning = false;
    _tester = null;
    notifyListeners();
  }

  void cancelSpeed() => _tester?.cancel();

  // ---------- Varredura ----------
  bool scanRunning = false;
  bool scanFinished = false;
  int scanDone = 0;
  int scanTotal = 0;
  List<Device> devices = [];
  final _scanner = NetworkScanner();

  Future<void> startScan() async {
    if (scanRunning) return;
    await refreshNet();
    scanRunning = true;
    scanFinished = false;
    devices = [];
    scanDone = 0;
    notifyListeners();
    final list = await _scanner.scan(
      net,
      onProgress: (d, t) {
        scanDone = d;
        scanTotal = t;
        notifyListeners();
      },
      onFound: (d) {
        devices = [...devices, d]..sort((a, b) => NetworkScanner.ipToInt(a.ip).compareTo(NetworkScanner.ipToInt(b.ip)));
        notifyListeners();
      },
    );
    devices = list;
    scanRunning = false;
    scanFinished = true;
    notifyListeners();
  }

  void stopScan() => _scanner.stop();

  // ---------- Ping ----------
  bool pingRunning = false;
  List<String> pingLines = [];
  PingStats? pingStats;
  final _pingTool = IcmpTools();

  Future<void> startPing(String host, int count, int size, bool df) async {
    if (pingRunning || host.trim().isEmpty) return;
    pingRunning = true;
    pingLines = [];
    pingStats = null;
    notifyListeners();
    try {
      pingStats = await _pingTool.ping(
        host.trim(),
        count: count,
        size: size,
        dontFragment: df,
        onLine: (l) {
          pingLines = [...pingLines, l];
          if (pingLines.length > 300) pingLines = pingLines.sublist(pingLines.length - 300);
          notifyListeners();
        },
        onProgress: (p) {
          pingStats = p;
          notifyListeners();
        },
      );
    } catch (e) {
      pingLines = [...pingLines, 'Erro: $e'];
    }
    pingRunning = false;
    notifyListeners();
  }

  void stopPing() => _pingTool.stop();

  // ---------- Traceroute ----------
  bool traceRunning = false;
  String traceTarget = '';
  List<Hop> hops = [];
  String? traceError;
  final _traceTool = IcmpTools();

  Future<void> startTrace(String host) async {
    if (traceRunning || host.trim().isEmpty) return;
    traceRunning = true;
    traceTarget = host.trim();
    hops = [];
    traceError = null;
    notifyListeners();
    try {
      await _traceTool.traceroute(traceTarget, onHop: (h) {
        hops = [...hops, h];
        notifyListeners();
      });
    } catch (e) {
      traceError = 'Não foi possível rastrear: $e';
    }
    traceRunning = false;
    notifyListeners();
  }

  void stopTrace() => _traceTool.stop();

  // ---------- Wi-Fi ----------
  bool wifiRunning = false;
  List<WifiNet> wifiNets = [];
  String? wifiMessage;

  Future<void> scanWifi() async {
    if (wifiRunning) return;
    wifiRunning = true;
    wifiMessage = null;
    notifyListeners();
    await refreshNet();
    try {
      final r = await WifiAnalyzer.scan();
      wifiNets = r.nets;
      if (!r.supported) {
        wifiMessage = null;
      } else if (r.nets.isEmpty) {
        wifiMessage = 'Nenhuma rede encontrada. Verifique se a Localização está ligada e a permissão concedida.';
      } else if (!r.fresh) {
        wifiMessage = 'O Android limita varreduras (4 a cada 2 min). Mostrando o último resultado.';
      }
    } catch (e) {
      wifiMessage = 'Erro na varredura: $e';
    }
    wifiRunning = false;
    notifyListeners();
  }

  // ---------- Relatório ----------
  final cliente = TextEditingController();
  final contrato = TextEditingController();
  final endereco = TextEditingController();
  final tecnico = TextEditingController();
  final plano = TextEditingController();
  final ooklaDown = TextEditingController();
  final ooklaUp = TextEditingController();
  final ooklaPing = TextEditingController();
  final observacoes = TextEditingController();

  void touch() => notifyListeners();

  double? get planoMbps => double.tryParse(plano.text.replaceAll(',', '.'));

  List<List<Offset>> signature = [];
  Size signatureSize = const Size(1, 1);

  void setSignature(List<List<Offset>> strokes, Size size) {
    signature = strokes;
    signatureSize = size;
    notifyListeners();
  }

  Future<Uint8List?> _signaturePng() async {
    if (signature.isEmpty) return null;
    final w = signatureSize.width.ceil().clamp(1, 4000);
    final h = signatureSize.height.ceil().clamp(1, 4000);
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    final pen = Paint()
      ..color = const Color(0xFF0F1E50)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final s in signature) {
      if (s.length < 2) continue;
      final p = Path()..moveTo(s.first.dx, s.first.dy);
      for (final o in s.skip(1)) {
        p.lineTo(o.dx, o.dy);
      }
      c.drawPath(p, pen);
    }
    final img = await rec.endRecording().toImage(w, h);
    final bd = await img.toByteData(format: ui.ImageByteFormat.png);
    return bd?.buffer.asUint8List();
  }

  Future<(Uint8List, String)> buildReport() async {
    final sig = await _signaturePng();
    final data = ReportData(
      cliente: cliente.text,
      contrato: contrato.text,
      endereco: endereco.text,
      tecnico: tecnico.text,
      planoMbps: planoMbps,
      ooklaDown: ooklaDown.text,
      ooklaUp: ooklaUp.text,
      ooklaPing: ooklaPing.text,
      observacoes: observacoes.text,
      net: net,
      speed: (speed?.complete ?? false) ? speed : null,
      devices: devices,
      ping: pingStats,
      traceTarget: traceTarget,
      hops: hops,
      wifi: wifiNets,
      signaturePng: sig,
    );
    final bytes = await PdfReport.build(data);
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final safe = (cliente.text.isEmpty ? 'cliente' : cliente.text).replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
    final name = 'visita_${safe}_${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}.pdf';
    return (bytes, name);
  }
}

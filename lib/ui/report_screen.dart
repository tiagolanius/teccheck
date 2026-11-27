import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../main.dart';
import '../state.dart';
import 'company_screen.dart';
import 'widgets.dart';

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});
  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  final s = VisitState.I;
  bool busy = false;
  String? err;
  Uint8List? pdf;
  String name = 'relatorio.pdf';

  Future<void> _generate() async {
    FocusScope.of(context).unfocus();
    setState(() {
      busy = true;
      err = null;
    });
    try {
      final (bytes, n) = await s.buildReport();
      pdf = bytes;
      name = n;
    } catch (e) {
      err = 'Erro ao gerar PDF: $e';
    }
    if (mounted) setState(() => busy = false);
  }

  Widget _field(String label, TextEditingController c, {int lines = 1}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: c,
          minLines: lines,
          maxLines: lines == 1 ? 1 : 6,
          decoration: InputDecoration(labelText: label),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Relatório da visita')),
      body: ListenableBuilder(
        listenable: s,
        builder: (context, _) => ListView(padding: const EdgeInsets.all(16), children: [
          _CompanyCard(s),
          const SizedBox(height: 12),
          SectionCard(title: 'Dados do atendimento', children: [
            _field('Cliente', s.cliente),
            _field('Contrato / código', s.contrato),
            _field('Endereço', s.endereco),
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TextField(
                controller: s.redeWifi,
                decoration: InputDecoration(
                  labelText: 'Rede Wi-Fi do cliente (SSID)',
                  prefixIcon: const Icon(Icons.wifi, size: 20),
                  suffixIcon: IconButton(
                    tooltip: 'Usar a rede conectada agora',
                    icon: const Icon(Icons.sync, color: Tec.cyan),
                    onPressed: () async {
                      await s.refreshNet();
                      if (s.net.ssid != null) {
                        s.redeWifi.text = s.net.ssid!;
                      } else if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('Nome da rede indisponível. Conecte no Wi-Fi e permita a Localização.'),
                        ));
                      }
                    },
                  ),
                ),
              ),
            ),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 3, child: _field('Técnico', s.tecnico)),
              const SizedBox(width: 8),
              Expanded(flex: 2, child: NumField('Plano (Mbps)', controller: s.plano)),
            ]),
            _field('Observações / serviço executado', s.observacoes, lines: 3),
          ]),
          const SizedBox(height: 12),
          SectionCard(title: 'O que vai no relatório', children: [
            _check('Teste de velocidade',
                (s.speed?.complete ?? false) || s.ooklaDown.text.isNotEmpty),
            _check('Análise Wi-Fi (${s.wifiNets.length} redes)', s.wifiNets.isNotEmpty),
            _check('Dispositivos (${s.devices.length})', s.devices.isNotEmpty),
            _check('Ping', s.pingStats != null),
            _check('Traceroute', s.hops.isNotEmpty),
            const Text('Itens não executados ficam de fora.', style: TextStyle(color: Tec.muted, fontSize: 11)),
          ]),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Assinatura do cliente',
            trailing: TextButton.icon(
              onPressed: () => s.setSignature([], const Size(1, 1)),
              icon: const Icon(Icons.delete, size: 18),
              label: const Text('Limpar'),
            ),
            children: [_SignaturePad(s)],
          ),
          if (err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(err!, style: const TextStyle(color: Tec.bad))),
          const SizedBox(height: 14),
          BigButton(Icons.picture_as_pdf, busy ? 'Gerando…' : 'Gerar PDF', busy ? null : _generate),
          if (pdf != null) ...[
            const SizedBox(height: 10),
            Text('Gerado: $name', style: const TextStyle(color: Tec.good, fontSize: 12)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: BigButton(Icons.visibility, 'Abrir', () => Printing.layoutPdf(onLayout: (_) async => pdf!, name: name),
                    outlined: true),
              ),
              const SizedBox(width: 8),
              Expanded(child: BigButton(Icons.share, 'Enviar', () => Printing.sharePdf(bytes: pdf!, filename: name))),
            ]),
          ],
          const SizedBox(height: 24),
        ]),
      ),
    );
  }

  Widget _check(String label, bool ok) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Icon(ok ? Icons.check_circle : Icons.radio_button_unchecked, size: 18, color: ok ? Tec.good : Tec.muted),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(color: ok ? Tec.text : Tec.muted)),
        ]),
      );
}

class _SignaturePad extends StatefulWidget {
  final VisitState s;
  const _SignaturePad(this.s);
  @override
  State<_SignaturePad> createState() => _SignaturePadState();
}

class _SignaturePadState extends State<_SignaturePad> {
  List<Offset> current = [];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final size = Size(box.maxWidth, 160);
      return GestureDetector(
        onPanStart: (d) => setState(() => current = [d.localPosition]),
        onPanUpdate: (d) => setState(() => current = [...current, d.localPosition]),
        onPanEnd: (_) {
          widget.s.setSignature([...widget.s.signature, current], size);
          setState(() => current = []);
        },
        child: Container(
          width: size.width,
          height: size.height,
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
          child: CustomPaint(painter: _SigPainter([...widget.s.signature, current])),
        ),
      );
    });
  }
}

class _SigPainter extends CustomPainter {
  final List<List<Offset>> strokes;
  _SigPainter(this.strokes);

  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..color = const Color(0xFF0F1E50)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    var empty = true;
    for (final s in strokes) {
      if (s.length < 2) continue;
      empty = false;
      final p = Path()..moveTo(s.first.dx, s.first.dy);
      for (final o in s.skip(1)) {
        p.lineTo(o.dx, o.dy);
      }
      canvas.drawPath(p, pen);
    }
    if (empty) {
      canvas.drawLine(Offset(24, size.height - 30), Offset(size.width - 24, size.height - 30),
          Paint()..color = const Color(0xFFCCCCCC)..strokeWidth = 2);
    }
  }

  @override
  bool shouldRepaint(_SigPainter old) => true;
}

class _CompanyCard extends StatelessWidget {
  final VisitState s;
  const _CompanyCard(this.s);

  @override
  Widget build(BuildContext context) {
    final c = s.company;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => go(context, const CompanyScreen()),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Container(
              width: 64,
              height: 64,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
              child: c.logo == null
                  ? const Icon(Icons.add_photo_alternate, color: Colors.black38)
                  : Image.memory(c.logo!, fit: BoxFit.contain),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Empresa no cabeçalho do PDF', style: TextStyle(color: Tec.muted, fontSize: 11)),
                Text(c.nome.isEmpty ? 'Cadastrar empresa e logotipo' : c.nome,
                    style: TextStyle(fontWeight: FontWeight.bold, color: c.nome.isEmpty ? Tec.cyan : Tec.text)),
                if (c.contactLines.isNotEmpty)
                  Text(c.contactLines.first, style: const TextStyle(color: Tec.muted, fontSize: 12), maxLines: 1),
              ]),
            ),
            const Icon(Icons.edit, color: Tec.cyan, size: 20),
          ]),
        ),
      ),
    );
  }
}

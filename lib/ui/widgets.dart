import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class Tec {
  static const cyan = Color(0xFF00D4FF);
  static const violet = Color(0xFF7C4DFF);
  static const good = Color(0xFF00E676);
  static const warn = Color(0xFFFFC400);
  static const bad = Color(0xFFFF5370);
  static const bg = Color(0xFF0A0F1A);
  static const card = Color(0xFF111827);
  static const cardHi = Color(0xFF1A2332);
  static const muted = Color(0xFF8B9AB0);
  static const text = Color(0xFFE6EDF7);

  static Color rssi(int? v) {
    if (v == null) return muted;
    if (v >= -55) return good;
    if (v >= -67) return cyan;
    if (v >= -75) return warn;
    return bad;
  }

  static Color latency(double? ms) {
    if (ms == null) return muted;
    if (ms < 30) return good;
    if (ms < 80) return warn;
    return bad;
  }

  static Color loss(double? p) {
    if (p == null) return muted;
    if (p == 0) return good;
    if (p < 5) return warn;
    return bad;
  }

  static ThemeData theme() {
    final scheme = ColorScheme.fromSeed(
      seedColor: cyan,
      brightness: Brightness.dark,
    ).copyWith(
      primary: cyan,
      onPrimary: const Color(0xFF00141A),
      secondary: violet,
      surface: card,
      onSurface: text,
      error: bad,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      appBarTheme: const AppBarTheme(backgroundColor: bg, elevation: 0, centerTitle: false),
      cardTheme: const CardThemeData(color: card, margin: EdgeInsets.zero),
      inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder(), isDense: true),
    );
  }
}

String fmt(double? v, [int d = 1]) => v == null ? '—' : v.toStringAsFixed(d).replaceAll('.', ',');

class SectionCard extends StatelessWidget {
  final String? title;
  final Widget? trailing;
  final List<Widget> children;
  const SectionCard({super.key, this.title, this.trailing, required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  Container(width: 4, height: 16, color: Tec.cyan),
                  const SizedBox(width: 8),
                  Expanded(child: Text(title!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
                  if (trailing != null) trailing!,
                ]),
              ),
            ...children,
          ],
        ),
      ),
    );
  }
}

class InfoRow extends StatelessWidget {
  final String label;
  final String? value;
  final Color? color;
  const InfoRow(this.label, this.value, {super.key, this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 110, child: Text(label, style: const TextStyle(color: Tec.muted, fontSize: 13))),
        Expanded(
          child: Text(
            (value == null || value!.isEmpty) ? '—' : value!,
            style: TextStyle(color: color ?? Tec.text, fontSize: 13, fontFamily: 'monospace'),
          ),
        ),
      ]),
    );
  }
}

class StatTile extends StatelessWidget {
  final String label, value, unit;
  final Color color;
  const StatTile(this.label, this.value, this.unit, this.color, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Tec.cardHi, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(color: Tec.muted, fontSize: 11), maxLines: 1),
        const SizedBox(height: 2),
        Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          Flexible(
            child: Text(value,
                style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false),
          ),
          const SizedBox(width: 3),
          Text(unit, style: const TextStyle(color: Tec.muted, fontSize: 11)),
        ]),
      ]),
    );
  }
}

class BigButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool outlined;
  final Color? color;
  const BigButton(this.icon, this.label, this.onPressed, {super.key, this.outlined = false, this.color});

  @override
  Widget build(BuildContext context) {
    final style = (outlined ? OutlinedButton.styleFrom() : FilledButton.styleFrom(backgroundColor: color)).copyWith(
      minimumSize: const WidgetStatePropertyAll(Size.fromHeight(52)),
      shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
    );
    final child = Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(icon),
      const SizedBox(width: 8),
      Flexible(child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold))),
    ]);
    return outlined
        ? OutlinedButton(onPressed: onPressed, style: style, child: child)
        : FilledButton(onPressed: onPressed, style: style, child: child);
  }
}

class NumField extends StatelessWidget {
  final String label;
  final TextEditingController? controller;
  final String? initial;
  final ValueChanged<String>? onChanged;
  const NumField(this.label, {super.key, this.controller, this.initial, this.onChanged});

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      initialValue: controller == null ? initial : null,
      onChanged: onChanged,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
      decoration: InputDecoration(labelText: label),
    );
  }
}

/// Velocímetro em arco de 270°.
class Gauge extends StatelessWidget {
  final double value, max;
  final String label, unit;
  const Gauge({super.key, required this.value, required this.max, required this.label, required this.unit});

  @override
  Widget build(BuildContext context) {
    final frac = (value / max).clamp(0.0, 1.0);
    return SizedBox(
      width: 230,
      height: 230,
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: frac),
        duration: const Duration(milliseconds: 300),
        builder: (_, f, __) => CustomPaint(
          painter: _GaugePainter(f),
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(value >= 100 ? fmt(value, 0) : fmt(value),
                  style: const TextStyle(fontSize: 44, fontWeight: FontWeight.bold)),
              Text(unit, style: const TextStyle(color: Tec.muted)),
              const SizedBox(height: 4),
              Text(label, style: const TextStyle(color: Tec.cyan, fontSize: 13)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double frac;
  _GaugePainter(this.frac);

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 16.0;
    final rect = Rect.fromLTWH(stroke, stroke, size.width - 2 * stroke, size.height - 2 * stroke);
    const start = 135 * math.pi / 180;
    const sweep = 270 * math.pi / 180;
    final track = Paint()
      ..color = Tec.cardHi
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, start, sweep, false, track);
    if (frac > 0) {
      final p = Paint()
        ..shader = const SweepGradient(
          colors: [Tec.violet, Tec.cyan, Tec.good, Tec.violet],
          transform: GradientRotation(start),
        ).createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(rect, start, sweep * frac, false, p);
    }
  }

  @override
  bool shouldRepaint(_GaugePainter old) => old.frac != frac;
}

/// Linha de latência por pacote.
class Sparkline extends StatelessWidget {
  final List<double> values;
  const Sparkline(this.values, {super.key});

  @override
  Widget build(BuildContext context) =>
      SizedBox(height: 80, width: double.infinity, child: CustomPaint(painter: _SparkPainter(values)));
}

class _SparkPainter extends CustomPainter {
  final List<double> v;
  _SparkPainter(this.v);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(Offset(0, size.height), Offset(size.width, size.height), Paint()..color = Tec.cardHi);
    if (v.length < 2) return;
    final maxV = math.max(v.reduce(math.max), 1.0) * 1.15;
    final dx = size.width / (v.length - 1);
    final path = Path();
    for (var i = 0; i < v.length; i++) {
      final x = i * dx;
      final y = size.height - v[i] / maxV * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = Tec.cyan
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_SparkPainter old) => true;
}

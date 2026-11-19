import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../company.dart';
import '../state.dart';
import 'widgets.dart';

/// Cadastro da empresa (logo + dados) usado no cabeçalho do relatório.
class CompanyScreen extends StatefulWidget {
  const CompanyScreen({super.key});
  @override
  State<CompanyScreen> createState() => _CompanyScreenState();
}

class _CompanyScreenState extends State<CompanyScreen> {
  final s = VisitState.I;
  late Company c = s.company;
  late final nome = TextEditingController(text: c.nome);
  late final cnpj = TextEditingController(text: c.cnpj);
  late final telefone = TextEditingController(text: c.telefone);
  late final email = TextEditingController(text: c.email);
  late final site = TextEditingController(text: c.site);
  late final endereco = TextEditingController(text: c.endereco);
  bool saving = false;

  Future<void> _pickLogo() async {
    try {
      final img = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 90,
      );
      if (img == null) return;
      final bytes = await img.readAsBytes();
      setState(() => c = c.copyWith(logo: bytes));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível abrir a imagem: $e')));
      }
    }
  }

  Future<void> _save() async {
    setState(() => saving = true);
    final updated = c.copyWith(
      nome: nome.text.trim(),
      cnpj: cnpj.text.trim(),
      telefone: telefone.text.trim(),
      email: email.text.trim(),
      site: site.text.trim(),
      endereco: endereco.text.trim(),
    );
    await s.saveCompany(updated);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Dados da empresa salvos.')));
    Navigator.pop(context);
  }

  Widget _field(String label, TextEditingController ctl,
          {TextInputType? type, List<TextInputFormatter>? fmt, IconData? icon}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: ctl,
          keyboardType: type,
          inputFormatters: fmt,
          decoration: InputDecoration(labelText: label, prefixIcon: icon == null ? null : Icon(icon, size: 20)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dados da empresa')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        SectionCard(title: 'Logotipo', children: [
          Center(
            child: GestureDetector(
              onTap: _pickLogo,
              child: Container(
                width: double.infinity,
                height: 140,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Tec.cardHi, width: 2),
                ),
                child: c.logo == null
                    ? const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.add_photo_alternate, size: 40, color: Colors.black45),
                        SizedBox(height: 6),
                        Text('Toque para escolher a imagem', style: TextStyle(color: Colors.black54)),
                      ])
                    : Image.memory(c.logo!, fit: BoxFit.contain),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickLogo,
                icon: const Icon(Icons.photo_library),
                label: Text(c.logo == null ? 'Escolher' : 'Trocar'),
              ),
            ),
            if (c.logo != null) ...[
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => setState(() => c = c.copyWith(clearLogo: true)),
                  icon: const Icon(Icons.delete),
                  label: const Text('Remover'),
                ),
              ),
            ],
          ]),
          const SizedBox(height: 4),
          const Text('Prefira PNG com fundo transparente ou branco. O PDF usa fundo branco no cabeçalho.',
              style: TextStyle(color: Tec.muted, fontSize: 11)),
        ]),
        const SizedBox(height: 12),
        SectionCard(title: 'Cadastro', children: [
          _field('Nome / razão social', nome, icon: Icons.business),
          _field('CNPJ', cnpj, type: TextInputType.number, fmt: [_CnpjFormatter()], icon: Icons.badge),
          _field('Telefone / WhatsApp', telefone, type: TextInputType.phone, icon: Icons.phone),
          _field('E-mail', email, type: TextInputType.emailAddress, icon: Icons.email),
          _field('Site', site, type: TextInputType.url, icon: Icons.language),
          _field('Endereço', endereco, icon: Icons.place),
        ]),
        const SizedBox(height: 14),
        BigButton(Icons.save, saving ? 'Salvando…' : 'Salvar', saving ? null : _save),
        const SizedBox(height: 8),
        const Text('Os dados ficam salvos neste aparelho e saem em todos os relatórios.',
            textAlign: TextAlign.center, style: TextStyle(color: Tec.muted, fontSize: 11)),
      ]),
    );
  }
}

/// Máscara 00.000.000/0000-00.
class _CnpjFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final d = newValue.text.replaceAll(RegExp(r'\D'), '');
    final digits = d.length > 14 ? d.substring(0, 14) : d;
    final b = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i == 2 || i == 5) b.write('.');
      if (i == 8) b.write('/');
      if (i == 12) b.write('-');
      b.write(digits[i]);
    }
    final t = b.toString();
    return TextEditingValue(text: t, selection: TextSelection.collapsed(offset: t.length));
  }
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

/// Cadastro da empresa que aparece no cabeçalho do relatório PDF.
class Company {
  final String nome;
  final String cnpj;
  final String telefone;
  final String email;
  final String site;
  final String endereco;
  final Uint8List? logo;

  const Company({
    this.nome = '',
    this.cnpj = '',
    this.telefone = '',
    this.email = '',
    this.site = '',
    this.endereco = '',
    this.logo,
  });

  bool get isEmpty => nome.isEmpty && logo == null;

  /// Linhas de contato para o cabeçalho, sem as vazias.
  List<String> get contactLines => [
        if (cnpj.isNotEmpty) 'CNPJ $cnpj',
        [telefone, email].where((s) => s.isNotEmpty).join('  ·  '),
        [site, endereco].where((s) => s.isNotEmpty).join('  ·  '),
      ].where((s) => s.isNotEmpty).toList();

  Company copyWith({
    String? nome,
    String? cnpj,
    String? telefone,
    String? email,
    String? site,
    String? endereco,
    Uint8List? logo,
    bool clearLogo = false,
  }) =>
      Company(
        nome: nome ?? this.nome,
        cnpj: cnpj ?? this.cnpj,
        telefone: telefone ?? this.telefone,
        email: email ?? this.email,
        site: site ?? this.site,
        endereco: endereco ?? this.endereco,
        logo: clearLogo ? null : (logo ?? this.logo),
      );

  static const _key = 'company_profile';

  static Future<Company> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_key);
      if (raw == null) return const Company();
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final logo = j['logo'] as String?;
      return Company(
        nome: j['nome'] as String? ?? '',
        cnpj: j['cnpj'] as String? ?? '',
        telefone: j['telefone'] as String? ?? '',
        email: j['email'] as String? ?? '',
        site: j['site'] as String? ?? '',
        endereco: j['endereco'] as String? ?? '',
        logo: logo == null ? null : base64Decode(logo),
      );
    } catch (_) {
      return const Company();
    }
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
      _key,
      jsonEncode({
        'nome': nome,
        'cnpj': cnpj,
        'telefone': telefone,
        'email': email,
        'site': site,
        'endereco': endereco,
        'logo': logo == null ? null : base64Encode(logo!),
      }),
    );
  }
}

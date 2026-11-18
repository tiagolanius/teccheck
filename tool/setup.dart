// Ajusta os arquivos gerados pelo `flutter create` com o que o TecCheck precisa.
//
// Uso (na raiz do projeto):
//   flutter create --org com.dfsolutions --project-name teccheck --platforms android,ios .
//   dart run tool/setup.dart                  # permissões iOS
//   dart run tool/setup.dart --wifi-entitlement   # + leitura do SSID no iOS (conta Apple paga)
//
// Android: nada a fazer, as permissões vêm do manifesto do plugin local (mesclado no build).
import 'dart:io';

void main(List<String> args) {
  final plist = File('ios/Runner/Info.plist');
  if (!plist.existsSync()) {
    stderr.writeln('ios/Runner/Info.plist não encontrado. Rode antes:\n'
        '  flutter create --org com.dfsolutions --project-name teccheck --platforms android,ios .');
    exit(1);
  }

  var s = plist.readAsStringSync();
  final entries = <String, String>{
    'NSLocationWhenInUseUsageDescription':
        '<string>O iOS exige a localização para mostrar o nome da rede Wi-Fi (SSID) conectada.</string>',
    'NSLocalNetworkUsageDescription':
        '<string>Usado para encontrar os aparelhos da rede do cliente e testar o roteador.</string>',
    'NSAppTransportSecurity': '<dict>\n\t\t<key>NSAllowsArbitraryLoads</key>\n\t\t<true/>\n'
        '\t\t<key>NSAllowsLocalNetworking</key>\n\t\t<true/>\n\t</dict>',
    'LSApplicationQueriesSchemes': '<array>\n\t\t<string>speedtest</string>\n\t</array>',
  };
  var added = 0;
  entries.forEach((key, value) {
    if (s.contains('<key>$key</key>')) return;
    final i = s.lastIndexOf('</dict>');
    s = '${s.substring(0, i)}\t<key>$key</key>\n\t$value\n${s.substring(i)}';
    added++;
  });
  plist.writeAsStringSync(s);
  stdout.writeln('Info.plist: $added chave(s) adicionada(s).');

  if (args.contains('--wifi-entitlement')) {
    final ent = File('ios/Runner/Runner.entitlements');
    ent.writeAsStringSync('''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.developer.networking.wifi-info</key>
	<true/>
</dict>
</plist>
''');
    final pbx = File('ios/Runner.xcodeproj/project.pbxproj');
    var p = pbx.readAsStringSync();
    if (!p.contains('CODE_SIGN_ENTITLEMENTS')) {
      p = p.replaceAll(
        'INFOPLIST_FILE = Runner/Info.plist;',
        'INFOPLIST_FILE = Runner/Info.plist;\n\t\t\t\tCODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;',
      );
      pbx.writeAsStringSync(p);
    }
    stdout.writeln('Entitlement "Access WiFi Information" configurado.');
  }
  stdout.writeln('Pronto. Agora: flutter run');
}

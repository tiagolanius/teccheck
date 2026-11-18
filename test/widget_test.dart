import 'package:flutter_test/flutter_test.dart';
import 'package:teccheck/net/scanner.dart';

void main() {
  test('faixa /24', () {
    final hosts = NetworkScanner.hostRange('192.168.1.37', 24);
    expect(hosts.length, 254);
    expect(hosts.first, '192.168.1.1');
    expect(hosts.last, '192.168.1.254');
  });
}

# TecCheck 2.0 (Flutter): Android e iOS

App para técnico de telecom checar a instalação na casa do cliente e gerar laudo em PDF.
O mesmo código roda nos dois sistemas. A parte nativa fica no plugin local `packages/teccheck_native`.

## Funções por plataforma

| Recurso | Android | iPhone |
|---|---|---|
| Teste de velocidade (Cloudflare) + % do plano | ✅ | ✅ |
| Abrir Speedtest Ookla | ✅ app ou site | ✅ app ou site |
| Varredura da rede (IPs, portas, tipo, nome) | ✅ | ✅ pede permissão "Rede local" |
| MAC dos aparelhos | só via NetBIOS | só via NetBIOS |
| Ping (tamanho, DF/MTU, gráfico, perda, jitter) | ✅ | ✅ ICMP nativo |
| Traceroute | ✅ | ✅ ICMP nativo com TTL |
| Acessar roteador (WebView + login HTTP) | ✅ | ✅ |
| SSID / BSSID / IP / gateway | ✅ | ✅ SSID precisa de conta Apple paga (ver abaixo) |
| DNS em uso | ✅ | ❌ |
| Sinal dBm, canal, velocidade de link | ✅ | ❌ a Apple não libera |
| Redes vizinhas e recomendação de canal | ✅ | ❌ a Apple não libera |
| Relatório PDF com assinatura, compartilhar | ✅ | ✅ |

## Primeira vez: gerar as pastas `android/` e `ios/`

Precisa do Flutter 3.27 ou mais novo (`flutter --version`).

```bash
cd teccheck_flutter
flutter create --org com.dfsolutions --project-name teccheck --platforms android,ios .
dart run tool/setup.dart
flutter pub get
```

O `flutter create` não sobrescreve nada do que já existe; só cria o que falta.
O `setup.dart` adiciona as permissões do iOS no `Info.plist`. No Android as permissões já vêm do plugin.

## Rodar / gerar instalável

**Android** (Windows, Linux ou Mac):
```bash
flutter run                 # celular conectado com depuração USB
flutter build apk --release # gera build/app/outputs/flutter-apk/app-release.apk
```

**iPhone** (precisa de Mac com Xcode):
```bash
open ios/Runner.xcworkspace
```
No Xcode: **Runner → Signing & Capabilities → Team**, escolha sua conta Apple e rode no iPhone.
- Conta gratuita: funciona, mas o app expira em 7 dias e o SSID aparece vazio.
- Conta paga (US$ 99/ano): para ler o SSID, rode `dart run tool/setup.dart --wifi-entitlement`. O Xcode habilita "Access WiFi Information" sozinho. Também permite distribuir via TestFlight.

## Sem instalar nada: GitHub Actions

Suba a pasta num repositório no GitHub. O workflow `.github/workflows/build.yml`:
- compila o **APK Android** (baixe em *Actions → Artifacts → TecCheck-android*);
- compila o **iOS sem assinatura** num Mac da nuvem, só para validar o código. Para instalar no iPhone, ainda é preciso assinar no Xcode.

## Estrutura

```
lib/
  main.dart               tela inicial e checklist
  state.dart              estado da visita (todos os resultados)
  net/                    net_info, speed_test, scanner, icmp (ping/trace), wifi
  report/pdf_report.dart  geração do PDF
  ui/                     telas
packages/teccheck_native/ plugin local
  android/…/TecCheckNativePlugin.kt   permissões, rede atual, varredura Wi-Fi, ping
  ios/Classes/TecCheckNativePlugin.swift  ICMP com TTL, localização, Speedtest
tool/setup.dart           ajustes pós `flutter create`
```

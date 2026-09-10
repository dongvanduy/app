import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_code_scanner_plus/qr_code_scanner_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_app/features/pe_system/presentation/screens/qr_scan_page.dart';
import 'business_screens_test.dart' show Harness;

void main() {
  testWidgets(
    'QR scales to the viewport and returns only the first code without closing a callback route',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final messenger = tester.binding.defaultBinaryMessenger;
      String? qrChannel;
      bool flash = false;
      messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
        call,
      ) async {
        if (call.method == 'create') {
          final id = (call.arguments as Map)['id'];
          qrChannel = 'net.touchcapture.qr.flutterqrplus/qrview_$id';
          messenger.setMockMethodCallHandler(MethodChannel(qrChannel!), (
            call,
          ) async {
            if (call.method == 'toggleFlash') flash = !flash;
            if (call.method == 'getFlashInfo') return flash;
            return null;
          });
          return 1;
        }
        if (call.method == 'resize') {
          final args = call.arguments as Map;
          return {'width': args['width'], 'height': args['height']};
        }
        return null;
      });
      final received = <String>[];
      final h = Harness(tester, width: 320, scale: 2);
      await h.mount(
        Scaffold(
          body: Builder(
            builder:
                (context) => Center(
                  child: FilledButton(
                    onPressed:
                        () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder:
                                (_) => QRScanPage(
                                  onCodeScanned: (value) {
                                    received.add(value);
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder:
                                            (_) => const Scaffold(
                                              body: Center(
                                                child: Text('Accepted'),
                                              ),
                                            ),
                                      ),
                                    );
                                  },
                                ),
                          ),
                        ),
                    child: const Text('Scan'),
                  ),
                ),
          ),
        ),
      );
      await tester.tap(find.text('Scan'));
      await tester.pumpAndSettle();
      final view = tester.widget<QRView>(find.byType(QRView));
      expect(view.overlay!.cutOutWidth, lessThanOrEqualTo(272));
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Bật đèn pin'));
      await tester.pumpAndSettle();
      expect(find.text('Tắt đèn pin'), findsOneWidget);
      expect(qrChannel, isNotNull);
      Future<void> send(String code) async {
        final done = <void>[];
        await messenger.handlePlatformMessage(
          qrChannel!,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('onRecognizeQR', {'code': code, 'type': 'QR_CODE'}),
          ),
          (_) => done.add(null),
        );
      }

      await send('');
      await tester.pump();
      expect(received, isEmpty);
      await send('SN-FIRST');
      await send('SN-SECOND');
      await tester.pumpAndSettle();
      expect(received, ['SN-FIRST']);
      expect(find.text('Accepted'), findsOneWidget);
      expect(find.byType(QRScanPage), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      h.dispose();
    },
  );
}

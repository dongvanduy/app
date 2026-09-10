import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:qr_code_scanner_plus/qr_code_scanner_plus.dart';
import '../widgets/business_widgets.dart';
import '../widgets/dashboard_theme.dart';

class QRScanPage extends StatelessWidget {
  final ValueChanged<String> onCodeScanned;
  const QRScanPage({super.key, required this.onCodeScanned});
  @override
  Widget build(BuildContext context) =>
      DashboardTheme(child: _QRScanBody(onCodeScanned: onCodeScanned));
}

class _QRScanBody extends StatefulWidget {
  const _QRScanBody({required this.onCodeScanned});
  final ValueChanged<String> onCodeScanned;
  @override
  State<_QRScanBody> createState() => _QRScanBodyState();
}

class _QRScanBodyState extends State<_QRScanBody> {
  final _qrKey = GlobalKey(debugLabel: 'QR');
  QRViewController? _controller;
  StreamSubscription<Barcode>? _subscription;
  bool _accepted = false;
  bool _flash = false;
  @override
  void dispose() {
    _subscription?.cancel();
    // QRView disposes its controller when it is unmounted.
    super.dispose();
  }

  void _onCreated(QRViewController controller) {
    _controller = controller;
    _subscription?.cancel();
    _subscription = controller.scannedDataStream.listen((data) {
      final code = data.code;
      if (!mounted || _accepted || code == null || code.trim().isEmpty) return;
      _accepted = true;
      // Close this route before a callback can open another route or dialog.
      Navigator.of(context).pop();
      widget.onCodeScanned(code);
    });
  }

  Future<void> _toggleFlash() async {
    final controller = _controller;
    if (controller == null) return;
    try {
      await controller.toggleFlash();
      final enabled = await controller.getFlashStatus();
      if (mounted) setState(() => _flash = enabled ?? false);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(bt(context, 'flash_unavailable'))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    watchBusinessLanguage(context);
    return BusinessPage(
      title: bt(context, 'qrScan'),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final cutout = math.max(
            48.0,
            math.min(
              320.0,
              math.min(constraints.maxWidth - 48, constraints.maxHeight - 144),
            ),
          );
          return Stack(
            fit: StackFit.expand,
            children: [
              QRView(
                key: _qrKey,
                onQRViewCreated: _onCreated,
                overlay: QrScannerOverlayShape(
                  borderColor: DashboardColors.of(context).accent,
                  borderRadius: 20,
                  borderLength: 32,
                  borderWidth: 6,
                  cutOutSize: cutout,
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: Center(
                  child: FilledButton.icon(
                    onPressed: _toggleFlash,
                    icon: Icon(
                      _flash ? Icons.flashlight_off : Icons.flashlight_on,
                    ),
                    label: Text(bt(context, _flash ? 'flash_off' : 'flash_on')),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

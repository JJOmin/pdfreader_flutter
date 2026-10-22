import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'shared/pairing.dart';

/// Builds what shows the camera and reports every text it reads.
typedef ScannerBuilder = Widget Function(BuildContext context, void Function(String text) onText);

Widget _camera(BuildContext context, void Function(String text) onText) => MobileScanner(
  controller: MobileScannerController(formats: const [BarcodeFormat.qrCode]),
  onDetect: (capture) {
    for (final barcode in capture.barcodes) {
      final text = barcode.rawValue;
      if (text != null) onText(text);
    }
  },
  errorBuilder: (context, error) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        error.errorCode == MobileScannerErrorCode.permissionDenied
            ? 'The camera is needed only to read the picture on the computer. Allow it in the phone’s settings, '
                  'or choose the computer from the list and type its code.'
            : 'The camera could not be opened: ${error.errorDetails?.message ?? error.errorCode.name}',
        textAlign: TextAlign.center,
      ),
    ),
  ),
);

/// Reads the QR code in the desktop's Phone dialog (PLAN 7.6). The camera permission is asked when this
/// page opens, which is when the user tapped "Scan to pair". Pops with what the code holds.
class ScanPage extends StatefulWidget {
  const ScanPage({super.key, this.scanner = _camera});

  final ScannerBuilder scanner;

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  var _done = false;
  var _foreign = false;

  void _onText(String text) {
    if (_done) return;
    final url = parsePairingUrl(text);
    if (url == null) {
      if (!_foreign) setState(() => _foreign = true);
      return;
    }
    _done = true;
    Navigator.of(context).pop(url);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Scan to pair')),
    body: Column(
      children: [
        Expanded(child: widget.scanner(context, _onText)),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            _foreign
                ? 'That is not a pairing code from PDF Reader.'
                : 'On the computer, open Phone, switch on Wi-Fi sync, and point the camera at the picture.',
            key: const Key('scan-hint'),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    ),
  );
}

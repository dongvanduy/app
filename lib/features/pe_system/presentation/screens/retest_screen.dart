import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/code_provider.dart';
import '../widgets/business_widgets.dart';
import '../widgets/dashboard_theme.dart';
import 'qr_scan_page.dart';

class RetestScreen extends StatelessWidget {
  const RetestScreen({super.key});
  @override
  Widget build(BuildContext context) =>
      const DashboardTheme(child: _RetestBody());
}

class _RetestBody extends StatefulWidget {
  const _RetestBody();
  @override
  State<_RetestBody> createState() => _RetestBodyState();
}

class _RetestBodyState extends State<_RetestBody> {
  final _serialController = TextEditingController();
  final _notesController = TextEditingController();
  bool _initialized = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      final provider = context.read<CodeProvider>();
      _serialController.text = provider.scannedSerialNumber ?? '';
      _notesController.text = provider.notes ?? '';
      _initialized = true;
    }
  }

  @override
  void dispose() {
    _serialController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _scan(CodeProvider provider) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder:
            (_) => QRScanPage(
              onCodeScanned: (code) {
                if (!mounted) return;
                _serialController.text = code;
                provider.updateScannedSerialNumber(code.trim());
              },
            ),
      ),
    );
  }

  Future<void> _submit(CodeProvider provider) async {
    FocusScope.of(context).unfocus();
    await provider.submitRetest();
    if (!mounted) return;
    if (provider.retestError == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(bt(context, 'retestSuccess'))));
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    watchBusinessLanguage(context);
    final provider = context.watch<CodeProvider>();
    final colors = DashboardColors.of(context);
    final hasSerial = provider.scannedSerialNumber?.trim().isNotEmpty ?? false;
    return BusinessPage(
      title: bt(context, 'retest'),
      maxWidth: 760,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: AbsorbPointer(
          absorbing: provider.isSubmittingRetest,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BusinessSection(
                title: bt(context, 'serialNumber'),
                icon: Icons.qr_code,
                child: TextField(
                  key: const ValueKey('retest_serial_input'),
                  controller: _serialController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    hintText: bt(context, 'enter_scan_sn'),
                    suffixIcon: IconButton(
                      tooltip: bt(context, 'qrScan'),
                      onPressed: () => _scan(provider),
                      icon: const Icon(Icons.qr_code_scanner),
                    ),
                  ),
                  onChanged:
                      (value) =>
                          provider.updateScannedSerialNumber(value.trim()),
                ),
              ),
              const SizedBox(height: 16),
              BusinessSection(
                title: bt(context, 'results'),
                icon: Icons.fact_check_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        for (final status in ['Pass', 'Fail'])
                          ChoiceChip(
                            key: ValueKey('retest_$status'),
                            label: Text(bt(context, status)),
                            avatar: Icon(
                              status == 'Pass'
                                  ? Icons.check_circle_outline
                                  : Icons.cancel_outlined,
                              color:
                                  status == 'Pass'
                                      ? colors.success
                                      : colors.danger,
                            ),
                            selected: provider.retestResult == status,
                            onSelected:
                                hasSerial
                                    ? (_) => provider.setRetestResult(status)
                                    : null,
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      key: const ValueKey('retest_notes_input'),
                      controller: _notesController,
                      enabled: hasSerial,
                      minLines: 3,
                      maxLines: 6,
                      decoration: InputDecoration(
                        labelText: bt(context, 'Notes'),
                        alignLabelWithHint: true,
                      ),
                      onChanged: provider.setNotes,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              BusinessSection(
                title: bt(context, 'Photo'),
                icon: Icons.add_a_photo_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OutlinedButton.icon(
                      onPressed: hasSerial ? provider.pickImage : null,
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: Text(bt(context, 'importPhoto')),
                    ),
                    if (provider.retestImage != null) ...[
                      const SizedBox(height: 16),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.file(
                          provider.retestImage!,
                          height: 220,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (provider.retestError != null) ...[
                const SizedBox(height: 16),
                Text(
                  provider.retestError!,
                  style: TextStyle(color: colors.danger),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton.icon(
                key: const ValueKey('retest_submit'),
                onPressed:
                    hasSerial && !provider.isSubmittingRetest
                        ? () => _submit(provider)
                        : null,
                icon:
                    provider.isSubmittingRetest
                        ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : const Icon(Icons.send_outlined),
                label: Text(
                  bt(
                    context,
                    provider.isSubmittingRetest ? 'loading' : 'submit',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

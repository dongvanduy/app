import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../auth/domain/entities/auth_user.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../pe_system/presentation/screens/qr_scan_page.dart';
import '../../domain/entities/inventory_models.dart';
import '../../domain/entities/stock_type.dart';
import '../providers/inventory_import_provider.dart';

class InventoryImportScreen extends StatefulWidget {
  const InventoryImportScreen({super.key});

  @override
  State<InventoryImportScreen> createState() => _InventoryImportScreenState();
}

class _InventoryImportScreenState extends State<InventoryImportScreen> {
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _serialController = TextEditingController();
  final FocusNode _locationFocusNode = FocusNode();
  final FocusNode _serialFocusNode = FocusNode();
  InventoryImportProvider? _provider;
  bool _softwareKeyboardEnabled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusField(_locationFocusNode);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = context.read<InventoryImportProvider>();
    if (!identical(_provider, provider)) {
      _provider?.removeListener(_synchronizeControllers);
      _provider = provider;
      _provider?.addListener(_synchronizeControllers);
      _synchronizeControllers();
    }
  }

  @override
  void dispose() {
    _provider?.removeListener(_synchronizeControllers);
    _locationController.dispose();
    _serialController.dispose();
    _locationFocusNode.dispose();
    _serialFocusNode.dispose();
    super.dispose();
  }

  void _synchronizeControllers() {
    final provider = _provider;
    if (provider == null || !mounted) {
      return;
    }
    _setControllerText(_locationController, provider.locationInput);
    _setControllerText(_serialController, provider.serialInput);
  }

  void _setControllerText(TextEditingController controller, String value) {
    if (controller.text == value) {
      return;
    }
    controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  Future<void> _scanLocation() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder:
            (_) => QRScanPage(
              onCodeScanned: (value) {
                _provider?.updateLocation(value);
              },
            ),
      ),
    );
    if (mounted) {
      await _handleLocationSubmitted(_locationController.text);
    }
  }

  Future<void> _scanSerial() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder:
            (_) => QRScanPage(
              onCodeScanned: (value) => _provider?.appendScannedSerial(value),
            ),
      ),
    );
    if (mounted) {
      _focusField(_serialFocusNode);
    }
  }

  void _toggleSoftwareKeyboard() {
    setState(() {
      _softwareKeyboardEnabled = !_softwareKeyboardEnabled;
    });

    final targetFocus =
        _serialFocusNode.hasFocus ? _serialFocusNode : _locationFocusNode;
    _focusField(targetFocus);
  }

  void _focusField(FocusNode focusNode) {
    focusNode.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !focusNode.hasFocus) {
        return;
      }
      if (_softwareKeyboardEnabled) {
        SystemChannels.textInput.invokeMethod<void>('TextInput.show');
      } else {
        _hideSoftwareKeyboard();
      }
    });
  }

  void _keepSoftwareKeyboardHidden() {
    if (!_softwareKeyboardEnabled) {
      _hideSoftwareKeyboard();
    }
  }

  void _hideSoftwareKeyboard() {
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    Future<void>.delayed(const Duration(milliseconds: 80), () {
      if (mounted &&
          !_softwareKeyboardEnabled &&
          (_locationFocusNode.hasFocus || _serialFocusNode.hasFocus)) {
        SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      }
    });
  }

  void _clearForm(InventoryImportProvider provider) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    provider.clearForm();
    _focusField(_locationFocusNode);
  }

  Future<void> _handleLocationSubmitted(String value) async {
    final provider = _provider;
    if (provider == null || provider.busy) {
      return;
    }

    provider.updateLocation(value);
    if (provider.location == null) {
      _selectLocationAndFocus();
      return;
    }

    if (provider.stockType.supportsTray) {
      await provider.refreshTray();
      if (!mounted) {
        return;
      }

      if (provider.trayInfo == null) {
        _selectLocationAndFocus();
        return;
      }

      if (provider.isTrayFull) {
        await _showTrayFullDialog(provider);
        if (mounted) {
          _selectLocationAndFocus();
        }
        return;
      }
    }

    _focusField(_serialFocusNode);
  }

  void _selectLocationAndFocus() {
    _locationController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _locationController.text.length,
    );
    _focusField(_locationFocusNode);
  }

  Future<void> _showTrayFullDialog(InventoryImportProvider provider) async {
    final tray = provider.trayInfo!;
    FocusScope.of(context).unfocus();
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Tray is full'),
            content: Text(
              'Location ${provider.location!.normalized} is full '
              '(${tray.actualOccupiedCount}/${tray.maxSlots}). '
              'Please select another tray.',
            ),
            actions: <Widget>[
              TextButton(
                key: const ValueKey<String>('tray_full_ok_button'),
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
    );
  }

  Future<void> _submit(InventoryImportProvider provider) async {
    FocusScope.of(context).unfocus();
    await provider.submit();
    if (!mounted) {
      return;
    }

    final hasErrors =
        provider.error != null ||
        provider.failedImportResults.isNotEmpty ||
        provider.invalidSerials.isNotEmpty;
    final title =
        provider.error != null
            ? 'Import failed'
            : hasErrors
            ? 'Import completed with errors'
            : 'Import successful';

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder:
          (dialogContext) => AlertDialog(
            title: Text(title),
            content: SingleChildScrollView(
              child: Text(_buildImportResultMessage(provider)),
            ),
            actions: <Widget>[
              TextButton(
                key: const ValueKey<String>('inventory_result_ok_button'),
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
    );
    if (mounted) {
      _clearForm(provider);
    }
  }

  String _buildImportResultMessage(InventoryImportProvider provider) {
    final sections = <String>[
      if (provider.error != null) provider.error!,
      if (provider.operationSummary != null) provider.operationSummary!,
      if (provider.warning != null) provider.warning!,
      if (provider.invalidSerials.isNotEmpty)
        'Invalid Serial Numbers:\n${provider.invalidSerials.join('\n')}',
      if (provider.failedImportResults.isNotEmpty)
        'Failed:\n${provider.failedImportResults.map((item) {
          return '${item.serialNumber}: ${item.message}';
        }).join('\n')}',
    ];
    return sections.isEmpty
        ? 'Inventory import could not be completed.'
        : sections.join('\n\n');
  }

  Future<void> _exportTray(InventoryImportProvider provider) async {
    final location = provider.location;
    final tray = provider.trayInfo;
    if (location == null || tray == null || !provider.canExport) {
      return;
    }

    FocusScope.of(context).unfocus();
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Confirm inventory export'),
            content: Text(
              'Export all ${tray.occupiedPositions.length} SN(s) from '
              'location ${location.normalized}?',
            ),
            actions: <Widget>[
              TextButton(
                key: const ValueKey<String>('inventory_export_cancel_button'),
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('CANCEL'),
              ),
              FilledButton(
                key: const ValueKey<String>('inventory_export_confirm_button'),
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('EXPORT'),
              ),
            ],
          ),
    );
    if (!mounted) {
      return;
    }
    if (confirmed != true) {
      _focusField(_locationFocusNode);
      return;
    }

    final succeeded = await provider.exportTray();
    if (!mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder:
          (dialogContext) => AlertDialog(
            title: Text(succeeded ? 'Export successful' : 'Export failed'),
            content: Text(_buildExportResultMessage(provider)),
            actions: <Widget>[
              TextButton(
                key: const ValueKey<String>(
                  'inventory_export_result_ok_button',
                ),
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
    );
    if (!mounted) {
      return;
    }

    if (succeeded) {
      _clearForm(provider);
    } else {
      _selectLocationAndFocus();
    }
  }

  String _buildExportResultMessage(InventoryImportProvider provider) {
    final sections = <String>[
      if (provider.error != null) provider.error!,
      if (provider.operationSummary != null) provider.operationSummary!,
      if (provider.warning != null) provider.warning!,
    ];
    return sections.isEmpty
        ? 'Inventory export could not be completed.'
        : sections.join('\n\n');
  }

  @override
  Widget build(BuildContext context) {
    final authenticatedUser = context.watch<AuthProvider>().user;
    return Scaffold(
      appBar: AppBar(title: const Text('INVENTORY IMPORT')),
      body: SafeArea(
        child: Consumer<InventoryImportProvider>(
          builder: (context, provider, _) {
            return AbsorbPointer(
              absorbing: provider.busy,
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  16,
                  16,
                  16,
                  16 + MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 900),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        _buildFormActions(provider, authenticatedUser),
                        const SizedBox(height: 12),
                        _buildStockTypeSelector(provider),
                        const SizedBox(height: 16),
                        _SectionCard(
                          title: 'Location',
                          child: _buildLocationSection(provider),
                        ),
                        const SizedBox(height: 16),
                        _SectionCard(
                          title: 'Tray information',
                          child: _buildTraySection(provider),
                        ),
                        const SizedBox(height: 16),
                        _SectionCard(
                          title: 'Serial Numbers',
                          child: _buildSerialSection(provider),
                        ),
                        if (provider.error != null ||
                            provider.operationSummary != null ||
                            provider.warning != null) ...<Widget>[
                          const SizedBox(height: 16),
                          _buildOperationMessages(provider),
                        ],
                        const SizedBox(height: 24),
                        _buildInventoryActions(provider),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildFormActions(InventoryImportProvider provider, AuthUser? user) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final colorScheme = Theme.of(context).colorScheme;
        final username =
            user?.username.trim().isNotEmpty == true
                ? user!.username.trim()
                : 'Chưa đăng nhập';
        final usernameMaxWidth =
            constraints.maxWidth < 260 ? constraints.maxWidth : 260.0;

        return Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            Tooltip(
              message: username,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: usernameMaxWidth),
                child: OutlinedButton.icon(
                  key: const ValueKey<String>('inventory_username'),
                  onPressed: null,
                  style: OutlinedButton.styleFrom(
                    disabledForegroundColor: colorScheme.onSurface,
                    side: BorderSide(color: colorScheme.outline),
                  ),
                  icon: const Icon(Icons.person_outline),
                  label: Text(
                    username,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
            OutlinedButton.icon(
              key: const ValueKey<String>('inventory_refresh_button'),
              onPressed: provider.busy ? null : () => _clearForm(provider),
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
            ),
            OutlinedButton.icon(
              key: const ValueKey<String>('software_keyboard_toggle'),
              onPressed: _toggleSoftwareKeyboard,
              icon: Icon(
                _softwareKeyboardEnabled
                    ? Icons.keyboard_hide_outlined
                    : Icons.keyboard_alt_outlined,
              ),
              label: Text(
                'Keyboard: ${_softwareKeyboardEnabled ? 'ON' : 'OFF'}',
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildInventoryActions(InventoryImportProvider provider) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 430;
        final importButton = ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: ElevatedButton.icon(
            onPressed: provider.canSubmit ? () => _submit(provider) : null,
            icon:
                provider.submitting
                    ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Icon(Icons.inventory_2_outlined),
            label: Text(
              provider.submitting ? 'IMPORTING...' : 'IMPORT',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        );
        final exportButton = ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: ElevatedButton.icon(
            key: const ValueKey<String>('inventory_export_button'),
            onPressed: provider.canExport ? () => _exportTray(provider) : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade800,
              foregroundColor: Colors.white,
            ),
            icon:
                provider.exporting
                    ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Icon(Icons.outbox_outlined),
            label: Text(
              provider.exporting ? 'EXPORTING...' : 'EXPORT',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        );

        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              importButton,
              const SizedBox(height: 12),
              exportButton,
            ],
          );
        }
        return Row(
          children: <Widget>[
            Expanded(child: importButton),
            const SizedBox(width: 12),
            Expanded(child: exportButton),
          ],
        );
      },
    );
  }

  Widget _buildStockTypeSelector(InventoryImportProvider provider) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final type in StockType.values)
          ChoiceChip(
            label: Text(type.displayName),
            selected: provider.stockType == type,
            onSelected:
                provider.busy
                    ? null
                    : (selected) {
                      if (selected) {
                        provider.selectStockType(type);
                      }
                    },
          ),
      ],
    );
  }

  Widget _buildLocationSection(InventoryImportProvider provider) {
    final location = provider.location;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        TextField(
          key: const ValueKey<String>('inventory_location_input'),
          controller: _locationController,
          focusNode: _locationFocusNode,
          enabled: !provider.busy,
          keyboardType: TextInputType.text,
          textInputAction: TextInputAction.next,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: const <TextInputFormatter>[
            _UpperCaseTextFormatter(),
          ],
          decoration: InputDecoration(
            hintText:
                provider.stockType == StockType.scrap
                    ? 'A1-2-K3 or CARTON-1'
                    : 'A1-2-K3',
            border: const OutlineInputBorder(),
            errorText:
                provider.hasInvalidLocation
                    ? 'Location format is invalid.'
                    : null,
            suffixIcon: IconButton(
              tooltip: 'Scan location',
              onPressed: provider.busy ? null : _scanLocation,
              icon: const Icon(Icons.qr_code_scanner),
            ),
          ),
          onChanged: provider.updateLocation,
          onTap: _keepSoftwareKeyboardHidden,
          onSubmitted: _handleLocationSubmitted,
        ),
        if (location != null) ...<Widget>[
          const SizedBox(height: 12),
          Text(
            'Normalized: ${location.normalized}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              _LocationValue(label: 'Shelf', value: location.shelf),
              _LocationValue(label: 'Column', value: '${location.column}'),
              _LocationValue(label: 'Level', value: '${location.level}'),
              _LocationValue(label: 'Tray', value: '${location.tray}'),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildTraySection(InventoryImportProvider provider) {
    if (!provider.stockType.supportsTray) {
      return const ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.info_outline),
        title: Text('OK inventory does not use a Tray API.'),
      );
    }
    if (provider.loadingTray) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final tray = provider.trayInfo;
    if (tray == null) {
      return Row(
        children: <Widget>[
          const Expanded(
            child: Text('Enter a complete location to load tray information.'),
          ),
          if (provider.location != null)
            IconButton(
              tooltip: 'Refresh tray',
              onPressed: provider.refreshTray,
              icon: const Icon(Icons.refresh),
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                '${tray.actualOccupiedCount} / ${tray.maxSlots}',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            IconButton(
              tooltip: 'Refresh tray',
              onPressed: provider.refreshTray,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        if (tray.occupiedPositions.isNotEmpty)
          ExpansionTile(
            initiallyExpanded: true,
            tilePadding: EdgeInsets.zero,
            title: Text('Existing SNs (${tray.occupiedPositions.length})'),
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _TraySerialInfoTable(
                  positions: tray.occupiedPositions,
                  serialDetails: provider.serialDetails,
                  lookupErrors: provider.serialLookupErrors,
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildSerialSection(InventoryImportProvider provider) {
    final maxSlots = provider.trayInfo?.maxSlots;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 600;

        final serialInput = TextField(
          key: const ValueKey<String>('inventory_serial_input'),
          controller: _serialController,
          focusNode: _serialFocusNode,
          enabled: !provider.busy,
          minLines: isCompact ? 4 : 7,
          maxLines: isCompact ? 7 : 12,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: const <TextInputFormatter>[
            _UpperCaseTextFormatter(),
          ],
          keyboardType: TextInputType.multiline,
          decoration: InputDecoration(
            labelText: 'Serial Number',
            hintText: 'One SN per line',
            alignLabelWithHint: true,
            contentPadding: const EdgeInsets.fromLTRB(14, 16, 8, 14),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            suffixIcon: IconButton(
              tooltip: 'Scan Serial Number',
              onPressed: provider.busy ? null : _scanSerial,
              icon: const Icon(Icons.qr_code_scanner),
            ),
          ),
          onChanged: provider.updateSerialInput,
          onTap: _keepSoftwareKeyboardHidden,
        );

        final serialTable = _SerialInfoTable(
          serialNumbers: provider.serialNumbers,
          serialDetails: provider.serialDetails,
          lookupErrors: provider.serialLookupErrors,
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (isCompact) ...[
              serialInput,
              const SizedBox(height: 14),
              serialTable,
            ] else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(flex: 5, child: serialInput),
                  const SizedBox(width: 16),
                  Expanded(flex: 7, child: serialTable),
                ],
              ),

            const SizedBox(height: 14),

            // Summary
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Wrap(
                spacing: 20,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  _SerialSummaryItem(
                    icon: Icons.format_list_numbered,
                    label: 'Entered SN',
                    value: '${provider.serialNumbers.length}',
                  ),
                  if (provider.stockType.supportsTray && maxSlots != null)
                    _SerialSummaryItem(
                      icon:
                          provider.isOverCapacity
                              ? Icons.warning_amber_rounded
                              : Icons.inventory_2_outlined,
                      label: 'After import',
                      value: '${provider.capacityAfterImport} / $maxSlots',
                      error: provider.isOverCapacity,
                    ),
                ],
              ),
            ),

            if (provider.duplicateSerials.isNotEmpty)
              _ValidationMessage(
                text:
                    'Duplicate input: ${provider.duplicateSerials.join(', ')}',
              ),

            if (provider.trayDuplicateSerials.isNotEmpty)
              _ValidationMessage(
                text:
                    'Already stored in this tray: '
                    '${provider.trayDuplicateSerials.join(', ')}',
              ),

            if (provider.isOverCapacity)
              const _ValidationMessage(
                text: 'Tray is full or exceeds capacity.',
              ),
          ],
        );
      },
    );
  }

  Widget _buildOperationMessages(InventoryImportProvider provider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (provider.operationSummary != null)
          _MessageCard(
            icon: Icons.check_circle_outline,
            color: Colors.green,
            message: provider.operationSummary!,
          ),
        if (provider.error != null)
          _MessageCard(
            icon: Icons.error_outline,
            color: Colors.red,
            message: provider.error!,
          ),
        if (provider.warning != null)
          _MessageCard(
            icon: Icons.warning_amber_rounded,
            color: Colors.orange,
            message: provider.warning!,
          ),
        if (provider.invalidSerials.isNotEmpty)
          _MessageCard(
            icon: Icons.report_gmailerrorred,
            color: Colors.red,
            message:
                'Invalid Serial Numbers:\n'
                '${provider.invalidSerials.join('\n')}',
          ),
        if (provider.failedImportResults.isNotEmpty)
          _MessageCard(
            icon: Icons.replay,
            color: Colors.orange,
            message:
                'Failed:\n${provider.failedImportResults.map((item) {
                  return '${item.serialNumber}: ${item.message}';
                }).join('\n')}',
          ),
      ],
    );
  }
}

class _UpperCaseTextFormatter extends TextInputFormatter {
  const _UpperCaseTextFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _LocationValue extends StatelessWidget {
  final String label;
  final String value;

  const _LocationValue({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: <Widget>[
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _SerialSummaryItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool error;

  const _SerialSummaryItem({
    required this.icon,
    required this.label,
    required this.value,
    this.error = false,
  });

  @override
  Widget build(BuildContext context) {
    final color =
        error
            ? Theme.of(context).colorScheme.error
            : Theme.of(context).colorScheme.onSurfaceVariant;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 8),
        Text('$label: '),
        Text(
          value,
          style: TextStyle(color: color, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}

class _ValidationMessage extends StatelessWidget {
  final String text;

  const _ValidationMessage({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.error_outline, color: Colors.red, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

class _TraySerialInfoTable extends StatelessWidget {
  final List<TrayPosition> positions;
  final Map<String, SerialInfo?> serialDetails;
  final Map<String, String> lookupErrors;

  const _TraySerialInfoTable({
    required this.positions,
    required this.serialDetails,
    required this.lookupErrors,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey<String>('inventory_tray_serial_info_table'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          DecoratedBox(
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
            ),
            child: const IntrinsicHeight(
              child: Row(
                children: <Widget>[
                  _SerialInfoHeaderCell(label: 'Position / SN'),
                  VerticalDivider(width: 1),
                  _SerialInfoHeaderCell(label: 'WIP Group'),
                  VerticalDivider(width: 1),
                  _SerialInfoHeaderCell(label: 'Model Name'),
                ],
              ),
            ),
          ),
          for (var index = 0; index < positions.length; index++) ...[
            _buildDataRow(positions[index]),
            if (index < positions.length - 1)
              Divider(height: 1, color: colorScheme.outlineVariant),
          ],
        ],
      ),
    );
  }

  Widget _buildDataRow(TrayPosition position) {
    final serialNumber = position.serialNumber.trim().toUpperCase();
    final hasResult = serialDetails.containsKey(serialNumber);
    final info = serialDetails[serialNumber];
    final lookupError = lookupErrors[serialNumber];

    return Tooltip(
      message: position.location ?? serialNumber,
      child: IntrinsicHeight(
        key: ValueKey<String>('inventory_tray_serial_info_row_$serialNumber'),
        child: Row(
          children: <Widget>[
            _TrayPositionCell(
              position: position.positionInTray,
              serialNumber: serialNumber,
            ),
            const VerticalDivider(width: 1),
            _SerialInfoValueCell(
              value: hasResult ? info?.wipGroup : null,
              loading: !hasResult && lookupError == null,
              notFound: hasResult && info == null,
              error: lookupError,
            ),
            const VerticalDivider(width: 1),
            _SerialInfoValueCell(
              value: hasResult ? info?.modelName : null,
              loading: !hasResult && lookupError == null,
              notFound: hasResult && info == null,
              error: lookupError,
            ),
          ],
        ),
      ),
    );
  }
}

class _TrayPositionCell extends StatelessWidget {
  final int? position;
  final String serialNumber;

  const _TrayPositionCell({required this.position, required this.serialNumber});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Expanded(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (position != null)
                Text(
                  '#$position',
                  textAlign: TextAlign.center,
                  style: textTheme.labelSmall,
                ),
              Text(
                serialNumber,
                textAlign: TextAlign.center,
                style: textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SerialInfoTable extends StatelessWidget {
  final List<String> serialNumbers;
  final Map<String, SerialInfo?> serialDetails;
  final Map<String, String> lookupErrors;

  const _SerialInfoTable({
    required this.serialNumbers,
    required this.serialDetails,
    required this.lookupErrors,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey<String>('inventory_serial_info_table'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          DecoratedBox(
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
            ),
            child: const IntrinsicHeight(
              child: Row(
                children: <Widget>[
                  _SerialInfoHeaderCell(label: 'WIP Group'),
                  VerticalDivider(width: 1),
                  _SerialInfoHeaderCell(label: 'Model Name'),
                  VerticalDivider(width: 1),
                  _SerialInfoHeaderCell(label: 'Product Line'),
                ],
              ),
            ),
          ),
          if (serialNumbers.isEmpty)
            const SizedBox(
              height: 132,
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'Enter an SN to load information.',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            )
          else
            for (var index = 0; index < serialNumbers.length; index++) ...[
              _buildDataRow(context, serialNumbers[index]),
              if (index < serialNumbers.length - 1)
                Divider(height: 1, color: colorScheme.outlineVariant),
            ],
        ],
      ),
    );
  }

  Widget _buildDataRow(BuildContext context, String serialNumber) {
    final hasResult = serialDetails.containsKey(serialNumber);
    final info = serialDetails[serialNumber];
    final lookupError = lookupErrors[serialNumber];
    return Tooltip(
      message: serialNumber,
      child: IntrinsicHeight(
        key: ValueKey<String>('inventory_serial_info_row_$serialNumber'),
        child: Row(
          children: <Widget>[
            _SerialInfoValueCell(
              value: hasResult ? info?.wipGroup : null,
              loading: !hasResult && lookupError == null,
              notFound: hasResult && info == null,
              error: lookupError,
            ),
            const VerticalDivider(width: 1),
            _SerialInfoValueCell(
              value: hasResult ? info?.modelName : null,
              loading: !hasResult && lookupError == null,
              notFound: hasResult && info == null,
              error: lookupError,
            ),
            const VerticalDivider(width: 1),
            _SerialInfoValueCell(
              value: hasResult ? info?.productLine : null,
              loading: !hasResult && lookupError == null,
              notFound: hasResult && info == null,
              error: lookupError,
            ),
          ],
        ),
      ),
    );
  }
}

class _SerialInfoHeaderCell extends StatelessWidget {
  final String label;

  const _SerialInfoHeaderCell({required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

class _SerialInfoValueCell extends StatelessWidget {
  final String? value;
  final bool loading;
  final bool notFound;
  final String? error;

  const _SerialInfoValueCell({
    required this.value,
    required this.loading,
    required this.notFound,
    this.error,
  });

  @override
  Widget build(BuildContext context) {
    final displayValue =
        error != null
            ? error!
            : loading
            ? 'Loading...'
            : notFound
            ? 'Not found'
            : value ?? '—';
    return Expanded(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: Center(
            child: Text(
              displayValue,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color:
                    error == null ? null : Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  final IconData icon;
  final MaterialColor color;
  final String message;

  const _MessageCard({
    required this.icon,
    required this.color,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, color: color.shade700),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }
}

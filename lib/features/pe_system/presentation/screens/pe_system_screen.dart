import 'dart:async';
import 'package:flutter/foundation.dart';
import '../widgets/business_widgets.dart';
import '../widgets/dashboard_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../providers/code_provider.dart';
import '../models/scan_outcome.dart';
import '../widgets/code_item.dart';
import 'qr_scan_page.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../domain/entities/borrow_repair_result.dart';
import '../widgets/borrow_repair_dialog.dart';

class PESystemScreen extends StatelessWidget {
  const PESystemScreen({super.key});
  @override
  Widget build(BuildContext context) =>
      const DashboardTheme(child: _PESystemBody());
}

class _PESystemBody extends StatefulWidget {
  const _PESystemBody();

  @override
  _PESystemScreenState createState() => _PESystemScreenState();
}

class _PESystemScreenState extends State<_PESystemBody> {
  final TextEditingController _scannedCodeController = TextEditingController();
  final FocusNode _scanInputFocus = FocusNode();
  late AudioPlayer _audioPlayer;
  CodeProvider? _scanProvider;
  String? _lastSubmitted;
  bool _wasBlocked = false;
  int _inputGeneration = 0;

  void _onScanStateChanged() {
    final provider = _scanProvider!;
    final blocked = !provider.canSubmitScan;
    if (_wasBlocked && !blocked && _lastSubmitted != null) {
      final generation = _inputGeneration;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            generation != _inputGeneration ||
            !provider.canSubmitScan ||
            ModalRoute.of(context)?.isCurrent != true ||
            _scannedCodeController.text != _lastSubmitted)
          return;
        _scanInputFocus.requestFocus();
        _scannedCodeController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _scannedCodeController.text.length,
        );
      });
    }
    _wasBlocked = blocked;
  }

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    debugPrint('Initialized _scanInputFocus: ${_scanInputFocus.hashCode}');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final codeProvider = Provider.of<CodeProvider>(context, listen: false);
        _scanProvider = codeProvider;
        codeProvider.addListener(_onScanStateChanged);
        codeProvider.fetchSearchList(); //Lay danh sach tu database

        //hien thi ban phim khi moi load vao he thong
        // Future.delayed(const Duration(milliseconds: 100), () {
        //   FocusScope.of(context).requestFocus(_scanInputFocus);
        //   debugPrint('Initial focus requested for _scanInputFocus');
        // });
      }
    });
  }

  Future<void> _handleScanCode(String code, {bool isFromQR = false}) async {
    final provider = Provider.of<CodeProvider>(context, listen: false);
    if (code.trim().isEmpty) return;
    if (!provider.canSubmitScan) {
      debugPrint(
        'PE scan input ignored: scanner is processing, cooling down, loading, '
        'or blocked by authentication.',
      );
      return;
    }
    debugPrint('PE scan accepted: sn=${code.trim()}, isFromQR=$isFromQR');
    _inputGeneration++;
    _lastSubmitted = code;
    _scannedCodeController.value = TextEditingValue(
      text: code,
      selection: TextSelection(baseOffset: 0, extentOffset: code.length),
    );
    final pending = provider.handleScanCode(code);

    final outcome = await pending;
    if (!mounted || outcome.status == ScanOutcomeStatus.cancelled) return;
    debugPrint('Scan outcome: ${outcome.status}, message: ${outcome.message}');
    _showScanOutcome(outcome);
    if (outcome.isFound) unawaited(_playFoundFeedback());
  }

  void _showScanOutcome(ScanOutcome outcome) {
    final color = switch (outcome.status) {
      ScanOutcomeStatus.found || ScanOutcomeStatus.pendingFound => Colors.green,
      ScanOutcomeStatus.notInList ||
      ScanOutcomeStatus.pendingNotInList => Colors.orange.shade800,
      _ => Colors.red,
    };
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(outcome.message),
          backgroundColor: color,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  Future<void> _playFoundFeedback() async {
    try {
      await _audioPlayer.play(AssetSource('sounds/iphone.mp3'));
      if (mounted && await Vibration.hasVibrator()) {
        await Vibration.vibrate(duration: 150);
      }
    } catch (error) {
      debugPrint('Scan hardware feedback unavailable: $error');
    }
  }

  void _openQRScanner() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (context) => QRScanPage(
              onCodeScanned: (code) {
                if (mounted) {
                  _scannedCodeController.text = code;
                  FocusScope.of(context).unfocus();
                  debugPrint('QR code set to TextField: $code');
                  _handleScanCode(code, isFromQR: true);
                }
              },
            ),
      ),
    );
  }

  void _syncSearchLists() async {
    final provider = Provider.of<CodeProvider>(context, listen: false);
    await provider.fetchSearchList();
    debugPrint('Sync search lists triggered');
  }

  Future<void> _openBorrowDialog() async {
    final provider = context.read<CodeProvider>();
    final selectedListId = provider.selectedSearchListId;
    final eligibleSerials = provider.borrowableSerialNumbers;
    if (kDebugMode) {
      debugPrint(
        '[PE Borrow][FAB] clicked: searchListId=$selectedListId, '
        'foundCount=${provider.foundCount}, '
        'eligibleCount=${eligibleSerials.length}, '
        'serialNumbers=$eligibleSerials',
      );
    }
    final batch = provider.createBorrowBatch();
    if (batch == null) {
      if (kDebugMode) {
        debugPrint(
          '[PE Borrow][FAB] no batch created: isBusy=${provider.isBusy}, '
          'searchListId=$selectedListId, eligibleCount=${eligibleSerials.length}',
        );
      }
      return;
    }
    FocusScope.of(context).unfocus();
    final result = await showDialog<BorrowRepairResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DashboardTheme(child: BorrowRepairDialog(batch: batch)),
    );
    if (!mounted) return;
    if (result != null) {
      if (kDebugMode) {
        debugPrint(
          '[PE Borrow][FAB] dialog completed: '
          'totalBorrowed=${result.totalBorrowed}, '
          'totalNotFound=${result.totalNotFound}, '
          'totalFailed=${result.totalFailed}, '
          'notFoundSerials=${result.notFoundSerials}, '
          'failedSerials=${result.failedSerials}, '
          'warnings=${result.warnings}, '
          'borrowedSerials=${result.borrowed.map((item) => item.serialNumber).toList()}',
        );
      }
      final resultLines = <String>[
        '${bt(context, 'pe_borrowed_count')}: ${result.totalBorrowed}; '
            '${bt(context, 'Not found')}: ${result.totalNotFound}; '
            '${bt(context, 'Failed')}: ${result.totalFailed}',
        if (result.notFoundSerials.isNotEmpty)
          '${bt(context, 'Not found')}: ${result.notFoundSerials.join(', ')}',
        if (result.failedSerials.isNotEmpty)
          '${bt(context, 'Failed')}: ${result.failedSerials.join(', ')}',
        ...result.warnings,
      ];
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(resultLines.join('\n'))));
    } else if (kDebugMode) {
      debugPrint('[PE Borrow][FAB] dialog cancelled');
    }
    // Wait until the dialog is removed before restoring scanner focus.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scanInputFocus.requestFocus();
      _scannedCodeController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _scannedCodeController.text.length,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    watchBusinessLanguage(context);
    final provider = context.watch<CodeProvider>();
    final username = context.watch<AuthProvider>().user?.username.trim() ?? '';
    final canBorrow =
        !provider.isBusy &&
        username.isNotEmpty &&
        provider.borrowableSerialNumbers.isNotEmpty;
    return BusinessPage(
      title: bt(context, 'search'),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: RefreshIndicator(
                    onRefresh: provider.fetchSearchList,
                    child: CustomScrollView(
                      key: const PageStorageKey('search_scroll'),
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        SliverPadding(
                          padding: const EdgeInsets.all(16),
                          sliver: SliverToBoxAdapter(
                            child: BusinessSection(
                              title: bt(context, 'Search lists'),
                              icon: Icons.list_alt,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _buildListSelector(context, provider),
                                  if (provider.searchListTotalPages > 1)
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        IconButton(
                                          tooltip: 'Trang tr\u01b0\u1edbc',
                                          onPressed:
                                              provider.isBusy ||
                                                      provider.searchListPage <=
                                                          1
                                                  ? null
                                                  : () => provider
                                                      .goToSearchListPage(
                                                        provider.searchListPage -
                                                            1,
                                                      ),
                                          icon: const Icon(Icons.chevron_left),
                                        ),
                                        Text(
                                          '${provider.searchListPage}/${provider.searchListTotalPages}',
                                        ),
                                        IconButton(
                                          tooltip: 'Trang sau',
                                          onPressed:
                                              provider.isBusy ||
                                                      provider.searchListPage >=
                                                          provider
                                                              .searchListTotalPages
                                                  ? null
                                                  : () => provider
                                                      .goToSearchListPage(
                                                        provider.searchListPage +
                                                            1,
                                                      ),
                                          icon: const Icon(Icons.chevron_right),
                                        ),
                                      ],
                                    ),
                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      Chip(
                                        avatar: const Icon(
                                          Icons.check_circle_outline,
                                          size: 18,
                                        ),
                                        label: Text(
                                          '${bt(context, 'Found')}: ${provider.foundCount}',
                                        ),
                                      ),
                                      Chip(
                                        label: Text(
                                          '${bt(context, 'Total')}: ${provider.totalCount}',
                                        ),
                                      ),
                                      IconButton.filledTonal(
                                        tooltip: bt(context, 'Sync lists'),
                                        onPressed:
                                            provider.isBusy
                                                ? null
                                                : _syncSearchLists,
                                        icon: const Icon(Icons.sync),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (provider.error != null)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    provider.searchListErrorKey == null
                                        ? provider.error!
                                        : bt(
                                          context,
                                          provider.searchListErrorKey!,
                                        ),
                                  ),
                                  if (provider.canRetrySearchList)
                                    TextButton.icon(
                                      key: const ValueKey('pe_list_retry'),
                                      onPressed:
                                          provider.isBusy
                                              ? null
                                              : provider.retrySearchList,
                                      icon: const Icon(Icons.refresh),
                                      label: Text(bt(context, 'retry')),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        if (provider.isLoadingLocations)
                          const SliverToBoxAdapter(
                            child: LinearProgressIndicator(
                              key: ValueKey('pe_locations_loading'),
                            ),
                          ),
                        if (provider.locationError != null)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(bt(context, 'pe_location_failed')),
                                  TextButton.icon(
                                    key: const ValueKey('pe_locations_retry'),
                                    onPressed:
                                        provider.isSubmittingBorrow
                                            ? null
                                            : provider.refreshLocations,
                                    icon: const Icon(Icons.refresh),
                                    label: Text(bt(context, 'retry')),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        if (provider.isLoading)
                          const SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Center(child: CircularProgressIndicator()),
                            ),
                          )
                        else if (provider.codeList.isEmpty)
                          SliverFillRemaining(
                            hasScrollBody: false,
                            child: BusinessEmptyState(
                              message: bt(context, 'search_empty'),
                            ),
                          )
                        else
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
                            sliver: SliverList.builder(
                              itemCount: provider.codeList.length,
                              itemBuilder:
                                  (context, index) => Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: CodeItem(
                                      code: provider.codeList[index],
                                      borrower: provider.borrowerFor(
                                        provider.codeList[index].serialNumber,
                                      ),
                                      isFound: provider.foundCodes.contains(
                                        provider.codeList[index].serialNumber,
                                      ),
                                    ),
                                  ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: FloatingActionButton(
                    key: const ValueKey('pe_borrow_fab'),
                    heroTag: 'pe_borrow',
                    tooltip: bt(context, 'pe_borrow'),
                    onPressed: canBorrow ? _openBorrowDialog : null,
                    backgroundColor:
                        canBorrow
                            ? DashboardColors.of(context).accent
                            : DashboardColors.of(context).tint,
                    foregroundColor:
                        canBorrow
                            ? Colors.white
                            : DashboardColors.of(context).muted,
                    child: SvgPicture.asset(
                      'assets/logo/fab.svg',
                      width: 28,
                      height: 28,
                      fit: BoxFit.contain,
                      semanticsLabel: 'Borrow scanned serial numbers',
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 280),
                  child: Text(
                    provider.isScanning
                        ? bt(context, 'pe_scan_recording')
                        : provider.isCoolingDown
                        ? bt(context, 'pe_scan_cooldown')
                        : '${bt(context, 'pe_scan_pending')}: ${provider.pendingSyncCount} ${bt(context, 'pe_scan_occurrences')}',
                    key: const ValueKey('scan_sync_status'),
                  ),
                ),
                TextButton(
                  onPressed: provider.isBusy ? null : provider.syncScans,
                  child: Text(bt(context, 'pe_scan_sync')),
                ),
              ],
            ),
          ),
          if (provider.syncWarning != null)
            Text(
              provider.syncWarning!,
              style: const TextStyle(color: Colors.orange),
            ),
          if (provider.syncErrors.isNotEmpty)
            TextButton(
              onPressed:
                  () => showDialog<void>(
                    context: context,
                    builder:
                        (_) => AlertDialog(
                          title: Text(bt(context, 'pe_scan_errors_title')),
                          content: SingleChildScrollView(
                            child: SelectableText(
                              provider.syncErrors.join('\n'),
                            ),
                          ),
                        ),
                  ),
              child: Text(
                '${bt(context, 'pe_scan_errors_count')}: ${provider.syncErrors.length} — ${bt(context, 'pe_scan_errors_view')}',
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              key: const ValueKey('search_serial_input'),
              readOnly: false,
              keyboardType: TextInputType.text,
              autocorrect: false,
              enableSuggestions: false,
              onEditingComplete: () {},
              controller: _scannedCodeController,
              focusNode: _scanInputFocus,
              decoration: InputDecoration(
                hintText: bt(context, 'enter_scan_sn'),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  tooltip: bt(context, 'qrScan'),
                  onPressed: !provider.canSubmitScan ? null : _openQRScanner,
                  icon: const Icon(Icons.qr_code_scanner),
                ),
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: _handleScanCode,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListSelector(BuildContext context, CodeProvider provider) {
    if (provider.isLoading) {
      return const Center(child: LinearProgressIndicator(minHeight: 2));
    }
    if (provider.searchLists.isEmpty) {
      return Text(bt(context, 'No search lists'));
    }

    // Dropdown trong "InputDecorator" Ãƒâ€žÃ¢â‚¬ËœÃƒÂ¡Ã‚Â»Ã†â€™ Ãƒâ€žÃ¢â‚¬ËœÃƒÂ¡Ã‚Â»Ã¢â‚¬Å“ng bÃƒÂ¡Ã‚Â»Ã¢â€žÂ¢ style vÃƒÂ¡Ã‚Â»Ã¢â‚¬Âºi TextField
    return InputDecorator(
      decoration: InputDecoration(
        labelText: bt(context, 'Search lists'),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        filled: true,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          isExpanded: true,
          itemHeight: null,
          value: provider.selectedSearchListIndex,
          hint: Text(bt(context, 'Choose a list')),
          items:
              provider.searchLists.asMap().entries.map((entry) {
                return DropdownMenuItem<int>(
                  value: entry.key,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(entry.value.listName),
                  ),
                );
              }).toList(),
          onChanged:
              provider.isBusy
                  ? null
                  : (value) {
                    if (value != null) {
                      provider.setSelectedSearchListIndex(value);
                    }
                  },
        ),
      ),
    );
  }

  @override
  void dispose() {
    debugPrint('Disposing _scanInputFocus: ${_scanInputFocus.hashCode}');
    _inputGeneration++;
    _scanProvider?.removeListener(_onScanStateChanged);
    _scannedCodeController.dispose();
    _scanInputFocus.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }
}

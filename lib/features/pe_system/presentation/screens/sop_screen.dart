import '../widgets/business_widgets.dart';
import '../widgets/dashboard_theme.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import 'qr_scan_page.dart';

class SopScreen extends StatelessWidget {
  const SopScreen({super.key});
  @override
  Widget build(BuildContext context) => const DashboardTheme(child: _SopBody());
}

class _SopBody extends StatefulWidget {
  const _SopBody();

  @override
  State<_SopBody> createState() => _SopScreenState();
}

class _SopScreenState extends State<_SopBody> {
  late final http.Client _client;
  final TextEditingController _serialController = TextEditingController();
  final TextEditingController _stationController = TextEditingController();
  final FocusNode _serialFocusNode = FocusNode();
  final FocusNode _stationFocusNode = FocusNode();

  Uint8List? _pdfBytes;
  bool _isLoading = false;
  String? _errorMessage;
  List<String> _stationHistory = [];

  static const String _baseUrl =
      'https://pembd-adapter.cns.myfiinet.com/api/Sop/';

  @override
  void initState() {
    super.initState();
    _client = http.Client();
    _loadStationHistory();
  }

  @override
  void dispose() {
    _serialController.dispose();
    _stationController.dispose();
    _serialFocusNode.dispose();
    _stationFocusNode.dispose();
    _client.close();
    super.dispose();
  }

  Future<void> _loadStationHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final savedStations = prefs.getStringList('sop_station_history') ?? [];
    if (!mounted) return;
    setState(() {
      _stationHistory = savedStations;
    });
  }

  Future<void> _saveStationToHistory(String station) async {
    final normalized = station.trim().toUpperCase();
    if (normalized.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final updatedHistory =
        <String>{normalized, ..._stationHistory}.toList()..sort();

    await prefs.setStringList('sop_station_history', updatedHistory);
    if (!mounted) return;
    setState(() {
      _stationHistory = updatedHistory;
      _stationController.text = normalized;
    });
  }

  Future<void> _openStationSelector() async {
    FocusScope.of(context).unfocus();
    if (_stationHistory.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(bt(context, 'stationHistoryEmpty'))),
      );
      return;
    }

    final selectedStation = await showModalBottomSheet<String>(
      context: context,
      builder: (context) {
        final maxHeight = MediaQuery.of(context).size.height * 0.5;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: Column(
              children: [
                ListTile(
                  title: Text(
                    bt(context, 'stationHistoryTitle'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const Divider(height: 1),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _stationHistory.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final station = _stationHistory[index];
                      return ListTile(
                        title: Text(station),
                        onTap: () => Navigator.of(context).pop(station),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (selectedStation != null && selectedStation.isNotEmpty && mounted) {
      setState(() {
        _stationController.text = selectedStation;
      });
    }
  }

  Future<void> _fetchSop(String serialNumber) async {
    if (_isLoading) return;
    final trimmedSerial = serialNumber.trim();
    final trimmedStation = _stationController.text.trim();
    if (trimmedSerial.isEmpty) {
      setState(() {
        _errorMessage = bt(context, 'serialNumberRequired');
        _pdfBytes = null;
      });
      return;
    }

    if (trimmedStation.isEmpty) {
      setState(() {
        _errorMessage = bt(context, 'stationRequired');
        _pdfBytes = null;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _pdfBytes = null;
    });

    try {
      final normalizedStation = trimmedStation.toUpperCase();
      final uri = Uri.parse(
        '$_baseUrl${Uri.encodeComponent(trimmedSerial)}/${Uri.encodeComponent(normalizedStation)}',
      );
      final response = await _client.get(
        uri,
        headers: const {'Accept': 'application/pdf'},
      );

      if (!mounted) return;

      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        final pdfBytes = response.bodyBytes;
        setState(() {
          _pdfBytes = pdfBytes;
        });
        _showPdfFullScreen(pdfBytes, trimmedSerial);
        await _saveStationToHistory(normalizedStation);
      } else if (response.statusCode == 404) {
        setState(() {
          _errorMessage = bt(context, 'sopNotFound');
        });
      } else {
        setState(() {
          _errorMessage =
              '${bt(context, 'sopLoadFailed')} (${response.statusCode})';
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = '${bt(context, 'sopLoadFailed')}: $error';
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showPdfFullScreen(
    Uint8List pdfBytes,
    String serialNumber,
  ) async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (context) => SopPdfViewerPage(
              pdfBytes: pdfBytes,
              serialNumber: serialNumber,
            ),
      ),
    );
  }

  void _openScanner() {
    FocusScope.of(context).unfocus();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (context) => QRScanPage(
              onCodeScanned: (code) {
                _serialController.text = code;
                _fetchSop(code);
              },
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    watchBusinessLanguage(context);
    return BusinessPage(
      title: bt(context, 'sop'),
      body: LayoutBuilder(
        builder:
            (context, constraints) => CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: SliverToBoxAdapter(
                    child: BusinessSection(
                      title: bt(context, 'SOP controls'),
                      icon: Icons.picture_as_pdf_outlined,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(bt(context, 'sopInstruction')),
                          const SizedBox(height: 16),
                          TextField(
                            key: const ValueKey('sop_serial_input'),
                            controller: _serialController,
                            focusNode: _serialFocusNode,
                            enabled: !_isLoading,
                            textInputAction: TextInputAction.next,
                            onSubmitted:
                                (_) => _stationFocusNode.requestFocus(),
                            decoration: InputDecoration(
                              labelText: bt(context, 'serialNumber'),
                              suffixIcon: IconButton(
                                tooltip: bt(context, 'qrScan'),
                                icon: const Icon(Icons.qr_code_scanner),
                                onPressed: _openScanner,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            key: const ValueKey('sop_station_input'),
                            controller: _stationController,
                            focusNode: _stationFocusNode,
                            enabled: !_isLoading,
                            textCapitalization: TextCapitalization.characters,
                            onSubmitted:
                                (_) => _fetchSop(_serialController.text),
                            decoration: InputDecoration(
                              labelText: bt(context, 'station'),
                              suffixIcon: IconButton(
                                tooltip: bt(context, 'selectStation'),
                                icon: const Icon(Icons.history),
                                onPressed:
                                    _stationHistory.isEmpty
                                        ? null
                                        : _openStationSelector,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            key: const ValueKey('sop_view_button'),
                            onPressed:
                                _isLoading
                                    ? null
                                    : () {
                                      FocusScope.of(context).unfocus();
                                      _fetchSop(_serialController.text);
                                    },
                            icon: const Icon(Icons.picture_as_pdf_outlined),
                            label: Text(bt(context, 'viewSop')),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                SliverFillRemaining(
                  hasScrollBody: true,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 240),
                    child: _buildPdfContent(),
                  ),
                ),
              ],
            ),
      ),
    );
  }

  Widget _buildPdfContent() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_errorMessage != null) {
      return BusinessEmptyState(
        message: _errorMessage!,
        error: true,
        icon: Icons.error_outline,
        onRetry: () => _fetchSop(_serialController.text),
      );
    }
    if (_pdfBytes != null) return SfPdfViewer.memory(_pdfBytes!);
    return BusinessEmptyState(
      message: bt(context, 'sopPlaceholder'),
      icon: Icons.picture_as_pdf_outlined,
    );
  }
}

class SopPdfViewerPage extends StatelessWidget {
  const SopPdfViewerPage({
    super.key,
    required this.pdfBytes,
    required this.serialNumber,
  });
  final Uint8List pdfBytes;
  final String serialNumber;
  @override
  Widget build(BuildContext context) => DashboardTheme(
    child: _SopPdfBody(pdfBytes: pdfBytes, serialNumber: serialNumber),
  );
}

class _SopPdfBody extends StatefulWidget {
  const _SopPdfBody({required this.pdfBytes, required this.serialNumber});

  final Uint8List pdfBytes;
  final String serialNumber;

  @override
  State<_SopPdfBody> createState() => _SopPdfViewerPageState();
}

class _SopPdfViewerPageState extends State<_SopPdfBody> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _enterFullScreen();
    });
  }

  Future<void> _enterFullScreen() async {
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    if (mounted) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  Future<void> _exitFullScreen() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  }

  @override
  void dispose() {
    _exitFullScreen();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    watchBusinessLanguage(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Material(
              color: DashboardColors.of(context).surface,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    IconButton(
                      key: const ValueKey('sop_pdf_close'),
                      tooltip: bt(context, 'close'),
                      icon: const Icon(Icons.close),
                      onPressed: () async {
                        await _exitFullScreen();
                        if (context.mounted) Navigator.pop(context);
                      },
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.serialNumber,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.picture_as_pdf_outlined),
                    const SizedBox(width: 8),
                  ],
                ),
              ),
            ),
            Expanded(child: SfPdfViewer.memory(widget.pdfBytes)),
          ],
        ),
      ),
    );
  }
}

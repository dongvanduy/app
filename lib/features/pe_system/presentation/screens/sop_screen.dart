import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/localization/app_localizations.dart';
import 'qr_scan_page.dart';

class SopScreen extends StatefulWidget {
  const SopScreen({super.key});

  @override
  State<SopScreen> createState() => _SopScreenState();
}

class _SopScreenState extends State<SopScreen> {
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
    _client = IOClient(
      HttpClient()
        ..badCertificateCallback =
            (X509Certificate cert, String host, int port) =>
                host == 'pembd-adapter.cns.myfiinet.com',
    );
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
    final updatedHistory = <String>{normalized, ..._stationHistory}.toList()
      ..sort();

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
        SnackBar(
          content:
              Text(AppLocalizations.of(context, 'stationHistoryEmpty')),
        ),
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
                    AppLocalizations.of(context, 'stationHistoryTitle'),
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
    final trimmedSerial = serialNumber.trim();
    final trimmedStation = _stationController.text.trim();
    if (trimmedSerial.isEmpty) {
      setState(() {
        _errorMessage = AppLocalizations.of(context, 'serialNumberRequired');
        _pdfBytes = null;
      });
      return;
    }

    if (trimmedStation.isEmpty) {
      setState(() {
        _errorMessage = AppLocalizations.of(context, 'stationRequired');
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
          _errorMessage = AppLocalizations.of(context, 'sopNotFound');
        });
      } else {
        setState(() {
          _errorMessage =
              '${AppLocalizations.of(context, 'sopLoadFailed')} (${response.statusCode})';
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage =
            '${AppLocalizations.of(context, 'sopLoadFailed')}: $error';
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _showPdfFullScreen(Uint8List pdfBytes, String serialNumber) async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => SopPdfViewerPage(
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
        builder: (context) => QRScanPage(
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
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context, 'sop')),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppLocalizations.of(context, 'sopInstruction'),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _serialController,
                    focusNode: _serialFocusNode,
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) {
                      FocusScope.of(context).requestFocus(_stationFocusNode);
                    },
                    decoration: InputDecoration(
                      labelText:
                          AppLocalizations.of(context, 'serialNumber'),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.qr_code_scanner),
                        color: AppColors.primary,
                        onPressed: _openScanner,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _stationController,
                    textCapitalization: TextCapitalization.characters,
                    focusNode: _stationFocusNode,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _fetchSop(_serialController.text),
                    decoration: InputDecoration(
                      labelText: AppLocalizations.of(context, 'station'),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.history),
                        color: _stationHistory.isEmpty
                            ? Colors.grey
                            : AppColors.primary,
                        onPressed:
                            _stationHistory.isEmpty ? null : _openStationSelector,
                        tooltip:
                            AppLocalizations.of(context, 'selectStation'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isLoading
                          ? null
                          : () {
                              FocusScope.of(context).unfocus();
                              _fetchSop(_serialController.text);
                            },
                      icon: const Icon(Icons.picture_as_pdf),
                      label: Text(AppLocalizations.of(context, 'viewSop')),
                    ),
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _errorMessage!,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Colors.red),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: _buildPdfContent(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPdfContent() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_pdfBytes != null) {
      return SfPdfViewer.memory(_pdfBytes!);
    }

    return Center(
      child: Text(
        AppLocalizations.of(context, 'sopPlaceholder'),
        textAlign: TextAlign.center,
        style: Theme.of(context)
            .textTheme
            .bodyLarge
            ?.copyWith(color: Colors.grey.shade600),
      ),
    );
  }
}

class SopPdfViewerPage extends StatefulWidget {
  const SopPdfViewerPage({
    super.key,
    required this.pdfBytes,
    required this.serialNumber,
  });

  final Uint8List pdfBytes;
  final String serialNumber;

  @override
  State<SopPdfViewerPage> createState() => _SopPdfViewerPageState();
}

class _SopPdfViewerPageState extends State<SopPdfViewerPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _enterFullScreen();
    });
  }

  Future<void> _enterFullScreen() async {
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
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
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: SfPdfViewer.memory(widget.pdfBytes),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () async {
                          await _exitFullScreen();
                          if (mounted) {
                            Navigator.of(context).pop();
                          }
                        },
                      ),
                      Padding(
                        padding: const EdgeInsets.only(right: 12.0),
                        child: Text(
                          widget.serialNumber,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

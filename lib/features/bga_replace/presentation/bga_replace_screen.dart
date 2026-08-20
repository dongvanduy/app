import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:mobile_app/core/error/exceptions.dart';
import 'package:mobile_app/features/bga_replace/data/datasources/bga_replace_api_service.dart';
import 'package:mobile_app/features/bga_replace/data/models/bga_status_model.dart';
import 'package:mobile_app/features/pe_system/presentation/screens/qr_scan_page.dart';

class BgaReplaceScreen extends StatefulWidget {
  const BgaReplaceScreen({super.key});

  @override
  State<BgaReplaceScreen> createState() => _BgaReplaceScreenState();
}

class _BgaReplaceScreenState extends State<BgaReplaceScreen> {
  final TextEditingController _inputController = TextEditingController();
  final BgaReplaceApiService _apiService = BgaReplaceApiService();
  final Map<String, TextEditingController> _remarkControllers = {};
  final Map<String, bool> _updating = {};

  bool _isLoading = false;
  List<BgaStatusModel> _results = [];
  int? _lockedStatus;
  List<String> _lastSuccessfulSerials = [];
  List<String> _serialsBeforeAutoFetch = [];
  List<BgaStatusModel> _resultsBeforeAutoFetch = [];
  int? _lockedStatusBeforeAutoFetch;
  static const int _maxSnPerRequest = 100;

  @override
  void dispose() {
    _inputController.dispose();
    for (final controller in _remarkControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _fetchStatuses({List<String>? sns, bool triggeredByInput = false}) async {
    final serialNumbers = sns ?? _extractSerialNumbers();

    if (_isLoading) {
      return;
    }

    if (serialNumbers.isEmpty) {
      if (!triggeredByInput) {
        _showMessage('Vui lòng nhập ít nhất 1 SerialNumber.');
      }
      if (mounted) {
        setState(() {
          _results = [];
          _lockedStatus = null;
          _resetRemarkControllers();
        });
        _syncStateCaches();
      }
      return;
    }

    if (serialNumbers.length > _maxSnPerRequest) {
      _showMessage('Tối đa $_maxSnPerRequest SerialNumber mỗi lần kiểm tra.');
      return;
    }

    _resultsBeforeAutoFetch = List<BgaStatusModel>.from(_results);
    _serialsBeforeAutoFetch = List<String>.from(_lastSuccessfulSerials);
    _lockedStatusBeforeAutoFetch = _lockedStatus;

    setState(() {
      _isLoading = true;
    });

    try {
      final statuses = await _apiService.fetchStatuses(serialNumbers);
      if (!mounted) return;
      final ordered = _orderStatuses(serialNumbers, statuses);

      int? newLockedStatus = _lockedStatus;
      final firstSn = serialNumbers.isNotEmpty ? serialNumbers.first : null;
      final firstItem = firstSn != null ? _findStatusBySn(ordered, firstSn) : null;

      if (firstItem == null || firstItem.applyTaskStatus == null) {
        if (triggeredByInput) {
          _showMessage('Không đúng trạng thái update');
        }
        newLockedStatus = null;
      } else if (firstItem.applyTaskStatus == 10 || firstItem.applyTaskStatus == 11) {
        newLockedStatus = firstItem.applyTaskStatus;
      } else {
        if (triggeredByInput) {
          _showMessage('Không đúng trạng thái update');
        }
        newLockedStatus = null;
      }

      if (newLockedStatus != null) {
        final mismatched = ordered
            .where((item) => item.applyTaskStatus != null && item.applyTaskStatus != newLockedStatus)
            .toList();
        if (mismatched.isNotEmpty) {
          _showMessage('Không cùng trạng thái cập nhật.');

          final fallbackSerials = _serialsBeforeAutoFetch.isNotEmpty
              ? _serialsBeforeAutoFetch
              : _lastSuccessfulSerials;
          final fallbackResults = _resultsBeforeAutoFetch.isNotEmpty
              ? _resultsBeforeAutoFetch
              : _results;
          final fallbackLocked = _lockedStatusBeforeAutoFetch ?? _lockedStatus;

          if (mounted) {
            setState(() {
              _results = List<BgaStatusModel>.from(fallbackResults);
              _lockedStatus = fallbackLocked;
              _resetRemarkControllers();
            });
            _syncStateCaches();
          }
          _restoreSerialInput(fallbackSerials);
          return;
        }
      }

      setState(() {
        _results = ordered;
        _lockedStatus = newLockedStatus;
        _resetRemarkControllers();
      });
      _syncStateCaches();
    } on ServerException catch (e) {
      _showMessage(e.message);
    } catch (e) {
      _showMessage('Không thể tải trạng thái: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  List<String> _extractSerialNumbers([String? rawText]) {
    final raw = rawText ?? _inputController.text;
    final cleaned = raw
        .split(RegExp(r'[\n,\s]+'))
        .map((sn) => sn.trim())
        .where((sn) => sn.isNotEmpty)
        .map((sn) => sn.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), ''))
        .where((sn) => sn.isNotEmpty)
        .toSet()
        .toList();
    return cleaned;
  }

  void _onInputChanged(String value) {
    final serials = _extractSerialNumbers(value);

    if (serials.isEmpty) {
      if (mounted) {
        setState(() {
          _results = [];
          _lockedStatus = null;
          _resetRemarkControllers();
        });
        _syncStateCaches();
      }
      return;
    }

    if (value.endsWith('\n')) {
      if (_isLoading) {
        return;
      }
      _serialsBeforeAutoFetch = List<String>.from(_lastSuccessfulSerials);
      _resultsBeforeAutoFetch = List<BgaStatusModel>.from(_results);
      _lockedStatusBeforeAutoFetch = _lockedStatus;
      _fetchStatuses(sns: serials, triggeredByInput: true);
    }
  }

  List<BgaStatusModel> _orderStatuses(
    List<String> orderedSerials,
    List<BgaStatusModel> statuses,
  ) {
    final lookup = <String, BgaStatusModel>{};
    for (final item in statuses) {
      lookup[item.sn.toLowerCase()] = item;
    }

    final seen = <String>{};
    final ordered = <BgaStatusModel>[];
    for (final sn in orderedSerials) {
      final key = sn.toLowerCase();
      final match = lookup[key];
      if (match != null) {
        ordered.add(match);
        seen.add(key);
      }
    }

    for (final item in statuses) {
      final key = item.sn.toLowerCase();
      if (!seen.contains(key)) {
        ordered.add(item);
      }
    }

    return ordered;
  }

  BgaStatusModel? _findStatusBySn(List<BgaStatusModel> items, String sn) {
    final target = sn.toLowerCase();
    for (final item in items) {
      if (item.sn.toLowerCase() == target) {
        return item;
      }
    }
    return null;
  }

  void _restoreSerialInput(List<String> sns) {
    final restored = sns.join('\n');
    _inputController
      ..text = restored
      ..selection = TextSelection.fromPosition(
        TextPosition(offset: restored.length),
      );
  }

  void _syncStateCaches() {
    _lastSuccessfulSerials = _results.map((item) => item.sn).toList();
    _serialsBeforeAutoFetch = List<String>.from(_lastSuccessfulSerials);
    _resultsBeforeAutoFetch = List<BgaStatusModel>.from(_results);
    _lockedStatusBeforeAutoFetch = _lockedStatus;
  }

  void _resetRemarkControllers() {
    for (final entry in _remarkControllers.entries) {
      entry.value.dispose();
    }
    _remarkControllers.clear();
    _updating.clear();

    for (final item in _results.where((item) => item.canUpdate)) {
      _remarkControllers[item.sn] = TextEditingController(text: item.remark ?? '');
      _updating[item.sn] = false;
    }
  }

  Future<void> _handleUpdate(BgaStatusModel item) async {
    if (!item.canUpdate || item.applyTaskStatus == null) {
      _showMessage('Trạng thái hiện tại không hỗ trợ cập nhật.');
      return;
    }

    final remarkController = _remarkControllers[item.sn];
    final remark = remarkController?.text.trim() ?? '';
    if (remark.isEmpty) {
      _showMessage('Vui lòng nhập Remark trước khi cập nhật.');
      return;
    }

    final verified = await _requestQrVerification();
    if (!verified) {
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _updating[item.sn] = true;
    });

    try {
      await _apiService.updateStatus(
        sn: item.sn,
        currentStatus: item.applyTaskStatus!,
        remark: remark,
      );
      final refreshed = await _apiService.fetchStatuses([item.sn]);
      if (!mounted) return;
      setState(() {
        final index = _results.indexWhere((element) => element.sn == item.sn);
        if (index != -1 && refreshed.isNotEmpty) {
          _results[index] = refreshed.first;
        }
        _resetRemarkControllers();
      });
      _syncStateCaches();
      _showMessage('Cập nhật trạng thái thành công cho ${item.sn}.', isError: false);
    } on ServerException catch (e) {
      _showMessage(e.message);
    } catch (e) {
      _showMessage('Không thể cập nhật trạng thái: $e');
    } finally {
      if (mounted) {
        setState(() {
          _updating[item.sn] = false;
        });
      }
    }
  }

  Future<bool> _requestQrVerification() async {
    if (!mounted) {
      return false;
    }

    final completer = Completer<String?>();

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => QRScanPage(
          onCodeScanned: (code) {
            if (!completer.isCompleted) {
              completer.complete(code);
            }
          },
        ),
      ),
    );

    if (!completer.isCompleted) {
      completer.complete(null);
    }

    final scannedCode = await completer.future;

    if (scannedCode == null) {
      _showMessage('Xác thực QR không thành công.');
      return false;
    }

    if (scannedCode.trim() != 'duytaocode') {
      _showMessage('QR code không hợp lệ.');
      return false;
    }

    return true;
  }

  void _showMessage(String message, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('BGA Replace'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _buildInputCard(),
              const SizedBox(height: 16),
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: CircularProgressIndicator(),
                ),
              if (!_isLoading && _results.isEmpty)
                const Expanded(
                  child: Center(
                    child: Text('Chưa có dữ liệu!'),
                  ),
                )
              else if (_results.isNotEmpty)
                Expanded(
                  child: _buildResultList(),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInputCard() {
    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            TextField(
              controller: _inputController,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                hintText:
                    'Nhập SerialNumber',
                alignLabelWithHint: true,
                suffixIcon: _isLoading
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : null,
              ),
              maxLines: 3,
              minLines: 2,
              onChanged: _onInputChanged,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultList() {
    return ListView.separated(
      itemCount: _results.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final item = _results[index];
        final isUpdating = _updating[item.sn] ?? false;
        final remarkController = _remarkControllers[item.sn];
        return Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        'SN: ${item.sn}',
                        maxLines: 1,
                        softWrap: false,
                        //overflow: TextOverflow.ellipsis,  // nếu SN dài sẽ thêm "..."
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'Status: ${item.applyTaskStatus ?? '--'}',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.statusLabel,
                          style: TextStyle(fontSize: 10,
                            color: item.canUpdate ? Colors.blueAccent : Colors.grey,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                if (item.message != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      item.message!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                if (item.canUpdate)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: remarkController,
                          maxLength: 50,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            labelText: 'Remark',
                          ),
                        ),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerRight,
                          child: item.applyTaskStatus == 10
                              ? ElevatedButton.icon(
                                  onPressed:
                                      isUpdating ? null : () => _handleUpdate(item),
                                  icon: isUpdating
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.login),
                                  label: const Text('CheckInBarking'),
                                )
                              : item.applyTaskStatus == 11
                                  ? ElevatedButton.icon(
                                      onPressed: isUpdating
                                          ? null
                                          : () => _handleUpdate(item),
                                      icon: isUpdating
                                          ? const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Icon(Icons.logout),
                                      label: const Text('CheckOutBarking'),
                                    )
                                  : const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Chip(
                      label: const Text('Không thể cập nhật'),
                      backgroundColor: Colors.grey.shade200,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

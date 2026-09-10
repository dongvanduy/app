import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../../../../core/error/exceptions.dart';
import '../../domain/entities/export_inventory_request.dart';
import '../../domain/entities/import_inventory_request.dart';
import '../../domain/entities/inventory_location.dart';
import '../../domain/entities/inventory_models.dart';
import '../../domain/entities/stock_type.dart';
import '../../domain/repositories/inventory_repository.dart';
import '../../domain/services/inventory_rules.dart';

class InventoryImportProvider with ChangeNotifier {
  static const int maxConcurrentSerialLookups = 6;
  static const Duration locationDebounce = Duration(milliseconds: 350);
  static const Duration serialLookupDebounce = Duration(milliseconds: 400);

  final InventoryRepository _repository;
  final ListQueue<String> _serialLookupQueue = ListQueue<String>();
  final Set<String> _queuedSerials = <String>{};
  final Map<String, Future<SerialInfo?>> _pendingSerialLookups =
      <String, Future<SerialInfo?>>{};
  final Map<String, SerialInfo?> _serialInfoCache = <String, SerialInfo?>{};
  final Map<String, String> _serialLookupErrors = <String, String>{};

  StockType _stockType = StockType.repair;
  String _locationInput = '';
  InventoryLocation? _location;
  String _serialInput = '';
  List<String> _serialNumbers = const <String>[];
  TrayInfo? _trayInfo;
  Map<String, SerialInfo?> _serialDetails = const <String, SerialInfo?>{};
  Set<String> _duplicateSerials = const <String>{};
  Set<String> _trayDuplicateSerials = const <String>{};
  List<ImportItemResult> _failedImportResults = const <ImportItemResult>[];
  List<String> _invalidSerials = const <String>[];
  bool _loadingTray = false;
  bool _submitting = false;
  bool _exporting = false;
  InventoryExportSelection? _pendingExport;
  String? _error;
  String? _operationSummary;
  String? _warning;
  Timer? _locationTimer;
  Timer? _serialLookupTimer;
  int _trayRequestId = 0;
  bool _disposed = false;

  InventoryImportProvider({required InventoryRepository repository})
    : _repository = repository;

  StockType get stockType => _stockType;
  String get locationInput => _locationInput;
  InventoryLocation? get location => _location;
  String get serialInput => _serialInput;
  List<String> get serialNumbers => List<String>.unmodifiable(_serialNumbers);
  TrayInfo? get trayInfo => _trayInfo;
  Map<String, SerialInfo?> get serialDetails =>
      Map<String, SerialInfo?>.unmodifiable(_serialDetails);
  Map<String, String> get serialLookupErrors =>
      Map<String, String>.unmodifiable(_serialLookupErrors);
  Set<String> get duplicateSerials =>
      Set<String>.unmodifiable(_duplicateSerials);
  Set<String> get trayDuplicateSerials =>
      Set<String>.unmodifiable(_trayDuplicateSerials);
  List<ImportItemResult> get failedImportResults =>
      List<ImportItemResult>.unmodifiable(_failedImportResults);
  List<String> get invalidSerials => List<String>.unmodifiable(_invalidSerials);
  bool get loadingTray => _loadingTray;
  bool get submitting => _submitting;
  bool get exporting => _exporting;
  bool get busy => _submitting || _exporting;
  String? get error => _error;
  String? get operationSummary => _operationSummary;
  String? get warning => _warning;

  bool get loadingSerialDetails {
    return _serialLookupTargets.any(
      (serial) =>
          !_serialInfoCache.containsKey(serial) &&
          !_serialLookupErrors.containsKey(serial),
    );
  }

  int get capacityAfterImport =>
      InventoryValidation.capacityAfterImport(_trayInfo, _serialNumbers.length);

  bool get isOverCapacity =>
      _stockType.supportsTray &&
      InventoryValidation.isOverCapacity(_trayInfo, _serialNumbers.length);

  bool get isTrayFull {
    final tray = _trayInfo;
    return _stockType.supportsTray &&
        tray != null &&
        tray.maxSlots > 0 &&
        tray.actualOccupiedCount >= tray.maxSlots;
  }

  bool get hasInvalidLocation =>
      _locationInput.trim().isNotEmpty && _location == null;

  bool get canSubmit =>
      !busy &&
      _location != null &&
      _serialNumbers.isNotEmpty &&
      _duplicateSerials.isEmpty &&
      _trayDuplicateSerials.isEmpty &&
      !isOverCapacity;

  bool get canExport {
    if (busy || hasInvalidLocation || _duplicateSerials.isNotEmpty) {
      return false;
    }
    if (_serialNumbers.isNotEmpty) return true;
    return !_loadingTray &&
        _stockType.supportsTrayExport &&
        _location != null &&
        (_trayInfo?.occupiedPositions.any(
              (p) => SerialNumberParser.normalize(p.serialNumber).isNotEmpty,
            ) ??
            false);
  }

  InventoryExportSelection? prepareExport() {
    if (busy) return null;
    _pendingExport = null;
    if (!canExport) return null;
    final fromInput = _serialNumbers.isNotEmpty;
    final serials =
        fromInput
            ? List<String>.of(_serialNumbers)
            : _trayInfo!.occupiedPositions
                .map((p) => SerialNumberParser.normalize(p.serialNumber))
                .where((sn) => sn.isNotEmpty)
                .toSet()
                .toList();
    final currentLocation = _location;
    return _pendingExport = InventoryExportSelection(
      stockType: _stockType,
      location: currentLocation,
      fromInput: fromInput,
      request:
          currentLocation == null
              ? ExportInventoryRequest.fromSerialNumbers(serialNumbers: serials)
              : ExportInventoryRequest.fromLocation(
                location: currentLocation,
                serialNumbers: serials,
              ),
    );
  }

  void cancelExport(InventoryExportSelection selection) {
    if (identical(_pendingExport, selection)) _pendingExport = null;
  }

  void selectStockType(StockType value) {
    if (busy || value == _stockType) {
      return;
    }

    _stockType = value;
    _clearOperationMessages();
    _cancelScheduledTrayLoad();
    _location = InventoryLocationParser.parse(_locationInput, _stockType);
    _trayInfo = null;
    _loadingTray = false;
    _syncSerialDetails();
    _recalculateValidation();
    _notify();
    _scheduleTrayLoad();
  }

  void updateLocation(String value) {
    if (busy) {
      return;
    }

    _locationInput = value.toUpperCase();
    _location = InventoryLocationParser.parse(_locationInput, _stockType);
    _clearOperationMessages();
    _cancelScheduledTrayLoad();
    _trayInfo = null;
    _loadingTray = false;
    _syncSerialDetails();
    _recalculateValidation();
    _notify();
    _scheduleTrayLoad();
  }

  Future<void> refreshTray() async {
    final currentLocation = _location;
    if (!_stockType.supportsTray || currentLocation == null || busy) {
      return;
    }

    _cancelScheduledTrayLoad();
    await _loadTray(
      stockType: _stockType,
      location: currentLocation,
      requestId: _trayRequestId,
    );
  }

  void updateSerialInput(String value) {
    if (busy) {
      return;
    }

    _serialInput = value.toUpperCase();
    _serialNumbers = SerialNumberParser.parse(_serialInput);
    _clearOperationMessages();
    _recalculateValidation();
    _syncSerialDetails();
    _serialLookupTimer?.cancel();
    _serialLookupTimer = Timer(serialLookupDebounce, () {
      _enqueueMissingSerialLookups();
      _pumpSerialLookups();
    });
    _notify();
  }

  void appendScannedSerial(String value) {
    final serial = SerialNumberParser.normalize(value);
    if (serial.isEmpty || busy) {
      return;
    }
    final current = _serialInput.trimRight();
    updateSerialInput(current.isEmpty ? serial : '$current\n$serial');
  }

  void clearForm() {
    if (busy) {
      return;
    }

    _cancelScheduledTrayLoad();
    _serialLookupTimer?.cancel();
    _serialLookupTimer = null;
    _pendingExport = null;
    _serialLookupQueue.clear();
    _queuedSerials.clear();
    _locationInput = '';
    _location = null;
    _serialInput = '';
    _serialNumbers = const <String>[];
    _trayInfo = null;
    _serialDetails = const <String, SerialInfo?>{};
    _serialLookupErrors.clear();
    _duplicateSerials = const <String>{};
    _trayDuplicateSerials = const <String>{};
    _loadingTray = false;
    _clearOperationMessages();
    _notify();
  }

  Future<void> submit() async {
    if (busy) {
      return;
    }

    _clearOperationMessages();
    _location = InventoryLocationParser.parse(_locationInput, _stockType);
    _serialNumbers = SerialNumberParser.parse(_serialInput);
    _serialInput = _serialNumbers.join('\n');
    _recalculateValidation();
    _syncSerialDetails();

    final currentLocation = _location;
    if (currentLocation == null) {
      _error = 'Enter a valid location before importing.';
      _notify();
      return;
    }
    if (_serialNumbers.isEmpty) {
      _error = 'Enter at least one Serial Number.';
      _notify();
      return;
    }
    if (_duplicateSerials.isNotEmpty) {
      _error = 'Duplicate Serial Numbers must be removed before importing.';
      _notify();
      return;
    }

    final requestedSerials = List<String>.of(_serialNumbers);
    _submitting = true;
    _cancelScheduledTrayLoad();
    _notify();

    try {
      if (_stockType.supportsTray) {
        await _refreshTrayForSubmit(currentLocation);

        if (_trayDuplicateSerials.isNotEmpty) {
          _error = 'Some Serial Numbers are already stored in this tray.';
          return;
        }
        if (isOverCapacity) {
          _error = 'The tray is full or exceeds capacity.';
          return;
        }
      }

      final request = ImportInventoryRequest.fromLocation(
        location: currentLocation,
        serialNumbers: requestedSerials,
      );
      final result = await _repository.importInventory(_stockType, request);
      final failedResults = result.failedResultsFor(requestedSerials);
      final successfulCount = requestedSerials.length - failedResults.length;

      _failedImportResults = failedResults;
      _invalidSerials = result.invalidSerials;
      _recalculateValidation();
      _syncSerialDetails();
      _operationSummary =
          '${_stockType.displayName} inventory import: '
          '$successfulCount/${requestedSerials.length} SNs imported successfully.';

      if (successfulCount == 0 && !result.success) {
        _error = result.message;
      }

      if (_stockType.supportsTray && successfulCount > 0) {
        try {
          await _refreshTrayAfterOperation(currentLocation);
        } on ServerException catch (error, stackTrace) {
          debugPrint('Inventory tray refresh failed: $error\n$stackTrace');
          _warning =
              'Import completed, but tray information could not be refreshed.';
        }
      }
    } on ServerException catch (error, stackTrace) {
      debugPrint('Inventory import failed: $error\n$stackTrace');
      _invalidSerials = error.invalidSerials;
      _error = _formatServerError(error);
    } catch (error, stackTrace) {
      debugPrint('Unexpected inventory import failure: $error\n$stackTrace');
      _error = 'Inventory import could not be completed.';
    } finally {
      _submitting = false;
      _notify();
    }
  }

  Future<bool> exportTray() async {
    final selection = prepareExport();
    return selection != null && await exportInventory(selection);
  }

  Future<bool> exportInventory(InventoryExportSelection selection) async {
    if (busy || !identical(_pendingExport, selection)) return false;
    _pendingExport = null;
    _clearOperationMessages();
    _exporting = true;
    _cancelScheduledTrayLoad();
    _loadingTray = false;
    _notify();
    try {
      final result = await _repository.exportInventory(
        selection.stockType,
        selection.request,
      );
      if (!result.success) {
        _error = result.message;
        return false;
      }
      _operationSummary = result.message;
      final selectedLocation = selection.location;
      if (selectedLocation != null &&
          selection.stockType.supportsTray &&
          _stockType == selection.stockType &&
          _location?.normalized == selectedLocation.normalized) {
        try {
          await _refreshTrayAfterOperation(selectedLocation);
        } catch (error, stackTrace) {
          debugPrint('Inventory tray refresh failed: $error\n$stackTrace');
          _warning = 'inventory_export_refresh_warning';
        }
      }
      return true;
    } on ServerException catch (error, stackTrace) {
      debugPrint('Inventory export failed: $error\n$stackTrace');
      _invalidSerials = error.invalidSerials;
      _error = _formatServerError(error);
      return false;
    } catch (error, stackTrace) {
      debugPrint('Unexpected inventory export failure: $error\n$stackTrace');
      _error = 'inventory_export_failed';
      return false;
    } finally {
      _exporting = false;
      _notify();
    }
  }

  void clearMessages() {
    _clearOperationMessages();
    _notify();
  }

  void _scheduleTrayLoad() {
    final currentLocation = _location;
    if (!_stockType.supportsTray || currentLocation == null) {
      return;
    }
    final requestId = _trayRequestId;
    final stockType = _stockType;
    _locationTimer = Timer(locationDebounce, () {
      _loadTray(
        stockType: stockType,
        location: currentLocation,
        requestId: requestId,
      );
    });
  }

  Future<void> _loadTray({
    required StockType stockType,
    required InventoryLocation location,
    required int requestId,
  }) async {
    if (!_isCurrentTrayRequest(stockType, location, requestId)) {
      return;
    }

    _loadingTray = true;
    _notify();
    try {
      final tray = await _repository.getTrayInfo(stockType, location);
      if (_isCurrentTrayRequest(stockType, location, requestId)) {
        _trayInfo = tray;
        _error = null;
        _recalculateValidation();
        _syncSerialDetails();
        _startMissingSerialLookups();
      }
    } on ServerException catch (error, stackTrace) {
      debugPrint('Loading inventory tray failed: $error\n$stackTrace');
      if (_isCurrentTrayRequest(stockType, location, requestId)) {
        _trayInfo = null;
        _error = _formatServerError(error);
        _recalculateValidation();
        _syncSerialDetails();
      }
    } catch (error, stackTrace) {
      debugPrint('Unexpected tray loading failure: $error\n$stackTrace');
      if (_isCurrentTrayRequest(stockType, location, requestId)) {
        _trayInfo = null;
        _error = 'Tray information could not be loaded.';
        _recalculateValidation();
        _syncSerialDetails();
      }
    } finally {
      if (_isCurrentTrayRequest(stockType, location, requestId)) {
        _loadingTray = false;
        _notify();
      }
    }
  }

  Future<void> _refreshTrayForSubmit(InventoryLocation location) async {
    final stockType = _stockType;
    final requestId = ++_trayRequestId;
    _loadingTray = true;
    _notify();
    try {
      final tray = await _repository.getTrayInfo(stockType, location);
      if (_isCurrentTrayRequest(stockType, location, requestId)) {
        _trayInfo = tray;
        _recalculateValidation();
        _syncSerialDetails();
        _startMissingSerialLookups();
      }
    } finally {
      if (_isCurrentTrayRequest(stockType, location, requestId)) {
        _loadingTray = false;
        _notify();
      }
    }
  }

  Future<void> _refreshTrayAfterOperation(InventoryLocation location) async {
    final stockType = _stockType;
    final requestId = ++_trayRequestId;
    final tray = await _repository.getTrayInfo(stockType, location);
    if (_isCurrentTrayRequest(stockType, location, requestId)) {
      _trayInfo = tray;
      _recalculateValidation();
      _syncSerialDetails();
      _startMissingSerialLookups();
    }
  }

  bool _isCurrentTrayRequest(
    StockType stockType,
    InventoryLocation location,
    int requestId,
  ) {
    return !_disposed &&
        requestId == _trayRequestId &&
        stockType == _stockType &&
        location.normalized == _location?.normalized;
  }

  void _cancelScheduledTrayLoad() {
    _locationTimer?.cancel();
    _locationTimer = null;
    _trayRequestId++;
  }

  void _recalculateValidation() {
    _duplicateSerials = InventoryValidation.duplicateSerials(_serialNumbers);
    _trayDuplicateSerials =
        _stockType.supportsTray
            ? InventoryValidation.duplicateSerialsInTray(
              _serialNumbers,
              _trayInfo,
            )
            : const <String>{};
  }

  Set<String> get _serialLookupTargets => <String>{
    ..._serialNumbers,
    ...?_trayInfo?.occupiedPositions
        .map((position) => SerialNumberParser.normalize(position.serialNumber))
        .where((serial) => serial.isNotEmpty),
  };

  void _syncSerialDetails() {
    final targets = _serialLookupTargets;
    _serialLookupQueue.removeWhere((serial) => !targets.contains(serial));
    _queuedSerials.retainAll(targets);
    _serialLookupErrors.removeWhere((serial, _) => !targets.contains(serial));
    _serialDetails = <String, SerialInfo?>{
      for (final serial in targets)
        if (_serialInfoCache.containsKey(serial))
          serial: _serialInfoCache[serial],
    };
  }

  void _enqueueMissingSerialLookups() {
    for (final serial in _serialLookupTargets) {
      if (_serialInfoCache.containsKey(serial) ||
          _queuedSerials.contains(serial) ||
          _pendingSerialLookups.containsKey(serial)) {
        continue;
      }
      _serialLookupErrors.remove(serial);
      _serialLookupQueue.add(serial);
      _queuedSerials.add(serial);
    }
  }

  void _startMissingSerialLookups() {
    _enqueueMissingSerialLookups();
    _pumpSerialLookups();
  }

  void _pumpSerialLookups() {
    while (!_disposed &&
        _pendingSerialLookups.length < maxConcurrentSerialLookups &&
        _serialLookupQueue.isNotEmpty) {
      final serial = _serialLookupQueue.removeFirst();
      _queuedSerials.remove(serial);

      final lookup = _repository.getSerialInfo(serial);
      _pendingSerialLookups[serial] = lookup;

      lookup
          .then<void>(
            (info) {
              if (_disposed) {
                return;
              }
              _serialInfoCache[serial] = info;
              _serialLookupErrors.remove(serial);
              _syncSerialDetails();
              _notify();
            },
            onError: (Object error, StackTrace stackTrace) {
              if (_disposed) {
                return;
              }
              debugPrint(
                'Serial info lookup failed for $serial: $error\n$stackTrace',
              );
              _serialLookupErrors[serial] = _formatSerialLookupError(error);
              _notify();
            },
          )
          .whenComplete(() {
            _pendingSerialLookups.remove(serial);
            if (!_disposed) {
              _notify();
              _pumpSerialLookups();
            }
          });
    }
  }

  String _formatSerialLookupError(Object error) {
    if (error is! ServerException) {
      return 'API error';
    }
    if (error.statusCode != null) {
      return 'HTTP ${error.statusCode}';
    }
    return switch (error.kind) {
      ApiFailureKind.network => 'Network error',
      ApiFailureKind.timeout => 'Timeout',
      _ => 'API error',
    };
  }

  String _formatServerError(ServerException error) {
    if (error.invalidSerials.isEmpty) {
      return error.message;
    }
    return '${error.message}\nInvalid Serial Numbers: '
        '${error.invalidSerials.join(', ')}';
  }

  void _clearOperationMessages() {
    _error = null;
    _operationSummary = null;
    _warning = null;
    _failedImportResults = const <ImportItemResult>[];
    _invalidSerials = const <String>[];
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _locationTimer?.cancel();
    _serialLookupTimer?.cancel();
    _pendingExport = null;
    _serialLookupQueue.clear();
    _queuedSerials.clear();
    super.dispose();
  }
}

import 'dart:async';
import '../../data/services/scan_sync_service.dart';
import '../../domain/entities/scan_result.dart';
import '../models/scan_outcome.dart';
import 'dart:io';
import '../../../../core/error/exceptions.dart';
import '../../domain/entities/borrow_repair_result.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../../domain/entities/code_entity.dart';
import '../../domain/entities/search_list_entity.dart';
import '../../domain/usecases/manage_codes_usecase.dart';

/// A fixed batch belongs to one search list and one login session.
class BorrowBatch {
  BorrowBatch._(this.searchListId, List<String> serials, this._session)
    : serialNumbers = List.unmodifiable(serials);

  final String searchListId;
  final List<String> serialNumbers;
  final int _session;
}

class CodeProvider with ChangeNotifier {
  final ManageCodesUseCase useCase;
  final Connectivity connectivity;
  final ScanSyncService? scanSync;
  Timer? _cooldown;
  final Set<String> _appliedReceipts = {};

  List<SearchListEntity> _searchLists = [];
  int _searchListPage = 1;
  int _searchListTotalPages = 0;
  static const int searchListPageSize = 20;
  int get searchListPage => _searchListPage;
  int get searchListTotalPages => _searchListTotalPages;
  List<CodeEntity> _codeList = [];
  List<String> _foundCodes = [];
  List<String> _orderedFoundCodes = [];
  List<String> _recentlyScannedCodes = [];
  bool _isLoading = false;
  String? _error;
  String? _searchListErrorKey;
  String? _retryListId;
  int? _retryPage;
  bool _retryRefreshSelected = false;
  String? get searchListErrorKey => _searchListErrorKey;
  bool get canRetrySearchList =>
      _searchListErrorKey != null &&
      (_retryListId != null || _retryPage != null);
  final _scannedByList = <String, Set<String>>{};
  final _foundAtByList = <String, Map<String, DateTime?>>{};
  final _borrowersByList = <String, Map<String, String>>{};
  final _locationsByList = <String, Map<String, String?>>{};
  final _locationRequests = <String, int>{};
  final _loadingLocations = <String>{};
  final _locationErrors = <String, String>{};
  int _session = 0;
  bool _disposed = false;
  bool _isScanning = false;
  bool get isCoolingDown => _cooldown?.isActive ?? false;
  int get pendingSyncCount => scanSync?.pendingCount ?? 0;
  String? get syncWarning => scanSync?.warning;
  List<String> get syncErrors =>
      scanSync?.rows
          .where((r) => r.state == 'error')
          .map((r) => '${r.sn}: ${r.error}')
          .toList() ??
      [];
  bool _scanAccessBlocked = false;
  bool _isSubmittingBorrow = false;

  bool get isScanning => _isScanning;
  Future<void> syncScans() async => scanSync?.sync(manual: true);
  bool get canSubmitScan =>
      !_disposed &&
      !isBusy &&
      !_scanAccessBlocked &&
      (scanSync?.canRecord ?? true) &&
      _selectedSearchListIndex != null &&
      _searchLists[_selectedSearchListIndex!].hasDetails;
  bool get isSubmittingBorrow => _isSubmittingBorrow;
  bool get isBusy =>
      _isLoading || _isScanning || isCoolingDown || _isSubmittingBorrow;
  String? get selectedSearchListId =>
      _selectedSearchListIndex == null
          ? null
          : _searchLists[_selectedSearchListIndex!].id;
  bool get isLoadingLocations =>
      _loadingLocations.contains(selectedSearchListId);
  String? get locationError => _locationErrors[selectedSearchListId];

  String? borrowerFor(String serialNumber) =>
      _borrowersByList[selectedSearchListId]?[_normalizeSerial(serialNumber)];

  List<String> get borrowableSerialNumbers =>
      _codeList
          .where(
            (item) => item.isFound && borrowerFor(item.serialNumber) == null,
          )
          .map((item) => _normalizeSerial(item.serialNumber))
          .where((sn) => sn.isNotEmpty)
          .toSet()
          .toList();

  bool _isCurrentSession(int session) => !_disposed && session == _session;

  int _selectedIndex = 0;
  int? _selectedSearchListIndex;

  String? _scannedSerialNumber;
  String? _retestResult;
  File? _retestImage;
  bool _isSubmittingRetest = false;
  String? _retestError;
  String _employeeId = 'debug';
  String? _notes;
  String _handOverStatus = 'WAITING_HAND_OVER';

  List<SearchListEntity> get searchLists => _searchLists;
  List<CodeEntity> get codeList => _codeList;
  List<String> get foundCodes => _foundCodes;
  List<String> get recentlyScannedCodes => _recentlyScannedCodes;
  bool get isLoading => _isLoading;
  String? get error => _error;

  int get selectedIndex => _selectedIndex;
  int? get selectedSearchListIndex => _selectedSearchListIndex;

  int get foundCount => _foundCodes.length;
  int get totalCount => _codeList.length;

  String? get scannedSerialNumber => _scannedSerialNumber;
  String? get retestResult => _retestResult;
  File? get retestImage => _retestImage;
  bool get isSubmittingRetest => _isSubmittingRetest;
  String? get retestError => _retestError;
  String get employeeId => _employeeId;
  String? get notes => _notes;
  String get handOverStatus => _handOverStatus;

  CodeProvider({
    required this.useCase,
    required this.connectivity,
    this.scanSync,
  }) {
    scanSync?.addListener(_onSyncChanged);
  }

  void _onSyncChanged() {
    if (_disposed) return;
    for (final row in scanSync!.rows) {
      if (row.result != null && _appliedReceipts.add(row.id)) {
        _applyConfirmed(row.result!);
      }
    }
    notifyListeners();
  }

  void _applyConfirmed(ScanResult result) {
    final listId = result.searchListId.toString();
    final serial = result.serialNumber;
    if (result.isFound) {
      _scannedByList.putIfAbsent(listId, () => {}).add(serial);
      _foundAtByList.putIfAbsent(listId, () => {})[serial] = result.foundAt;
    } else {
      _scannedByList[listId]?.remove(serial);
      _foundAtByList[listId]?.remove(serial);
    }
    _searchLists =
        _searchLists
            .map(
              (list) =>
                  list.id != listId
                      ? list
                      : list.copyWith(
                        items:
                            list.items
                                .map(
                                  (item) =>
                                      item.serialNumber == serial
                                          ? item.copyWith(
                                            isFound: result.isFound,
                                            foundAt: result.foundAt,
                                          )
                                          : item,
                                )
                                .toList(),
                      ),
            )
            .toList();
    _updateCodeList();
    if (selectedSearchListId == listId && result.isFound)
      _promoteFoundCode(serial, result.foundAt);
  }

  Future<bool> _isConnected() async {
    final result = await connectivity.checkConnectivity();
    return result != ConnectivityResult.none;
  }

  void resetSessionState() {
    _session++;
    _searchListErrorKey = null;
    _retryListId = null;
    _retryPage = null;
    _cooldown?.cancel();
    _cooldown = null;
    _appliedReceipts.clear();
    _scanAccessBlocked = false;
    _selectedIndex = 0;
    _searchLists = [];
    _searchListPage = 1;
    _searchListTotalPages = 0;
    _codeList = [];
    _foundCodes = [];
    _orderedFoundCodes = [];
    _recentlyScannedCodes = [];
    _selectedSearchListIndex = null;
    _scannedByList.clear();
    _foundAtByList.clear();
    _borrowersByList.clear();
    _locationsByList.clear();
    _locationRequests.clear();
    _loadingLocations.clear();
    _locationErrors.clear();
    _isLoading = false;
    _isScanning = false;
    _isSubmittingBorrow = false;
    _error = null;
    notifyListeners();
  }

  Future<void> fetchSearchList() =>
      _fetchSearchListPage(_searchListPage, refreshSelected: true);

  Future<void> _fetchSearchListPage(
    int page, {
    bool refreshSelected = false,
  }) async {
    if (isBusy || _disposed) return;
    final session = _session;
    final selectedId = selectedSearchListId;
    _isLoading = true;
    _error = null;
    _searchListErrorKey = null;
    _retryListId = null;
    _retryPage = page;
    _retryRefreshSelected = refreshSelected;
    notifyListeners();
    try {
      final cached = await scanSync?.cachedLists() ?? <SearchListEntity>[];
      if (!_isCurrentSession(session)) return;
      final known = <String, SearchListEntity>{
        for (final list in cached) list.id: list,
        for (final list in _searchLists) list.id: list,
      };
      final connected = await _isConnected();
      if (!_isCurrentSession(session)) return;
      late List<SearchListEntity> pageLists;
      late int totalPages;
      final fresh = <SearchListEntity>[];
      if (connected) {
        final result = await useCase.getSearchListPage(
          page: page,
          pageSize: searchListPageSize,
        );
        if (!_isCurrentSession(session)) return;
        totalPages = result.totalPages;
        pageLists =
            result.lists.map((summary) {
              if (summary.hasDetails) {
                fresh.add(summary);
                return summary;
              }
              final previous = known[summary.id];
              return previous?.hasDetails == true
                  ? summary.copyWith(items: previous!.items, hasDetails: true)
                  : summary;
            }).toList();
        for (final list in pageLists) {
          known[list.id] = list;
        }
        if (refreshSelected &&
            selectedId != null &&
            !fresh.any((list) => list.id == selectedId)) {
          final detail = await useCase.getSearchListDetails(
            int.parse(selectedId),
          );
          if (!_isCurrentSession(session)) return;
          _validateDetails(detail, selectedId);
          fresh.add(detail);
          known[selectedId] = detail;
          pageLists = [
            for (final list in pageLists)
              if (list.id == selectedId) detail else list,
          ];
        }
      } else {
        final ordered =
            known.values.where((list) => list.hasDetails).toList()
              ..sort((a, b) {
                final date = b.createdAt.compareTo(a.createdAt);
                return date != 0
                    ? date
                    : int.parse(b.id).compareTo(int.parse(a.id));
              });
        if (ordered.isEmpty) throw _offlineListError;
        totalPages =
            (ordered.length + searchListPageSize - 1) ~/ searchListPageSize;
        page = page.clamp(1, totalPages);
        pageLists =
            ordered
                .skip((page - 1) * searchListPageSize)
                .take(searchListPageSize)
                .toList();
      }
      if (!_isCurrentSession(session)) return;
      // A full server snapshot is authoritative; cached confirmations must not
      // overwrite changes made to a list on the server.
      for (final list in fresh) {
        _scannedByList.remove(list.id);
        _foundAtByList.remove(list.id);
      }
      final active = selectedId == null ? null : known[selectedId];
      _searchListPage = page;
      _searchListTotalPages = totalPages;
      _replaceSearchLists([
        if (active?.hasDetails == true &&
            !pageLists.any((list) => list.id == active!.id))
          active!,
        ...pageLists,
      ], selectedId);
      if (connected) {
        await scanSync?.cacheLists(known.values.toList());
        if (!_isCurrentSession(session)) return;
        unawaited(scanSync?.sync());
      }
      _retryPage = null;
    } catch (error) {
      if (_isCurrentSession(session)) _setSearchListError(error);
    } finally {
      if (_isCurrentSession(session)) {
        _isLoading = false;
        notifyListeners();
      }
    }
    if (_isCurrentSession(session)) await refreshLocations();
  }

  Future<void> goToSearchListPage(int page) async {
    if (isBusy || page < 1 || page > _searchListTotalPages) return;
    await _fetchSearchListPage(page);
  }

  Future<void> retrySearchList() async {
    if (isBusy || _disposed) return;
    final id = _retryListId;
    if (id != null) {
      final index = _searchLists.indexWhere((list) => list.id == id);
      if (index >= 0) await _loadSelectedList(index);
    } else if (_retryPage != null) {
      await _fetchSearchListPage(
        _retryPage!,
        refreshSelected: _retryRefreshSelected,
      );
    }
  }

  static const _offlineListError = ServerException(
    'Cần có mạng để tải đầy đủ danh sách này trước khi scan.',
    kind: ApiFailureKind.network,
    responseData: {'code': 'SEARCH_LIST_OFFLINE'},
  );

  void _setSearchListError(Object error) {
    _error = error.toString();
    final body = error is ServerException ? error.responseData : null;
    _searchListErrorKey = switch (error) {
      ServerException(statusCode: 401) => 'pe_list_unauthorized',
      ServerException(statusCode: 403) => 'pe_list_forbidden',
      ServerException(statusCode: 404)
          when body is Map && body['code'] == 'SEARCH_LIST_NOT_FOUND' =>
        'pe_list_deleted',
      ServerException(statusCode: 404) => 'pe_list_endpoint_missing',
      ServerException(kind: ApiFailureKind.invalidResponse) =>
        'pe_list_invalid',
      _ when body is Map && body['code'] == 'SEARCH_LIST_OFFLINE' =>
        'pe_list_offline',
      _ => 'pe_list_load_failed',
    };
  }

  static void _validateDetails(SearchListEntity detail, String id) {
    if (detail.id != id || !detail.hasDetails) {
      throw const ServerException(
        'Chi tiết danh sách không hợp lệ.',
        kind: ApiFailureKind.invalidResponse,
      );
    }
  }

  Future<void> refreshLocations() async {
    final listId = selectedSearchListId;
    if (_disposed || listId == null || _isLoading || _isSubmittingBorrow) {
      return;
    }
    final session = _session;
    final request = (_locationRequests[listId] ?? 0) + 1;
    _locationRequests[listId] = request;
    final serials =
        _codeList
            .map((item) => _normalizeSerial(item.serialNumber))
            .where((sn) => sn.isNotEmpty)
            .toSet()
            .toList();
    if (serials.isEmpty) {
      _loadingLocations.remove(listId);
      _locationErrors.remove(listId);
      notifyListeners();
      return;
    }
    _loadingLocations.add(listId);
    _locationErrors.remove(listId);
    notifyListeners();
    bool isCurrent() =>
        _isCurrentSession(session) && _locationRequests[listId] == request;
    try {
      final locations = await useCase.findLocations(serials);
      if (!isCurrent()) return;
      final cache = _locationsByList.putIfAbsent(listId, () => {});
      for (final sn in serials) {
        cache[sn] = locations[sn];
      }
      // Merge into the latest items: a scan may have finished during this request.
      _searchLists = [
        for (final list in _searchLists)
          if (list.id == listId)
            list.copyWith(
              items: [
                for (final item in list.items)
                  if (cache.containsKey(item.serialNumber))
                    item.copyWith(location: cache[item.serialNumber])
                  else
                    item,
              ],
            )
          else
            list,
      ];
      if (selectedSearchListId == listId) _updateCodeList();
    } catch (e) {
      if (isCurrent()) _locationErrors[listId] = e.toString();
    } finally {
      if (isCurrent()) {
        _loadingLocations.remove(listId);
        notifyListeners();
      }
    }
  }

  BorrowBatch? createBorrowBatch() {
    final listId = selectedSearchListId;
    final serials = borrowableSerialNumbers;
    if (isBusy || _disposed || listId == null || serials.isEmpty) return null;
    return BorrowBatch._(listId, serials, _session);
  }

  Future<BorrowRepairResult?> borrowFoundCodes({
    required BorrowBatch batch,
    required String borrower,
  }) async {
    if (!_isCurrentSession(batch._session) ||
        isBusy ||
        selectedSearchListId != batch.searchListId) {
      return null;
    }
    final eligible = borrowableSerialNumbers.toSet();
    final serials = batch.serialNumbers.where(eligible.contains).toList();
    if (serials.isEmpty) return null;
    final normalizedBorrower = borrower.trim();
    if (normalizedBorrower.isEmpty || normalizedBorrower.length > 100)
      return null;
    var refreshAfterBorrow = false;
    _isSubmittingBorrow = true;
    notifyListeners();
    try {
      if (!await _isConnected()) {
        throw const ServerException(
          'Cần có mạng để cho mượn.',
          kind: ApiFailureKind.network,
        );
      }
      if (!_isCurrentSession(batch._session)) return null;
      final result = await useCase.borrowRepair(
        serialNumbers: serials,
        borrower: normalizedBorrower,
      );
      if (!_isCurrentSession(batch._session)) return null;
      final borrowers = _borrowersByList.putIfAbsent(
        batch.searchListId,
        () => {},
      );
      final submitted = serials.toSet();
      for (final item in result.borrowed) {
        final requested = _normalizeSerial(item.requestedSerialNumber ?? item.serialNumber);
        if (submitted.contains(requested)) {
          refreshAfterBorrow = true;
          // This confirmed loan came from a found SN, including API scan history.
          _scannedByList
              .putIfAbsent(batch.searchListId, () => {})
              .add(requested);
          borrowers[requested] =
              item.borrowPerson?.trim().isNotEmpty == true
                  ? item.borrowPerson!.trim()
                  : '';
        }
      }
      return result;
    } catch (_) {
      if (!_isCurrentSession(batch._session)) return null;
      rethrow;
    } finally {
      if (_isCurrentSession(batch._session)) {
        _isSubmittingBorrow = false;
        notifyListeners();
        if (refreshAfterBorrow && selectedSearchListId == batch.searchListId) {
          unawaited(refreshLocations());
        }
      }
    }
  }

  Future<ScanOutcome> handleScanCode(String rawCode) {
    final serialNumber = _normalizeSerial(rawCode);
    if (!canSubmitScan) {
      return Future.value(
        _rejectScan(
          serialNumber,
          _scanAccessBlocked
              ? 'Cần đăng nhập lại hoặc kiểm tra quyền scan. Lượt scan chưa được gửi.'
              : 'Chưa thể nhận scan lúc này. Lượt scan chưa được gửi.',
        ),
      );
    }
    final listId = selectedSearchListId;
    if (listId == null) {
      return Future.value(
        _rejectScan(
          serialNumber,
          'Vui lòng chọn một danh sách trước khi quét!',
        ),
      );
    }
    final searchListId = int.tryParse(listId.trim());
    if (searchListId == null || searchListId <= 0) {
      return Future.value(
        _rejectScan(
          serialNumber,
          'ID danh sách không hợp lệ. Vui lòng đồng bộ lại.',
        ),
      );
    }
    if (serialNumber.isEmpty) {
      return Future.value(
        _rejectScan(serialNumber, 'Serial Number không được để trống.'),
      );
    }
    if (serialNumber.length != 12 && serialNumber.length != 14) {
      return Future.value(
        _rejectScan(
          serialNumber,
          'Serial Number phải có độ dài 12 hoặc 14 ký tự.',
        ),
      );
    }
    _isScanning = true;
    _error = null;
    final session = _session;
    notifyListeners();
    return _recordScan(listId, serialNumber, session);
  }

  ScanOutcome _rejectScan(String serialNumber, String message) {
    _error = message;
    if (!_disposed) notifyListeners();
    return ScanOutcome(
      status: ScanOutcomeStatus.failed,
      serialNumber: serialNumber,
      message: message,
    );
  }

  Future<ScanOutcome> _recordScan(
    String listId,
    String serialNumber,
    int session,
  ) async {
    try {
      ScanResult? result;
      if (scanSync != null) {
        final stored = await scanSync!.record(
          listId: int.parse(listId),
          sn: serialNumber,
          localFound: _codeList.any((i) => i.serialNumber == serialNumber),
        );
        if (!_isCurrentSession(session)) return _cancelledScan(serialNumber);
        result = stored.result;
        if (result == null) {
          final message = stored.error ?? scanSync!.warning;
          if (stored.state == 'error' || scanSync!.accessBlocked) {
            return _rejectScan(
              serialNumber,
              message ?? 'Chưa đồng bộ; cần xử lý lỗi.',
            );
          }
          return ScanOutcome(
            status:
                stored.localFound
                    ? ScanOutcomeStatus.pendingFound
                    : ScanOutcomeStatus.pendingNotInList,
            serialNumber: serialNumber,
            message:
                stored.localFound
                    ? 'Tìm thấy — chờ đồng bộ'
                    : 'Không thuộc danh sách — chờ đồng bộ',
          );
        }
      } else {
        result = await useCase.scanSerialNumber(
          serialNumber,
          searchListId: int.parse(listId),
        );
      }
      if (!_isCurrentSession(session)) return _cancelledScan(serialNumber);
      _applyConfirmed(result);
      return ScanOutcome(
        status:
            result.isFound
                ? ScanOutcomeStatus.found
                : ScanOutcomeStatus.notInList,
        serialNumber: serialNumber,
        result: result,
        message:
            result.isFound
                ? 'SN $serialNumber: Found!'
                : 'Không thuộc danh sách — đã ghi nhận lượt scan',
      );
    } catch (e) {
      if (!_isCurrentSession(session)) return _cancelledScan(serialNumber);
      if (e is ServerException &&
          (e.statusCode == 401 ||
              e.statusCode == 403 ||
              e.kind == ApiFailureKind.unauthorized ||
              e.kind == ApiFailureKind.forbidden)) {
        _scanAccessBlocked = true;
      }
      return _rejectScan(serialNumber, _scanError(e, serialNumber));
    } finally {
      if (_isCurrentSession(session)) {
        _isScanning = false;
        _cooldown = Timer(const Duration(seconds: 2), () {
          if (_isCurrentSession(session)) notifyListeners();
        });
        notifyListeners();
      }
    }
  }

  ScanOutcome _cancelledScan(String serial) => ScanOutcome(
    status: ScanOutcomeStatus.cancelled,
    serialNumber: serial,
    message: '',
  );

  bool _promoteFoundCode(String serialNumber, DateTime? foundAt) {
    final itemIndex = _codeList.indexWhere(
      (item) => item.serialNumber == serialNumber,
    );
    if (itemIndex < 0) return false;
    _recentlyScannedCodes.remove(serialNumber);
    _recentlyScannedCodes.insert(0, serialNumber);
    final scanned = _codeList[itemIndex];
    _codeList = [
      scanned.copyWith(isFound: true, foundAt: foundAt),
      ..._codeList.where((item) => item.serialNumber != serialNumber),
    ];
    _searchLists[_selectedSearchListIndex!] =
        _searchLists[_selectedSearchListIndex!].copyWith(items: _codeList);
    _updateCodeList();
    return true;
  }

  void _replaceSearchLists(List<SearchListEntity> lists, String? selectedId) {
    _searchLists = [
      for (final list in lists)
        list.copyWith(
          items: [
            for (final item in list.items) _mergeServerItem(list.id, item),
          ],
        ),
    ];
    final index = _searchLists.indexWhere((list) => list.id == selectedId);
    _selectedSearchListIndex = index < 0 ? null : index;
    _updateCodeList();
  }

  CodeEntity _mergeServerItem(String listId, CodeEntity item) {
    final serialNumber = _normalizeSerial(item.serialNumber);
    final foundAtCache = _foundAtByList[listId];
    final wasScanned = _scannedByList[listId]?.contains(serialNumber) ?? false;
    return item.copyWith(
      serialNumber: serialNumber,
      isFound: item.isFound || wasScanned,
      foundAt:
          foundAtCache?.containsKey(serialNumber) == true
              ? foundAtCache![serialNumber]
              : item.foundAt,
      location: _locationsByList[listId]?[serialNumber],
    );
  }

  String _scanError(Object error, String serialNumber) {
    if (error is ServerException) {
      final response = error.responseData;
      if (error.statusCode == 404 &&
          response is Map &&
          response['code'] == 'SEARCH_LIST_NOT_FOUND') {
        return 'Danh sách đã chọn không còn tồn tại. Vui lòng đồng bộ lại.';
      }
      return switch (error.kind) {
        ApiFailureKind.unauthorized =>
          'Phiên đăng nhập không hợp lệ. Vui lòng đăng nhập lại.',
        ApiFailureKind.forbidden =>
          'Bạn không có quyền quét SN trong danh sách này.',
        ApiFailureKind.timeout ||
        ApiFailureKind.network ||
        ApiFailureKind.invalidResponse =>
          'Chưa xác nhận được lượt scan $serialNumber. Request có thể đã được ghi; kiểm tra lịch sử trước khi scan lại.',
        _ => error.message,
      };
    }
    return error.toString().replaceFirst('Exception: ', '');
  }

  static String _normalizeSerial(String value) => value.trim().toUpperCase();

  void setSelectedIndex(int index) {
    _selectedIndex = index;
    notifyListeners();
  }

  void setSelectedSearchListIndex(int index) {
    if (isBusy || _disposed || index < 0 || index >= _searchLists.length)
      return;
    final selected = _searchLists[index];
    if (selected.hasDetails) {
      _error = null;
      _searchListErrorKey = null;
      _retryListId = null;
      _retryPage = null;
      _selectedSearchListIndex = index;
      _recentlyScannedCodes = [];
      _updateCodeList();
      unawaited(refreshLocations());
      return;
    }
    unawaited(_loadSelectedList(index));
  }

  Future<void> _loadSelectedList(int index) async {
    final session = _session;
    final requested = _searchLists[index];
    // Lock synchronously, before checking connectivity or awaiting any I/O.
    _isLoading = true;
    _error = null;
    _searchListErrorKey = null;
    _retryListId = requested.id;
    _retryPage = null;
    notifyListeners();
    try {
      final connected = await _isConnected();
      if (!_isCurrentSession(session)) return;
      if (!connected) throw _offlineListError;
      final detail = await useCase.getSearchListDetails(
        int.parse(requested.id),
      );
      if (!_isCurrentSession(session)) return;
      _validateDetails(detail, requested.id);
      final cached = await scanSync?.cachedLists() ?? <SearchListEntity>[];
      if (!_isCurrentSession(session)) return;
      final currentIndex = _searchLists.indexWhere(
        (list) => list.id == requested.id,
      );
      if (currentIndex < 0) return;
      final all = <String, SearchListEntity>{
        for (final list in cached) list.id: list,
        for (final list in _searchLists) list.id: list,
        detail.id: detail,
      };
      await scanSync?.cacheLists(all.values.toList());
      if (!_isCurrentSession(session)) return;
      _scannedByList.remove(detail.id);
      _foundAtByList.remove(detail.id);
      _searchLists[currentIndex] = detail.copyWith(
        items: [
          for (final item in detail.items) _mergeServerItem(detail.id, item),
        ],
      );
      _selectedSearchListIndex = currentIndex;
      _recentlyScannedCodes = [];
      _retryListId = null;
      _updateCodeList();
    } catch (error) {
      if (_isCurrentSession(session)) _setSearchListError(error);
    } finally {
      if (_isCurrentSession(session)) {
        _isLoading = false;
        notifyListeners();
        unawaited(refreshLocations());
      }
    }
  }

  void _updateCodeList() {
    if (_selectedSearchListIndex != null) {
      _codeList = List.of(_searchLists[_selectedSearchListIndex!].items)
        ..sort(_compareCodesByLocation);
      _foundCodes =
          _codeList
              .where((item) => item.isFound)
              .map((item) => item.serialNumber)
              .toSet()
              .toList();
      _orderedFoundCodes = List.of(_foundCodes);
      _codeList = [
        for (final item in _codeList)
          if (item.isFound)
            item.copyWith(
              foundOrder: _orderedFoundCodes.indexOf(item.serialNumber) + 1,
            )
          else
            item,
      ];
    } else {
      _codeList = [];
      _foundCodes = [];
      _orderedFoundCodes = [];
      _recentlyScannedCodes = [];
    }
    notifyListeners();
  }

  static int _compareCodesByLocation(CodeEntity left, CodeEntity right) {
    final leftLocation = left.location?.trim() ?? '';
    final rightLocation = right.location?.trim() ?? '';
    final leftHasLocation = leftLocation.isNotEmpty;
    final rightHasLocation = rightLocation.isNotEmpty;

    if (leftHasLocation != rightHasLocation) return leftHasLocation ? -1 : 1;

    if (leftHasLocation) {
      final locationOrder = _compareNaturally(leftLocation, rightLocation);
      if (locationOrder != 0) return locationOrder;
    }

    final serialOrder = _compareNaturally(
      left.serialNumber,
      right.serialNumber,
    );
    if (serialOrder != 0) return serialOrder;
    return left.id.compareTo(right.id);
  }

  static int _compareNaturally(String left, String right) {
    final pattern = RegExp(r'\d+|\D+');
    final leftParts =
        pattern
            .allMatches(left.trim().toUpperCase())
            .map((match) => match.group(0)!)
            .toList();
    final rightParts =
        pattern
            .allMatches(right.trim().toUpperCase())
            .map((match) => match.group(0)!)
            .toList();
    final sharedLength =
        leftParts.length < rightParts.length
            ? leftParts.length
            : rightParts.length;

    for (var index = 0; index < sharedLength; index++) {
      final leftPart = leftParts[index];
      final rightPart = rightParts[index];
      final leftNumber = BigInt.tryParse(leftPart);
      final rightNumber = BigInt.tryParse(rightPart);
      final partOrder =
          leftNumber != null && rightNumber != null
              ? leftNumber.compareTo(rightNumber)
              : leftPart.compareTo(rightPart);
      if (partOrder != 0) return partOrder;
    }

    final lengthOrder = leftParts.length.compareTo(rightParts.length);
    if (lengthOrder != 0) return lengthOrder;
    return left.compareTo(right);
  }

  @override
  void dispose() {
    scanSync?.removeListener(_onSyncChanged);
    _disposed = true;
    _session++;
    _cooldown?.cancel();
    _cooldown = null;
    _appliedReceipts.clear();
    super.dispose();
  }

  // Thêm phương thức updateScannedSerialNumber

  //===========CHUC NANG RETEST=============

  void updateScannedSerialNumber(String serialNumber) {
    _scannedSerialNumber = serialNumber;
    _retestResult = null;
    _retestImage = null;
    _retestError = null;
    notifyListeners();
  }

  // Chọn trạng thái Pass/Fail
  void setRetestResult(String? result) {
    _retestResult = result;
    notifyListeners();
  }

  // Nhập ghi chú
  void setNotes(String? notes) {
    _notes = notes;
    notifyListeners();
  }

  // Chụp ảnh
  Future<void> pickImage() async {
    try {
      await _requestCameraPermission();
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: ImageSource.camera);

      if (pickedFile != null) {
        _retestImage = File(pickedFile.path);
        notifyListeners();
      }
    } catch (e) {
      _retestError = 'Lỗi khi chụp ảnh: $e';
      notifyListeners();
    }
  }

  // Gửi kết quả Retest lên API
  Future<void> submitRetest() async {
    if (_scannedSerialNumber == null ||
        _retestResult == null ||
        _retestImage == null) {
      print(
        'Validation failed: serialNumber=$_scannedSerialNumber, result=$_retestResult, image=$_retestImage',
      );
      _retestError = 'Vui lòng điền đầy đủ thông tin (mã, trạng thái, và ảnh).';
      notifyListeners();
      return;
    }
    // // Kiểm tra status
    // if (_retestResult != 'Pass' && _retestResult != 'Fail') {
    //   print('Invalid status: $_retestResult');
    //   _retestError = 'Trạng thái chỉ được là "Pass" hoặc "Fail".';
    //   notifyListeners();
    //   return;
    // }

    // Kiểm tra file ảnh
    if (!await _retestImage!.exists()) {
      print('Image file does not exist: ${_retestImage!.path}');
      _retestError = 'File ảnh không tồn tại.';
      notifyListeners();
      return;
    }

    _isSubmittingRetest = true;
    _retestError = null;
    notifyListeners();
    print('Starting submission process...');

    try {
      print(
        'Sending: serialNumber=$_scannedSerialNumber, status=$_retestResult, employeeId=$_employeeId, notes=$_notes, handOverStatus=$_handOverStatus, imagePath=${_retestImage!.path}',
      );
      final client = _createIoClient();
      var request = http.MultipartRequest(
        'POST',
        Uri.parse(
          'https://pembd-adapter.cns.myfiinet.com/api/RetestResult/submit-with-img',
        ),
      );

      request.fields['serialNumber'] = _scannedSerialNumber!;
      request.fields['status'] = _retestResult!;
      request.fields['employeeId'] = _employeeId;
      request.fields['notes'] = _notes ?? '';
      request.fields['handOverStatus'] = _handOverStatus;
      request.files.add(
        await http.MultipartFile.fromPath('image', _retestImage!.path),
      );

      var response = await client
          .send(request)
          .timeout(const Duration(seconds: 60));

      print('API response status: ${response.statusCode}');
      var responseBody = await http.Response.fromStream(response);
      print('API response body: ${responseBody.body}');

      if (response.statusCode == 200) {
        print('Submission successful');
        _scannedSerialNumber = null;
        _retestResult = null;
        _retestImage = null;
        _notes = null;
        _retestError = null;
      } else {
        print('Submission failed with status: ${response.statusCode}');
        _retestError =
            'Lỗi khi gửi kết quả: ${response.statusCode} - ${responseBody.body}';
      }
    } catch (e) {
      print('Error in submitRetest: $e');
      _retestError = 'Lỗi khi gửi kết quả: $e';
    }

    _isSubmittingRetest = false;
    notifyListeners();
    print('submitRetest completed');
  }

  // Lấy kết quả Retest từ API
  Future<Map<String, dynamic>> fetchRetestResult(String serialNumber) async {
    try {
      final client = _createIoClient();
      final response = await client.get(
        Uri.parse(
          'https://pembd-adapter.cns.myfiinet.com/api/RetestResult/get-result/$serialNumber',
        ),
      );

      if (response.statusCode == 200) {
        return {'success': true, 'data': response.body};
      } else {
        return {
          'success': false,
          'error':
              'Failed to fetch result: ${response.statusCode} - ${response.body}',
        };
      }
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  // Thêm phương thức requestCameraPermission (public)
  Future<void> requestCameraPermission() async {
    var status = await Permission.camera.request();
    if (!status.isGranted) {
      throw Exception('Camera permission denied');
    }
  }

  // Phương thức private để gọi trong các hàm khác
  Future<void> _requestCameraPermission() async {
    await requestCameraPermission();
  }

  http.Client _createIoClient() {
    return http.Client();
  }
}

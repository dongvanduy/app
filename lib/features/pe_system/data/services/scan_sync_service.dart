import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/error/exceptions.dart';
import '../../domain/entities/search_list_entity.dart';
import '../../domain/entities/scan_result.dart';
import '../local/scan_store.dart';

typedef UploadScan = Future<ScanResult> Function(StoredScan scan);

/// One durable upload worker, independent of the input's two-second cooldown.
class ScanSyncService extends ChangeNotifier with WidgetsBindingObserver {
  ScanSyncService({required this.store, required this.server,
    required this.upload, required this.supportsSync, required this.isConnected});
  final ScanStore store;
  final String server;
  final UploadScan upload;
  final Future<bool> Function() supportsSync;
  final Future<bool> Function() isConnected;
  String? _partition;
  int _generation = 0;
  bool _disposed = false;
  bool _foreground = true;
  int? _workingGeneration;
  Future<void>? _syncOperation;
  bool _syncAgain = false;
  bool _capable = false;
  bool accessBlocked = false;
  String? warning;
  List<StoredScan> rows = [];
  Timer? _retry;
  int _attempt = 0;
  StreamSubscription<ConnectivityResult>? _connection;
  String? get partition => _partition;
  bool get isSyncing => _workingGeneration == _generation;
  int get pendingCount => rows.where((r) => r.state != 'synced').length;
  bool get canRecord => !_disposed && _partition != null && !accessBlocked;
  bool _current(int generation) => !_disposed && generation == _generation;
  void _log(String message) {
    if (kDebugMode) debugPrint('PE scan sync: $message');
  }

  void observe(Connectivity connectivity) {
    WidgetsBinding.instance.addObserver(this);
    _connection = connectivity.onConnectivityChanged.listen((_) => unawaited(sync()));
  }

  Future<void> bindUser(int? userId) async {
    final generation = ++_generation;
    _retry?.cancel();
    _partition = userId == null ? null : '$server|$userId';
    rows = [];
    warning = null;
    accessBlocked = false;
    _capable = false;
    _attempt = 0;
    notifyListeners();
    if (_partition == null) return;
    try {
      await _refresh(generation);
      if (_current(generation) && await isConnected()) unawaited(sync());
    } catch (_) {
      if (_current(generation)) {
        warning = 'Không đọc được dữ liệu scan trên máy.';
        accessBlocked = true;
        notifyListeners();
      }
    }
  }

  Future<void> _refresh(int generation) async {
    final owner = _partition;
    if (owner == null) return;
    final loaded = await store.scans(owner);
    if (_current(generation)) { rows = loaded; notifyListeners(); }
  }

  Future<List<SearchListEntity>> cachedLists() async {
    final owner = _partition;
    if (owner == null) return [];
    final generation = _generation;
    final lists = await store.loadLists(owner);
    return _current(generation) ? lists : [];
  }

  Future<void> cacheLists(List<SearchListEntity> lists) async {
    final owner = _partition;
    if (owner != null) await store.saveLists(owner, lists);
  }

  Future<StoredScan> record({required int listId, required String sn, required bool localFound}) async {
    if (!canRecord) throw const ServerException('Cần đăng nhập hoặc kiểm tra quyền scan.');
    final generation = _generation;
    final owner = _partition!;
    final backlog = isSyncing || rows.any((r) => r.state == 'pending');
    final scan = StoredScan(id: const Uuid().v4(), listId: listId, sn: sn,
      scannedAt: DateTime.fromMillisecondsSinceEpoch(DateTime.now().millisecondsSinceEpoch, isUtc: true),
      localFound: localFound);
    // If this fails, nothing is sent or reported as recorded.
    await store.insert(owner, scan);
    _log('stored id=${scan.id}, list=$listId, sn=$sn, localFound=$localFound');
    if (!_current(generation)) return scan;
    await _refresh(generation);
    if (!_current(generation)) return scan;
    if (await isConnected()) {
      if (!backlog) {
        await sync();
      } else {
        unawaited(sync());
      }
    } else {
      _log('offline; id=${scan.id} remains pending');
    }
    if (!_current(generation)) return scan;
    return rows.firstWhere((r) => r.id == scan.id, orElse: () => scan);
  }

  Future<void> sync({bool manual = false}) {
    if (_disposed || !_foreground || _partition == null || accessBlocked) {
      return Future.value();
    }
    if (manual) _retry?.cancel();
    if (_retry?.isActive ?? false) return Future.value();
    final active = _syncOperation;
    if (active != null) {
      _syncAgain = true;
      return active;
    }
    final completion = Completer<void>();
    _syncOperation = completion.future;
    unawaited(_runSync(completion));
    return completion.future;
  }

  Future<void> _runSync(Completer<void> completion) async {
    try {
      do {
        _syncAgain = false;
        await _syncImpl();
      } while (_syncAgain && !_disposed && _foreground &&
          _partition != null && !accessBlocked && !(_retry?.isActive ?? false));
    } finally {
      _syncOperation = null;
      completion.complete();
    }
  }

  Future<void> _syncImpl() async {
    final generation = _generation;
    final owner = _partition!;
    _workingGeneration = generation;
    _retry?.cancel();
    notifyListeners();
    try {
      final online = await isConnected();
      if (!online || !_current(generation) || !_foreground) return;
      if (!_capable) {
        final capable = await supportsSync();
        if (!_current(generation)) return;
        if (!capable) {
          warning = 'API chưa hỗ trợ đồng bộ an toàn. Các lượt scan vẫn được giữ trên máy.';
          return;
        }
        _capable = true;
        _log('server capability v1 confirmed');
      }
      while (_current(generation) && _foreground && !accessBlocked) {
        await _refresh(generation);
        if (!_current(generation)) return;
        final pending = rows.where((r) => r.state == 'pending');
        if (pending.isEmpty) break;
        final scan = pending.first;
        try {
          _log('uploading id=${scan.id}, list=${scan.listId}, sn=${scan.sn}');
          final result = await upload(scan);
          if (!_current(generation)) return;
          if (result.clientScanId != scan.id || result.searchListId != scan.listId ||
              result.serialNumber != scan.sn || result.scannedAt != scan.scannedAt) {
            throw const ServerException('Phản hồi đồng bộ không khớp lượt scan.',
              kind: ApiFailureKind.invalidResponse);
          }
          await store.acknowledge(owner, scan, result);
          _log('acknowledged id=${scan.id}, eventId=${result.eventId}, isFound=${result.isFound}');
          if (!_current(generation)) return;
          warning = result.isFound != scan.localFound
            ? 'SN ${scan.sn}: kết quả server khác list đã lưu; đã cập nhật theo server.' : null;
          _attempt = 0;
        } on ServerException catch (e) {
          if (!_current(generation)) return;
          if (_authError(e)) {
            accessBlocked = true;
            warning = e.message;
            _log('authorization blocked id=${scan.id}, status=${e.statusCode}');
            break;
          }
          if (_temporary(e)) {
            warning = 'Chưa đồng bộ: ${e.message}';
            _log('temporary failure id=${scan.id}: ${e.message}');
            _scheduleRetry();
            break;
          }
          await store.fail(owner, scan.id, e.message);
          _log('requires review id=${scan.id}, status=${e.statusCode}: ${e.message}');
          if (!_current(generation)) return;
          warning = 'SN ${scan.sn}: ${e.message}';
        }
      }
    } on ServerException catch (e) {
      if (_current(generation)) {
        warning = e.message;
        if (_authError(e)) accessBlocked = true;
        if (_temporary(e)) _scheduleRetry();
        _log('worker stopped, status=${e.statusCode}, kind=${e.kind}: ${e.message}');
      }
    } catch (error) {
      if (_current(generation)) {
        warning = 'Không thể lưu kết quả đồng bộ. Dữ liệu chờ vẫn được giữ; hãy thử đồng bộ lại.';
        _log('worker stopped unexpectedly: $error');
      }
    } finally {
      if (_workingGeneration == generation) _workingGeneration = null;
      if (_current(generation)) {
        try { await _refresh(generation); } catch (_) { /* Keep last visible state. */ }
        if (_current(generation)) notifyListeners();
      }
    }
  }

  bool _authError(ServerException e) => e.statusCode == 401 || e.statusCode == 403 ||
    e.kind == ApiFailureKind.unauthorized || e.kind == ApiFailureKind.forbidden;
  bool _temporary(ServerException e) => e.kind == ApiFailureKind.network ||
    e.kind == ApiFailureKind.timeout || e.kind == ApiFailureKind.server || (e.statusCode ?? 0) >= 500;
  void _scheduleRetry() {
    const delays = [2, 5, 15, 60];
    final seconds = delays[_attempt.clamp(0, delays.length - 1)];
    _attempt++;
    _retry = Timer(Duration(seconds: seconds), () => unawaited(sync()));
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) { unawaited(sync()); } else { _retry?.cancel(); }
  }
  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _retry?.cancel();
    unawaited(_connection?.cancel());
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

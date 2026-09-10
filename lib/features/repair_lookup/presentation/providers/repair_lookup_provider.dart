import 'package:flutter/foundation.dart';

import '../../../../core/error/exceptions.dart';
import '../../domain/entities/repair_lookup_models.dart';
import '../../domain/repositories/repair_lookup_repository.dart';

enum LookupStatus { idle, loading, success, empty, error }

enum HistoryTab { test, repair }

class LookupSection<T> {
  const LookupSection({this.status = LookupStatus.idle, this.data, this.error});
  final LookupStatus status;
  final T? data;
  final ServerException? error;
}

class RepairLookupProvider extends ChangeNotifier {
  RepairLookupProvider({required this.repository});
  final RepairLookupRepository repository;

  String _sn = '';
  String get sn => _sn;
  int _generation = 0;
  int get generation => _generation;
  bool _disposed = false;
  final _requests = <int>[0, 0, 0];
  HistoryTab _tab = HistoryTab.test;
  HistoryTab get tab => _tab;
  LookupSection<SnInfo> _info = const LookupSection();
  LookupSection<SnInfo> get info => _info;
  LookupSection<HistoryResult<TestHistoryEntry>> _tests = const LookupSection();
  LookupSection<HistoryResult<TestHistoryEntry>> get tests => _tests;
  LookupSection<HistoryResult<RepairHistoryEntry>> _repairs =
      const LookupSection();
  LookupSection<HistoryResult<RepairHistoryEntry>> get repairs => _repairs;

  bool get isLoading => [
    info.status,
    tests.status,
    repairs.status,
  ].contains(LookupStatus.loading);

  void selectTab(HistoryTab value) {
    if (_disposed || value == _tab) return;
    _tab = value;
    notifyListeners();
  }

  Future<void> lookup(String value) async {
    final serial = value.trim();
    if (_disposed || serial.isEmpty || (serial == _sn && isLoading)) return;
    _sn = serial;
    _generation++;
    _info = const LookupSection(status: LookupStatus.loading);
    _tests = const LookupSection(status: LookupStatus.loading);
    _repairs = const LookupSection(status: LookupStatus.loading);
    notifyListeners();
    await Future.wait([_loadInfo(), _loadTests(), _loadRepairs()]);
  }

  Future<void> retryInfo() => _retry(0);
  Future<void> retryTests() => _retry(1);
  Future<void> retryRepairs() => _retry(2);

  Future<void> _retry(int section) async {
    if (_disposed || _sn.isEmpty) return;
    switch (section) {
      case 0:
        if (info.status == LookupStatus.loading) return;
        _info = const LookupSection(status: LookupStatus.loading);
      case 1:
        if (tests.status == LookupStatus.loading) return;
        _tests = const LookupSection(status: LookupStatus.loading);
      case 2:
        if (repairs.status == LookupStatus.loading) return;
        _repairs = const LookupSection(status: LookupStatus.loading);
    }
    notifyListeners();
    await switch (section) {
      0 => _loadInfo(),
      1 => _loadTests(),
      _ => _loadRepairs(),
    };
  }

  Future<void> _loadInfo() =>
      _load<SnInfo>(0, repository.getSnInfo, (value) => _info = value);
  Future<void> _loadTests() => _load<HistoryResult<TestHistoryEntry>>(
    1,
    repository.getTestHistory,
    (value) => _tests = value,
    isEmpty: (value) => value.histories.isEmpty,
  );
  Future<void> _loadRepairs() => _load<HistoryResult<RepairHistoryEntry>>(
    2,
    repository.getRepairHistory,
    (value) => _repairs = value,
    isEmpty: (value) => value.histories.isEmpty,
  );

  Future<void> _load<T>(
    int section,
    Future<T> Function(String) fetch,
    void Function(LookupSection<T>) update, {
    bool Function(T)? isEmpty,
  }) async {
    final generation = _generation;
    final request = ++_requests[section];
    bool current() =>
        !_disposed &&
        generation == _generation &&
        request == _requests[section];
    try {
      final data = await fetch(_sn);
      if (!current()) return;
      update(
        LookupSection(
          status:
              isEmpty?.call(data) == true
                  ? LookupStatus.empty
                  : LookupStatus.success,
          data: data,
        ),
      );
    } catch (error) {
      if (!current()) return;
      update(
        LookupSection(
          status: LookupStatus.error,
          error:
              error is ServerException
                  ? error
                  : const ServerException('lookup_unknown_error'),
        ),
      );
    }
    if (current()) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

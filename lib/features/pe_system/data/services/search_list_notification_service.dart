import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/search_list_entity.dart';
import '../../domain/usecases/manage_codes_usecase.dart';

/// Checks for new lists only while the app is in the foreground.
class SearchListNotificationService with WidgetsBindingObserver {
  SearchListNotificationService({
    required this.useCase,
    required this.server,
    this.onNewLists,
    this.onOpen,
    FlutterLocalNotificationsPlugin? notifications,
    Future<void> Function(int, String, String)? showNotification,
  }) : _notifications = notifications ?? FlutterLocalNotificationsPlugin(),
       _showNotification = showNotification;

  static const interval = Duration(minutes: 5);
  static const _channelId = 'new_search_lists';

  final ManageCodesUseCase useCase;
  final String server;
  final void Function(List<SearchListEntity>)? onNewLists;
  final VoidCallback? onOpen;
  final FlutterLocalNotificationsPlugin _notifications;
  final Future<void> Function(int, String, String)? _showNotification;

  Timer? _timer;
  int? _userId;
  int _generation = 0;
  bool _checking = false;
  bool _initialized = false;
  bool _observing = false;
  bool _foreground = true;

  Future<void> bindUser(int? userId) async {
    _generation++;
    _timer?.cancel();
    _userId = userId;
    if (userId == null) return;

    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
    try {
      if (!_initialized && _showNotification == null) {
        await _notifications.initialize(
          const InitializationSettings(
            android: AndroidInitializationSettings(
              'ic_search_list_notification',
            ),
            iOS: DarwinInitializationSettings(),
          ),
          onDidReceiveNotificationResponse: (_) => onOpen?.call(),
        );
        _initialized = true;
        final launch = await _notifications.getNotificationAppLaunchDetails();
        if (launch?.didNotificationLaunchApp == true) {
          WidgetsBinding.instance.addPostFrameCallback((_) => onOpen?.call());
        }
      }
      if (_showNotification == null) {
        await _notifications
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.requestNotificationsPermission();
      }
    } catch (error) {
      debugPrint('SearchList notification setup failed: $error');
    }
    if (_userId != userId || !_foreground) return;
    _startTimer();
    await checkNow();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => unawaited(checkNow()));
  }

  Future<void> checkNow() async {
    final userId = _userId;
    if (userId == null || !_foreground || _checking) return;
    final generation = _generation;
    _checking = true;
    try {
      final page = await useCase.getSearchListPage(page: 1, pageSize: 20);
      if (_generation != generation || _userId != userId || !_foreground) {
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      final key = 'search_list_seen_${Uri.encodeComponent(server)}_$userId';
      final currentMax = page.lists
          .map((list) => int.tryParse(list.id) ?? 0)
          .fold<int>(0, (max, id) => id > max ? id : max);
      final previousMax = prefs.getInt(key);
      if (previousMax == null) {
        await prefs.setInt(key, currentMax); // First load is the baseline.
        return;
      }
      if (currentMax <= previousMax) return;
      final newLists =
          page.lists
              .where((list) => (int.tryParse(list.id) ?? 0) > previousMax)
              .toList();
      if (_generation != generation || _userId != userId || !_foreground) {
        return;
      }
      await prefs.setInt(key, currentMax);
      if (newLists.isEmpty) return;
      onNewLists?.call(newLists);
      final title =
          newLists.length == 1
              ? 'Danh s\u00e1ch t\u00ecm ki\u1ebfm m\u1edbi'
              : '${newLists.length} danh s\u00e1ch t\u00ecm ki\u1ebfm m\u1edbi';
      final body =
          newLists.length == 1
              ? newLists.first.listName
              : newLists.take(3).map((list) => list.listName).join(', ');
      if (_showNotification case final show?) {
        await show(currentMax, title, body);
      } else {
        await _notifications.show(
          currentMax,
          title,
          body,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              _channelId,
              'Danh s\u00e1ch t\u00ecm ki\u1ebfm m\u1edbi',
              channelDescription:
                  'Th\u00f4ng b\u00e1o khi c\u00f3 SearchList m\u1edbi',
              importance: Importance.high,
              priority: Priority.high,
            ),
          ),
        );
      }
    } catch (error, stackTrace) {
      debugPrint('SearchList notification check failed: $error');
      if (kDebugMode) debugPrintStack(stackTrace: stackTrace);
    } finally {
      _checking = false;
      if (generation != _generation && _userId != null && _foreground) {
        unawaited(checkNow());
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _timer?.cancel();
    } else if (_userId != null) {
      _startTimer();
      unawaited(checkNow());
    }
  }

  void dispose() {
    _generation++;
    _timer?.cancel();
    if (_observing) WidgetsBinding.instance.removeObserver(this);
  }
}

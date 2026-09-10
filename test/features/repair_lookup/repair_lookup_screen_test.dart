import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_app/core/error/exceptions.dart';
import 'package:mobile_app/features/pe_system/presentation/providers/language_provider.dart';
import 'package:mobile_app/features/pe_system/presentation/screens/qr_scan_page.dart';
import 'package:mobile_app/features/repair_lookup/domain/entities/repair_lookup_models.dart';
import 'package:mobile_app/features/repair_lookup/domain/repositories/repair_lookup_repository.dart';
import 'package:mobile_app/features/repair_lookup/presentation/providers/repair_lookup_provider.dart';
import 'package:mobile_app/features/repair_lookup/presentation/screens/repair_lookup_screen.dart';
import 'package:mobile_app/features/repair_lookup/presentation/widgets/history_timeline.dart';

import '../../support/repair_lookup_fixtures.dart';

const _screenshots = bool.fromEnvironment('LOOKUP_SCREENSHOTS');
final _boundary = GlobalKey();
final _scrollFinder = find.descendant(
  of: find.byKey(const ValueKey('lookup-scroll')),
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is Scrollable && widget.axisDirection == AxisDirection.down,
  ),
);

Future<FixtureRepairRepository> mountLookup(
  WidgetTester tester, {
  double width = 390,
  double scale = 1,
  Brightness brightness = Brightness.light,
  FixtureRepairRepository? repository,
  String locale = 'vi',
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final language = LanguageProvider();
  SharedPreferences.setMockInitialValues({'languageCode': locale});
  await language.initialize();
  final repo = repository ?? FixtureRepairRepository();
  addTearDown(language.dispose);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: language),
        Provider<RepairLookupRepository>.value(value: repo),
      ],
      child: MaterialApp(
        theme: ThemeData(
          brightness: brightness,
          fontFamily: _screenshots ? 'LookupPreview' : null,
        ),
        locale: Locale(locale),
        supportedLocales: const [Locale('vi'), Locale('en'), Locale('zh')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder:
            (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: RepaintBoundary(key: _boundary, child: child!),
            ),
        home: Scaffold(body: RepairLookupScreen(onBack: () {})),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

RepairLookupProvider lookupProvider(WidgetTester tester) =>
    tester
        .element(find.byKey(const ValueKey('lookup-scroll')))
        .read<RepairLookupProvider>();

Future<void> search(WidgetTester tester, [String sn = sampleSn]) async {
  await tester.enterText(find.byKey(const ValueKey('lookup-sn-input')), sn);
  await tester.testTextInput.receiveAction(TextInputAction.search);
  await tester.pumpAndSettle();
}

Future<void> reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    350,
    scrollable: _scrollFinder,
    maxScrolls: 100,
  );
  await tester.pumpAndSettle();
}

Future<void> top(WidgetTester tester) async {
  tester
      .widget<CustomScrollView>(find.byKey(const ValueKey('lookup-scroll')))
      .controller!
      .jumpTo(0);
  await tester.pumpAndSettle();
}

Future<void> capture(WidgetTester tester, String name) async {
  if (!_screenshots) return;
  await tester.pumpAndSettle();
  final render =
      _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await render.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory('build/repair_lookup_preview').create(recursive: true);
    await File(
      'build/repair_lookup_preview/$name.png',
    ).writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    if (_screenshots) {
      final loader = FontLoader('LookupPreview');
      final bytes = await File('C:/Windows/Fonts/segoeui.ttf').readAsBytes();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
      await loader.load();
      final icons = FontLoader('MaterialIcons');
      final iconBytes =
          await File(
            'C:/src/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
          ).readAsBytes();
      icons.addFont(Future.value(ByteData.sublistView(iconBytes)));
      await icons.load();
    }
  });

  testWidgets('search validates input and preserves full logs when copied', (
    tester,
  ) async {
    final repo = await mountLookup(tester);
    expect(repo.calls, isEmpty);
    expect(find.byKey(const ValueKey('lookup-found')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('lookup-search')));
    await tester.pumpAndSettle();
    expect(find.text('Vui lòng nhập SN.'), findsOneWidget);
    await search(tester, ' $sampleSn\r\n');
    expect(repo.calls.length, 3);
    expect(find.text('BLOCK-R_ICT'), findsOneWidget);
    expect(find.text('699-9X9OE-0301EBAN'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(find.text('—'), findsWidgets);
    expect(find.byKey(const ValueKey('lookup-found')), findsOneWidget);
    await capture(tester, 'phone-product');
    await reveal(tester, find.byKey(const ValueKey('lookup-details-R002')));
    await tester.tap(find.byKey(const ValueKey('lookup-details-R002')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('lookup-detail-scroll')), findsOneWidget);
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.tap(find.byKey(const ValueKey('lookup-copy')));
    await tester.pumpAndSettle();
    expect(copied, contains('ID: R002'));
    expect(copied, contains('\nName=C1850\n'));
    expect(copied, contains('\nName=C1961\n'));
    expect(copied, contains('RC35'));
    expect(copied, contains('N/A'));
    expect(find.text('Đã sao chép nội dung.'), findsOneWidget);
    await tester.tap(find.byTooltip('Đóng'));
    await tester.pumpAndSettle();
    await top(tester);
    await tester.tap(find.byKey(const ValueKey('lookup-tab-repair')));
    await tester.pumpAndSettle();
    await reveal(tester, find.text('V4100523'));
    expect(find.text('retets fail đúng lỗi chờ FA TIP'), findsOneWidget);
    expect(find.text('06/09/2026 14:45:57 GMT+7'), findsOneWidget);
    expect(repo.calls.length, 3);
    await capture(tester, 'phone-repair');
    expect(tester.takeException(), isNull);
  });

  testWidgets('history tab scroll is retained and a new lookup resets scroll', (
    tester,
  ) async {
    final repo = await mountLookup(tester);
    await search(tester);
    await reveal(tester, find.byKey(const ValueKey('lookup-details-R002')));
    final controller =
        tester
            .widget<CustomScrollView>(
              find.byKey(const ValueKey('lookup-scroll')),
            )
            .controller!;
    final offset = controller.offset;
    final provider = lookupProvider(tester);
    provider.selectTab(HistoryTab.repair);
    await tester.pumpAndSettle();
    expect(controller.offset, 0);
    provider.selectTab(HistoryTab.test);
    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(offset, 1));
    await provider.lookup('NEXT-SN');
    await tester.pumpAndSettle();
    expect(controller.offset, 0);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('lookup-sn-input')))
          .controller!
          .text,
      'NEXT-SN',
    );
    expect(repo.calls.length, 6);
  });

  testWidgets(
    'loading, partial error and retry are separate from empty history',
    (tester) async {
      final pending = Completer<SnInfo>();
      final repo = FixtureRepairRepository();
      repo.onInfo = (_) => pending.future;
      repo.onTests =
          (_) async =>
              throw const ServerException(
                'timeout',
                kind: ApiFailureKind.timeout,
              );
      repo.onRepairs =
          (sn) async => HistoryResult(sn: sn, total: 0, histories: []);
      await mountLookup(tester, repository: repo);
      final provider = lookupProvider(tester);
      final request = provider.lookup(sampleSn);
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      pending.complete(fixtureInfo(sampleSn));
      await request;
      await tester.pumpAndSettle();
      await reveal(
        tester,
        find.text('Yêu cầu quá thời gian chờ. Vui lòng thử lại.'),
      );
      expect(
        find.text('Yêu cầu quá thời gian chờ. Vui lòng thử lại.'),
        findsOneWidget,
      );
      repo.onTests = null;
      await tester.tap(find.text('Thử lại'));
      await tester.pumpAndSettle();
      expect(provider.tests.status, LookupStatus.success);
      expect(repo.calls.length, 4);
      provider.selectTab(HistoryTab.repair);
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Chưa có lịch sử.'));
      expect(find.text('Chưa có lịch sử.'), findsOneWidget);
    },
  );

  testWidgets(
    'camera cancel leaves lookup unchanged and callback runs the lookup',
    (tester) async {
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
        call,
      ) async {
        if (call.method == 'create') {
          final id = (call.arguments as Map)['id'];
          messenger.setMockMethodCallHandler(
            MethodChannel('net.touchcapture.qr.flutterqrplus/qrview_$id'),
            (_) async => null,
          );
          return 1;
        }
        if (call.method == 'resize') {
          final args = call.arguments as Map;
          return {'width': args['width'], 'height': args['height']};
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          SystemChannels.platform_views,
          null,
        ),
      );
      final repo = await mountLookup(tester);
      await tester.tap(find.byKey(const ValueKey('lookup-camera')));
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.byType(QRScanPage))).pop();
      await tester.pumpAndSettle();
      expect(repo.calls, isEmpty);
      await tester.tap(find.byKey(const ValueKey('lookup-camera')));
      await tester.pumpAndSettle();
      final page = tester.widget<QRScanPage>(find.byType(QRScanPage));
      Navigator.of(tester.element(find.byType(QRScanPage))).pop();
      page.onCodeScanned(sampleSn);
      await tester.pumpAndSettle();
      expect(repo.calls, [
        'info:$sampleSn',
        'tests:$sampleSn',
        'repairs:$sampleSn',
      ]);
      expect(find.byType(QRScanPage), findsNothing);
      expect(find.text('BLOCK-R_ICT'), findsOneWidget);
    },
  );

  for (final pair in [
    ('vi', 'Tra cứu sửa chữa'),
    ('en', 'Repair lookup'),
    ('zh', '维修查询'),
  ]) {
    testWidgets(
      'lookup labels follow locale ${pair.$1} and preserve API text',
      (tester) async {
        await mountLookup(tester, locale: pair.$1);
        expect(find.text(pair.$2.toUpperCase()), findsOneWidget);
        await search(tester);
        expect(find.text('BLOCK-R_ICT'), findsOneWidget);
        expect(find.text('699-9X9OE-0301EBAN'), findsOneWidget);
        lookupProvider(tester).selectTab(HistoryTab.repair);
        await tester.pumpAndSettle();
        await reveal(tester, find.text('retets fail đúng lỗi chờ FA TIP'));
        expect(find.text('retets fail đúng lỗi chờ FA TIP'), findsOneWidget);
      },
    );
  }

  testWidgets(
    'many events are built lazily and all reported totals are retained',
    (tester) async {
      final repo = FixtureRepairRepository();
      repo.onTests =
          (sn) async => HistoryResult(
            sn: sn,
            total: 201,
            histories: List.generate(
              200,
              (index) => TestHistoryEntry(
                id: 'R$index',
                testGroup: 'ICT',
                errorDesc: 'Long log\n' * 40,
              ),
            ),
          );
      await mountLookup(tester, width: 1024, repository: repo);
      await search(tester);
      expect(lookupProvider(tester).tests.data!.histories.length, 200);
      expect(find.text('200/201 bản ghi · GMT+7'), findsOneWidget);
      expect(find.byType(HistoryTimelineItem).evaluate().length, lessThan(10));
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [320.0, 390.0, 720.0, 1024.0]) {
    for (final scale in [1.0, 1.5, 2.0]) {
      for (final brightness in Brightness.values) {
        testWidgets('responsive $width / $scale / $brightness', (tester) async {
          await mountLookup(
            tester,
            width: width,
            scale: scale,
            brightness: brightness,
          );
          await search(tester);
          expect(tester.takeException(), isNull);
          await reveal(
            tester,
            find.byKey(const ValueKey('lookup-details-R001')),
          );
          final item =
              tester
                  .widgetList<HistoryTimelineItem>(
                    find.byType(HistoryTimelineItem),
                  )
                  .first;
          expect(item.wide, width - 24 >= 720 && scale <= 1.3);
          expect(tester.takeException(), isNull);
          if (width == 1024 && scale == 1 && brightness == Brightness.light) {
            await capture(tester, 'wide-test');
          }
          lookupProvider(tester).selectTab(HistoryTab.repair);
          await tester.pumpAndSettle();
          await reveal(
            tester,
            find.byKey(const ValueKey('lookup-details-FA001')),
          );
          await tester.tap(find.byKey(const ValueKey('lookup-details-FA001')));
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('lookup-copy')), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
        });
      }
    }
  }
}

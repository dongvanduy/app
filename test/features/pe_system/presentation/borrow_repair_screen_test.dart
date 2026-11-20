import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile_app/core/network/api_client.dart';
import 'package:mobile_app/core/network/auth_token_provider.dart';
import 'package:mobile_app/features/pe_system/data/datasources/remote_datasource.dart';
import 'package:mobile_app/features/pe_system/data/repositories/code_repository_impl.dart';
import 'package:mobile_app/features/pe_system/domain/repositories/code_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_app/core/error/exceptions.dart';
import 'package:mobile_app/features/pe_system/domain/entities/borrow_repair_result.dart';
import 'package:mobile_app/features/pe_system/presentation/screens/pe_system_screen.dart';
import '../../../support/pe_inventory_fixtures.dart';
import 'business_screens_test.dart' show Harness;

class _BorrowTokens implements AuthTokenProvider {
  @override
  String? get accessToken => 'borrow-test-token';
  @override
  Future<String?> refreshAccessToken() async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('vibration'),
          (_) async => false,
        );
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (_) async => 'wifi',
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers.global'),
      (_) async => null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers.global/events'),
      (_) async => null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers'),
      (call) async {
        if (call.method == 'create') {
          final id = (call.arguments as Map)['playerId'];
          messenger.setMockMethodCallHandler(
            MethodChannel('xyz.luan/audioplayers/events/$id'),
            (_) async => null,
          );
        }
        return null;
      },
    );
  });

  Finder key(String value) => find.byKey(ValueKey(value));
  Future<void> tap(WidgetTester tester, String value) async {
    await tester.ensureVisible(key(value));
    await tester.tap(key(value));
    await tester.pumpAndSettle();
  }

  Future<Harness> mount(
    WidgetTester tester,
    CodeRepository repository, {
    double width = 390,
    double scale = 1,
    bool dark = false,
    String locale = 'vi',
  }) async {
    final h = Harness(
      tester,
      codeRepository: repository,
      width: width,
      scale: scale,
      dark: dark,
    );
    await h.auth.initialize();
    await h.language.setLocale(Locale(locale));
    await h.mount(const PESystemScreen());
    h.code.setSelectedSearchListIndex(0);
    await tester.pumpAndSettle();
    addTearDown(h.dispose);
    return h;
  }

  testWidgets(
    'FAB validates borrower, cancels, submits once and shows partial loan status',
    (tester) async {
      final repository = PeTestRepository();
      final h = await mount(tester, repository);
      expect(
        tester.widget<FloatingActionButton>(key('pe_borrow_fab')).onPressed,
        isNull,
      );
      expect(find.text('Location: PE3-4-K4-2'), findsOneWidget);
      expect(h.code.foundCount, 0);
      await h.code.handleScanCode(peSnA);
      await h.code.handleScanCode(peSnB);
      await tester.pumpAndSettle();
      await tap(tester, 'pe_borrow_fab');
      expect(find.text('Số lượng: 2'), findsOneWidget);
      await tap(tester, 'pe_borrow_confirm');
      expect(find.text('Vui lòng nhập tên người mượn.'), findsOneWidget);
      expect(repository.loans, isEmpty);
      await tester.enterText(key('pe_borrower_input'), 'Duy');
      await tap(tester, 'pe_borrow_cancel');
      expect(repository.loans, isEmpty);
      expect(
        tester
            .widget<TextField>(key('search_serial_input'))
            .focusNode!
            .hasFocus,
        isTrue,
      );

      await tap(tester, 'pe_borrow_fab');
      await tester.enterText(key('pe_borrower_input'), '  Duy PE  ');
      repository.borrowCompleter = Completer<BorrowRepairResult>();
      final submit =
          tester.widget<FilledButton>(key('pe_borrow_confirm')).onPressed!;
      submit();
      submit();
      await tester.pump();
      expect(repository.loans, hasLength(1));
      expect(repository.loans.single.borrower, 'Duy PE');
      expect(repository.loans.single.admin, 'TEST001');
      expect(
        tester.widget<TextButton>(key('pe_borrow_cancel')).onPressed,
        isNull,
      );
      expect(
        tester.widget<FilledButton>(key('pe_borrow_confirm')).onPressed,
        isNull,
      );
      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pump();
      expect(key('pe_borrower_input'), findsOneWidget);
      repository.borrowCompleter!.complete(
        peBorrowResult([peSnA], person: 'API Name', notFound: 1),
      );
      await tester.pumpAndSettle();
      expect(find.text('Borrower: API Name'), findsOneWidget);
      expect(find.textContaining('Đã cho mượn: 1;'), findsOneWidget);
      expect(h.code.foundCount, 2);
      expect(h.code.borrowableSerialNumbers, [peSnB]);
      expect(
        tester
            .widget<TextField>(key('search_serial_input'))
            .focusNode!
            .hasFocus,
        isTrue,
      );
      repository.borrowCompleter = null;
      await tap(tester, 'pe_borrow_fab');
      expect(find.text('Số lượng: 1'), findsOneWidget);
      await tester.enterText(key('pe_borrower_input'), 'Second');
      await tap(tester, 'pe_borrow_confirm');
      expect(repository.loans.last.serials, [peSnB]);
      expect(find.text('Borrower: Second'), findsOneWidget);
      expect(
        tester.widget<FloatingActionButton>(key('pe_borrow_fab')).onPressed,
        isNull,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'loan error preserves typed name for manual retry; missing user disables FAB',
    (tester) async {
      final repository = PeTestRepository();
      final h = await mount(tester, repository);
      await h.code.handleScanCode(peSnA);
      await tester.pumpAndSettle();
      await tap(tester, 'pe_borrow_fab');
      await tester.enterText(key('pe_borrower_input'), 'Duy');
      repository.borrowError = const ServerException(
        'Timeout',
        kind: ApiFailureKind.timeout,
      );
      await tap(tester, 'pe_borrow_confirm');
      expect(key('pe_borrow_error'), findsOneWidget);
      expect(
        tester.widget<TextFormField>(key('pe_borrower_input')).controller!.text,
        'Duy',
      );
      expect(h.code.borrowerFor(peSnA), isNull);
      expect(repository.loans, hasLength(1));
      repository.borrowError = null;
      await tap(tester, 'pe_borrow_confirm');
      expect(find.text('Borrower: Duy'), findsOneWidget);
      await h.code.handleScanCode(peSnB);
      await h.auth.logout();
      await tester.pumpAndSettle();
      expect(
        tester.widget<FloatingActionButton>(key('pe_borrow_fab')).onPressed,
        isNull,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'failed locations can retry without blocking eligible loans; reopening keeps borrower',
    (tester) async {
      final repository =
          PeTestRepository()
            ..lists = [
              peList('1', [peSnA], found: {peSnA}),
            ]
            ..locationError = const ServerException('offline');
      final h = await mount(tester, repository);
      expect(key('pe_locations_retry'), findsOneWidget);
      expect(
        tester.widget<FloatingActionButton>(key('pe_borrow_fab')).onPressed,
        isNotNull,
      );
      repository.locationError = null;
      await tap(tester, 'pe_locations_retry');
      expect(find.text('Location: PE3-4-K4-2'), findsOneWidget);
      await tap(tester, 'pe_borrow_fab');
      await tester.enterText(key('pe_borrower_input'), 'Duy');
      await tap(tester, 'pe_borrow_confirm');
      await h.mount(const PESystemScreen());
      expect(h.code.selectedSearchListId, '1');
      expect(find.text('Borrower: Duy'), findsOneWidget);
      expect(
        tester.widget<FloatingActionButton>(key('pe_borrow_fab')).onPressed,
        isNull,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'entering a scan confirms found and restores scan/borrow controls after feedback',
    (tester) async {
      final repository = PeTestRepository();
      final h = await mount(tester, repository);
      await tester.enterText(key('search_serial_input'), peSnA);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(repository.scans, [peSnA]);
      expect(find.text('Tìm thấy!'), findsOneWidget);
      expect(h.code.foundCount, 1);
      expect(
        tester.widget<FloatingActionButton>(key('pe_borrow_fab')).onPressed,
        isNull,
      );
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text('Tìm thấy!'), findsNothing);
      expect(
        tester.widget<FloatingActionButton>(key('pe_borrow_fab')).onPressed,
        isNotNull,
      );
      expect(
        tester
            .widget<TextField>(key('search_serial_input'))
            .focusNode!
            .hasFocus,
        isTrue,
      );
      await tap(tester, 'pe_borrow_fab');
      await tap(tester, 'pe_borrow_cancel');
      expect(find.byType(PESystemScreen), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  for (final status in [200, 400]) {
    testWidgets(
      'full HTTP flow sends nonempty JSON and retains Data not empty rejection ($status)',
      (tester) async {
        final requests = <http.Request>[];
        final logs = <String>[];
        final previousDebugPrint = debugPrint;
        debugPrint = (String? message, {int? wrapWidth}) {
          if (message != null) logs.add(message);
        };
        try {
          var reject = true;
          final httpClient = MockClient((request) async {
            switch (request.url.path) {
              case '/api/Scan/search-lists/details':
                return http.Response(
                  jsonEncode({
                    'success': true,
                    'data': {
                      'lists': [
                        {
                          'searchListId': 42,
                          'listName': 'Borrow HTTP test',
                          'createdAt': '2026-09-11T00:00:00',
                          'createdBy': 'TEST001',
                          'items': [
                            {'serialNumber': peSnA, 'isFound': false},
                            {'serialNumber': peSnB, 'isFound': false},
                          ],
                        },
                      ],
                    },
                  }),
                  200,
                );
              case '/api/Inventory/FindLocations':
                return http.Response(
                  jsonEncode({
                    'success': true,
                    'data': [
                      {'serialNumber': peSnA, 'location': 'PE3-4-K4-2'},
                    ],
                  }),
                  200,
                );
              case '/api/Scan/scanSN':
                expect(request.method, 'POST');
                expect(jsonDecode(request.body), {
                  'searchListId': 42,
                  'serialNumber': peSnA,
                });
                return http.Response(
                  jsonEncode({
                    'eventId': 101,
                    'searchListId': 42,
                    'serialNumber': peSnA,
                    'isFound': true,
                    'scannedAt': '2026-09-17T08:05:00+00:00',
                    'scannedBy': 'TEST001',
                    'foundAt': '2026-09-17T08:00:00+00:00',
                  }),
                  200,
                );
              case '/api/Inventory/inventory-borrow-repair':
                requests.add(request);
                return http.Response(
                  jsonEncode(
                    reject
                        ? {'success': false, 'message': 'Data not empty'}
                        : {
                          ...peBorrowFixture,
                          'borrowedResults': [
                            {
                              'serialNumber': peSnA,
                              'borrowStatus': 'Borrowed',
                              'borrowPerson': 'Đỗ Duy',
                            },
                          ],
                        },
                  ),
                  reject ? status : 200,
                  headers: {'content-type': 'application/json; charset=utf-8'},
                );
              default:
                throw StateError('Unexpected request: ${request.url}');
            }
          });
          addTearDown(httpClient.close);
          final repository = CodeRepositoryImpl(
            remoteDataSource: RemoteDataSource(
              apiClient: ApiClient(
                baseUrl: 'https://example.test/api/Scan/',
                client: httpClient,
                authTokenProvider: _BorrowTokens(),
              ),
              inventoryApiClient: ApiClient(
                baseUrl: 'https://example.test/api/',
                client: httpClient,
                authTokenProvider: _BorrowTokens(),
              ),
            ),
          );
          final h = await mount(tester, repository);
          await h.code.handleScanCode(' $peSnA ');
          await tester.pumpAndSettle();
          await tap(tester, 'pe_borrow_fab');
          await tester.enterText(key('pe_borrower_input'), ' Đỗ Duy ');
          await tap(tester, 'pe_borrow_confirm');

          expect(requests, hasLength(1));
          expect(requests.single.method, 'POST');
          expect(
            requests.single.headers['content-type'],
            startsWith('application/json'),
          );
          expect(
            requests.single.headers['authorization'],
            'Bearer borrow-test-token',
          );
          final body = jsonDecode(utf8.decode(requests.single.bodyBytes));
          expect(body, {
            'serialNumbers': [peSnA],
            'borrower': 'Đỗ Duy',
            'admin': 'TEST001',
          });
          expect(find.text('Data not empty'), findsOneWidget);
          expect(h.code.borrowerFor(peSnA), isNull);
          expect(h.code.borrowableSerialNumbers, [peSnA]);
          expect(
            tester
                .widget<TextFormField>(key('pe_borrower_input'))
                .controller!
                .text,
            ' Đỗ Duy ',
          );
          expect(logs, contains('PE borrow body: ${jsonEncode(body)}'));
          expect(
            logs,
            contains(
              '[PE Borrow][FAB] clicked: searchListId=42, foundCount=1, '
              'eligibleCount=1, serialNumbers=[$peSnA]',
            ),
          );
          expect(
            logs,
            contains(
              '[PE Borrow][Confirm] submit: searchListId=42, serialCount=1, '
              'serialNumbers=[$peSnA], borrower=Đỗ Duy, admin=TEST001',
            ),
          );
          expect(logs.join('\n'), contains('[PE Borrow][Confirm] API error:'));
          expect(logs.join('\n'), contains('message=Data not empty'));
          expect(logs.join('\n'), isNot(contains('borrow-test-token')));
          await tester.pump(const Duration(seconds: 5));
          expect(requests, hasLength(1));

          reject = false;
          await tap(tester, 'pe_borrow_confirm');
          expect(requests, hasLength(2));
          expect(find.text('Borrower: Đỗ Duy'), findsOneWidget);
          expect(h.code.borrowableSerialNumbers, isEmpty);
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
        } finally {
          debugPrint = previousDebugPrint;
        }
      },
    );
  }

  for (final dark in [false, true]) {
    for (final locale in ['vi', 'en', 'zh']) {
      testWidgets(
        'borrow layout at 320px / 2x / keyboard / dark=$dark / $locale',
        (tester) async {
          final repository =
              PeTestRepository()
                ..lists = [
                  peList('1', [peSnA], found: {peSnA}),
                ];
          await mount(
            tester,
            repository,
            width: 320,
            scale: 2,
            dark: dark,
            locale: locale,
          );
          final fabRect = tester.getRect(key('pe_borrow_fab'));
          final scanRect = tester.getRect(key('search_serial_input'));
          expect(fabRect.bottom, lessThan(scanRect.top));
          await tap(tester, 'pe_borrow_fab');
          tester.view.viewInsets = FakeViewPadding(bottom: 300);
          addTearDown(tester.view.resetViewInsets);
          await tester.pumpAndSettle();
          await tester.enterText(
            key('pe_borrower_input'),
            'Tên người mượn rất dài / Long borrower name',
          );
          await tester.ensureVisible(key('pe_borrow_confirm'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tap(tester, 'pe_borrow_cancel');
          expect(repository.loans, isEmpty);
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
        },
      );
    }
  }
}

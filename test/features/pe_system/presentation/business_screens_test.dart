import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:mobile_app/features/inventory_import/domain/entities/stock_type.dart';
import 'package:mobile_app/features/inventory_import/presentation/providers/inventory_import_provider.dart';
import 'package:mobile_app/features/inventory_import/presentation/screens/inventory_import_screen.dart';
import 'package:mobile_app/features/pe_system/domain/usecases/manage_codes_usecase.dart';
import 'package:mobile_app/features/pe_system/presentation/providers/code_provider.dart';
import 'package:mobile_app/features/pe_system/presentation/providers/dataCloud_provider.dart';
import 'package:mobile_app/features/pe_system/presentation/providers/language_provider.dart';
import 'package:mobile_app/features/pe_system/presentation/screens/data_cloud_screen.dart';
import 'package:mobile_app/features/pe_system/presentation/screens/pe_system_screen.dart';
import 'package:mobile_app/features/pe_system/presentation/screens/retest_screen.dart';
import 'package:mobile_app/features/pe_system/presentation/screens/sign_in_page.dart';
import 'package:mobile_app/features/pe_system/presentation/screens/sop_screen.dart';
import 'package:mobile_app/features/pe_system/presentation/widgets/dashboard_theme.dart';
import 'package:mobile_app/features/pe_system/presentation/widgets/form_content.dart';
import '../../../support/business_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
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

  for (final width in [320.0, 390.0, 600.0, 900.0, 1200.0]) {
    for (final scale in [1.0, 1.5, 2.0]) {
      for (final dark in [false, true]) {
        testWidgets('business layouts $width / $scale / dark=$dark', (
          tester,
        ) async {
          final h = Harness(tester, width: width, scale: scale, dark: dark);
          for (final locale in ['vi', 'en', 'zh']) {
            await h.language.setLocale(Locale(locale));
            for (final screen in <Widget>[
              const SignInPage(),
              const InventoryImportScreen(),
              const RetestScreen(),
              const SopScreen(),
              const DataCloudScreen(),
              const PESystemScreen(),
            ]) {
              await h.mount(screen);
              if (screen is InventoryImportScreen) {
                h.inventory.updateLocation('A1-2-K3');
                h.inventory.updateSerialInput(
                  'IN-TRAY-1\nSN-012345678901234567890123456789',
                );
                await h.inventory.refreshTray();
                await tester.pumpAndSettle();
              }
              if (screen is PESystemScreen) {
                h.code.setSelectedSearchListIndex(0);
                await tester.pumpAndSettle();
              }
              expect(
                tester.takeException(),
                isNull,
                reason: '${screen.runtimeType} $locale',
              );
              final scaffold = find.byType(Scaffold).last;
              expect(
                Theme.of(tester.element(scaffold)).colorScheme.primary,
                dark ? const Color(0xFF69D8C8) : DashboardColors.teal,
              );
              final scroll = find.byType(Scrollable).first;
              await tester.drag(scroll, const Offset(0, -1800));
              await tester.pumpAndSettle();
              expect(
                tester.takeException(),
                isNull,
                reason: 'scroll ${screen.runtimeType} $locale',
              );
              await tester.pumpWidget(const SizedBox());
              await tester.pumpAndSettle();
            }
          }
          h.dispose();
        });
      }
    }
  }

  testWidgets(
    'SN-only export: separate buttons, confirmation, cancel, success and focus',
    (tester) async {
      final h = Harness(tester);
      await h.mount(const InventoryImportScreen());
      h.inventory.updateSerialInput(' sn1\nSN2 ');
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ElevatedButton>(
              find.byKey(const ValueKey('inventory_import_button')),
            )
            .onPressed,
        isNull,
      );
      await _tap(tester, 'inventory_export_button');
      expect(find.text('Xuất theo danh sách SN'), findsOneWidget);
      expect(find.text('Loại kho: Repair'), findsOneWidget);
      expect(find.text('Số lượng: 2'), findsOneWidget);
      expect(
        tester
            .widget<SelectableText>(
              find.byKey(const ValueKey('inventory_export_serials')),
            )
            .data,
        'SN1\nSN2',
      );
      await _tap(tester, 'inventory_export_cancel_button');
      expect(h.repository.exports, isEmpty);
      expect(h.inventory.serialNumbers, ['SN1', 'SN2']);
      await _tap(tester, 'inventory_export_button');
      await _tap(tester, 'inventory_export_confirm_button');
      expect(h.repository.exports.single.request.toJson(), {
        'SerialNumbers': ['SN1', 'SN2'],
      });
      await _tap(tester, 'inventory_export_result_ok_button');
      expect(h.inventory.serialInput, isEmpty);
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('inventory_serial_input')),
            )
            .focusNode!
            .hasFocus,
        isTrue,
      );
      await tester.pumpWidget(const SizedBox());
      h.dispose();
    },
  );

  testWidgets('failed export preserves location and SN inputs for retry', (
    tester,
  ) async {
    final h = Harness(tester);
    h.repository.exportSuccess = false;
    await h.mount(const InventoryImportScreen());
    h.inventory.updateLocation('A1-2-K3');
    h.inventory.updateSerialInput('SN1');
    await tester.pumpAndSettle();
    await _tap(tester, 'inventory_export_button');
    await _tap(tester, 'inventory_export_confirm_button');
    expect(find.text('Xuất kho thất bại'), findsOneWidget);
    await _tap(tester, 'inventory_export_result_ok_button');
    expect(h.inventory.locationInput, 'A1-2-K3');
    expect(h.inventory.serialInput, 'SN1');
    await tester.pumpWidget(const SizedBox());
    h.dispose();
  });

  testWidgets(
    'whole-tray confirmation exports the tray and returns focus to location',
    (tester) async {
      final h = Harness(tester);
      await h.mount(const InventoryImportScreen());
      h.inventory.updateLocation('A1-2-K3');
      await h.inventory.refreshTray();
      await tester.pumpAndSettle();
      await _tap(tester, 'inventory_export_button');
      expect(find.text('Xuất toàn bộ SN trong khay'), findsOneWidget);
      expect(find.text('Số lượng: 2'), findsOneWidget);
      await _tap(tester, 'inventory_export_confirm_button');
      await _tap(tester, 'inventory_export_result_ok_button');
      expect(h.repository.exports.single.request.serialNumbers, [
        'IN-TRAY-1',
        'IN-TRAY-2',
      ]);
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('inventory_location_input')),
            )
            .focusNode!
            .hasFocus,
        isTrue,
      );
      await tester.pumpWidget(const SizedBox());
      h.dispose();
    },
  );

  testWidgets('OK requires SNs; invalid Location disables export', (
    tester,
  ) async {
    final h = Harness(tester);
    await h.mount(const InventoryImportScreen());
    h.inventory.selectStockType(StockType.ok);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('inventory_export_button')),
          )
          .onPressed,
      isNull,
    );
    h.inventory.updateSerialInput('SN1');
    h.inventory.updateLocation('BAD');
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('inventory_export_button')),
          )
          .onPressed,
      isNull,
    );
    h.inventory.updateLocation('');
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('inventory_export_button')),
          )
          .onPressed,
      isNotNull,
    );
    await tester.pumpWidget(const SizedBox());
    h.dispose();
  });

  testWidgets('Retest preserves SN, result and notes when reopened', (
    tester,
  ) async {
    final h = Harness(tester);
    await h.mount(const RetestScreen());
    await tester.enterText(
      find.byKey(const ValueKey('retest_serial_input')),
      'SN-TEST',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('retest_Pass')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('retest_notes_input')),
      'Keep this note',
    );
    await tester.pumpWidget(const SizedBox());
    await h.mount(const RetestScreen());
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('retest_serial_input')))
          .controller!
          .text,
      'SN-TEST',
    );
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const ValueKey('retest_Pass')))
          .selected,
      isTrue,
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('retest_notes_input')))
          .controller!
          .text,
      'Keep this note',
    );
    await tester.pumpWidget(const SizedBox());
    h.dispose();
  });

  testWidgets(
    'SOP validation and Station history remain available with keyboard open',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'sop_station_history': ['FCT', 'ICT'],
      });
      final h = Harness(tester, width: 320, scale: 2);
      await h.mount(const SopScreen());
      await _tap(tester, 'sop_view_button');
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -900));
      await tester.pumpAndSettle();
      expect(find.text('Vui lòng nhập SerialNumber'), findsOneWidget);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 1800));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byIcon(Icons.history));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.history));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ICT'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('sop_station_input')))
            .controller!
            .text,
        'ICT',
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      tester.view.resetViewInsets();
      h.dispose();
    },
  );

  testWidgets('sign-in remembers username only and validates blank fields', (
    tester,
  ) async {
    final h = Harness(tester, width: 320, scale: 2);
    await h.mount(const SignInPage());
    await _tap(tester, 'login_submit');
    expect(find.text('Vui lòng nhập mã thẻ hoặc username'), findsOneWidget);
    expect(find.text('Vui lòng nhập mật khẩu'), findsOneWidget);
    // Mount the same real form with a callback that records validated credentials.
    String? user;
    await h.mount(
      DashboardTheme(
        child: Scaffold(
          body: SingleChildScrollView(
            child: FormContent(
              onLogin: (_, username, password) async => user = username,
            ),
          ),
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('login_username')),
      'V123',
    );
    await tester.enterText(
      find.byKey(const ValueKey('login_password')),
      'test-password',
    );
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await _tap(tester, 'login_submit');
    expect(user, 'V123');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('remembered_username'), 'V123');
    expect(prefs.containsKey('password'), isFalse);
    await tester.pumpWidget(const SizedBox());
    h.dispose();
  });
}

Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

class Harness {
  Harness(this.tester, {this.width = 390, this.scale = 1, this.dark = false}) {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }
  final WidgetTester tester;
  final double width;
  final double scale;
  final bool dark;
  final repository = TestInventoryRepository();
  late final inventory = InventoryImportProvider(repository: repository);
  final language = LanguageProvider();
  final auth = AuthProvider(repository: TestAuthRepository());
  final code = CodeProvider(
    useCase: ManageCodesUseCase(repository: TestCodeRepository()),
    connectivity: Connectivity(),
  );
  final cloud = DatacloudProvider(
    baseUrl: 'https://example.test/api/',
    client: MockClient(
      (_) async => http.Response(
        jsonEncode({
          'success': true,
          'data': {
            'currentPath': '',
            'items': [
              {
                'name': 'Very long instruction file name with spaces.pdf',
                'relativePath':
                    'guides/Very long instruction file name with spaces.pdf',
                'type': 'File',
              },
            ],
          },
        }),
        200,
      ),
    ),
  );
  Future<void> mount(Widget screen) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: language),
          ChangeNotifierProvider.value(value: auth),
          ChangeNotifierProvider.value(value: inventory),
          ChangeNotifierProvider.value(value: code),
          ChangeNotifierProvider.value(value: cloud),
        ],
        child: MaterialApp(
          key: UniqueKey(),
          theme: ThemeData(
            brightness: dark ? Brightness.dark : Brightness.light,
            primarySwatch: Colors.blue,
          ),
          locale: language.locale,
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
                child: child!,
              ),
          home: screen,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  void dispose() {
    inventory.dispose();
    language.dispose();
    auth.dispose();
    code.dispose();
    cloud.dispose();
  }
}

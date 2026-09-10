import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/auth/domain/entities/auth_user.dart';
import 'package:mobile_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:mobile_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:mobile_app/features/bga_replace/presentation/bga_replace_screen.dart';
import 'package:mobile_app/features/inventory_import/presentation/screens/inventory_import_screen.dart';
import 'package:mobile_app/features/pe_system/domain/repositories/code_repository.dart';
import 'package:mobile_app/features/pe_system/domain/usecases/manage_codes_usecase.dart';
import 'package:mobile_app/features/pe_system/presentation/providers/code_provider.dart';
import 'package:mobile_app/features/pe_system/presentation/providers/language_provider.dart';
import 'package:mobile_app/features/pe_system/presentation/providers/theme_provider.dart';
import 'package:mobile_app/features/pe_system/presentation/screens/data_cloud_screen.dart';
import 'package:mobile_app/features/pe_system/presentation/screens/navigation_rail_page.dart';
import 'package:mobile_app/features/pe_system/presentation/screens/pe_system_screen.dart';
import 'package:mobile_app/features/pe_system/presentation/screens/retest_screen.dart';
import 'package:mobile_app/features/pe_system/presentation/screens/sign_in_page.dart';
import 'package:mobile_app/features/pe_system/presentation/screens/sop_screen.dart';
import 'package:mobile_app/features/pe_system/presentation/widgets/dashboard_features.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_app/features/repair_lookup/domain/repositories/repair_lookup_repository.dart';
import 'package:mobile_app/features/repair_lookup/presentation/screens/repair_lookup_screen.dart';
import '../../../support/repair_lookup_fixtures.dart';

const _user = AuthUser(
  userId: 1,
  username: 'V3201425',
  role: 'Operator',
  allowedAreas: '',
  permissions: [],
  fullName: 'Đồng Văn Duy',
  chineseName: '陈明',
  email: 'operator@example.test',
  department: 'PE',
  cft: 'CFT 1',
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // Run the failure case before PackageInfo caches a successful response.
  testWidgets('app information handles a platform failure', (tester) async {
    const channel = MethodChannel('dev.fluttercommunity.plus/package_info');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (_) async => throw PlatformException(code: 'unavailable'),
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    final harness = await _mount(tester);
    harness.code.setSelectedIndex(2);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('app-info')));
    await tester.tap(find.byKey(const ValueKey('app-info')));
    await tester.pumpAndSettle();
    expect(find.text('FindBoard'), findsOneWidget);
    expect(find.text('Phiên bản: Chưa xác định'), findsOneWidget);
    expect(find.text('Số build: Chưa xác định'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('close-app-info')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('app information reads the installed version and build', (
    tester,
  ) async {
    PackageInfo.setMockInitialValues(
      appName: 'FindBoard',
      packageName: 'com.example.mobile_app',
      version: '2.4.6',
      buildNumber: '37',
      buildSignature: '',
    );
    final harness = await _mount(tester);
    harness.code.setSelectedIndex(2);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('app-info')));
    await tester.tap(find.byKey(const ValueKey('app-info')));
    await tester.pumpAndSettle();
    expect(find.text('Phiên bản: 2.4.6'), findsOneWidget);
    expect(find.text('Số build: 37'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final scale in [1.5, 2.0]) {
    testWidgets(
      'dropdown menus and dialogs remain usable at text $scale on a small phone',
      (tester) async {
        final harness = await _mount(tester, width: 320, scale: scale);
        await harness.language.setLocale(const Locale('en'));
        harness.code.setSelectedIndex(2);
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const ValueKey('language-selector')),
        );
        await tester.tap(find.byKey(const ValueKey('language-selector')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Chinese').last);
        await tester.pumpAndSettle();
        expect(harness.language.locale, const Locale('zh'));
        await tester.ensureVisible(
          find.byKey(const ValueKey('theme-selector')),
        );
        await tester.tap(find.byKey(const ValueKey('theme-selector')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('暗').last);
        await tester.pumpAndSettle();
        expect(harness.theme.themeMode, ThemeMode.dark);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.byKey(const ValueKey('app-info')));
        await tester.tap(find.byKey(const ValueKey('app-info')));
        await tester.pumpAndSettle();
        expect(find.text('FindBoard'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('close-app-info')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final width in [320.0, 390.0, 600.0, 900.0, 1200.0]) {
    for (final scale in [1.0, 1.5, 2.0]) {
      for (final mode in [ThemeMode.light, ThemeMode.dark]) {
        testWidgets('dashboard layout $width / text $scale / ${mode.name}', (
          tester,
        ) async {
          final harness = await _mount(
            tester,
            width: width,
            scale: scale,
            mode: mode,
          );
          for (final locale in [
            const Locale('vi'),
            const Locale('en'),
            const Locale('zh'),
          ]) {
            await harness.language.setLocale(locale);
            harness.code.setSelectedIndex(0);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            expect(
              find.byKey(const ValueKey('dashboard-rail')),
              width >= 900 ? findsOneWidget : findsNothing,
            );
            await tester.ensureVisible(
              find.byKey(const ValueKey('home-feature-dataCloud')),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            harness.code.setSelectedIndex(2);
            await tester.pumpAndSettle();
            await tester.ensureVisible(
              find.byKey(const ValueKey('logout-row')),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          }
        });
      }
    }
  }

  for (final tab in [0, 2]) {
    testWidgets(
      'all six shortcuts from tab $tab use the right route and preserve scroll',
      (tester) async {
        final harness = await _mount(tester);
        harness.code.setSelectedIndex(tab);
        await tester.pumpAndSettle();
        final order =
            tab == 0
                ? DashboardFeature.homeOrder
                : DashboardFeature.settingsOrder;
        final expectedTypes = <DashboardFeature, Type>{
          DashboardFeature.inventory: InventoryImportScreen,
          DashboardFeature.bga: BgaReplaceScreen,
          DashboardFeature.sop: SopScreen,
          DashboardFeature.search: PESystemScreen,
          DashboardFeature.retest: RetestScreen,
          DashboardFeature.dataCloud: DataCloudScreen,
        };
        for (final feature in order) {
          final key =
              '${tab == 0 ? 'home' : 'settings'}-feature-${feature.name}';
          final shortcut = find.byKey(ValueKey(key));
          await tester.ensureVisible(shortcut);
          await tester.pumpAndSettle();
          final before = tester.getTopLeft(shortcut);
          await tester.tap(shortcut);
          final route = harness.observer.lastRoute! as MaterialPageRoute<void>;
          expect(route.settings.name, '/features/${feature.name}');
          // Inspect the actual route builder before building business screens:
          // their API, camera and platform integrations have their own tests.
          expect(
            route.builder(harness.navigator.currentContext!).runtimeType,
            expectedTypes[feature],
          );
          harness.navigator.currentState!.pop();
          await tester.pumpAndSettle();
          expect(harness.code.selectedIndex, tab);
          expect(tester.getTopLeft(shortcut), before);
          expect(tester.takeException(), isNull);
        }
      },
    );
  }

  testWidgets('tab switching retains home scroll and repair lookup state', (
    tester,
  ) async {
    await _mount(tester);
    final lastCard = find.byKey(const ValueKey('home-feature-dataCloud'));
    await tester.ensureVisible(lastCard);
    await tester.pumpAndSettle();
    final before = tester.getTopLeft(lastCard);
    await tester.tap(find.byKey(const ValueKey('navigation-tab-1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('lookup-sn-input')), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('lookup-sn-input')),
      sampleSn,
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text('BLOCK-R_ICT'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('navigation-tab-2')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('operator-card')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('navigation-tab-0')));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(lastCard), before);
    await tester.tap(find.byKey(const ValueKey('navigation-tab-1')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('lookup-sn-input')))
          .controller!
          .text,
      sampleSn,
    );
    await tester.tap(find.byKey(const ValueKey('lookup-back')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-feature-inventory')), findsWidgets);
  });

  testWidgets('detail system back returns home and logout drops lookup state', (
    tester,
  ) async {
    final harness = await _mount(tester);
    harness.code.setSelectedIndex(1);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('lookup-sn-input')),
      sampleSn,
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    await harness.navigator.currentState!.maybePop();
    await tester.pumpAndSettle();
    expect(harness.code.selectedIndex, 0);
    expect(find.byType(SignInPage), findsNothing);
    harness.code.setSelectedIndex(2);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('logout-row')));
    await tester.tap(find.byKey(const ValueKey('logout-row')));
    await tester.pumpAndSettle();
    expect(find.byType(RepairLookupScreen), findsNothing);
    harness.navigator.currentState!.pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const NavigationRailPage()),
      (_) => false,
    );
    harness.code.setSelectedIndex(1);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('lookup-sn-input')))
          .controller!
          .text,
      isEmpty,
    );
    expect(find.text('BLOCK-R_ICT'), findsNothing);
    expect(harness.repair.calls.length, 3);
    expect(tester.takeException(), isNull);
  });

  for (final key in ['logout-header', 'logout-row']) {
    testWidgets(
      '$key clears the session and prevents returning to the dashboard',
      (tester) async {
        final harness = await _mount(tester);
        harness.code.setSelectedIndex(2);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(ValueKey(key)));
        await tester.tap(find.byKey(ValueKey(key)));
        await tester.pumpAndSettle();
        expect(harness.repository.logoutCount, 1);
        expect(harness.auth.user, isNull);
        expect(harness.code.selectedIndex, 0);
        expect(find.byType(SignInPage), findsOneWidget);
        expect(harness.navigator.currentState!.canPop(), isFalse);
        expect(await harness.navigator.currentState!.maybePop(), isFalse);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'theme and language selectors update the UI and restore saved choices',
    (tester) async {
      final harness = await _mount(tester);
      harness.code.setSelectedIndex(2);
      await tester.pumpAndSettle();
      for (final item in [
        ('Tối', ThemeMode.dark),
        ('Sáng', ThemeMode.light),
        ('Hệ thống', ThemeMode.system),
      ]) {
        await tester.ensureVisible(
          find.byKey(const ValueKey('theme-selector')),
        );
        await tester.tap(find.byKey(const ValueKey('theme-selector')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(item.$1).last);
        await tester.pumpAndSettle();
        expect(harness.theme.themeMode, item.$2);
        final restored = ThemeProvider();
        await restored.initialize();
        expect(restored.themeMode, item.$2);
        restored.dispose();
      }
      await tester.ensureVisible(
        find.byKey(const ValueKey('language-selector')),
      );
      await tester.tap(find.byKey(const ValueKey('language-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tiếng Anh').last);
      await tester.pumpAndSettle();
      expect(harness.language.locale, const Locale('en'));
      expect(find.text('Appearance'), findsOneWidget);
      final restored = LanguageProvider();
      await restored.initialize();
      expect(restored.locale, const Locale('en'));
      restored.dispose();
      tester.binding.platformDispatcher.platformBrightnessTestValue =
          Brightness.dark;
      addTearDown(
        tester.binding.platformDispatcher.clearPlatformBrightnessTestValue,
      );
      await tester.pumpAndSettle();
      expect(
        Theme.of(
          tester.element(find.byKey(const ValueKey('operator-card'))),
        ).brightness,
        Brightness.dark,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('profile is read only, scrolls and shows real account data', (
    tester,
  ) async {
    final harness = await _mount(tester, width: 320, scale: 2);
    harness.code.setSelectedIndex(2);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('operator-card')));
    await tester.pumpAndSettle();
    expect(find.text('Thông tin tài khoản'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(SelectableText), findsNWidgets(7));
    await tester.ensureVisible(find.text('CFT 1'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('close-profile')));
    await tester.pumpAndSettle();
    expect(find.text('Thông tin tài khoản'), findsNothing);
  });

  testWidgets('missing names and optional profile values have safe fallbacks', (
    tester,
  ) async {
    const user = AuthUser(
      userId: 2,
      username: 'V00001',
      role: '',
      allowedAreas: '',
      permissions: [],
      fullName: ' ',
      chineseName: '',
      email: '',
      department: '',
      cft: '',
    );
    final harness = await _mount(tester, user: user);
    expect(find.text('V00001'), findsOneWidget);
    harness.code.setSelectedIndex(2);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('operator-card')));
    await tester.pumpAndSettle();
    expect(find.byType(SelectableText), findsNWidgets(2));
    expect(find.text('Phòng ban'), findsNothing);
    expect(find.text('Vai trò'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long names and department names wrap at large text sizes', (
    tester,
  ) async {
    const user = AuthUser(
      userId: 3,
      username: 'V123456789012345678901234567890',
      role: '',
      allowedAreas: '',
      permissions: [],
      fullName: 'Nguyễn Hoàng Thị Minh Phương Đồng Văn Duy',
      chineseName: '',
      email: '',
      department: 'Phòng kỹ thuật và quản lý chất lượng sản xuất',
      cft: '',
    );
    final harness = await _mount(tester, width: 320, scale: 2, user: user);
    expect(tester.takeException(), isNull);
    harness.code.setSelectedIndex(2);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing user is neutral and profile is not actionable', (
    tester,
  ) async {
    final harness = await _mount(tester, user: null);
    expect(find.text('Chưa có thông tin tài khoản'), findsOneWidget);
    harness.code.setSelectedIndex(2);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('operator-card')));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Future<_Harness> _mount(
  WidgetTester tester, {
  double width = 390,
  double scale = 1,
  ThemeMode mode = ThemeMode.light,
  AuthUser? user = _user,
}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final harness = _Harness(user);
  await harness.auth.initialize();
  await harness.theme.initialize();
  await harness.language.initialize();
  await harness.theme.setThemeMode(mode);
  addTearDown(harness.dispose);
  await tester.pumpWidget(harness.build(scale));
  await tester.pumpAndSettle();
  return harness;
}

class _Harness {
  _Harness(AuthUser? user) : repository = _AuthRepository(user);
  final _AuthRepository repository;
  late final auth = AuthProvider(repository: repository);
  final theme = ThemeProvider();
  final language = LanguageProvider();
  final code = CodeProvider(
    useCase: ManageCodesUseCase(repository: _CodeRepository()),
    connectivity: Connectivity(),
  );
  final repair = FixtureRepairRepository();
  final navigator = GlobalKey<NavigatorState>();
  final observer = _RouteObserver();

  Widget build(double scale) => MultiProvider(
    providers: [
      Provider<RepairLookupRepository>.value(value: repair),
      ChangeNotifierProvider.value(value: auth),
      ChangeNotifierProvider.value(value: theme),
      ChangeNotifierProvider.value(value: language),
      ChangeNotifierProvider.value(value: code),
    ],
    child: Builder(
      builder:
          (context) => MaterialApp(
            navigatorKey: navigator,
            navigatorObservers: [observer],
            theme: ThemeData(
              brightness: Brightness.light,
              primarySwatch: Colors.blue,
            ),
            darkTheme: ThemeData(
              brightness: Brightness.dark,
              primarySwatch: Colors.blue,
            ),
            themeMode: context.watch<ThemeProvider>().themeMode,
            locale: context.watch<LanguageProvider>().locale,
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
            home: const NavigationRailPage(),
          ),
    ),
  );

  void dispose() {
    auth.dispose();
    theme.dispose();
    language.dispose();
    code.dispose();
  }
}

class _AuthRepository extends Fake implements AuthRepository {
  _AuthRepository(this.currentUser);
  @override
  AuthUser? currentUser;
  int logoutCount = 0;
  @override
  String? get accessToken => currentUser == null ? null : 'test-token';
  @override
  Future<AuthUser?> restoreSession() async => currentUser;
  @override
  Future<void> logout() async {
    logoutCount++;
    currentUser = null;
  }
}

class _CodeRepository extends Fake implements CodeRepository {}

class _RouteObserver extends NavigatorObserver {
  Route<dynamic>? lastRoute;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    lastRoute = route;
  }
}

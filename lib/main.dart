// lib/
// ├── core/
// │   ├── network/
// │   │   └── api_client.dart       # Xử lý gọi API chung
// │   ├── error/
// │   │   └── exceptions.dart       # Định nghĩa lỗi (API, mạng)
// │   └── constants/
// │       └── colors.dart           # Màu sắc, hằng số chung
// ├── features/
// │   └── pe_system/
// │       ├── data/
// │       │   ├── models/
// │       │   │   └── code_model.dart  # Mô hình dữ liệu từ API
// │       │   ├── repositories/
// │       │   │   └── code_repository_impl.dart  # Triển khai repository
// │       │   └── datasources/
// │       │       └── remote_datasource.dart    # Gọi API cụ thể
// │       ├── domain/
// │       │   ├── entities/
// │       │   │   └── code_entity.dart  # Mô hình dữ liệu thuần túy
// │       │   ├── repositories/
// │       │   │   └── code_repository.dart  # Interface cho repository
// │       │   └── usecases/
// │       │       └── manage_codes_usecase.dart  # Logic nghiệp vụ
// │       └── presentation/
// │           ├── providers/
// │           │   └── code_provider.dart    # Quản lý trạng thái
// │           ├── screens/
// │           │   └── pe_system_screen.dart  # Màn hình chính
// │           └── widgets/
// │               ├── code_item.dart        # Widget mã trong danh sách
// ├── main.dart                            # Điểm vào ứng dụng
// pubspec.yaml                            # Cấu hình dependencies

import 'dart:async';
import 'features/pe_system/data/local/scan_store.dart';
import 'features/pe_system/data/services/scan_sync_service.dart';
import 'features/pe_system/data/services/search_list_notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'features/pe_system/presentation/providers/theme_provider.dart';
import 'features/pe_system/presentation/providers/code_provider.dart';
import 'features/pe_system/presentation/providers/dataCloud_provider.dart';
import 'features/pe_system/presentation/providers/language_provider.dart';
import 'features/pe_system/presentation/screens/sign_in_page.dart';
import 'features/pe_system/presentation/screens/navigation_rail_page.dart';
import 'features/pe_system/presentation/screens/pe_system_screen.dart';
import 'features/inventory_import/data/datasources/inventory_remote_data_source.dart';
import 'features/inventory_import/data/repositories/inventory_repository_impl.dart';
import 'features/inventory_import/presentation/providers/inventory_import_provider.dart';
import 'core/config/api_config.dart';
import 'core/network/api_client.dart';
import 'features/chat/data/datasources/chat_remote_data_source.dart';
import 'features/chat/data/repositories/chat_repository_impl.dart';
import 'features/chat/data/services/chat_realtime_service.dart';
import 'features/chat/presentation/providers/chat_provider.dart';
import 'features/auth/data/datasources/auth_remote_data_source.dart';
import 'features/auth/data/repositories/auth_repository_impl.dart';
import 'features/auth/data/storage/auth_session_storage.dart';
import 'features/auth/presentation/providers/auth_provider.dart';
import 'features/pe_system/data/datasources/remote_datasource.dart';
import 'features/pe_system/data/repositories/code_repository_impl.dart';
import 'features/pe_system/domain/usecases/manage_codes_usecase.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'core/constants/colors.dart';
import 'features/repair_lookup/data/datasources/repair_lookup_remote_data_source.dart';
import 'features/repair_lookup/data/repositories/repair_lookup_repository_impl.dart';
import 'features/repair_lookup/domain/repositories/repair_lookup_repository.dart';

final scanNavigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  final authRemoteDataSource = AuthRemoteDataSource(
    apiClient: ApiClient(baseUrl: ApiConfig.inventoryBaseUrl),
  );
  final authRepository = AuthRepositoryImpl(
    remoteDataSource: authRemoteDataSource,
    sessionStorage: SecureAuthSessionStorage(),
  );
  final authProvider = AuthProvider(repository: authRepository);
  final chatApiClient = ApiClient(baseUrl: ApiConfig.chatBaseUrl, authTokenProvider: authRepository,
    sessionIdentity: () => authRepository.sessionGeneration);
  final chatProvider = ChatProvider(
    repository: ChatRepositoryImpl(ChatRemoteDataSource(chatApiClient)),
    realtime: ChatRealtimeService(hubUrl: ApiConfig.chatHubUrl, tokens: authRepository),
    closeClient: chatApiClient.close,
    onUnauthorized: () {
      unawaited(authProvider.logout());
      scanNavigatorKey.currentState?.pushNamedAndRemoveUntil('/sign-in', (_) => false);
    },
  );

  final apiClient = ApiClient(
    baseUrl: ApiConfig.scanBaseUrl,
    authTokenProvider: authRepository,
  );
  final inventoryApiClient = ApiClient(
    baseUrl: ApiConfig.inventoryBaseUrl,
    authTokenProvider: authRepository,
  );
  final inventoryRemoteDataSource = InventoryRemoteDataSource(
    inventoryApiClient: inventoryApiClient,
  );
  final inventoryRepository = InventoryRepositoryImpl(
    remoteDataSource: inventoryRemoteDataSource,
  );
  final inventoryImportProvider = InventoryImportProvider(
    repository: inventoryRepository,
  );
  final repairLookupRepository = RepairLookupRepositoryImpl(
    remoteDataSource: RepairLookupRemoteDataSource(apiClient: apiClient),
  );
  final remoteDataSource = RemoteDataSource(
    apiClient: apiClient,
    inventoryApiClient: inventoryApiClient,
  );
  final repository = CodeRepositoryImpl(remoteDataSource: remoteDataSource);
  final useCase = ManageCodesUseCase(repository: repository);
  final connectivity = Connectivity();
  final scanSync = ScanSyncService(
    store: ScanStore(),
    server: Uri.parse(ApiConfig.scanBaseUrl).normalizePath().toString(),
    isConnected:
        () async =>
            await connectivity.checkConnectivity() != ConnectivityResult.none,
    supportsSync: remoteDataSource.supportsScanSync,
    upload:
        (scan) => remoteDataSource.scanSerialNumber(
          scan.sn,
          searchListId: scan.listId,
          clientScanId: scan.id,
          scannedAt: scan.scannedAt,
        ),
  );
  scanSync.observe(connectivity);
  final codeProvider = CodeProvider(
    useCase: useCase,
    connectivity: connectivity,
    scanSync: scanSync,
  );
  bool openScanAfterLogin = false;
  void openScanFromNotification() {
    openScanAfterLogin = true;
    if (!authProvider.isLoggedIn) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!openScanAfterLogin || !authProvider.isLoggedIn) return;
      final navigator = scanNavigatorKey.currentState;
      if (navigator == null) return;
      openScanAfterLogin = false;
      navigator.pushNamed('/pe-system');
    });
  }

  final listNotifications = SearchListNotificationService(
    useCase: useCase,
    server: Uri.parse(ApiConfig.scanBaseUrl).normalizePath().toString(),
    onNewLists: (_) {
      if (codeProvider.searchListPage == 1) {
        unawaited(codeProvider.fetchSearchList());
      }
    },
    onOpen: openScanFromNotification,
  );
  Object? boundUser;
  authProvider.addListener(() {
    final user = authProvider.user;
    if (identical(boundUser, user)) return;
    boundUser = user;
    codeProvider.resetSessionState();
    chatProvider.bindUser(user?.userId);
    unawaited(scanSync.bindUser(user?.userId));
    unawaited(listNotifications.bindUser(user?.userId));
    if (openScanAfterLogin && user != null) openScanFromNotification();
  });
  boundUser = authProvider.user;
  chatProvider.bindUser(authProvider.user?.userId);
  unawaited(scanSync.bindUser(authProvider.user?.userId));
  unawaited(listNotifications.bindUser(authProvider.user?.userId));
  final themeProvider = ThemeProvider();
  final dataCloudProvider = DatacloudProvider(
    baseUrl: ApiConfig.dataCloudBaseUrl,
    rootPath: ApiConfig.dataCloudRootPath,
    authTokenProvider: authRepository,
  );
  final languageProvider = LanguageProvider();

  // Khởi tạo async cho các provider
  await Future.wait([
    authProvider.initialize(),
    themeProvider.initialize(),
    languageProvider.initialize(),
  ]);

  runApp(
    MultiProvider(
      providers: [
        Provider<RepairLookupRepository>.value(value: repairLookupRepository),
        ChangeNotifierProvider(create: (_) => authProvider),
        ChangeNotifierProvider(create: (_) => chatProvider),
        ChangeNotifierProvider(create: (_) => codeProvider),
        ChangeNotifierProvider(create: (_) => themeProvider),
        ChangeNotifierProvider(create: (_) => dataCloudProvider),
        ChangeNotifierProvider(create: (_) => languageProvider),
        ChangeNotifierProvider(create: (_) => inventoryImportProvider),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    bool isDarkMode = _getIsDarkMode(themeProvider, context);

    _updateSystemUIOverlayStyle(isDarkMode);
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final authProvider = Provider.of<AuthProvider>(context);
    bool isDarkMode = _getIsDarkMode(themeProvider, context);
    final appBarBackgroundColor =
        isDarkMode ? Colors.grey[900] : AppColors.background;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateSystemUIOverlayStyle(isDarkMode);
    });

    final lightTheme = ThemeData(
      primarySwatch: Colors.blue,
      brightness: Brightness.light,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      scaffoldBackgroundColor: AppColors.background,
      appBarTheme: AppBarTheme(
        backgroundColor: appBarBackgroundColor,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
        titleTextStyle: const TextStyle(
          color: Colors.black87,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: appBarBackgroundColor,
          statusBarIconBrightness: Brightness.dark,
        ),
      ),
      cardTheme: const CardThemeData(
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      dropdownMenuTheme: const DropdownMenuThemeData(
        textStyle: TextStyle(color: Colors.black, fontSize: 14),
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(Colors.white),
          elevation: WidgetStatePropertyAll(4),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(8)),
            ),
          ),
        ),
      ),
      textTheme: const TextTheme(
        bodyMedium: TextStyle(color: Colors.black),
        bodyLarge: TextStyle(color: Colors.black),
        labelLarge: TextStyle(color: Colors.black),
      ),
    );

    final darkTheme = ThemeData(
      primarySwatch: Colors.blue,
      brightness: Brightness.dark,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      scaffoldBackgroundColor: Colors.grey[900],
      appBarTheme: AppBarTheme(
        backgroundColor: appBarBackgroundColor,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: appBarBackgroundColor,
          statusBarIconBrightness: Brightness.light,
        ),
      ),
      cardTheme: const CardThemeData(
        elevation: 4,
        color: Colors.grey,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      dropdownMenuTheme: const DropdownMenuThemeData(
        textStyle: TextStyle(color: Colors.white, fontSize: 14),
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(Colors.grey),
          elevation: WidgetStatePropertyAll(4),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(8)),
            ),
          ),
        ),
      ),
      textTheme: const TextTheme(
        bodyMedium: TextStyle(color: Colors.white),
        bodyLarge: TextStyle(color: Colors.white),
        labelLarge: TextStyle(color: Colors.white),
      ),
    );

    return AnimatedTheme(
      data: Theme.of(context),
      duration: const Duration(milliseconds: 300),
      child: MaterialApp(
        navigatorKey: scanNavigatorKey,
        theme: lightTheme,
        darkTheme: darkTheme,
        themeMode: themeProvider.themeMode,
        locale: Provider.of<LanguageProvider>(context).locale,
        supportedLocales: const [Locale('vi'), Locale('en'), Locale('zh')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        initialRoute: authProvider.isLoggedIn ? '/navigation' : '/sign-in',
        routes: {
          '/sign-in': (context) => const SignInPage(),
          '/navigation': (context) => const NavigationRailPage(),
          '/pe-system': (context) => const PESystemScreen(),
        },
        debugShowCheckedModeBanner: false,
      ),
    );
  }

  bool _getIsDarkMode(ThemeProvider themeProvider, BuildContext context) {
    if (themeProvider.themeMode == ThemeMode.system) {
      return MediaQuery.of(context).platformBrightness == Brightness.dark;
    } else {
      return themeProvider.themeMode == ThemeMode.dark;
    }
  }

  void _updateSystemUIOverlayStyle(bool isDarkMode) {
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: isDarkMode ? Colors.grey[900] : AppColors.background,
        statusBarIconBrightness:
            isDarkMode ? Brightness.light : Brightness.dark,
        systemNavigationBarColor:
            isDarkMode ? Colors.grey[900] : AppColors.background,
        systemNavigationBarIconBrightness:
            isDarkMode ? Brightness.light : Brightness.dark,
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/auth/domain/entities/auth_user.dart';
import 'package:mobile_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:mobile_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:mobile_app/features/inventory_import/domain/entities/export_inventory_request.dart';
import 'package:mobile_app/features/inventory_import/domain/entities/import_inventory_request.dart';
import 'package:mobile_app/features/inventory_import/domain/entities/inventory_location.dart';
import 'package:mobile_app/features/inventory_import/domain/entities/inventory_models.dart';
import 'package:mobile_app/features/inventory_import/domain/entities/stock_type.dart';
import 'package:mobile_app/features/inventory_import/domain/repositories/inventory_repository.dart';
import 'package:mobile_app/features/inventory_import/presentation/providers/inventory_import_provider.dart';
import 'package:mobile_app/features/inventory_import/presentation/screens/inventory_import_screen.dart';
import 'package:provider/provider.dart';

void main() {
  const locationKey = ValueKey<String>('inventory_location_input');
  const serialKey = ValueKey<String>('inventory_serial_input');
  const keyboardToggleKey = ValueKey<String>('software_keyboard_toggle');
  const refreshKey = ValueKey<String>('inventory_refresh_button');
  const exportKey = ValueKey<String>('inventory_export_button');

  testWidgets('keyboard toggle defaults off and Enter moves focus to SN', (
    tester,
  ) async {
    final repository = _ScreenTestRepository(trayInfo: _availableTray);
    final provider = InventoryImportProvider(repository: repository);
    addTearDown(provider.dispose);
    await tester.pumpWidget(await _testApp(provider));
    expect(find.text('Inventory Operator (V1234567)'), findsOneWidget);

    expect(
      tester.widget<TextField>(find.byKey(locationKey)).keyboardType,
      TextInputType.text,
    );
    expect(
      tester.widget<TextField>(find.byKey(serialKey)).keyboardType,
      TextInputType.multiline,
    );

    await tester.tap(find.byKey(keyboardToggleKey));
    await tester.pump();
    expect(find.text('Keyboard: ON'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byKey(locationKey)).keyboardType,
      TextInputType.text,
    );

    await tester.tap(find.byKey(keyboardToggleKey));
    await tester.pump();
    expect(find.text('Keyboard: OFF'), findsOneWidget);

    await tester.enterText(find.byKey(locationKey), 'A1-2-K3');
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pumpAndSettle();

    expect(repository.trayRequestCount, 1);
    expect(
      tester.widget<TextField>(find.byKey(serialKey)).focusNode!.hasFocus,
      isTrue,
    );

    await tester.enterText(find.byKey(serialKey), 'pda-sn-1');
    await tester.pumpAndSettle();
    expect(provider.serialInput, 'PDA-SN-1');
    final inputInfoTable = find.byKey(
      const ValueKey<String>('inventory_serial_info_table'),
    );
    expect(inputInfoTable, findsOneWidget);
    expect(
      find.descendant(of: inputInfoTable, matching: find.text('WIP-TEST')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: inputInfoTable, matching: find.text('MODEL-TEST')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: inputInfoTable, matching: find.text('LINE-TEST')),
      findsOneWidget,
    );
    expect(find.text('Serial information'), findsNothing);
  });

  testWidgets('SN input and three-column table fit side by side on PDA width', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _ScreenTestRepository(trayInfo: _availableTray);
    final provider = InventoryImportProvider(repository: repository);
    addTearDown(provider.dispose);
    await tester.pumpWidget(await _testApp(provider));

    await tester.enterText(find.byKey(serialKey), 'SN-001');
    await tester.pumpAndSettle();

    final inputRect = tester.getRect(find.byKey(serialKey));
    final tableRect = tester.getRect(
      find.byKey(const ValueKey<String>('inventory_serial_info_table')),
    );
    expect(inputRect.right, lessThan(tableRect.left));
    expect(find.text('WIP Group'), findsOneWidget);
    expect(find.text('Model Name'), findsOneWidget);
    expect(find.text('Product Line'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Tray information shows WIP Group and Model Name for each SN', (
    tester,
  ) async {
    final repository = _ScreenTestRepository(trayInfo: _availableTray);
    final provider = InventoryImportProvider(repository: repository);
    addTearDown(provider.dispose);
    await tester.pumpWidget(await _testApp(provider));

    await tester.enterText(find.byKey(locationKey), 'A1-2-K3');
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pumpAndSettle();

    final table = find.byKey(
      const ValueKey<String>('inventory_tray_serial_info_table'),
    );
    expect(table, findsOneWidget);
    expect(
      find.descendant(of: table, matching: find.text('EXISTING-1')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: table, matching: find.text('WIP-TEST')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: table, matching: find.text('MODEL-TEST')),
      findsOneWidget,
    );
  });

  testWidgets('full tray shows an OK dialog and returns focus to Location', (
    tester,
  ) async {
    final repository = _ScreenTestRepository(trayInfo: _fullTray);
    final provider = InventoryImportProvider(repository: repository);
    addTearDown(provider.dispose);
    await tester.pumpWidget(await _testApp(provider));

    await tester.enterText(find.byKey(locationKey), 'A1-2-K3');
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pumpAndSettle();

    expect(find.text('Tray is full'), findsOneWidget);
    expect(find.textContaining('(2/2)'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('tray_full_ok_button')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Tray is full'), findsNothing);
    expect(
      tester.widget<TextField>(find.byKey(locationKey)).focusNode!.hasFocus,
      isTrue,
    );
  });

  testWidgets('Refresh clears the form and returns focus to Location', (
    tester,
  ) async {
    final repository = _ScreenTestRepository(trayInfo: _availableTray);
    final provider = InventoryImportProvider(repository: repository);
    addTearDown(provider.dispose);
    await tester.pumpWidget(await _testApp(provider));

    await tester.enterText(find.byKey(locationKey), 'A1-2-K3');
    await tester.enterText(find.byKey(serialKey), 'SN-TO-CLEAR');
    await tester.ensureVisible(find.byKey(refreshKey));
    await tester.tap(find.byKey(refreshKey));
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(find.byKey(locationKey)).controller!.text,
        isEmpty);
    expect(tester.widget<TextField>(find.byKey(serialKey)).controller!.text,
        isEmpty);
    expect(provider.location, isNull);
    expect(provider.serialNumbers, isEmpty);
    expect(provider.trayInfo, isNull);
    expect(
      tester.widget<TextField>(find.byKey(locationKey)).focusNode!.hasFocus,
      isTrue,
    );
  });

  testWidgets('successful import clears inputs only after OK', (
    tester,
  ) async {
    final repository = _ScreenTestRepository(trayInfo: _availableTray);
    final provider = InventoryImportProvider(repository: repository);
    addTearDown(provider.dispose);
    await tester.pumpWidget(await _testApp(provider));

    await _enterValidImport(tester, locationKey, serialKey);
    await tester.ensureVisible(find.widgetWithText(ElevatedButton, 'IMPORT'));
    await tester.tap(find.widgetWithText(ElevatedButton, 'IMPORT'));
    await tester.pumpAndSettle();

    expect(find.text('Import successful'), findsOneWidget);
    expect(provider.locationInput, 'A1-2-K3');
    expect(provider.serialInput, 'SN-001');

    await tester.tap(
      find.byKey(const ValueKey<String>('inventory_result_ok_button')),
    );
    await tester.pumpAndSettle();

    expect(provider.locationInput, isEmpty);
    expect(provider.serialInput, isEmpty);
    expect(find.text('Import successful'), findsNothing);
  });

  testWidgets('failed import clears inputs after OK', (tester) async {
    final repository = _ScreenTestRepository(
      trayInfo: _availableTray,
      importResult: const InventoryImportResult(
        success: false,
        message: 'Serial was rejected.',
      ),
    );
    final provider = InventoryImportProvider(repository: repository);
    addTearDown(provider.dispose);
    await tester.pumpWidget(await _testApp(provider));

    await _enterValidImport(tester, locationKey, serialKey);
    await tester.ensureVisible(find.widgetWithText(ElevatedButton, 'IMPORT'));
    await tester.tap(find.widgetWithText(ElevatedButton, 'IMPORT'));
    await tester.pumpAndSettle();

    expect(find.text('Import failed'), findsOneWidget);
    expect(find.textContaining('Serial was rejected.'), findsWidgets);
    expect(provider.locationInput, 'A1-2-K3');
    expect(provider.serialInput, 'SN-001');

    await tester.tap(
      find.byKey(const ValueKey<String>('inventory_result_ok_button')),
    );
    await tester.pumpAndSettle();

    expect(provider.locationInput, isEmpty);
    expect(provider.serialInput, isEmpty);
    expect(find.text('Import failed'), findsNothing);
  });

  testWidgets('Export enables for an occupied tray and requires confirmation', (
    tester,
  ) async {
    final repository = _ScreenTestRepository(trayInfo: _availableTray);
    final provider = InventoryImportProvider(repository: repository);
    addTearDown(provider.dispose);
    await tester.pumpWidget(await _testApp(provider));

    expect(
      tester.widget<ElevatedButton>(find.byKey(exportKey)).onPressed,
      isNull,
    );

    await tester.enterText(find.byKey(locationKey), 'A1-2-K3');
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pumpAndSettle();
    expect(
      tester.widget<ElevatedButton>(find.byKey(exportKey)).onPressed,
      isNotNull,
    );

    await tester.ensureVisible(find.byKey(exportKey));
    await tester.tap(find.byKey(exportKey));
    await tester.pumpAndSettle();
    expect(find.text('Confirm inventory export'), findsOneWidget);
    expect(find.textContaining('1 SN(s)'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('inventory_export_cancel_button')),
    );
    await tester.pumpAndSettle();
    expect(repository.exportRequestCount, 0);

    await tester.ensureVisible(find.byKey(exportKey));
    await tester.tap(find.byKey(exportKey));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('inventory_export_confirm_button')),
    );
    await tester.pumpAndSettle();

    expect(repository.exportRequestCount, 1);
    expect(repository.lastExportRequest?.serialNumbers, <String>['EXISTING-1']);
    expect(find.text('Export successful'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('inventory_export_result_ok_button')),
    );
    await tester.pumpAndSettle();

    expect(provider.locationInput, isEmpty);
    expect(provider.trayInfo, isNull);
    expect(
      tester.widget<ElevatedButton>(find.byKey(exportKey)).onPressed,
      isNull,
    );
  });
}

Future<void> _enterValidImport(
  WidgetTester tester,
  ValueKey<String> locationKey,
  ValueKey<String> serialKey,
) async {
  await tester.enterText(find.byKey(locationKey), 'A1-2-K3');
  await tester.testTextInput.receiveAction(TextInputAction.next);
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(serialKey), 'SN-001');
  await tester.pumpAndSettle();
}

Future<Widget> _testApp(InventoryImportProvider inventoryProvider) async {
  final authProvider = AuthProvider(repository: _TestAuthRepository());
  await authProvider.initialize();

  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
      ChangeNotifierProvider<InventoryImportProvider>.value(
        value: inventoryProvider,
      ),
    ],
    child: const MaterialApp(home: InventoryImportScreen()),
  );
}

const _availableTray = TrayInfo(
  maxSlots: 2,
  occupiedCount: 1,
  occupiedPositions: <TrayPosition>[
    TrayPosition(serialNumber: 'EXISTING-1', positionInTray: 1),
  ],
);

const _fullTray = TrayInfo(
  maxSlots: 2,
  occupiedCount: 2,
  occupiedPositions: <TrayPosition>[
    TrayPosition(serialNumber: 'EXISTING-1', positionInTray: 1),
    TrayPosition(serialNumber: 'EXISTING-2', positionInTray: 2),
  ],
);

class _ScreenTestRepository implements InventoryRepository {
  final TrayInfo trayInfo;
  final InventoryImportResult importResult;
  int trayRequestCount = 0;
  int exportRequestCount = 0;
  ExportInventoryRequest? lastExportRequest;

  _ScreenTestRepository({
    required this.trayInfo,
    this.importResult = const InventoryImportResult(
      success: true,
      message: 'Completed',
    ),
  });

  @override
  Future<TrayInfo> getTrayInfo(
    StockType stockType,
    InventoryLocation location,
  ) async {
    trayRequestCount++;
    return trayInfo;
  }

  @override
  Future<SerialInfo?> getSerialInfo(String serialNumber) async {
    return SerialInfo(
      serialNumber: serialNumber,
      wipGroup: 'WIP-TEST',
      modelName: 'MODEL-TEST',
      productLine: 'LINE-TEST',
    );
  }

  @override
  Future<InventoryImportResult> importInventory(
    StockType stockType,
    ImportInventoryRequest request,
  ) async {
    return importResult;
  }

  @override
  Future<InventoryExportResult> exportInventory(
    StockType stockType,
    ExportInventoryRequest request,
  ) async {
    exportRequestCount++;
    lastExportRequest = request;
    return const InventoryExportResult(
      success: true,
      message: 'Export completed',
    );
  }
}

class _TestAuthRepository implements AuthRepository {
  static const AuthUser _user = AuthUser(
    userId: 1,
    username: 'V1234567',
    role: 'User',
    allowedAreas: 'Inventory',
    permissions: <String>['Inventory.View', 'Inventory.Input'],
    fullName: 'Inventory Operator',
    chineseName: '',
    email: '',
    department: 'PE',
    cft: 'Adapter',
  );

  @override
  String? get accessToken => 'test-token';

  @override
  AuthUser? get currentUser => _user;

  @override
  Future<AuthUser> login(String username, String password) async => _user;

  @override
  Future<void> logout() async {}

  @override
  Future<String?> refreshAccessToken() async => accessToken;

  @override
  Future<AuthUser?> restoreSession() async => _user;
}

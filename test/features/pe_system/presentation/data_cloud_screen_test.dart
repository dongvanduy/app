import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:mobile_app/features/pe_system/presentation/providers/dataCloud_provider.dart';
import 'package:mobile_app/features/pe_system/presentation/providers/language_provider.dart';
import 'package:mobile_app/features/pe_system/presentation/screens/data_cloud_screen.dart';
import 'package:mobile_app/features/pe_system/presentation/widgets/data_cloud_item.dart';

void main() {
  for (final width in [320.0, 1200.0]) {
    testWidgets('scope menus and layout at width $width', (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final provider = DatacloudProvider(
        baseUrl: 'https://example.test/api/datacloud/',
        client: MockClient(
          (request) async => http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'currentPath': '',
                'items': [
                  {
                    'name': 'board-guide.txt',
                    'relativePath': 'board-guide.txt',
                    'type': 'File',
                  },
                ],
              },
            }),
            200,
          ),
        ),
      );
      final language = LanguageProvider();
      addTearDown(provider.dispose);
      addTearDown(language.dispose);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: provider),
            ChangeNotifierProvider.value(value: language),
          ],
          child: const MaterialApp(home: DataCloudScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Đổi tên'), findsOneWidget);
      await tester.tapAt(const Offset(2, 2));
      await tester.pumpAndSettle();
      await provider.changeScope(DataCloudScope.dataTraining);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      expect(find.text('Đổi tên'), findsNothing);
      expect(find.byIcon(Icons.delete), findsNothing);
      expect(find.byIcon(Icons.download), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}

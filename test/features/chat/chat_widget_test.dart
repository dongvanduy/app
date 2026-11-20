import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_app/features/chat/presentation/providers/chat_provider.dart';
import 'package:mobile_app/features/chat/presentation/screens/chat_list_screen.dart';
import 'package:mobile_app/features/chat/presentation/widgets/chat_emoji_picker.dart';
import 'package:mobile_app/features/chat/presentation/widgets/chat_unread_badge.dart';
import 'package:mobile_app/features/pe_system/presentation/providers/language_provider.dart';
import 'chat_fakes.dart';

void main() {
  test('emoji replaces the selection and enforces the UTF-16 character limit', () {
    final controller = TextEditingController(text: 'Hello world')..selection = const TextSelection(baseOffset: 6, extentOffset: 11);
    expect(insertChatEmoji(controller, '😀'), isTrue); expect(controller.text, 'Hello 😀'); expect(controller.selection.extentOffset, 8);
    controller.text = 'a' * 3999; controller.selection = const TextSelection.collapsed(offset: 3999);
    expect(insertChatEmoji(controller, '😀'), isFalse); controller.dispose();
  });
  for (final language in ['vi','en','zh']) {
    for (final dark in [false, true]) {
      testWidgets('chat list, badge and composer fit 320px ($language, dark=$dark)', (tester) async {
        SharedPreferences.setMockInitialValues({});
        await tester.binding.setSurfaceSize(const Size(320, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final repository = FakeChatRepository()..unread = 120;
        final realtime = FakeChatRealtime();
        final chat = ChatProvider(repository: repository, realtime: realtime, photoPicker: FakePhotoPicker());
        final locale = LanguageProvider(); await locale.setLocale(Locale(language));
        chat.bindUser(1);
        await tester.pumpWidget(MultiProvider(providers: [
          ChangeNotifierProvider<ChatProvider>.value(value: chat), ChangeNotifierProvider<LanguageProvider>.value(value: locale),
        ], child: MaterialApp(theme: dark ? ThemeData.dark() : ThemeData.light(), home: const Scaffold(body: Column(children: [
          ChatUnreadBadge(child: Icon(Icons.chat)), Expanded(child: ChatListScreen()),
        ])))));
        await tester.pump(); await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('99+'), findsOneWidget);
        expect(find.byKey(const ValueKey('chat-conversation-1')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('chat-conversation-1')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('chat-draft')), findsOneWidget);
        await tester.enterText(find.byKey(const ValueKey('chat-draft')), 'Hello Android');
        await tester.tap(find.byKey(const ValueKey('chat-emoji'))); await tester.pump();
        expect(find.byType(ChatEmojiPicker), findsOneWidget);
        await tester.tap(find.text('😀')); await tester.pump();
        await tester.tap(find.byKey(const ValueKey('chat-send'))); await tester.pumpAndSettle();
        expect(repository.sent.single.text, 'Hello Android😀');
        expect(tester.takeException(), isNull);
        await tester.pageBack(); await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('chat-search')), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink()); chat.dispose(); locale.dispose();
      });
    }
  }
  testWidgets('image preview can be removed and logout clears messages and draft', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final repository = FakeChatRepository()..history = [chatMessage('1')];
    final chat = ChatProvider(repository: repository, realtime: FakeChatRealtime(), photoPicker: FakePhotoPicker());
    final locale = LanguageProvider(); chat.bindUser(1);
    await tester.pumpWidget(MultiProvider(providers: [
      ChangeNotifierProvider<ChatProvider>.value(value: chat), ChangeNotifierProvider<LanguageProvider>.value(value: locale),
    ], child: const MaterialApp(home: ChatListScreen())));
    await tester.pump(); await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chat-conversation-1'))); await tester.pumpAndSettle();
    await chat.pickImage('1', camera: false); await tester.pump();
    expect(find.byKey(const ValueKey('chat-remove-image')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('chat-remove-image'))); await tester.pump();
    expect(chat.draftImage('1'), isNull);
    await tester.enterText(find.byKey(const ValueKey('chat-draft')), 'Private draft');
    chat.bindUser(null); await tester.pump();
    expect(chat.messages('1'), isEmpty); expect(chat.draft('1'), isEmpty); expect(find.text('Private draft'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink()); chat.dispose(); locale.dispose();
  });
}

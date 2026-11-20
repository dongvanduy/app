import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_app/core/error/exceptions.dart';
import 'package:mobile_app/features/chat/data/models/chat_dtos.dart';
import 'package:mobile_app/features/chat/domain/entities/chat_models.dart';
import 'package:mobile_app/features/chat/domain/entities/chat_mentions.dart';
import 'package:mobile_app/features/chat/presentation/controllers/chat_mention_controller.dart';
import 'package:mobile_app/features/chat/presentation/providers/chat_provider.dart';
import 'package:mobile_app/features/chat/presentation/screens/chat_list_screen.dart';
import 'package:mobile_app/features/chat/presentation/widgets/chat_mention_suggestions.dart';
import 'package:mobile_app/features/pe_system/presentation/providers/language_provider.dart';
import 'chat_fakes.dart';

const _user = ChatUser(userId: 2, username: 'V2', fullName: 'Đồng Văn Duy', department: 'PE');
const _other = ChatUser(userId: 3, username: 'V3', fullName: 'Đồng Văn Duy', department: 'PE');
const _group = ChatConversation(id: '1', type: 'group', name: 'Team', myRole: 'owner', memberCount: 3, version: '1');
ChatMember _member(ChatUser user) => ChatMember(user: user, role: 'member', joinedAt: DateTime.utc(2026), lastReadSequence: '0');

Future<void> _mount(WidgetTester tester, ChatProvider chat, LanguageProvider language) async {
  await tester.pumpWidget(MultiProvider(providers: [
    ChangeNotifierProvider.value(value: chat), ChangeNotifierProvider.value(value: language),
  ], child: MaterialApp(theme: language.locale.languageCode == 'zh' ? ThemeData.dark() : ThemeData.light(), home: const ChatListScreen())));
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the @ button inserts at the selection and full names with spaces match without accents', () {
    final input = ChatMentionController(text: 'Hello'); addTearDown(input.dispose);
    input.selection = const TextSelection.collapsed(offset: 5);
    expect(input.beginMention(), isTrue); expect(input.text, 'Hello @');
    input.value = const TextEditingValue(text: 'Hello @dong van', selection: TextSelection.collapsed(offset: 15));
    expect(input.suggestions([_member(_user), _member(_other)]).map((user) => user.username), ['V2', 'V3']);
    expect(input.choose(_other), isTrue);
    expect(input.text, 'Hello @Đồng Văn Duy '); expect(input.mentions.single.userId, 3);
    expect(input.query, isNull);
    expect(input.beginMention(), isTrue); expect(input.choose(_user), isTrue);
    expect(input.mentions.map((item) => item.userId), [3, 2]);
    input.restore('mail@example.com', []); expect(input.query, isNull);
    input.restore('', []); expect(input.query, isNull);
  });

  test('selection-aware edits preserve identity when the inserted text equals a token prefix', () {
    final input = ChatMentionController(text: '@Đồng Văn Duy ', mentions: const [ChatMention(userId: 2, start: 0, length: 13)]);
    addTearDown(input.dispose);
    input.selection = const TextSelection.collapsed(offset: 0);
    input.value = const TextEditingValue(text: '@@Đồng Văn Duy ', selection: TextSelection.collapsed(offset: 1));
    expect(input.mentions.single.start, 1);
    input.selection = const TextSelection(baseOffset: 14, extentOffset: 1);
    input.value = const TextEditingValue(text: '@ ', selection: TextSelection.collapsed(offset: 1));
    expect(input.mentions, isEmpty);
    input.restore('😀 @Đồng Văn Duy ', const [ChatMention(userId: 2, start: 3, length: 13)]);
    input.selection = const TextSelection.collapsed(offset: 0);
    input.value = TextEditingValue(text: '📷 ${input.text}', selection: const TextSelection.collapsed(offset: 3));
    expect(input.mentions.single.start, 6);
  });

  test('malformed or conflicting metadata cannot highlight an arbitrary user', () {
    expect(validChatMentions('@User', const [ChatMention(userId: 2, start: 0, length: 5),
      ChatMention(userId: 3, start: 0, length: 5)]), isEmpty);
    expect(validChatMentions('@😀', const [ChatMention(userId: 2, start: 0, length: 2)]), isEmpty);
    final message = ChatDtos.message({'id': '1', 'conversationId': '1', 'sequence': '1', 'senderUserId': 2,
      'clientMessageId': 'uuid', 'text': '@😀 ok @User', 'createdAt': '2026-11-20T00:00:00Z',
      'mentions': [null, {'userId': '2', 'start': 0, 'length': 3}, {'userId': 2, 'start': 0, 'length': 2},
        {'userId': 3, 'start': 7, 'length': 5}]});
    expect(message.text, '@😀 ok @User'); expect(message.mentions.single.userId, 3);
    final input = ChatMentionController(text: '@User', mentions: const [ChatMention(userId: 2, start: -1, length: 5)]);
    addTearDown(input.dispose); expect(input.mentions, isEmpty);
  });

  testWidgets('selected labels use rich text while native IME composition remains intact', (tester) async {
    final input = ChatMentionController(text: '@Đồng Văn Duy ', mentions: const [ChatMention(userId: 2, start: 0, length: 13)]);
    addTearDown(input.dispose);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: TextField(controller: input))));
    final context = tester.element(find.byType(TextField));
    var span = input.buildTextSpan(context: context, withComposing: true);
    expect(span.children!.whereType<TextSpan>().first.style!.fontWeight, FontWeight.w700);
    input.value = const TextEditingValue(text: '@Đồng Văn Duy 中', selection: TextSelection.collapsed(offset: 15), composing: TextRange(start: 14, end: 15));
    expect(input.query, isNull); expect(input.mentions.single.userId, 2);
    span = input.buildTextSpan(context: context, withComposing: true);
    expect(span.toPlainText(), input.text); expect(input.value.composing, const TextRange(start: 14, end: 15));
    input.value = input.value.copyWith(composing: TextRange.empty);
    expect(input.buildTextSpan(context: context, withComposing: true).children!.whereType<TextSpan>().first.style!.fontWeight, FontWeight.w700);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a roster failure does not block history and retry cannot hide a newer send error', (tester) async {
    final repository = FakeChatRepository()..item = _group
      ..membersHandler = (_) async => throw const ServerException('Members unavailable', kind: ApiFailureKind.server, statusCode: 500);
    final chat = ChatProvider(repository: repository, realtime: FakeChatRealtime()); addTearDown(chat.dispose);
    chat.bindUser(1); await tester.pump(); await chat.openConversation('1'); await tester.pump();
    expect(chat.threadReady('1'), isTrue); expect(chat.membersState('1'), ChatMemberLoadState.failed);
    final response = Completer<List<ChatMember>>(); repository.membersHandler = (_) => response.future;
    final operation = chat.reloadMembers('1'); await tester.pump();
    repository.sendError = const ServerException('Offline', kind: ApiFailureKind.network);
    await chat.send('1', 'Keep this error');
    response.complete([_member(_user)]); expect(await operation, isTrue);
    expect(chat.membersState('1'), ChatMemberLoadState.ready); expect(chat.error, 'chatNetwork');
  });

  testWidgets('older roster failures and logout responses cannot overwrite fresh members', (tester) async {
    final repository = FakeChatRepository()..item = _group;
    final chat = ChatProvider(repository: repository, realtime: FakeChatRealtime()); addTearDown(chat.dispose);
    chat.bindUser(1); await tester.pump();
    final first = Completer<List<ChatMember>>(), second = Completer<List<ChatMember>>();
    repository.membersHandler = (_) => repository.memberRequests == 1 ? first.future : second.future;
    final old = chat.loadConversation('1', withMembers: true); await tester.pump();
    final fresh = chat.loadConversation('1', withMembers: true); await tester.pump();
    second.complete([_member(_other)]); expect(await fresh, isTrue);
    first.completeError(const ServerException('Old failure', statusCode: 500)); expect(await old, isFalse);
    expect(chat.error, isNull); expect(chat.members('1').single.user.userId, 3);
    final delayed = Completer<List<ChatMember>>(); repository.membersHandler = (_) => delayed.future;
    final late = chat.loadConversation('1', withMembers: true); await tester.pump();
    chat.bindUser(null); delayed.complete([_member(_user)]); expect(await late, isFalse);
    expect(chat.members('1'), isEmpty); expect(chat.membersState('1'), ChatMemberLoadState.idle);
  });

  for (final language in ['vi', 'en', 'zh']) {
    testWidgets('mobile @ button, loading, search, selection and keyboard fit PDA ($language)', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null)); addTearDown(tester.view.resetViewInsets);
      final response = Completer<List<ChatMember>>();
      final repository = FakeChatRepository()..item = _group..membersHandler = (_) => response.future;
      final chat = ChatProvider(repository: repository, realtime: FakeChatRealtime());
      final locale = LanguageProvider(); await locale.setLocale(Locale(language));
      addTearDown(chat.dispose); addTearDown(locale.dispose); chat.bindUser(1);
      await _mount(tester, chat, locale);
      await tester.tap(find.byKey(const ValueKey('chat-conversation-1')));
      await tester.pump(); await tester.pump(const Duration(milliseconds: 350));
      tester.view.viewInsets = FakeViewPadding(bottom: 300 * tester.view.devicePixelRatio);
      await tester.tap(find.byKey(const ValueKey('chat-mention'))); await tester.pump();
      expect(tester.widget<ChatMentionSuggestions>(find.byType(ChatMentionSuggestions)).state, ChatMemberLoadState.loading);
      expect(repository.memberRequests, 1);
      response.complete([_member(_user), _member(_other)]); await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('chat-draft')), '@dong van'); await tester.pumpAndSettle();
      final target = find.byKey(const ValueKey('chat-mention-user-3'));
      await tester.ensureVisible(target); await tester.tap(target); await tester.pumpAndSettle();
      final input = tester.widget<TextField>(find.byKey(const ValueKey('chat-draft'))).controller! as ChatMentionController;
      expect(input.mentions.single.userId, 3); expect(find.byType(ChatMentionSuggestions), findsNothing);
      await tester.tap(find.byKey(const ValueKey('chat-send'))); await tester.pumpAndSettle();
      expect(repository.sent.single.mentions.single.userId, 3); expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('empty results can be dismissed and mention badge is independent from unread total', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final repository = FakeChatRepository()..item = const ChatConversation(id: '1', type: 'group', name: 'Team',
      memberCount: 3, version: '1', unreadMentionCount: 2, unreadCount: 0)..groupMembers = [_member(_user)];
    final chat = ChatProvider(repository: repository, realtime: FakeChatRealtime());
    final locale = LanguageProvider(); await locale.setLocale(const Locale('vi'));
    addTearDown(chat.dispose); addTearDown(locale.dispose); chat.bindUser(1);
    await _mount(tester, chat, locale); await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('chat-unread-mention-1'))); await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('chat-draft')), '@does not exist'); await tester.pumpAndSettle();
    expect(find.byType(ChatMentionSuggestions), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('chat-mention-dismiss'))); await tester.pumpAndSettle();
    expect(find.byType(ChatMentionSuggestions), findsNothing);
    expect(tester.widget<TextField>(find.byKey(const ValueKey('chat-draft'))).controller!.text, '@does not exist');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('roster retry preserves the draft and hardware keys select the intended account', (tester) async {
    SharedPreferences.setMockInitialValues({});
    var offline = true;
    final repository = FakeChatRepository()..item = _group..membersHandler = (_) async {
      if (offline) throw const ServerException('Members unavailable', kind: ApiFailureKind.server, statusCode: 500);
      return [_member(_user), _member(_other)];
    };
    final chat = ChatProvider(repository: repository, realtime: FakeChatRealtime());
    final locale = LanguageProvider(); await locale.setLocale(const Locale('vi'));
    addTearDown(chat.dispose); addTearDown(locale.dispose); chat.bindUser(1);
    await _mount(tester, chat, locale);
    await tester.tap(find.byKey(const ValueKey('chat-conversation-1'))); await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('chat-draft')), '@dong van'); await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chat-mention-retry')), findsOneWidget);
    offline = false;
    await tester.tap(find.byKey(const ValueKey('chat-mention-retry'))); await tester.pumpAndSettle();
    final field = tester.widget<TextField>(find.byKey(const ValueKey('chat-draft')));
    expect(field.controller!.text, '@dong van'); expect(field.focusNode!.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown); await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter); await tester.pumpAndSettle();
    expect((field.controller! as ChatMentionController).mentions.single.userId, 3);
    expect(repository.sent, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('roster reordering keeps the highlighted user and removal requires a new choice', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final repository = FakeChatRepository()..item = _group..groupMembers = [_member(_user), _member(_other)];
    final chat = ChatProvider(repository: repository, realtime: FakeChatRealtime());
    final locale = LanguageProvider(); await locale.setLocale(const Locale('vi'));
    addTearDown(chat.dispose); addTearDown(locale.dispose); chat.bindUser(1);
    await _mount(tester, chat, locale);
    await tester.tap(find.byKey(const ValueKey('chat-conversation-1'))); await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('chat-draft')), '@dong'); await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown); await tester.pump();
    repository.groupMembers = [_member(_other), _member(_user)];
    await chat.loadConversation('1', withMembers: true); await tester.pumpAndSettle();
    expect(tester.widget<ChatMentionSuggestions>(find.byType(ChatMentionSuggestions)).selected, 0);
    repository.groupMembers = [_member(_user)];
    await chat.loadConversation('1', withMembers: true); await tester.pumpAndSettle();
    expect(tester.widget<ChatMentionSuggestions>(find.byType(ChatMentionSuggestions)).selected, -1);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter); await tester.pump();
    final input = tester.widget<TextField>(find.byKey(const ValueKey('chat-draft'))).controller! as ChatMentionController;
    expect(input.mentions, isEmpty); expect(repository.sent, isEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown); await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter); await tester.pumpAndSettle();
    expect(input.mentions.single.userId, 2);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

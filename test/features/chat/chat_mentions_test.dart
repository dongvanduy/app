import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_app/core/error/exceptions.dart';
import 'package:mobile_app/features/chat/domain/entities/chat_models.dart';
import 'package:mobile_app/features/chat/data/models/chat_dtos.dart';
import 'package:mobile_app/features/chat/presentation/controllers/chat_mention_controller.dart';
import 'package:mobile_app/features/chat/presentation/providers/chat_provider.dart';
import 'package:mobile_app/features/chat/presentation/screens/chat_thread_screen.dart';
import 'package:mobile_app/features/chat/presentation/widgets/chat_emoji_picker.dart';
import 'package:mobile_app/features/pe_system/presentation/providers/language_provider.dart';
import 'chat_fakes.dart';

const selectedUser = ChatUser(userId: 2, username: 'V2', fullName: 'Đồng Văn Duy', department: 'PE');
const group = ChatConversation(id: '1', type: 'group', name: 'Group', myRole: 'owner', memberCount: 3, version: '1');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('selection creates UTF-16 spans; emoji shifts them and editing a label removes identity', () {
    final controller = ChatMentionController(text: '😀 @duy');
    addTearDown(controller.dispose);
    controller.selection = TextSelection.collapsed(offset: controller.text.length);
    expect(controller.choose(selectedUser), isTrue);
    expect(controller.mentions.single.start, 3); expect(controller.mentions.single.length, 13);
    controller.selection = const TextSelection.collapsed(offset: 0);
    insertChatEmoji(controller, '😀');
    expect(controller.mentions.single.start, 5);
    controller.value = TextEditingValue(text: controller.text.replaceFirst('Đồng', 'Đong'));
    expect(controller.mentions, isEmpty); expect(controller.text, contains('@Đong'));
    controller.text = '@Đồng Văn Duy';
    expect(controller.mentions, isEmpty);
    expect(normalizeChatMentionSearch('ĐỒNG VĂN DUY'), 'dong van duy');
  });

  test('IME and message limits prevent accidental selection', () {
    final controller = ChatMentionController(text: '@duy');
    addTearDown(controller.dispose);
    controller.value = const TextEditingValue(text: '@duy', selection: TextSelection.collapsed(offset: 4), composing: TextRange(start: 0, end: 4));
    expect(controller.query, isNull); expect(controller.choose(selectedUser), isFalse);
    controller.value = TextEditingValue(text: '${'a' * 3990} @duy', selection: const TextSelection.collapsed(offset: 3995));
    expect(controller.choose(selectedUser), isFalse); expect(controller.mentions, isEmpty);
    controller.restore('@Đồng Văn Duy', const [ChatMention(userId: 2, start: 0, length: 13)]);
    controller.clear(); expect(controller.mentions, isEmpty);
  });

  testWidgets('pending image retry keeps UUID/mention and logout clears mention drafts', (tester) async {
    final repo = FakeChatRepository()..item = group..sendError = const ServerException('Offline', kind: ApiFailureKind.network);
    final chat = ChatProvider(repository: repo, realtime: FakeChatRealtime(), photoPicker: FakePhotoPicker());
    addTearDown(chat.dispose);
    chat.bindUser(1); await tester.pump(); await chat.openConversation('1');
    await chat.pickImage('1', camera: false);
    const mentions = [ChatMention(userId: 2, start: 0, length: 13)];
    await chat.send('1', '@Đồng Văn Duy', mentions: mentions);
    final pending = chat.messages('1').single;
    repo.sendError = null; await chat.retry(pending.clientMessageId);
    expect(repo.sent[0].id, repo.sent[1].id);
    expect(repo.sent[1].mentions.single.toJson(), mentions.single.toJson());
    expect(repo.sent[0].image, same(repo.sent[1].image));
    chat.setDraft('1', '@Đồng Văn Duy', mentions: mentions);
    repo.delayedSend = Completer<ChatMessage>();
    final operation = chat.send('1', '@Đồng Văn Duy', mentions: mentions);
    chat.bindUser(null);
    repo.delayedSend!.complete(chatMessage('2', sender: 1, mentions: mentions)); await operation;
    expect(chat.draftMentions('1'), isEmpty); expect(chat.messages('1'), isEmpty);
  });

  for (final width in [320.0, 360.0]) {
    testWidgets('mention picker distinguishes identical names and sends an image caption on $width PDA', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.binding.setSurfaceSize(Size(width, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null)); addTearDown(tester.view.resetViewInsets);
      final repo = FakeChatRepository()..item = group..groupMembers = [
        ChatMember(user: selectedUser, role: 'member', joinedAt: DateTime.utc(2026), lastReadSequence: '0'),
        ChatMember(user: const ChatUser(userId: 3, username: 'V3', fullName: 'Đồng Văn Duy', department: 'PE'),
          role: 'member', joinedAt: DateTime.utc(2026), lastReadSequence: '0'),
      ];
      final chat = ChatProvider(repository: repo, realtime: FakeChatRealtime(), photoPicker: FakePhotoPicker());
      final language = LanguageProvider(); await language.setLocale(const Locale('vi'));
      addTearDown(chat.dispose); addTearDown(language.dispose); chat.bindUser(1);
      await tester.pumpWidget(MultiProvider(providers: [ChangeNotifierProvider.value(value: chat),
        ChangeNotifierProvider.value(value: language)], child: MaterialApp(
          theme: width == 320 ? ThemeData.light() : ThemeData.dark(), home: const ChatThreadScreen(conversationId: '1'))));
      await tester.pumpAndSettle();
      tester.view.viewInsets = FakeViewPadding(bottom: 300 * tester.view.devicePixelRatio);
      await tester.enterText(find.byKey(const ValueKey('chat-draft')), '@duy'); await tester.pumpAndSettle();
      expect(find.text('V2'), findsOneWidget); expect(find.text('V3'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('chat-mention-user-3'))); await tester.pump();
      await chat.pickImage('1', camera: false); await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('chat-send'))); await tester.pumpAndSettle();
      expect(repo.sent.single.mentions.single.userId, 3); expect(repo.sent.single.image, isNotNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  test('DTO defaults preserve old messages and parses typed mention metadata', () {
    final input = {'id': '9007199254740993', 'conversationId': '1', 'sequence': '2', 'senderUserId': 2,
      'clientMessageId': 'uuid', 'text': '@Đồng Văn Duy', 'createdAt': '2026-11-11T00:00:00Z'};
    expect(ChatDtos.message(input).mentions, isEmpty);
    input['mentions'] = [{'userId': 2, 'start': 0, 'length': 13}];
    expect(ChatDtos.message(input).mentions.single.userId, 2);
  });
}

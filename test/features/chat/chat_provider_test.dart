import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/core/error/exceptions.dart';
import 'package:mobile_app/features/chat/data/models/chat_dtos.dart';
import 'package:mobile_app/features/chat/domain/entities/chat_models.dart';
import 'package:mobile_app/features/chat/presentation/providers/chat_provider.dart';
import 'chat_fakes.dart';

Future<void> settleChat() async { for (var i = 0; i < 6; i++) { await Future<void>.delayed(Duration.zero); } }

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeChatRepository repository;
  late FakeChatRealtime realtime;
  late FakePhotoPicker photos;
  late ChatProvider provider;
  setUp(() {
    repository = FakeChatRepository(); realtime = FakeChatRealtime(); photos = FakePhotoPicker();
    provider = ChatProvider(repository: repository, realtime: realtime, photoPicker: photos);
  });
  tearDown(() => provider.dispose());
  test('DTO preserves BIGINT strings and normalizes UTC time', () {
    final message = ChatDtos.message({'id':'9007199254740993','conversationId':'1','sequence':'9007199254740994',
      'senderUserId':2,'clientMessageId':'ABC','text':'Hi 😀','createdAt':'2026-01-01T07:00:00+07:00','image':null});
    expect(message.id, '9007199254740993'); expect(message.createdAt.hour, 0);
    expect(compareChatSequence(message.sequence!, '9007199254740993'), greaterThan(0));
  });
  test('empty thread opens and merges duplicate, out of order events without gaps', () async {
    provider.bindUser(1); await settleChat(); await provider.openConversation('1');
    realtime.messageController.add(chatMessage('2')); await settleChat();
    await provider.markRead('1', '2'); expect(repository.readSequences, isEmpty);
    realtime.messageController.add(chatMessage('1')); realtime.messageController.add(chatMessage('2'));
    await settleChat(); await provider.markRead('1', '2');
    expect(provider.messages('1').map((item) => item.sequence), ['1','2']);
    expect(repository.readSequences, ['2']);
  });
  test('image retry keeps UUID and original bytes and clears pending on commit', () async {
    provider.bindUser(1); await settleChat(); await provider.openConversation('1');
    await provider.pickImage('1', camera: false);
    repository.sendError = const ServerException('offline', kind: ApiFailureKind.network);
    await provider.send('1', 'Caption 😀');
    final pending = provider.messages('1').single;
    expect(pending.delivery, ChatDelivery.failed); expect(pending.draftImage!.bytes, pngBytes);
    repository.sendError = null;
    await provider.retry(pending.clientMessageId);
    expect(repository.sent[0].id, repository.sent[1].id);
    expect(identical(repository.sent[0].image, repository.sent[1].image), isTrue);
    expect(provider.messages('1').length, 1); expect(provider.messages('1').single.delivery, ChatDelivery.sent);
  });
  test('a late send after account change cannot repopulate cleared memory', () async {
    provider.bindUser(1); await settleChat(); await provider.openConversation('1');
    repository.delayedSend = Completer<ChatMessage>();
    final operation = provider.send('1', 'Hello');
    provider.bindUser(null); provider.bindUser(3);
    repository.delayedSend!.complete(chatMessage('1', sender: 1));
    await operation; expect(provider.messages('1'), isEmpty); expect(provider.draftImage('1'), isNull);
  });
  test('picker result after logout is discarded and cancel preserves selected image', () async {
    provider.bindUser(1); await settleChat(); await provider.openConversation('1');
    await provider.pickImage('1', camera: false); final original = provider.draftImage('1');
    photos.operation = Completer<ChatDraftImage?>(); final cancel = provider.pickImage('1', camera: false);
    photos.operation!.complete(null); await cancel; expect(provider.draftImage('1'), same(original));
    photos.operation = Completer<ChatDraftImage?>(); final late = provider.pickImage('1', camera: false);
    provider.bindUser(null); photos.operation!.complete(original); await late;
    expect(provider.draftImage('1'), isNull);
  });
  test('search generation rejects responses for a previous query', () async {
    provider.bindUser(1); await settleChat();
    final first = Completer<ChatPage<ChatUser>>();
    repository.searchHandler = (query, after) => query == 'old' ? first.future : Future.value(const ChatPage([], false));
    final old = provider.searchUsers('old'); provider.invalidateSearch('new'); await provider.searchUsers('new');
    first.complete(const ChatPage([chatUser], false)); await old; expect(provider.users, isEmpty);
  });
  testWidgets('background stops realtime and polling; resume starts and reconciles', (tester) async {
    provider.bindUser(1); await tester.pump(); await tester.pump();
    final requests = repository.conversationRequests;
    provider.didChangeAppLifecycleState(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 40)); expect(repository.conversationRequests, requests);
    provider.didChangeAppLifecycleState(AppLifecycleState.resumed); await tester.pump(); await tester.pump();
    expect(repository.conversationRequests, greaterThan(requests)); expect(realtime.starts, 2);
  });
}

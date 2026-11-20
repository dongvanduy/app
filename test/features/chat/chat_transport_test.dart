import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile_app/core/network/api_client.dart';
import 'package:mobile_app/core/network/auth_token_provider.dart';
import 'package:mobile_app/features/chat/data/services/chat_realtime_service.dart';
import 'package:mobile_app/features/chat/data/services/chat_image_service.dart';
import 'chat_fakes.dart';

class TestChatTokens implements AuthTokenProvider {
  @override
  String? accessToken = 'old-token';
  int refreshes = 0;
  @override
  Future<String?> refreshAccessToken() async { refreshes++; return accessToken = 'new-token'; }
}

void main() {
  test('SignalR decoder buffers split records and emits multiple events after handshake', () {
    final decoder = ChatHubDecoder();
    expect(decoder.add('{'), isEmpty);
    expect(decoder.add('}\u001e{"type":6}\u001e{"type":1'), [{'type':6}]);
    expect(decoder.handshaken, isTrue);
    expect(decoder.add(',"target":"MessageCreated","arguments":[]}\u001e').single['target'], 'MessageCreated');
    expect(() => ChatHubDecoder().add('{"error":"unsupported"}\u001e'), throwsFormatException);
  });
  test('native WebSocket uses a Bearer header and exchanges SignalR keepalive frames', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final receivedPing = Completer<void>();
    WebSocket? peer;
    server.listen((request) async {
      expect(request.uri.queryParameters.containsKey('access_token'), isFalse);
      expect(request.headers.value('Authorization'), 'Bearer old-token');
      final socket = await WebSocketTransformer.upgrade(request); peer = socket;
      socket.listen((dynamic chunk) {
        if ((chunk as String).contains('"protocol"')) {
          socket.add('{}\u001e{"type":1,"target":"MessageCreated","arguments":[{"id":"1","conversationId":"1","sequence":"1","senderUserId":2,"clientMessageId":"test","text":"Hello","createdAt":"2026-01-01T00:00:00Z"}]}\u001e');
        } else if (chunk.contains('"type":6') && !receivedPing.isCompleted) { receivedPing.complete(); }
      });
    });
    final realtime = ChatRealtimeService(hubUrl: 'http://127.0.0.1:${server.port}/api/hubs/chat', tokens: TestChatTokens(), keepAlive: const Duration(milliseconds: 30));
    final event = realtime.messages.first;
    try {
      await realtime.start(); expect((await event.timeout(const Duration(seconds: 3))).text, 'Hello');
      await receivedPing.future.timeout(const Duration(seconds: 3));
    } finally { await realtime.dispose(); await peer?.close(); await server.close(force: true); }
  });
  test('handshake timeout degrades without blocking REST and stop cancels retry', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final peers = <WebSocket>[];
    var requests = 0;
    server.listen((request) async { requests++; final peer = await WebSocketTransformer.upgrade(request); peers.add(peer); peer.listen((_) {}); });
    final realtime = ChatRealtimeService(hubUrl: 'http://127.0.0.1:${server.port}/hub', tokens: TestChatTokens(),
      handshakeTimeout: const Duration(milliseconds: 30), retryDelays: const [Duration(milliseconds: 80)]);
    try {
      await realtime.start(); await realtime.stop();
      final stoppedRequests = requests; await Future<void>.delayed(const Duration(milliseconds: 160));
      expect(requests, stoppedRequests);
    } finally { await realtime.dispose(); for (final peer in peers) { await peer.close(); } await server.close(force: true); }
  });
  test('native adapter receives group changes and removal across split and combined records', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    WebSocket? peer;
    server.listen((request) async {
      expect(request.headers.value('Authorization'), 'Bearer old-token');
      final socket = await WebSocketTransformer.upgrade(request); peer = socket;
      socket.listen((dynamic data) {
        if (!(data as String).contains('"protocol"')) return;
        socket.add('{}\u001e{"type":1,"target":"ConversationChanged","arguments":[{"conversationId":"1",');
        socket.add('"version":"9007199254740993"}]}\u001e{"type":1,"target":"ConversationRemoved","arguments":[{"conversationId":"1","version":"9007199254740994"}]}\u001e');
      });
    });
    final realtime = ChatRealtimeService(hubUrl: 'http://127.0.0.1:${server.port}/api/hubs/chat', tokens: TestChatTokens());
    final result = realtime.changes.take(2).toList();
    try {
      await realtime.start(); final events = await result.timeout(const Duration(seconds: 3));
      expect(events.map((event) => event.version), ['9007199254740993', '9007199254740994']);
      expect(events.map((event) => event.removed), [false, true]);
    } finally { await realtime.dispose(); await peer?.close(); await server.close(force: true); }
  });
  test('DELETE member retries authentication and accepts an empty 204 response', () async {
    final tokens = TestChatTokens(); var count = 0;
    final api = ApiClient(baseUrl: 'https://example.test/api/chat/', authTokenProvider: tokens,
      client: MockClient((request) async {
        count++; expect(request.method, 'DELETE'); expect(request.url.path, '/api/chat/groups/1/members/2');
        expect(request.headers['authorization'], count == 1 ? 'Bearer old-token' : 'Bearer new-token');
        return http.Response(count == 1 ? '{}' : '', count == 1 ? 401 : 204);
      }));
    try { expect(await api.delete('groups/1/members/2'), isNull); expect(count, 2); expect(tokens.refreshes, 1); }
    finally { api.close(); }
  });
  test('revoking one conversation evicts its bytes and pending download without clearing another', () async {
    final cache = ChatImageCache();
    await cache.load('1:first', () async => pngBytes); await cache.load('2:keep', () async => pngBytes);
    final delayed = Completer<Uint8List>(); final late = cache.load('1:late', () => delayed.future);
    final rejected = expectLater(late, throwsStateError);
    cache.evictConversation('1'); delayed.complete(pngBytes); await rejected;
    expect(cache.byteLength, pngBytes.length);
    expect(await cache.load('2:keep', () => throw StateError('Should use cache')), pngBytes);
    cache.clear();
  });
  test('multipart retries after refresh with the same UUID, fields and bytes', () async {
    final tokens = TestChatTokens(); var count = 0; final bodies = <String>[];
    final api = ApiClient(baseUrl: 'https://example.test/api/chat/', authTokenProvider: tokens,
      client: MockClient((request) async {
        count++; bodies.add(latin1.decode(request.bodyBytes));
        expect(request.headers['content-type'], startsWith('multipart/form-data; boundary='));
        expect(request.headers['authorization'], count == 1 ? 'Bearer old-token' : 'Bearer new-token');
        return http.Response(count == 1 ? '{"message":"expired"}' : '{"id":"1"}', count == 1 ? 401 : 200);
      }));
    await api.postMultipart('conversations/1/images', fields: {'clientMessageId':'same-id','text':'caption'}, bytes: pngBytes, fileName: 'image.png');
    expect(count, 2); expect(tokens.refreshes, 1);
    for (final body in bodies) { expect(body, contains('same-id')); expect(body, contains('caption')); expect(body, contains(latin1.decode(pngBytes))); }
    api.close();
  });
  test('PUT and image download share Bearer authentication and preserve image bytes', () async {
    final tokens = TestChatTokens();
    final api = ApiClient(baseUrl: 'https://example.test/api/chat/', authTokenProvider: tokens,
      client: MockClient((request) async {
        expect(request.headers['authorization'], 'Bearer old-token');
        if (request.method == 'PUT') { expect(jsonDecode(request.body), {'lastReadSequence':'9'}); return http.Response('{}', 200); }
        return http.Response.bytes(pngBytes, 200, headers: {'content-type':'image/png'});
      }));
    await api.put('conversations/1/read', {'lastReadSequence':'9'});
    expect(await api.getBytes('conversations/1/messages/9/image'), pngBytes); api.close();
  });
  test('byte cache shares downloads, evicts within its limit and discards logout responses', () async {
    var evicted = 0;
    final cache = ChatImageCache(maximumBytes: pngBytes.length * 2, onEvict: (_) => evicted++);
    var requests = 0;
    Future<Uint8List> fetch() async { requests++; return pngBytes; }
    await Future.wait([cache.load('1', fetch), cache.load('1', fetch)]); expect(requests, 1);
    await cache.load('2', fetch); await cache.load('3', fetch); expect(cache.byteLength, lessThanOrEqualTo(cache.maximumBytes));
    expect(evicted, 1);
    final delayed = Completer<Uint8List>(); final late = cache.load('late', () => delayed.future);
    final rejected = expectLater(late, throwsStateError); cache.clear(); delayed.complete(pngBytes);
    await rejected; expect(cache.byteLength, 0); expect(evicted, 3);
  });
}

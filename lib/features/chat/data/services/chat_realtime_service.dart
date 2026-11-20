import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../../../../core/network/auth_token_provider.dart';
import '../../domain/entities/chat_models.dart';
import '../models/chat_dtos.dart';

enum ChatConnectionState { offline, connecting, connected }

abstract interface class ChatRealtimeClient {
  Stream<ChatMessage> get messages;
  Stream<ChatReadState> get reads;
  Stream<ChatConversationChange> get changes;
  Stream<ChatConnectionState> get states;
  Future<void> start();
  Future<void> stop();
  Future<void> dispose();
}

/// SignalR JSON v1 framing. A socket event may contain partial or multiple records.
class ChatHubDecoder {
  String _buffer = '';
  bool handshaken = false;
  List<Map<String, dynamic>> add(String chunk) {
    _buffer += chunk;
    if (_buffer.length > 1024 * 1024) throw const FormatException('Chat frame too large');
    final records = _buffer.split('\u001e');
    _buffer = records.removeLast();
    final result = <Map<String, dynamic>>[];
    for (final record in records) {
      if (record.isEmpty) continue;
      final value = ChatDtos.object(jsonDecode(record));
      if (!handshaken) {
        if (value.containsKey('error') || value.containsKey('type')) throw const FormatException('Chat handshake rejected');
        handshaken = true;
      } else { result.add(value); }
    }
    return result;
  }
}

class ChatRealtimeService implements ChatRealtimeClient {
  ChatRealtimeService({required this.hubUrl, required this.tokens,
    this.handshakeTimeout = const Duration(seconds: 15), this.keepAlive = const Duration(seconds: 15),
    this.serverTimeout = const Duration(seconds: 45), this.retryDelays = const [Duration.zero, Duration(seconds: 2), Duration(seconds: 10), Duration(seconds: 30)]});
  final String hubUrl;
  final AuthTokenProvider tokens;
  final Duration handshakeTimeout, keepAlive, serverTimeout;
  final List<Duration> retryDelays;
  final _messages = StreamController<ChatMessage>.broadcast();
  final _reads = StreamController<ChatReadState>.broadcast();
  final _changes = StreamController<ChatConversationChange>.broadcast();
  final _states = StreamController<ChatConnectionState>.broadcast();
  WebSocket? _socket;
  StreamSubscription<dynamic>? _subscription;
  Timer? _retry, _ping, _watchdog;
  bool _enabled = false, _disposed = false;
  int _generation = 0, _attempt = 0;
  int? _connecting;
  @override
  Stream<ChatMessage> get messages => _messages.stream;
  @override
  Stream<ChatReadState> get reads => _reads.stream;
  @override
  Stream<ChatConversationChange> get changes => _changes.stream;
  @override
  Stream<ChatConnectionState> get states => _states.stream;

  @override
  Future<void> start() async {
    if (_disposed) return;
    if (!_enabled) { _enabled = true; _generation++; }
    if (_socket != null || _connecting == _generation) return;
    _retry?.cancel();
    await _connect(_generation);
  }

  Future<String?> _token() async {
    final token = tokens.accessToken;
    if (token == null || token.isEmpty) return null;
    try {
      final claims = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(token.split('.')[1])))) as Map;
      final expiry = claims['exp'];
      if (expiry is num && DateTime.now().millisecondsSinceEpoch ~/ 1000 >= expiry - 30) return tokens.refreshAccessToken();
    } on Object { /* Opaque/test tokens are validated by the server. */ }
    return token;
  }

  bool _current(int generation) => !_disposed && _enabled && generation == _generation;

  Future<WebSocket> _openSocket(Uri uri, String token, int generation) {
    var timedOut = false;
    final operation = WebSocket.connect(uri.toString(), headers: {'Authorization': 'Bearer $token'}).then((socket) {
      if (timedOut || !_current(generation)) {
        unawaited(socket.close());
        throw StateError('Chat socket request canceled');
      }
      return socket;
    });
    return operation.timeout(handshakeTimeout, onTimeout: () {
      timedOut = true;
      throw TimeoutException('Chat socket connection timed out');
    });
  }

  Future<void> _connect(int generation) async {
    if (!_current(generation) || _connecting == generation) return;
    _connecting = generation;
    _states.add(ChatConnectionState.connecting);
    WebSocket? socket;
    try {
      var token = await _token();
      if (!_current(generation) || token == null) throw const WebSocketException('No active chat session');
      final base = Uri.parse(hubUrl);
      final uri = base.replace(scheme: base.scheme == 'https' ? 'wss' : base.scheme == 'http' ? 'ws' : base.scheme);
      try {
        socket = await _openSocket(uri, token, generation);
      } on WebSocketException catch (error) {
        if (!RegExp(r'\b401\b').hasMatch(error.message ?? '')) rethrow;
        // A stale server-side token may be rejected before a hub handshake exists.
        if (!_current(generation)) return;
        token = await tokens.refreshAccessToken();
        if (!_current(generation) || token == null) rethrow;
        socket = await _openSocket(uri, token, generation);
      }
      if (!_current(generation)) { await socket.close(); return; }
      _socket = socket;
      final connectedSocket = socket;
      final decoder = ChatHubDecoder();
      final handshake = Completer<void>();
      var lastReceived = DateTime.now();
      void closed() {
        if (!handshake.isCompleted) handshake.completeError(const WebSocketException('Chat socket closed'));
        if (_current(generation) && identical(_socket, connectedSocket)) _disconnectAndRetry(generation);
      }
      _subscription = socket.listen((dynamic chunk) {
        if (!_current(generation) || !identical(_socket, connectedSocket)) return;
        lastReceived = DateTime.now();
        try {
          final frames = decoder.add(chunk is String ? chunk : utf8.decode(chunk as List<int>));
          if (decoder.handshaken && !handshake.isCompleted) handshake.complete();
          for (final frame in frames) {
            if (frame['type'] == 7) { closed(); return; }
            if (frame['type'] != 1) continue;
            final arguments = frame['arguments'];
            if (arguments is! List || arguments.isEmpty) continue;
            switch (frame['target']) {
              case 'MessageCreated': _messages.add(ChatDtos.message(arguments.first));
              case 'ReadStateChanged': _reads.add(ChatDtos.read(arguments.first));
              case 'ConversationChanged': _changes.add(ChatDtos.change(arguments.first));
              case 'ConversationRemoved': _changes.add(ChatDtos.change(arguments.first, removed: true));
            }
          }
        } on Object { closed(); }
      }, onError: (Object _) => closed(), onDone: closed, cancelOnError: true);
      socket.add('{"protocol":"json","version":1}\u001e');
      await handshake.future.timeout(handshakeTimeout);
      if (!_current(generation) || !identical(_socket, connectedSocket)) return;
      _attempt = 0;
      _states.add(ChatConnectionState.connected);
      _ping = Timer.periodic(keepAlive, (_) {
        try { connectedSocket.add('{"type":6}\u001e'); } on Object { closed(); }
      });
      _watchdog = Timer.periodic(const Duration(seconds: 5), (_) {
        if (DateTime.now().difference(lastReceived) > serverTimeout) closed();
      });
    } on Object {
      if (_current(generation)) _disconnectAndRetry(generation);
      if (socket != null && !identical(_socket, socket)) unawaited(socket.close());
    } finally { if (_connecting == generation) _connecting = null; }
  }

  void _disconnectAndRetry(int generation) {
    if (!_current(generation)) return;
    _ping?.cancel(); _watchdog?.cancel();
    final socket = _socket;
    _socket = null;
    unawaited(_subscription?.cancel());
    _subscription = null;
    if (socket != null) unawaited(socket.close());
    _states.add(ChatConnectionState.offline);
    if (_retry?.isActive == true || tokens.accessToken == null) return;
    final delay = retryDelays[_attempt.clamp(0, retryDelays.length - 1).toInt()];
    _attempt++;
    _retry = Timer(delay, () { if (_current(generation)) unawaited(_connect(generation)); });
  }

  @override
  Future<void> stop() async {
    _enabled = false; _generation++;
    final generation = _generation;
    _retry?.cancel(); _ping?.cancel(); _watchdog?.cancel();
    final socket = _socket; _socket = null;
    final subscription = _subscription; _subscription = null;
    await subscription?.cancel();
    await socket?.close();
    if (!_disposed && generation == _generation) _states.add(ChatConnectionState.offline);
  }
  @override
  Future<void> dispose() async {
    await stop(); _disposed = true;
    await _messages.close(); await _reads.close(); await _changes.close(); await _states.close();
  }
}

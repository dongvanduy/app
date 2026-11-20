import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/widgets.dart';
import 'package:flutter/painting.dart' show MemoryImage;
import 'package:uuid/uuid.dart';
import '../../../../core/error/exceptions.dart';
import '../../data/services/chat_image_service.dart';
import '../../data/services/chat_realtime_service.dart';
import '../../domain/entities/chat_models.dart';
import '../../domain/repositories/chat_repository.dart';

enum ChatMemberLoadState { idle, loading, ready, failed }

class ChatProvider extends ChangeNotifier with WidgetsBindingObserver {
  ChatProvider({required this.repository, required this.realtime, this.onUnauthorized, this.closeClient, ChatPhotoPicker? photoPicker})
      : photoPicker = photoPicker ?? ChatImageService() {
    WidgetsBinding.instance.addObserver(this);
  }
  final ChatRepository repository;
  final ChatRealtimeClient realtime;
  final ChatPhotoPicker photoPicker;
  final VoidCallback? onUnauthorized;
  final VoidCallback? closeClient;
  final images = ChatImageCache(onEvict: _evictImage);
  static void _evictImage(Uint8List bytes) { unawaited(MemoryImage(bytes).evict()); }
  void _clearDraftImages() {
    for (final image in _draftImages.values) { _evictImage(image.bytes); }
    for (final message in _pending.values) {
      if (message.draftImage != null) _evictImage(message.draftImage!.bytes);
    }
  }
  final _subscriptions = <StreamSubscription<dynamic>>[];
  final _conversations = <String, ChatConversation>{};
  final _members = <String, Map<int, ChatMember>>{};
  final _memberStates = <String, ChatMemberLoadState>{};
  final _memberRevisions = <String, int>{};
  // Read events can arrive while the initial roster request is still in flight.
  final _memberReadCursors = <String, Map<int, String>>{};
  final _removed = <String, String>{};
  final _conversationEpochs = <String, int>{};
  final _messages = <String, Map<String, ChatMessage>>{};
  final _pending = <String, ChatMessage>{};
  final _synced = <String, String>{};
  final _drafts = <String, String>{};
  final _draftMentions = <String, List<ChatMention>>{};
  final _draftImages = <String, ChatDraftImage>{};
  final _older = <String, bool>{};
  final _initializedThreads = <String>{};
  Timer? _poll;
  int? _userId;
  int _generation = 0, _selection = 0, _searchRequest = 0, _conversationPages = 1, _errorRevision = 0;
  bool _foreground = true, _disposed = false, _syncing = false, _syncAgain = false;
  bool _opening = false, _loadingOlder = false, _reading = false, _searching = false;
  bool _moreUsers = false, _moreConversations = false;
  String? _activeId;
  List<ChatUser> _users = [];
  String _search = '';
  int _unread = 0;
  String? _error;
  ChatConnectionState _connection = ChatConnectionState.offline;
  int? get userId => _userId;
  int get generation => _generation;
  bool get foreground => _foreground;
  int get unreadCount => _unread;
  String? get error => _error;
  bool get opening => _opening;
  bool get loadingOlder => _loadingOlder;
  bool get searching => _searching;
  bool get moreUsers => _moreUsers;
  bool get moreConversations => _moreConversations;
  List<ChatUser> get users => List.unmodifiable(_users);
  String get search => _search;
  ChatConnectionState get connection => _connection;
  ChatConversation? conversation(String id) => _conversations[id];
  int conversationEpoch(String id) => _conversationEpochs[id] ?? 0;
  bool wasRemoved(String id) => _removed.containsKey(id);
  List<ChatMember> members(String id) => List.unmodifiable(_members[id]?.values ?? <ChatMember>[]);
  ChatMemberLoadState membersState(String id) => _memberStates[id] ?? ChatMemberLoadState.idle;
  List<ChatMember> readers(ChatMessage message) => message.sequence == null ? [] : members(message.conversationId)
    .where((member) => member.user.userId != message.senderUserId && compareChatSequence(member.lastReadSequence, message.sequence!) >= 0).toList();
  String draft(String id) => _drafts[id] ?? '';
  List<ChatMention> draftMentions(String id) => List.unmodifiable(_draftMentions[id] ?? const <ChatMention>[]);
  ChatDraftImage? draftImage(String id) => _draftImages[id];
  bool hasOlder(String id) => _older[id] ?? false;
  bool threadReady(String id) => _initializedThreads.contains(id);
  List<ChatConversation> get conversations => _conversations.values.toList()..sort((a, b) {
    final time = (b.lastMessage?.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(a.lastMessage?.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0));
    return time != 0 ? time : compareChatSequence(b.id, a.id);
  });
  List<ChatMessage> messages(String id) {
    final saved = (_messages[id]?.values.toList() ?? <ChatMessage>[])..sort((a, b) => compareChatSequence(a.sequence!, b.sequence!));
    return [...saved, ..._pending.values.where((item) => item.conversationId == id)];
  }
  bool _current(int generation) => !_disposed && _userId != null && generation == _generation;
  void _notify() { if (!_disposed) notifyListeners(); }

  void bindUser(int? id) {
    if (_userId == id || _disposed) return;
    _generation++; _selection++; _searchRequest++;
    _userId = id; _activeId = null;
    for (final subscription in _subscriptions) { unawaited(subscription.cancel()); }
    _subscriptions.clear();
    _poll?.cancel(); unawaited(realtime.stop());
    _clearDraftImages();
    images.clear(); _conversations.clear(); _messages.clear(); _pending.clear(); _synced.clear();
    _drafts.clear(); _draftMentions.clear(); _draftImages.clear(); _older.clear(); _initializedThreads.clear(); _users = [];
    _members.clear(); _memberStates.clear(); _memberRevisions.clear(); _memberReadCursors.clear(); _removed.clear(); _conversationEpochs.clear();
    _unread = 0; _error = null; _search = ''; _connection = ChatConnectionState.offline;
    _syncing = false; _syncAgain = false; _opening = false; _reading = false; _loadingOlder = false;
    _searching = false; _moreUsers = false; _moreConversations = false; _conversationPages = 1;
    _notify();
    if (id != null) {
      final generation = _generation;
      _subscriptions.add(realtime.messages.listen((event) { if (_current(generation)) _onMessage(event); }));
      _subscriptions.add(realtime.reads.listen((event) { if (_current(generation)) _onRead(event); }));
      _subscriptions.add(realtime.changes.listen((event) { if (_current(generation)) unawaited(_onChange(event)); }));
      _subscriptions.add(realtime.states.listen((event) { if (_current(generation)) _onConnection(event); }));
      if (_foreground) { _startPolling(); unawaited(realtime.start()); unawaited(refresh()); }
    }
  }

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(Duration(seconds: _connection == ChatConnectionState.connected ? 30 : 5), (_) => unawaited(refresh()));
  }
  void _onConnection(ChatConnectionState state) {
    if (_disposed || _userId == null || !_foreground) return;
    _connection = state; _startPolling(); _notify();
    if (state == ChatConnectionState.connected) unawaited(refresh());
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) { _poll?.cancel(); unawaited(realtime.stop()); }
    else if (_userId != null) { _startPolling(); unawaited(realtime.start()); unawaited(refresh()); }
    _notify();
  }

  Future<void> refresh() async {
    if (_disposed || _userId == null || !_foreground) return;
    if (_syncing) { _syncAgain = true; return; }
    final generation = _generation;
    _syncing = true;
    try {
      final first = await repository.conversations();
      if (!_current(generation)) return;
      for (final item in first.items) _mergeConversation(item);
      final seen = first.items.map((item) => item.id).toSet();
      var page = first;
      var offset = first.items.length;
      for (var i = 1; i < _conversationPages && page.hasMore; i++) {
        page = await repository.conversations(offset: offset);
        if (!_current(generation)) return;
        for (final item in page.items) _mergeConversation(item);
        seen.addAll(page.items.map((item) => item.id));
        offset += page.items.length;
      }
      _moreConversations = page.hasMore;
      for (final id in _conversations.keys.toList()) {
        if (!seen.contains(id)) {
          final loaded = await loadConversation(id);
          if (!loaded && _conversations.containsKey(id)) return;
        }
        if (!_current(generation)) return;
      }
      final unread = await repository.unreadCount();
      if (!_current(generation)) return;
      _unread = unread;
      final id = _activeId;
      final selection = _selection;
      if (id != null && _synced.containsKey(id)) {
        if (!await loadConversation(id, withMembers: true)) return;
        if (!_current(generation) || selection != _selection || !_conversations.containsKey(id)) return;
        var cursor = _synced[id]!;
        ChatPage<ChatMessage> messages;
        do {
          messages = await repository.messages(id, after: cursor);
          if (!_current(generation) || selection != _selection) return;
          for (final message in messages.items) _mergeMessage(message);
          if (messages.items.isNotEmpty) cursor = messages.items.last.sequence!;
        } while (messages.hasMore);
      }
      _error = null;
      _notify();
    } on Object catch (error) { _fail(error, generation); }
    finally {
      if (_current(generation)) {
        _syncing = false;
        if (_syncAgain) { _syncAgain = false; unawaited(refresh()); }
      }
    }
  }

  void _mergeConversation(ChatConversation incoming) {
    if (_removed.containsKey(incoming.id) && compareChatSequence(incoming.version, _removed[incoming.id]!) <= 0) return;
    final old = _conversations[incoming.id];
    if (old != null && compareChatSequence(old.version, incoming.version) > 0) return;
    if (old != null && incoming.isGroup && compareChatSequence(incoming.version, old.version) > 0
        && membersState(incoming.id) == ChatMemberLoadState.ready) {
      _memberStates[incoming.id] = ChatMemberLoadState.idle;
    }
    _removed.remove(incoming.id);
    if (old != null) {
      incoming = incoming.copyWith(
        lastReadSequence: _max(old.lastReadSequence, incoming.lastReadSequence),
        participantLastReadSequence: _max(old.participantLastReadSequence, incoming.participantLastReadSequence),
        lastMessage: old.lastMessage != null && compareChatSequence(old.lastMessage!.sequence!, incoming.lastMessage?.sequence ?? '0') > 0 ? old.lastMessage : incoming.lastMessage);
    }
    _conversations[incoming.id] = incoming;
  }
  static String _max(String a, String b) => compareChatSequence(a, b) > 0 ? a : b;
  void _mergeMessage(ChatMessage message) {
    if (_removed.containsKey(message.conversationId)) return;
    final map = _messages.putIfAbsent(message.conversationId, () => {});
    map[message.id] = message;
    if (message.senderUserId == _userId) {
      final pending = _pending.remove(message.clientMessageId.toLowerCase());
      if (pending?.draftImage != null) _evictImage(pending!.draftImage!.bytes);
    }
    final conversation = _conversations[message.conversationId];
    if (conversation != null && compareChatSequence(message.sequence!, conversation.lastMessage?.sequence ?? '0') > 0) {
      _conversations[conversation.id] = conversation.copyWith(lastMessage: message);
    }
    _advance(message.conversationId);
  }
  void _advance(String id) {
    if (!_synced.containsKey(id)) return;
    final sequences = (_messages[id]?.values ?? <ChatMessage>[]).map((item) => item.sequence).toSet();
    var cursor = BigInt.parse(_synced[id]!);
    while (sequences.contains((cursor + BigInt.one).toString())) { cursor += BigInt.one; }
    _synced[id] = cursor.toString();
  }
  void _onMessage(ChatMessage message) {
    if (_disposed || _userId == null) return;
    if (_removed.containsKey(message.conversationId)) return;
    if (!_conversations.containsKey(message.conversationId)) { unawaited(loadConversation(message.conversationId).then((_) => refresh())); return; }
    _mergeMessage(message); _notify(); unawaited(refresh());
  }
  void _onRead(ChatReadState state) {
    if (_disposed || _userId == null) return;
    _mergeRead(state); _notify();
    if (state.userId == _userId) unawaited(refresh());
  }
  void _mergeRead(ChatReadState state) {
    if (_removed.containsKey(state.conversationId)) return;
    final cursors = _memberReadCursors.putIfAbsent(state.conversationId, () => {});
    cursors[state.userId] = _max(cursors[state.userId] ?? '0', state.lastReadSequence);
    final member = _members[state.conversationId]?[state.userId];
    if (member != null) _members[state.conversationId]![state.userId] = member.readThrough(state.lastReadSequence);
    final conversation = _conversations[state.conversationId];
    if (conversation == null) return;
    if (conversation.isGroup && state.userId != _userId) return;
    _conversations[state.conversationId] = state.userId == _userId
      ? conversation.copyWith(lastReadSequence: _max(state.lastReadSequence, conversation.lastReadSequence))
      : conversation.copyWith(participantLastReadSequence: _max(state.lastReadSequence, conversation.participantLastReadSequence));
  }

  void invalidateSearch(String text) {
    _searchRequest++; _search = text.trim(); _users = []; _moreUsers = false; _searching = _search.isNotEmpty; _notify();
  }
  Future<void> searchUsers(String text, {bool more = false}) async {
    if (_userId == null || _disposed) return;
    final generation = _generation;
    final request = ++_searchRequest;
    _search = text.trim();
    if (_search.isEmpty) { _users = []; _moreUsers = false; _searching = false; _notify(); return; }
    _searching = true; _notify();
    try {
      final result = await repository.users(_search, afterUserId: more && _users.isNotEmpty ? _users.last.userId : 0);
      if (!_current(generation) || request != _searchRequest) return;
      _users = {...{for (final item in more ? _users : <ChatUser>[]) item.userId: item}, ...{for (final item in result.items) item.userId: item}}.values.toList();
      _moreUsers = result.hasMore;
    } on Object catch (error) { if (request == _searchRequest) _fail(error, generation); }
    finally { if (_current(generation) && request == _searchRequest) { _searching = false; _notify(); } }
  }
  Future<void> moreConversationsPage() async { _conversationPages++; await refresh(); }
  Future<ChatConversation?> createConversation(int userId) async {
    final generation = _generation;
    try {
      final conversation = await repository.createConversation(userId);
      if (!_current(generation)) return null;
      _mergeConversation(conversation); _notify(); return conversation;
    } on Object catch (error) { _fail(error, generation); return null; }
  }
  Future<void> openConversation(String id) async {
    if (_userId == null) return;
    _activeId = id; final selection = ++_selection; final generation = _generation;
    _opening = true; _error = null; _notify();
    try {
      if (!await loadConversation(id)) return;
      if (!_current(generation) || selection != _selection || !_conversations.containsKey(id)) return;
      // A roster outage must not block history or ordinary messages; the @ picker can retry it separately.
      if (_conversations[id]?.isGroup == true) unawaited(reloadMembers(id));
      final page = await repository.messages(id);
      if (!_current(generation) || selection != _selection) return;
      for (final message in page.items) { _mergeMessage(message); }
      _synced[id] = page.items.isEmpty ? '0' : page.items.last.sequence!;
      _advance(id);
      _older[id] = page.hasMore; _initializedThreads.add(id);
    } on Object catch (error) { if (selection == _selection) _fail(error, generation); }
    finally { if (_current(generation) && selection == _selection) { _opening = false; _notify(); } }
  }
  void closeConversation(String id) { if (_activeId == id) { _activeId = null; _selection++; } }
  Future<void> loadOlder(String id) async {
    final saved = messages(id).where((item) => item.sequence != null).toList();
    if (_loadingOlder || saved.isEmpty || !hasOlder(id)) return;
    final generation = _generation;
    final epoch = conversationEpoch(id);
    _loadingOlder = true; _notify();
    try {
      final page = await repository.messages(id, before: saved.first.sequence);
      if (!_current(generation) || epoch != conversationEpoch(id)) return;
      for (final message in page.items) { _mergeMessage(message); }
      _older[id] = page.hasMore;
    } on Object catch (error) { if (epoch == conversationEpoch(id)) _fail(error, generation); }
    finally { if (_current(generation) && epoch == conversationEpoch(id)) { _loadingOlder = false; _notify(); } }
  }
  void setDraft(String id, String text, {List<ChatMention> mentions = const []}) {
    if (_userId == null || _removed.containsKey(id)) return;
    _drafts[id] = text; _draftMentions[id] = List.unmodifiable(mentions);
  }
  void removeDraftImage(String id) {
    final removed = _draftImages.remove(id);
    if (removed != null) _evictImage(removed.bytes);
    _notify();
  }
  Future<void> pickImage(String id, {required bool camera}) async {
    final generation = _generation; final selection = _selection;
    try {
      final image = await photoPicker.pick(camera: camera);
      if (!_current(generation) || _activeId != id || selection != _selection || image == null) return;
      final old = _draftImages[id];
      if (old != null) _evictImage(old.bytes);
      _draftImages[id] = image; _notify();
    } on Object catch (error) { if (selection == _selection) _fail(error is FormatException ? error : const FormatException('chatPhotoPermission'), generation); }
  }
  Future<void> send(String id, String text, {List<ChatMention> mentions = const []}) async {
    if (_userId == null || _removed.containsKey(id) || text.length > 4000 || (text.trim().isEmpty && !_draftImages.containsKey(id))) return;
    final uuid = const Uuid().v4(); final image = _draftImages.remove(id);
    final message = ChatMessage(id: 'pending:$uuid', conversationId: id, sequence: null, senderUserId: _userId!,
      clientMessageId: uuid, text: text, createdAt: DateTime.now().toUtc(), delivery: ChatDelivery.sending,
      image: image == null ? null : ChatImageInfo(image.contentType, image.bytes.length), draftImage: image,
      mentions: List.unmodifiable(mentions));
    _pending[uuid] = message; _drafts.remove(id); _draftMentions.remove(id); _notify();
    await _sendPending(message);
  }
  Future<void> retry(String clientId) async {
    final message = _pending[clientId];
    if (message == null || message.delivery != ChatDelivery.failed) return;
    await _sendPending(message);
  }
  Future<void> _sendPending(ChatMessage pending) async {
    final generation = _generation;
    final epoch = conversationEpoch(pending.conversationId);
    _pending[pending.clientMessageId] = pending.withDelivery(ChatDelivery.sending); _error = null; _notify();
    try {
      final saved = await repository.send(pending.conversationId, pending.clientMessageId, pending.text, image: pending.draftImage, mentions: pending.mentions);
      if (!_current(generation) || epoch != conversationEpoch(pending.conversationId)) return;
      _mergeMessage(saved); _notify(); unawaited(refresh());
    } on Object catch (error) {
      if (!_current(generation) || epoch != conversationEpoch(pending.conversationId)) return;
      if (_pending.containsKey(pending.clientMessageId)) {
        _pending[pending.clientMessageId] = pending.withDelivery(ChatDelivery.failed); _fail(error, generation);
      }
    }
  }
  Future<Uint8List> loadImage(ChatMessage message) async {
    if (_removed.containsKey(message.conversationId)) throw StateError('Chat access revoked');
    if (message.draftImage != null) return message.draftImage!.bytes;
    final generation = _generation;
    try { return await images.load('${message.conversationId}:${message.id}', () => repository.image(message.conversationId, message.id)); }
    on Object catch (error) { if (error is ServerException && error.statusCode == 401) _fail(error, generation); rethrow; }
  }
  Future<void> markRead(String id, String sequence) async {
    final conversation = _conversations[id];
    if (_userId == null || !_foreground || _activeId != id || _reading || conversation == null
        || !_synced.containsKey(id) || compareChatSequence(sequence, _synced[id]!) > 0
        || compareChatSequence(sequence, conversation.lastReadSequence) <= 0) return;
    final generation = _generation; _reading = true;
    final epoch = conversationEpoch(id);
    try {
      final state = await repository.markRead(id, sequence);
      if (!_current(generation) || epoch != conversationEpoch(id)) return;
      _mergeRead(state); _notify(); unawaited(refresh());
    } on Object catch (error) { if (epoch == conversationEpoch(id)) _fail(error, generation); }
    finally { if (_current(generation) && epoch == conversationEpoch(id)) _reading = false; }
  }
  void clearError() { _error = null; _errorRevision++; _notify(); }
  Future<bool> reloadMembers(String id) async {
    if (_userId == null || _disposed || _removed.containsKey(id) || _conversations[id]?.isGroup != true
        || membersState(id) == ChatMemberLoadState.loading) return false;
    final generation = _generation, epoch = conversationEpoch(id);
    final previousError = _error, errorRevision = _errorRevision;
    final retrying = membersState(id) == ChatMemberLoadState.failed;
    final loaded = await loadConversation(id, withMembers: true);
    if (loaded && _current(generation) && epoch == conversationEpoch(id) && retrying
        && _errorRevision == errorRevision && _error == previousError) clearError();
    return loaded;
  }
  Future<bool> loadConversation(String id, {bool withMembers = false}) async {
    final generation = _generation, epoch = conversationEpoch(id);
    final revision = withMembers ? (_memberRevisions[id] ?? 0) + 1 : null;
    if (revision != null) {
      _memberRevisions[id] = revision;
      if (_conversations[id]?.isGroup == true) { _memberStates[id] = ChatMemberLoadState.loading; _notify(); }
    }
    try {
      final item = await repository.conversation(id);
      if (!_current(generation) || epoch != conversationEpoch(id)) return false;
      if (revision != null && _memberRevisions[id] != revision) return false;
      _mergeConversation(item);
      if (_conversations[id]?.version != item.version) return false;
      if (withMembers && item.isGroup && !_removed.containsKey(id)) {
        if (_memberRevisions[id] != revision) return false;
        if (membersState(id) != ChatMemberLoadState.loading) { _memberStates[id] = ChatMemberLoadState.loading; _notify(); }
        final users = await repository.members(id);
        if (!_current(generation) || epoch != conversationEpoch(id) || _conversations[id]?.version != item.version
            || _memberRevisions[id] != revision) return false;
        final cursors = _memberReadCursors.putIfAbsent(id, () => {});
        _members[id] = {
          for (final member in users)
            member.user.userId: member.readThrough(cursors[member.user.userId] ?? '0'),
        };
        final activeUsers = users.map((member) => member.user.userId).toSet();
        cursors.removeWhere((userId, _) => !activeUsers.contains(userId));
        for (final member in _members[id]!.values) {
          cursors[member.user.userId] = member.lastReadSequence;
        }
        _memberStates[id] = ChatMemberLoadState.ready;
      }
      _notify();
      return true;
    } on Object catch (error) {
      if (!_current(generation) || epoch != conversationEpoch(id)) return false;
      if (revision != null && _memberRevisions[id] != revision) return false;
      if (revision != null && _memberRevisions[id] == revision && _conversations[id]?.isGroup == true) {
        _memberStates[id] = ChatMemberLoadState.failed;
      }
      if (error is ServerException && error.statusCode == 404) removeConversation(id);
      else _fail(error, generation);
      return false;
    } finally {
      if (revision != null && _current(generation) && epoch == conversationEpoch(id)
          && _memberRevisions[id] == revision && membersState(id) == ChatMemberLoadState.loading) {
        _memberStates[id] = ChatMemberLoadState.failed; _notify();
      }
    }
  }
  Future<void> _onChange(ChatConversationChange change) async {
    final knownVersion = _conversations[change.conversationId]?.version ?? _removed[change.conversationId] ?? '0';
    if (compareChatSequence(change.version, knownVersion) < 0) return;
    if (change.removed) removeConversation(change.conversationId, version: change.version);
    else if (!_removed.containsKey(change.conversationId) || compareChatSequence(change.version, _removed[change.conversationId]!) > 0) {
      await loadConversation(change.conversationId, withMembers: true);
    }
    await refresh();
  }
  void removeConversation(String id, {String? version}) {
    final lastVersion = version ?? _conversations[id]?.version ?? _removed[id] ?? '0';
    _removed[id] = _max(lastVersion, _removed[id] ?? '0');
    _conversationEpochs[id] = conversationEpoch(id) + 1;
    final draftImage = _draftImages.remove(id); if (draftImage != null) _evictImage(draftImage.bytes);
    for (final message in _pending.values.where((item) => item.conversationId == id)) {
      if (message.draftImage != null) _evictImage(message.draftImage!.bytes);
    }
    _pending.removeWhere((key, item) => item.conversationId == id);
    _conversations.remove(id); _members.remove(id); _memberStates.remove(id); _memberRevisions.remove(id);
    _memberReadCursors.remove(id); _messages.remove(id); _synced.remove(id);
    _drafts.remove(id); _draftMentions.remove(id); _older.remove(id); _initializedThreads.remove(id); images.evictConversation(id);
    if (_activeId == id) { _activeId = null; _selection++; _opening = false; _loadingOlder = false; _reading = false; }
    _notify();
  }
  Future<ChatPage<ChatUser>> findGroupUsers(String search, {int afterUserId = 0}) async {
    final generation = _generation;
    try {
      final result = await repository.users(search, afterUserId: afterUserId);
      if (!_current(generation)) throw StateError('Chat session changed');
      return result;
    } on Object catch (error) { _fail(error, generation); rethrow; }
  }
  Future<ChatConversation?> createGroup(String clientId, String name, List<int> users) async {
    if (_userId == null || _disposed) return null;
    final generation = _generation;
    _error = null; _notify();
    try {
      final participants = users.toSet().toList()..sort();
      if (name.trim().isEmpty || name.trim().length > 100 || participants.length < 2
          || participants.length > 99 || participants.any((id) => id <= 0 || id == _userId)) {
        throw const FormatException('chatGroupInvalid');
      }
      final result = await repository.createGroup(clientId, name.trim(), participants);
      if (!_current(generation)) return null;
      _mergeConversation(result); _notify(); return result;
    } on Object catch (error) { _fail(error, generation); return null; }
  }
  Future<bool> changeGroup(String id, String action, {String? name, List<int>? userIds, int? userId, String? role}) async {
    final generation = _generation, epoch = conversationEpoch(id);
    _error = null; _notify();
    try {
      final group = _conversations[id];
      if (action == 'leave' && group?.myRole == 'owner' && group!.memberCount > 1) throw const FormatException('chatTransferRequired');
      if (action == 'rename' && (name == null || name.trim().isEmpty || name.trim().length > 100)) throw const FormatException('chatGroupInvalid');
      final result = await repository.changeGroup(id, action, name: name?.trim(), userIds: userIds, userId: userId, role: role);
      if (!_current(generation) || epoch != conversationEpoch(id)) return false;
      if (action == 'leave') removeConversation(id); else if (result != null) { _mergeConversation(result); await loadConversation(id, withMembers: true); }
      _notify(); unawaited(refresh()); return true;
    } on Object catch (error) { if (epoch == conversationEpoch(id)) _fail(error, generation); return false; }
  }
  void _fail(Object error, int generation) {
    if (!_current(generation)) return;
    _errorRevision++;
    if (error is ServerException && (error.kind == ApiFailureKind.unauthorized || error.statusCode == 401)) {
      bindUser(null); onUnauthorized?.call(); return;
    }
    _error = error is FormatException ? error.message : error is ServerException ? switch (error) {
      ServerException(kind: ApiFailureKind.network) => 'chatNetwork',
      ServerException(kind: ApiFailureKind.timeout) => 'chatTimeout',
      ServerException(statusCode: 413) => 'chatImageTooLarge',
      ServerException(statusCode: 415) => 'chatImageUnsupported',
      ServerException(statusCode: 409) => 'chatConflict',
      ServerException(statusCode: 403 || 404) => 'chatNoAccess',
      ServerException(kind: ApiFailureKind.server) => 'chatServerError',
      _ => error.message,
    } : 'chatFailed';
    _notify();
  }
  @override
  void dispose() {
    _disposed = true; _generation++; _poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    for (final subscription in _subscriptions) { unawaited(subscription.cancel()); }
    _clearDraftImages();
    unawaited(realtime.dispose()); images.clear(); _messages.clear(); _pending.clear(); _draftImages.clear(); _draftMentions.clear(); _drafts.clear();
    _members.clear(); _memberStates.clear(); _memberRevisions.clear();
    closeClient?.call();
    super.dispose();
  }
}

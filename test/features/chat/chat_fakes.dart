import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:mobile_app/core/error/exceptions.dart';
import 'package:mobile_app/features/chat/domain/entities/chat_models.dart';
import 'package:mobile_app/features/chat/domain/repositories/chat_repository.dart';
import 'package:mobile_app/features/chat/data/services/chat_image_service.dart';
import 'package:mobile_app/features/chat/data/services/chat_realtime_service.dart';

final pngBytes = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aD1sAAAAASUVORK5CYII=');
const chatUser = ChatUser(userId: 2, username: 'user2', fullName: 'User Two', department: 'Engineering');
ChatMessage chatMessage(String sequence, {int sender = 2, String? clientId, ChatImageInfo? image, List<ChatMention> mentions = const []}) => ChatMessage(
  id: sequence, conversationId: '1', sequence: sequence, senderUserId: sender,
  clientMessageId: clientId ?? 'message-$sequence', text: image == null ? 'Message $sequence' : '', createdAt: DateTime.utc(2026), image: image, mentions: mentions);

class FakeChatRepository implements ChatRepository {
  ChatConversation item = const ChatConversation(id: '1', participant: chatUser);
  List<ChatConversation>? conversationItems;
  List<ChatMessage> history = [];
  final sent = <({String id, String text, ChatDraftImage? image, List<ChatMention> mentions})>[];
  final readSequences = <String>[];
  int conversationRequests = 0, memberRequests = 0, unread = 0;
  Object? sendError;
  Completer<ChatMessage>? delayedSend;
  Future<ChatPage<ChatUser>> Function(String, int)? searchHandler;
  @override
  Future<ChatPage<ChatConversation>> conversations({int offset = 0}) async { conversationRequests++; return ChatPage(removed ? [] : conversationItems ?? [item], false); }
  @override
  Future<ChatConversation> createConversation(int participantUserId) async => item;
  bool removed = false;
  List<ChatMember> groupMembers = [];
  Future<List<ChatMember>> Function(String)? membersHandler;
  final createdGroups = <({String clientId, String name, List<int> userIds})>[];
  final groupChanges = <({String id, String action, int? userId, String? role, String? name, List<int>? userIds})>[];
  Object? createGroupError;
  Completer<ChatConversation>? delayedConversation;
  Object? detailError;
  @override
  Future<ChatConversation> conversation(String id) async {
    if (detailError != null) throw detailError!;
    if (removed) throw const ServerException('No access', statusCode: 404);
    return delayedConversation?.future ?? Future.value(item);
  }
  @override
  Future<List<ChatMember>> members(String id) async {
    memberRequests++;
    if (membersHandler != null) return membersHandler!(id);
    return groupMembers;
  }
  @override
  Future<ChatConversation> createGroup(String clientId, String name, List<int> userIds) async {
    createdGroups.add((clientId: clientId, name: name, userIds: List.of(userIds)));
    if (createGroupError != null) throw createGroupError!;
    return item;
  }
  @override
  Future<ChatConversation?> changeGroup(String id, String action, {String? name, List<int>? userIds, int? userId, String? role}) async {
    groupChanges.add((id: id, action: action, userId: userId, role: role, name: name, userIds: userIds));
    return action == 'leave' ? null : item;
  }
  @override
  Future<ChatPage<ChatMessage>> messages(String id, {String? before, String? after}) async => ChatPage(history.where((message) =>
    (after == null || compareChatSequence(message.sequence!, after) > 0)
    && (before == null || compareChatSequence(message.sequence!, before) < 0)).toList(), false);
  @override
  Future<ChatMessage> send(String id, String clientMessageId, String text, {ChatDraftImage? image, List<ChatMention> mentions = const []}) async {
    sent.add((id: clientMessageId, text: text, image: image, mentions: List.of(mentions)));
    if (sendError != null) throw sendError!;
    if (delayedSend != null) return delayedSend!.future;
    final message = ChatMessage(id: '${history.length + 1}', conversationId: id, sequence: '${history.length + 1}',
      senderUserId: 1, clientMessageId: clientMessageId, text: text, createdAt: DateTime.now().toUtc(),
      image: image == null ? null : ChatImageInfo(image.contentType, image.bytes.length), mentions: mentions);
    history.add(message);
    return message;
  }
  @override
  Future<ChatReadState> markRead(String id, String sequence) async { readSequences.add(sequence); return ChatReadState(id, 1, sequence); }
  @override
  Future<int> unreadCount() async => unread;
  @override
  Future<ChatPage<ChatUser>> users(String search, {int afterUserId = 0}) => searchHandler?.call(search, afterUserId) ?? Future.value(const ChatPage([chatUser], false));
  @override
  Future<Uint8List> image(String conversationId, String messageId) async => pngBytes;
}

class FakeChatRealtime implements ChatRealtimeClient {
  final messageController = StreamController<ChatMessage>.broadcast();
  final readController = StreamController<ChatReadState>.broadcast();
  final changeController = StreamController<ChatConversationChange>.broadcast();
  final stateController = StreamController<ChatConnectionState>.broadcast();
  int starts = 0, stops = 0;
  @override
  Stream<ChatMessage> get messages => messageController.stream;
  @override
  Stream<ChatReadState> get reads => readController.stream;
  @override
  Stream<ChatConversationChange> get changes => changeController.stream;
  @override
  Stream<ChatConnectionState> get states => stateController.stream;
  @override
  Future<void> start() async { starts++; }
  @override
  Future<void> stop() async { stops++; }
  @override
  Future<void> dispose() async { await stop(); await messageController.close(); await readController.close(); await changeController.close(); await stateController.close(); }
}

class FakePhotoPicker implements ChatPhotoPicker {
  Completer<ChatDraftImage?>? operation;
  @override
  Future<ChatDraftImage?> pick({required bool camera}) => operation?.future ?? Future.value(ChatDraftImage(bytes: pngBytes, contentType: 'image/png', fileName: 'image.png'));
}

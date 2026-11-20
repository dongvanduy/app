import 'dart:typed_data';
import '../entities/chat_models.dart';

abstract interface class ChatRepository {
  Future<ChatPage<ChatUser>> users(String search, {int afterUserId = 0});
  Future<ChatPage<ChatConversation>> conversations({int offset = 0});
  Future<ChatConversation> createConversation(int participantUserId);
  Future<ChatConversation> conversation(String id);
  Future<List<ChatMember>> members(String id);
  Future<ChatConversation> createGroup(String clientId, String name, List<int> userIds);
  Future<ChatConversation?> changeGroup(String id, String action, {String? name, List<int>? userIds, int? userId, String? role});
  Future<ChatPage<ChatMessage>> messages(String id, {String? before, String? after});
  Future<ChatMessage> send(String id, String clientMessageId, String text, {ChatDraftImage? image, List<ChatMention> mentions = const []});
  Future<ChatReadState> markRead(String id, String sequence);
  Future<int> unreadCount();
  Future<Uint8List> image(String conversationId, String messageId);
}

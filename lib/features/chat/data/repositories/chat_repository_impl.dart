import 'dart:typed_data';
import '../../domain/entities/chat_models.dart';
import '../../domain/repositories/chat_repository.dart';
import '../datasources/chat_remote_data_source.dart';
import '../models/chat_dtos.dart';

class ChatRepositoryImpl implements ChatRepository {
  const ChatRepositoryImpl(this.remote);
  final ChatRemoteDataSource remote;
  @override
  Future<ChatConversation> conversation(String id) async => ChatDtos.conversation(await remote.conversation(id));
  @override
  Future<List<ChatMember>> members(String id) async => ChatDtos.page(await remote.members(id), ChatDtos.member).items;
  @override
  Future<ChatConversation> createGroup(String clientId, String name, List<int> userIds) async => ChatDtos.conversation(await remote.createGroup(clientId, name, userIds));
  @override
  Future<ChatConversation?> changeGroup(String id, String action, {String? name, List<int>? userIds, int? userId, String? role}) async {
    final result = await remote.changeGroup(id, action, name: name, userIds: userIds, userId: userId, role: role);
    return result == null ? null : ChatDtos.conversation(result);
  }
  @override
  Future<ChatPage<ChatUser>> users(String search, {int afterUserId = 0}) async => ChatDtos.page(await remote.users(search, afterUserId), ChatDtos.user);
  @override
  Future<ChatPage<ChatConversation>> conversations({int offset = 0}) async => ChatDtos.page(await remote.conversations(offset), ChatDtos.conversation);
  @override
  Future<ChatConversation> createConversation(int participantUserId) async => ChatDtos.conversation(await remote.createConversation(participantUserId));
  @override
  Future<ChatPage<ChatMessage>> messages(String id, {String? before, String? after}) async => ChatDtos.page(await remote.messages(id, before, after), ChatDtos.message);
  @override
  Future<ChatMessage> send(String id, String clientMessageId, String text, {ChatDraftImage? image, List<ChatMention> mentions = const []}) async => ChatDtos.message(image == null
    ? await remote.send(id, clientMessageId, text, mentions: mentions)
    : await remote.sendImage(id, clientMessageId, text, image.bytes, image.fileName, mentions: mentions));
  @override
  Future<ChatReadState> markRead(String id, String sequence) async => ChatDtos.read(await remote.markRead(id, sequence));
  @override
  Future<int> unreadCount() async => ChatDtos.object(await remote.unreadCount())['unreadCount'] as int;
  @override
  Future<Uint8List> image(String conversationId, String messageId) => remote.image(conversationId, messageId);
}

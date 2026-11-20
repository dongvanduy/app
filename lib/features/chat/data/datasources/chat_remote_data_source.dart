import 'dart:typed_data';
import 'dart:convert';
import '../../../../core/network/api_client.dart';
import '../../domain/entities/chat_models.dart';

class ChatRemoteDataSource {
  const ChatRemoteDataSource(this.api);
  final ApiClient api;
  Future<dynamic> users(String search, int afterUserId) => api.get('users', queryParameters: {'search': search, 'afterUserId': afterUserId});
  Future<dynamic> conversations(int offset) => api.get('conversations', queryParameters: {'offset': offset, 'includeGroups': true});
  Future<dynamic> conversation(String id) => api.get('conversations/$id');
  Future<dynamic> members(String id) => api.get('conversations/$id/members');
  Future<dynamic> createGroup(String clientId, String name, List<int> userIds) => api.post('groups',
    {'clientConversationId': clientId, 'name': name, 'participantUserIds': userIds});
  Future<dynamic> changeGroup(String id, String action, {String? name, List<int>? userIds, int? userId, String? role}) => switch (action) {
    'rename' => api.put('groups/$id', {'name': name}),
    'add' => api.post('groups/$id/members', {'userIds': userIds}),
    'remove' => api.delete('groups/$id/members/$userId'),
    'role' => api.put('groups/$id/members/$userId/role', {'role': role}),
    'owner' => api.put('groups/$id/owner', {'newOwnerUserId': userId}),
    'leave' => api.post('groups/$id/leave', const {}),
    _ => throw ArgumentError.value(action, 'action'),
  };
  Future<dynamic> createConversation(int id) => api.post('conversations', {'participantUserId': id});
  Future<dynamic> messages(String id, String? before, String? after) => api.get('conversations/$id/messages',
    queryParameters: {if (before != null) 'beforeSequence': before, if (after != null) 'afterSequence': after});
  Future<dynamic> send(String id, String clientId, String text, {List<ChatMention> mentions = const []}) => api.post('conversations/$id/messages',
    {'clientMessageId': clientId, 'text': text, 'mentions': mentions.map((item) => item.toJson()).toList()});
  Future<dynamic> sendImage(String id, String clientId, String text, Uint8List bytes, String fileName, {List<ChatMention> mentions = const []}) => api.postMultipart(
    'conversations/$id/images', fields: {'clientMessageId': clientId, 'text': text,
      'mentions': jsonEncode(mentions.map((item) => item.toJson()).toList())}, bytes: bytes, fileName: fileName);
  Future<dynamic> markRead(String id, String sequence) => api.put('conversations/$id/read', {'lastReadSequence': sequence});
  Future<dynamic> unreadCount() => api.get('unread-count', queryParameters: {'includeGroups': true});
  Future<Uint8List> image(String id, String messageId) => api.getBytes('conversations/$id/messages/$messageId/image');
}

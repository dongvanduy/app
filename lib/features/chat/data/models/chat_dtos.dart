import '../../../../core/error/exceptions.dart';
import '../../domain/entities/chat_models.dart';
import '../../domain/entities/chat_mentions.dart';

class ChatDtos {
  static Map<String, dynamic> object(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    throw const ServerException('Invalid chat response.', kind: ApiFailureKind.invalidResponse);
  }
  static String id(dynamic value, {bool zero = false}) {
    final text = value?.toString() ?? '';
    final parsed = BigInt.tryParse(text);
    if (!RegExp(r'^\d+$').hasMatch(text) || parsed == null || parsed < (zero ? BigInt.zero : BigInt.one)) {
      throw const ServerException('Invalid chat ID.', kind: ApiFailureKind.invalidResponse);
    }
    return text;
  }
  static ChatUser user(dynamic data) {
    final json = object(data);
    return ChatUser(userId: json['userId'] as int, username: json['username'] as String? ?? '',
      fullName: json['fullName'] as String? ?? '', department: json['department'] as String? ?? '');
  }
  static ChatMessage message(dynamic data) {
    final json = object(data);
    final image = json['image'] == null ? null : object(json['image']);
    return ChatMessage(id: id(json['id']), conversationId: id(json['conversationId']), sequence: id(json['sequence']),
      senderUserId: json['senderUserId'] as int, clientMessageId: (json['clientMessageId'] as String).toLowerCase(),
      text: json['text'] as String? ?? '', createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
      sender: json['sender'] == null ? null : user(json['sender']), kind: json['kind'] as String? ?? 'user',
      systemEvent: json['systemEvent'] == null ? null : systemEvent(json['systemEvent']),
      mentions: _mentions(json['text'] as String? ?? '', json['mentions']),
      image: image == null ? null : ChatImageInfo(image['contentType'] as String, image['byteLength'] as int));
  }
  static List<ChatMention> _mentions(String text, dynamic data) {
    if (data is! List) return const [];
    return validChatMentions(text, data.whereType<Map<String, dynamic>>().where((item) =>
      item['userId'] is int && item['start'] is int && item['length'] is int).map((item) =>
        ChatMention(userId: item['userId'] as int, start: item['start'] as int, length: item['length'] as int)));
  }
  static ChatConversation conversation(dynamic data) {
    final json = object(data);
    return ChatConversation(id: id(json['id']), participant: json['participant'] == null ? null : user(json['participant']),
      type: json['type'] as String? ?? 'direct', name: json['name'] as String?, memberCount: json['memberCount'] as int? ?? 2,
      myRole: json['myRole'] as String? ?? 'member', version: id(json['version'] ?? '0', zero: true),
      lastMessage: json['lastMessage'] == null ? null : message(json['lastMessage']),
      lastReadSequence: id(json['lastReadSequence'], zero: true),
      participantLastReadSequence: id(json['participantLastReadSequence'] ?? '0', zero: true), unreadCount: json['unreadCount'] as int,
      unreadMentionCount: json['unreadMentionCount'] as int? ?? 0);
  }
  static ChatMember member(dynamic data) {
    final json = object(data);
    return ChatMember(user: user(json['user']), role: json['role'] as String,
      joinedAt: DateTime.parse(json['joinedAt'] as String).toUtc(), lastReadSequence: id(json['lastReadSequence'], zero: true));
  }
  static ChatSystemEvent systemEvent(dynamic data) {
    final json = object(data);
    return ChatSystemEvent(type: json['type'] as String, affectedUsers: (json['affectedUsers'] as List).map(user).toList(),
      previousName: json['previousName'] as String?, name: json['name'] as String?);
  }
  static ChatConversationChange change(dynamic data, {bool removed = false}) {
    final json = object(data);
    return ChatConversationChange(id(json['conversationId']), id(json['version'], zero: true), removed: removed);
  }
  static ChatReadState read(dynamic data) {
    final json = object(data);
    return ChatReadState(id(json['conversationId']), json['userId'] as int, id(json['lastReadSequence'], zero: true));
  }
  static ChatPage<T> page<T>(dynamic data, T Function(dynamic) parse) {
    final json = object(data);
    return ChatPage((json['items'] as List).map(parse).toList(growable: false), json['hasMore'] as bool);
  }
}

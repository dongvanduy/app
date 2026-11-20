import 'dart:typed_data';

int compareChatSequence(String a, String b) => BigInt.parse(a).compareTo(BigInt.parse(b));

class ChatUser {
  const ChatUser({required this.userId, required this.username, required this.fullName, required this.department});
  final int userId;
  final String username, fullName, department;
  String get displayName => fullName.trim().isEmpty ? username : fullName;
}

class ChatImageInfo {
  const ChatImageInfo(this.contentType, this.byteLength);
  final String contentType;
  final int byteLength;
}

class ChatDraftImage {
  ChatDraftImage({required this.bytes, required this.contentType, required this.fileName});
  final Uint8List bytes;
  final String contentType, fileName;
}

enum ChatDelivery { sending, failed, sent }

class ChatMention {
  const ChatMention({required this.userId, required this.start, required this.length});
  final int userId, start, length;
  Map<String, dynamic> toJson() => {'userId': userId, 'start': start, 'length': length};
  ChatMention at(int offset) => ChatMention(userId: userId, start: offset, length: length);
}

class ChatMessage {
  const ChatMessage({required this.id, required this.conversationId, required this.sequence,
    required this.senderUserId, required this.clientMessageId, required this.text,
    required this.createdAt, this.image, this.draftImage, this.delivery = ChatDelivery.sent,
    this.sender, this.kind = 'user', this.systemEvent, this.mentions = const []});
  final String id, conversationId, clientMessageId, text;
  final String? sequence;
  final int senderUserId;
  final DateTime createdAt;
  final ChatImageInfo? image;
  final ChatDraftImage? draftImage;
  final ChatDelivery delivery;
  final ChatUser? sender;
  final String kind;
  final ChatSystemEvent? systemEvent;
  final List<ChatMention> mentions;
  ChatMessage withDelivery(ChatDelivery value) => ChatMessage(id: id, conversationId: conversationId,
    sequence: sequence, senderUserId: senderUserId, clientMessageId: clientMessageId, text: text,
    createdAt: createdAt, image: image, draftImage: draftImage, delivery: value, sender: sender, kind: kind, systemEvent: systemEvent, mentions: mentions);
}

class ChatConversation {
  const ChatConversation({required this.id, this.participant, this.lastMessage,
    this.lastReadSequence = '0', this.participantLastReadSequence = '0', this.unreadCount = 0,
    this.type = 'direct', this.name, this.memberCount = 2, this.myRole = 'member', this.version = '0', this.unreadMentionCount = 0});
  final String id;
  final ChatUser? participant;
  final String type, myRole, version;
  final String? name;
  final int memberCount;
  bool get isGroup => type == 'group';
  String get displayName => isGroup ? name ?? '' : participant?.displayName ?? '';
  bool get canManage => isGroup && (myRole == 'owner' || myRole == 'admin');
  final ChatMessage? lastMessage;
  final String lastReadSequence, participantLastReadSequence;
  final int unreadCount;
  final int unreadMentionCount;
  ChatConversation copyWith({ChatMessage? lastMessage, String? lastReadSequence,
    String? participantLastReadSequence, int? unreadCount}) => ChatConversation(id: id, participant: participant,
      lastMessage: lastMessage ?? this.lastMessage, lastReadSequence: lastReadSequence ?? this.lastReadSequence,
      participantLastReadSequence: participantLastReadSequence ?? this.participantLastReadSequence,
      unreadCount: unreadCount ?? this.unreadCount, type: type, name: name, memberCount: memberCount, myRole: myRole, version: version, unreadMentionCount: unreadMentionCount);
}

class ChatMember {
  const ChatMember({required this.user, required this.role, required this.joinedAt, required this.lastReadSequence});
  final ChatUser user;
  final String role, lastReadSequence;
  final DateTime joinedAt;
  ChatMember readThrough(String sequence) => ChatMember(user: user, role: role, joinedAt: joinedAt,
    lastReadSequence: compareChatSequence(sequence, lastReadSequence) > 0 ? sequence : lastReadSequence);
}
class ChatSystemEvent {
  const ChatSystemEvent({required this.type, required this.affectedUsers, this.previousName, this.name});
  final String type;
  final List<ChatUser> affectedUsers;
  final String? previousName, name;
}
class ChatConversationChange {
  const ChatConversationChange(this.conversationId, this.version, {this.removed = false});
  final String conversationId, version;
  final bool removed;
}

class ChatPage<T> {
  const ChatPage(this.items, this.hasMore);
  final List<T> items;
  final bool hasMore;
}

class ChatReadState {
  const ChatReadState(this.conversationId, this.userId, this.lastReadSequence);
  final String conversationId, lastReadSequence;
  final int userId;
}

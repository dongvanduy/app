import 'chat_models.dart';

enum ChatMemberAction { promote, demote, transferOwner, remove }

/// Client presentation rules. The API always checks the actual membership again.
class ChatGroupPermissions {
  const ChatGroupPermissions._();

  static List<ChatMemberAction> memberActions(
    ChatConversation group,
    ChatMember member,
    int? currentUserId,
  ) {
    if (!group.canManage || member.user.userId == currentUserId || member.role == 'owner') {
      return const [];
    }
    if (group.myRole == 'owner') {
      return [
        member.role == 'admin' ? ChatMemberAction.demote : ChatMemberAction.promote,
        ChatMemberAction.transferOwner,
        ChatMemberAction.remove,
      ];
    }
    return member.role == 'member' ? const [ChatMemberAction.remove] : const [];
  }

  static bool canLeave(ChatConversation group) =>
      group.isGroup && (group.myRole != 'owner' || group.memberCount == 1);
}

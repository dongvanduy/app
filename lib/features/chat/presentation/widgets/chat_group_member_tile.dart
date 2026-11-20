import 'package:flutter/material.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../domain/entities/chat_group_permissions.dart';
import '../../domain/entities/chat_models.dart';
import 'chat_avatar.dart';
import 'chat_role_badge.dart';
import 'chat_theme.dart';

String chatMemberActionLabel(ChatMemberAction action) => switch (action) {
  ChatMemberAction.promote => 'chatPromote',
  ChatMemberAction.demote => 'chatDemote',
  ChatMemberAction.transferOwner => 'chatTransferOwner',
  ChatMemberAction.remove => 'chatRemoveMember',
};

class ChatGroupMemberTile extends StatelessWidget {
  const ChatGroupMemberTile({super.key, required this.member, required this.actions,
    required this.onAction, this.enabled = true});

  final ChatMember member;
  final List<ChatMemberAction> actions;
  final ValueChanged<ChatMemberAction> onAction;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = ChatColors.of(context);
    final role = AppLocalizations.of(context, 'chatRole_${member.role}');
    return ListTile(
      key: ValueKey('chat-member-${member.user.userId}'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      leading: ChatAvatar(name: member.user.displayName, userId: member.user.userId, size: 38),
      title: Text(member.user.displayName, maxLines: 2, overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.text)),
      subtitle: Padding(padding: const EdgeInsets.only(top: 4), child: Text(role,
        style: TextStyle(fontSize: 11, color: colors.muted))),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        ChatRoleBadge(role: member.role, compact: MediaQuery.sizeOf(context).width < 360),
        if (actions.isNotEmpty) SizedBox(width: 32, height: 40, child: PopupMenuButton<ChatMemberAction>(
          key: ValueKey('chat-member-menu-${member.user.userId}'),
          padding: EdgeInsets.zero,
          enabled: enabled,
          tooltip: AppLocalizations.of(context, 'chatMemberActions'),
          onSelected: onAction,
          itemBuilder: (context) => [
            for (final action in actions) PopupMenuItem(
              value: action,
              child: Text(AppLocalizations.of(context, chatMemberActionLabel(action))),
            ),
          ],
        )),
      ]),
    );
  }
}

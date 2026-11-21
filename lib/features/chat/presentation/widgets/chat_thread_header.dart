import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../data/services/chat_realtime_service.dart';
import '../../domain/entities/chat_models.dart';
import 'chat_avatar.dart';
import 'chat_theme.dart';

class ChatConnectionLabel extends StatelessWidget {
  const ChatConnectionLabel({super.key, required this.connection, this.onHeader = false, this.memberCount, this.fontSize = 10});
  final ChatConnectionState connection;
  final bool onHeader;
  final int? memberCount;
  final double fontSize;
  @override
  Widget build(BuildContext context) {
    final connected = connection == ChatConnectionState.connected;
    final status = AppLocalizations.of(context, connected ? 'chatConnected' : 'chatConnectingShort');
    final members = memberCount == null ? '' : '${AppLocalizations.of(context, 'chatMembersShort').replaceAll('{count}', '$memberCount')} · ';
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle,
        color: connected ? const Color(0xFF63D993) : const Color(0xFFFFCE70))),
      const SizedBox(width: 5),
      Flexible(child: Text('$members$status', maxLines: 1, overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: fontSize, height: 1.4, color: onHeader ? Colors.white.withValues(alpha: .85) : ChatColors.of(context).muted))),
    ]);
  }
}

class ChatThreadHeader extends StatelessWidget implements PreferredSizeWidget {
  const ChatThreadHeader({super.key, required this.conversation, required this.connection,
    required this.onGroupInfo, required this.onRefresh});
  final ChatConversation? conversation;
  final ChatConnectionState connection;
  final VoidCallback onGroupInfo, onRefresh;
  @override
  Size get preferredSize => const Size.fromHeight(72);
  @override
  Widget build(BuildContext context) {
    final item = conversation;
    return AppBar(
      key: const ValueKey('chat-thread-header'),
      toolbarHeight: 72, leadingWidth: 44, titleSpacing: 0,
      leading: const BackButton(color: Colors.white),
      foregroundColor: Colors.white, backgroundColor: Colors.transparent,
      systemOverlayStyle: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
      flexibleSpace: const DecoratedBox(decoration: BoxDecoration(gradient: ChatColors.headerGradient)),
      title: Row(children: [
        ChatAvatar(name: item?.displayName ?? '', userId: item?.participant?.userId ?? 0,
          group: item?.isGroup == true, size: 36, onHeader: true),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(item?.displayName ?? AppLocalizations.of(context, 'chatTitle'),
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
          const SizedBox(height: 3),
          ChatConnectionLabel(connection: connection, onHeader: true, memberCount: item?.isGroup == true ? item?.memberCount : null),
        ])),
      ]),
      actions: [
        if (item?.isGroup == true) IconButton(
          key: const ValueKey('chat-group-info'), onPressed: onGroupInfo,
          style: IconButton.styleFrom(foregroundColor: Colors.white),
          tooltip: AppLocalizations.of(context, 'chatGroupInfo'), icon: const Icon(Icons.info_outline, size: 22)),
        PopupMenuButton<String>(
          tooltip: AppLocalizations.of(context, 'chatOptions'),
          icon: const Icon(Icons.more_vert, color: Colors.white, size: 22),
          padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 150),
          onSelected: (_) => onRefresh(),
          itemBuilder: (context) => [PopupMenuItem(value: 'refresh', child: Row(children: [
            const Icon(Icons.refresh, size: 19), const SizedBox(width: 10),
            Text(AppLocalizations.of(context, 'chatRefresh')),
          ]))],
        ),
      ],
    );
  }
}

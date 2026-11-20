import 'package:flutter/material.dart';
import '../../../../core/localization/app_localizations.dart';
import 'chat_theme.dart';

class ChatMentionBadge extends StatelessWidget {
  const ChatMentionBadge({super.key, required this.count});
  final int count;
  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    final c = ChatColors.of(context);
    final label = AppLocalizations.of(context, 'chatMentionUnreadCount').replaceAll('{count}', '$count');
    return Semantics(label: label, child: Tooltip(message: label, excludeFromSemantics: true,
      child: ExcludeSemantics(child: Badge(backgroundColor: c.tint, textColor: c.accent,
        label: const Text('@')))));
  }
}

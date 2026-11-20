import 'package:flutter/material.dart';
import '../../../../core/localization/app_localizations.dart';
import 'chat_theme.dart';

class ChatRoleBadge extends StatelessWidget {
  const ChatRoleBadge({super.key, required this.role, this.compact = false});
  final String role;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final c = ChatColors.of(context);
    final label = AppLocalizations.of(context, 'chatRole_$role');
    final icon = switch (role) {
      'owner' => Icons.workspace_premium_outlined,
      'admin' => Icons.verified_user_outlined,
      _ => Icons.person_outline,
    };
    final color = role == 'owner' ? c.accent : c.text;
    return Tooltip(message: label, child: Container(
      constraints: const BoxConstraints(maxWidth: 106),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
      decoration: BoxDecoration(color: role == 'owner' ? c.tint : c.field, borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: color),
        if (!compact) ...[
          const SizedBox(width: 5),
          Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: color))),
        ],
      ]),
    ));
  }
}

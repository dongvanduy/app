import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';

class ChatUnreadBadge extends StatelessWidget {
  const ChatUnreadBadge({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final count = context.select<ChatProvider, int>((provider) => provider.unreadCount);
    return Badge(isLabelVisible: count > 0, label: Text(count > 99 ? '99+' : '$count'), child: child);
  }
}

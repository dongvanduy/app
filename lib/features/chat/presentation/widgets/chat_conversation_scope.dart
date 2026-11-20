import 'package:flutter/material.dart';
import '../providers/chat_provider.dart';

/// Removes covered chat routes too, so Back cannot reveal a revoked conversation.
class ChatConversationScope extends StatefulWidget {
  const ChatConversationScope({super.key, required this.provider, required this.conversationId, required this.child});
  final ChatProvider provider;
  final String conversationId;
  final Widget child;
  @override
  State<ChatConversationScope> createState() => _ChatConversationScopeState();
}
class _ChatConversationScopeState extends State<ChatConversationScope> {
  late final int _session, _epoch;
  bool _invalid = false;
  @override
  void initState() {
    super.initState(); _session = widget.provider.generation; _epoch = widget.provider.conversationEpoch(widget.conversationId);
    widget.provider.addListener(_check);
    WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _check(); });
  }
  void _check() {
    if (_invalid || !mounted) return;
    if (_session == widget.provider.generation && _epoch == widget.provider.conversationEpoch(widget.conversationId)
        && !widget.provider.wasRemoved(widget.conversationId)) return;
    setState(() => _invalid = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route != null && route.isActive) Navigator.of(context).removeRoute(route);
    });
  }
  @override
  void dispose() { widget.provider.removeListener(_check); super.dispose(); }
  @override
  Widget build(BuildContext context) => _invalid ? const SizedBox.shrink() : widget.child;
}

import 'package:flutter/material.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../domain/entities/chat_models.dart';
import '../providers/chat_provider.dart';
import 'chat_avatar.dart';
import 'chat_theme.dart';

class ChatMentionSuggestions extends StatefulWidget {
  const ChatMentionSuggestions({super.key, required this.users, required this.selected,
    required this.onSelected, this.compact = false, this.state = ChatMemberLoadState.ready,
    this.onRetry, this.onDismiss});
  final List<ChatUser> users;
  final int selected;
  final ValueChanged<ChatUser> onSelected;
  final bool compact;
  final ChatMemberLoadState state;
  final VoidCallback? onRetry, onDismiss;
  @override
  State<ChatMentionSuggestions> createState() => _ChatMentionSuggestionsState();
}

class _ChatMentionSuggestionsState extends State<ChatMentionSuggestions> {
  final _scroll = ScrollController();
  @override
  void initState() { super.initState(); _reveal(); }
  @override
  void didUpdateWidget(ChatMentionSuggestions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected || oldWidget.users != widget.users || oldWidget.state != widget.state) _reveal();
  }
  void _reveal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients || widget.selected < 0) return;
      final top = widget.selected * 52.0, bottom = top + 52;
      final offset = top < _scroll.offset ? top : bottom > _scroll.offset + _scroll.position.viewportDimension
        ? bottom - _scroll.position.viewportDimension : _scroll.offset;
      _scroll.jumpTo(offset.clamp(0.0, _scroll.position.maxScrollExtent).toDouble());
    });
  }
  @override
  void dispose() { _scroll.dispose(); super.dispose(); }

  Widget _status(BuildContext context, String message, {bool loading = false, bool retry = false}) {
    final c = ChatColors.of(context);
    return SingleChildScrollView(child: Padding(padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
      child: Row(children: [
        if (loading) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
        else Icon(retry ? Icons.cloud_off_outlined : Icons.alternate_email, size: 19, color: c.muted),
        const SizedBox(width: 10),
        Expanded(child: Text(AppLocalizations.of(context, message), style: TextStyle(fontSize: 12, color: c.muted))),
        if (retry) TextButton(key: const ValueKey('chat-mention-retry'), onPressed: widget.onRetry,
          child: Text(AppLocalizations.of(context, 'chatRetry'), style: const TextStyle(fontSize: 12))),
      ]),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c = ChatColors.of(context);
    final loading = widget.state == ChatMemberLoadState.idle || widget.state == ChatMemberLoadState.loading;
    final failed = widget.state == ChatMemberLoadState.failed;
    final selectionLost = !loading && !failed && widget.users.isNotEmpty && widget.selected < 0;
    return TextFieldTapRegion(child: Container(
      key: const ValueKey('chat-mention-options'),
      constraints: BoxConstraints(maxHeight: widget.compact ? 140 : 210),
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.border), borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(padding: const EdgeInsets.only(left: 12), child: Row(children: [
          Icon(Icons.alternate_email, size: 16, color: c.accent),
          const SizedBox(width: 7),
          Expanded(child: Text(AppLocalizations.of(context, selectionLost ? 'chatMentionChooseAgain' : 'chatMentionTitle'),
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: selectionLost ? c.danger : c.text))),
          SizedBox(width: 36, height: 34, child: IconButton(
            key: const ValueKey('chat-mention-dismiss'), onPressed: widget.onDismiss,
            padding: EdgeInsets.zero, tooltip: AppLocalizations.of(context, 'chatMentionClose'),
            icon: const Icon(Icons.close, size: 17))),
        ])),
        Flexible(child: loading ? _status(context, 'chatMentionLoading', loading: true)
          : failed ? _status(context, 'chatMentionLoadFailed', retry: true)
          : widget.users.isEmpty ? _status(context, 'chatMentionNoResults')
          : ListView.builder(controller: _scroll, itemExtent: 52, shrinkWrap: true, itemCount: widget.users.length,
            itemBuilder: (context, index) {
              final user = widget.users[index];
              return Semantics(selected: index == widget.selected, child: Material(
                color: index == widget.selected ? c.tint : c.surface,
                child: ListTile(key: ValueKey('chat-mention-user-${user.userId}'),
                  dense: true, visualDensity: VisualDensity.compact,
                  leading: ChatAvatar(name: user.displayName, userId: user.userId, size: 30),
                  title: Text(user.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                  subtitle: Text(user.username, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10, color: c.muted)),
                  onTap: () => widget.onSelected(user)),
              ));
            })),
      ]),
    ));
  }
}

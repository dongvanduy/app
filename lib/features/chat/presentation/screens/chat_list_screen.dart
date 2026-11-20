import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/localization/app_localizations.dart';
import 'package:flutter/services.dart';
import '../widgets/chat_avatar.dart';
import '../widgets/chat_day_divider.dart';
import '../widgets/chat_theme.dart';
import '../widgets/chat_thread_header.dart';
import '../../domain/entities/chat_models.dart';
import '../providers/chat_provider.dart';
import 'chat_thread_screen.dart';
import 'chat_group_compose_screen.dart';
import '../widgets/chat_system_message.dart';
import '../widgets/chat_mention_badge.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});
  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  int? _creatingUser;
  String _filter = 'all';
  @override
  void dispose() { _debounce?.cancel(); _search.dispose(); super.dispose(); }
  void _searchChanged(String text) {
    _debounce?.cancel();
    final provider = context.read<ChatProvider>();
    // Invalidate a pending response immediately, before waiting for the debounce.
    provider.invalidateSearch(text);
    _debounce = Timer(const Duration(milliseconds: 300), () { if (mounted) unawaited(provider.searchUsers(text)); });
  }
  Future<void> _startChat(ChatUser user) async {
    if (_creatingUser != null) return;
    setState(() => _creatingUser = user.userId);
    final provider = context.read<ChatProvider>();
    final item = await provider.createConversation(user.userId);
    if (!mounted) return;
    setState(() => _creatingUser = null);
    if (item != null) await _open(item);
  }
  Future<void> _open(ChatConversation item) async {
    await Navigator.of(context).push<void>(MaterialPageRoute(
      settings: RouteSettings(name: '/chat/${item.id}'), builder: (_) => ChatThreadScreen(conversationId: item.id)));
  }
  Future<void> _createGroup() async {
    final group = await Navigator.of(context).push<ChatConversation>(MaterialPageRoute(builder: (_) => const ChatGroupComposeScreen()));
    if (mounted && group != null) await _open(group);
  }

  Widget _conversationTile(BuildContext context, ChatConversation item) {
    final c = ChatColors.of(context);
    final last = item.lastMessage;
    final preview = last?.kind == 'system' ? chatSystemText(context, last!)
      : last?.text.isNotEmpty == true ? last!.text
      : AppLocalizations.of(context, last?.image != null ? 'chatImage' : 'chatStart');
    return Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Material(color: c.surface, clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: c.border)),
        child: ListTile(
          key: ValueKey('chat-conversation-${item.id}'),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          leading: ChatAvatar(name: item.displayName, userId: item.participant?.userId ?? 0,
            group: item.isGroup, size: 44),
          title: Text(item.displayName, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 14, fontWeight: item.unreadCount > 0 || item.isGroup && item.unreadMentionCount > 0
              ? FontWeight.w700 : FontWeight.w600)),
          subtitle: Padding(padding: const EdgeInsets.only(top: 5),
            child: Text(preview, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: c.muted))),
          trailing: last == null && item.unreadCount == 0 && item.unreadMentionCount == 0 ? null : SizedBox(width: 64, child: Column(
            mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
              if (last != null) Text(chatTime(last.createdAt), style: TextStyle(fontSize: 10, color: c.muted)),
              if (item.unreadCount > 0 || item.isGroup && item.unreadMentionCount > 0) ...[
                const SizedBox(height: 6),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  if (item.isGroup && item.unreadMentionCount > 0) Padding(padding: const EdgeInsets.only(right: 4),
                    child: ChatMentionBadge(key: ValueKey('chat-unread-mention-${item.id}'), count: item.unreadMentionCount)),
                  if (item.unreadCount > 0) Badge(backgroundColor: ChatColors.purple, textColor: Colors.white,
                    label: Text(item.unreadCount > 99 ? '99+' : '${item.unreadCount}')),
                ]),
              ],
            ],
          )),
          onTap: () => unawaited(_open(item)),
        ),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final items = chat.conversations.where((item) =>
      _filter == 'all' || (_filter == 'groups' ? item.isGroup : !item.isGroup)).toList();
    final searching = _search.text.trim().isNotEmpty;
    return ChatTheme(child: Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false, toolbarHeight: 76, titleSpacing: 16,
        foregroundColor: Colors.white, backgroundColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
        flexibleSpace: const DecoratedBox(decoration: BoxDecoration(gradient: ChatColors.headerGradient)),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(AppLocalizations.of(context, 'chatTitle'),
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700, color: Colors.white)),
          const SizedBox(height: 5),
          ChatConnectionLabel(connection: chat.connection, onHeader: true),
        ]),
        actions: [
          TextButton.icon(
            key: const ValueKey('chat-create-group'), onPressed: _createGroup,
            style: TextButton.styleFrom(foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 8),
              textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            label: Text(AppLocalizations.of(context, 'chatCreateGroup')),
            icon: const Icon(Icons.group_add_outlined, size: 20),
          ),
          IconButton(key: const ValueKey('chat-refresh'), onPressed: () => unawaited(chat.refresh()),
            style: IconButton.styleFrom(foregroundColor: Colors.white),
            tooltip: AppLocalizations.of(context, 'chatRefresh'), icon: const Icon(Icons.refresh, size: 21)),
        ],
      ),
      body: SafeArea(top: false, bottom: false, child: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(12, 16, 12, 6), child: TextField(
          key: const ValueKey('chat-search'), controller: _search, maxLength: 100,
          onChanged: _searchChanged, style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(counterText: '', prefixIcon: const Icon(Icons.search, size: 21),
            hintText: AppLocalizations.of(context, 'chatSearch')),
        )),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Align(alignment: Alignment.centerLeft,
          child: Wrap(spacing: 8, children: [
            for (final filter in const ['all', 'direct', 'groups']) ChoiceChip(
              key: ValueKey('chat-filter-$filter'), selected: _filter == filter, showCheckmark: false,
              label: Text(AppLocalizations.of(context, 'chatFilter_$filter')),
              onSelected: (_) => setState(() => _filter = filter)),
          ]))),
        if (chat.error != null) ChatErrorBanner(chat: chat),
        if (chat.searching) const LinearProgressIndicator(),
        Expanded(child: RefreshIndicator(onRefresh: chat.refresh, child: ListView(
          key: const PageStorageKey('chat-conversations'),
          padding: const EdgeInsets.symmetric(vertical: 8),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            if (searching) ...[
              for (final user in chat.users) ListTile(
                key: ValueKey('chat-user-${user.userId}'),
                leading: ChatAvatar(name: user.displayName, userId: user.userId),
                title: Text(user.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('${user.username} · ${user.department}', maxLines: 1, overflow: TextOverflow.ellipsis),
                enabled: _creatingUser == null,
                trailing: _creatingUser == user.userId
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : null,
                onTap: () => unawaited(_startChat(user)),
              ),
              if (!chat.searching && chat.users.isEmpty) _empty(context, 'chatNoUsers'),
              if (chat.moreUsers) TextButton(
                onPressed: chat.searching ? null : () => unawaited(chat.searchUsers(_search.text, more: true)),
                child: Text(AppLocalizations.of(context, 'chatMore'))),
              const Divider(indent: 16, endIndent: 16),
            ],
            for (final item in items) _conversationTile(context, item),
            if (items.isEmpty && !searching && chat.error == null)
              _empty(context, _filter == 'groups' ? 'chatNoGroups' : 'chatEmpty'),
            if (chat.moreConversations) TextButton(onPressed: () => unawaited(chat.moreConversationsPage()),
              child: Text(AppLocalizations.of(context, 'chatMore'))),
          ],
        ))),
      ])),
    ));
  }

  Widget _empty(BuildContext context, String key) {
    final c = ChatColors.of(context);
    return Padding(padding: const EdgeInsets.all(28), child: Column(children: [
      Container(width: 64, height: 64, decoration: BoxDecoration(color: c.tint, borderRadius: BorderRadius.circular(20)),
        child: Icon(_filter == 'groups' ? Icons.groups_outlined : Icons.forum_outlined, size: 30, color: c.accent)),
      const SizedBox(height: 14),
      Text(AppLocalizations.of(context, key), textAlign: TextAlign.center, style: TextStyle(color: c.muted, fontSize: 13)),
    ]));
  }
}

class ChatErrorBanner extends StatelessWidget {
  const ChatErrorBanner({super.key, required this.chat});
  final ChatProvider chat;
  @override
  Widget build(BuildContext context) => Material(color: Theme.of(context).colorScheme.errorContainer,
    child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Row(children: [
      Expanded(child: Text(AppLocalizations.of(context, chat.error ?? 'chatFailed'), maxLines: 3, overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12))),
      IconButton(onPressed: chat.clearError, icon: const Icon(Icons.close, size: 20),
        tooltip: AppLocalizations.of(context, 'close')),
    ])));
}

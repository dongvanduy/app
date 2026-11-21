import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/localization/app_localizations.dart';
import '../widgets/chat_avatar.dart';
import '../widgets/chat_empty_illustration.dart';
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
  const ChatListScreen({super.key, this.embedded = false});

  final bool embedded;
  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  int? _creatingUser;
  String _filter = 'all';
  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _searchChanged(String text) {
    _debounce?.cancel();
    final provider = context.read<ChatProvider>();
    // Invalidate a pending response immediately, before waiting for the debounce.
    provider.invalidateSearch(text);
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) unawaited(provider.searchUsers(text));
    });
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
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        settings: RouteSettings(name: '/chat/${item.id}'),
        builder: (_) => ChatThreadScreen(conversationId: item.id),
      ),
    );
  }

  Future<void> _createGroup() async {
    final group = await Navigator.of(context).push<ChatConversation>(
      MaterialPageRoute(builder: (_) => const ChatGroupComposeScreen()),
    );
    if (mounted && group != null) await _open(group);
  }

  Widget _conversationTile(BuildContext context, ChatConversation item) {
    final c = ChatColors.of(context);
    final last = item.lastMessage;
    final preview = last?.kind == 'system'
        ? chatSystemText(context, last!)
        : last?.text.isNotEmpty == true
        ? last!.text
        : AppLocalizations.of(
            context,
            last?.image != null ? 'chatImage' : 'chatStart',
          );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Material(
        color: c.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: c.border),
        ),
        child: ListTile(
          key: ValueKey('chat-conversation-${item.id}'),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 5,
          ),
          leading: ChatAvatar(
            name: item.displayName,
            userId: item.participant?.userId ?? 0,
            group: item.isGroup,
            size: 44,
          ),
          title: Text(
            item.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight:
                  item.unreadCount > 0 ||
                      item.isGroup && item.unreadMentionCount > 0
                  ? FontWeight.w700
                  : FontWeight.w600,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text(
              preview,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: c.muted),
            ),
          ),
          trailing:
              last == null &&
                  item.unreadCount == 0 &&
                  item.unreadMentionCount == 0
              ? null
              : SizedBox(
                  width: 64,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (last != null)
                        Text(
                          chatTime(last.createdAt),
                          style: TextStyle(fontSize: 10, color: c.muted),
                        ),
                      if (item.unreadCount > 0 ||
                          item.isGroup && item.unreadMentionCount > 0) ...[
                        const SizedBox(height: 6),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (item.isGroup && item.unreadMentionCount > 0)
                              Padding(
                                padding: const EdgeInsets.only(right: 4),
                                child: ChatMentionBadge(
                                  key: ValueKey(
                                    'chat-unread-mention-${item.id}',
                                  ),
                                  count: item.unreadMentionCount,
                                ),
                              ),
                            if (item.unreadCount > 0)
                              Badge(
                                backgroundColor: ChatColors.purple,
                                textColor: Colors.white,
                                label: Text(
                                  item.unreadCount > 99
                                      ? '99+'
                                      : '${item.unreadCount}',
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
          onTap: () => unawaited(_open(item)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final colors = ChatColors.of(context);
    final items = chat.conversations.where(
      (item) =>
          _filter == 'all' ||
          (_filter == 'groups' ? item.isGroup : !item.isGroup),
    );
    final searching = _search.text.trim().isNotEmpty;
    final empty = !searching && items.isEmpty;
    final fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(20),
      borderSide: BorderSide(color: colors.border),
    );

    return ChatTheme(
      embedded: widget.embedded,
      child: Scaffold(
        body: SafeArea(
          bottom: !widget.embedded,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: RefreshIndicator(
                onRefresh: chat.refresh,
                child: CustomScrollView(
                  key: const PageStorageKey('chat-conversations'),
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _header(context, chat, colors),
                            const SizedBox(height: 20),
                            TextField(
                              key: const ValueKey('chat-search'),
                              controller: _search,
                              maxLength: 100,
                              onChanged: _searchChanged,
                              style: TextStyle(
                                fontSize: 15,
                                color: colors.text,
                              ),
                              decoration: InputDecoration(
                                counterText: '',
                                prefixIcon: Icon(
                                  Icons.search_rounded,
                                  color: colors.muted,
                                ),
                                hintText: AppLocalizations.of(
                                  context,
                                  'chatSearch',
                                ),
                                fillColor: colors.surface.withValues(alpha: .7),
                                contentPadding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                border: fieldBorder,
                                enabledBorder: fieldBorder,
                                focusedBorder: fieldBorder.copyWith(
                                  borderSide: BorderSide(
                                    color: colors.accent,
                                    width: 1.5,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                for (final filter in const [
                                  'all',
                                  'direct',
                                  'groups',
                                ])
                                  ChoiceChip(
                                    key: ValueKey('chat-filter-$filter'),
                                    selected: _filter == filter,
                                    showCheckmark: false,
                                    backgroundColor: colors.surface.withValues(
                                      alpha: .65,
                                    ),
                                    selectedColor: ChatColors.purple,
                                    side: BorderSide(
                                      color: _filter == filter
                                          ? colors.accent
                                          : colors.border,
                                    ),
                                    shape: const StadiumBorder(),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 9,
                                      vertical: 5,
                                    ),
                                    labelStyle: TextStyle(
                                      color: _filter == filter
                                          ? Colors.white
                                          : colors.text,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    label: Text(
                                      AppLocalizations.of(
                                        context,
                                        'chatFilter_$filter',
                                      ),
                                    ),
                                    onSelected: (_) =>
                                        setState(() => _filter = filter),
                                  ),
                              ],
                            ),
                            if (chat.error != null) ...[
                              const SizedBox(height: 12),
                              ChatErrorBanner(chat: chat),
                            ],
                            if (chat.searching) const LinearProgressIndicator(),
                          ],
                        ),
                      ),
                    ),
                    SliverList.list(
                      children: [
                        if (searching) ...[
                          for (final user in chat.users)
                            ListTile(
                              key: ValueKey('chat-user-${user.userId}'),
                              leading: ChatAvatar(
                                name: user.displayName,
                                userId: user.userId,
                              ),
                              title: Text(
                                user.displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                '${user.username} · ${user.department}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              enabled: _creatingUser == null,
                              trailing: _creatingUser == user.userId
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : null,
                              onTap: () => unawaited(_startChat(user)),
                            ),
                          if (!chat.searching && chat.users.isEmpty)
                            Padding(
                              padding: const EdgeInsets.all(20),
                              child: Text(
                                AppLocalizations.of(context, 'chatNoUsers'),
                                textAlign: TextAlign.center,
                                style: TextStyle(color: colors.muted),
                              ),
                            ),
                          if (chat.moreUsers)
                            TextButton(
                              onPressed: chat.searching
                                  ? null
                                  : () => unawaited(
                                      chat.searchUsers(
                                        _search.text,
                                        more: true,
                                      ),
                                    ),
                              child: Text(
                                AppLocalizations.of(context, 'chatMore'),
                              ),
                            ),
                          const Divider(indent: 16, endIndent: 16),
                        ],
                        for (final item in items)
                          _conversationTile(context, item),
                        if (chat.moreConversations)
                          TextButton(
                            onPressed: () =>
                                unawaited(chat.moreConversationsPage()),
                            child: Text(
                              AppLocalizations.of(context, 'chatMore'),
                            ),
                          ),
                      ],
                    ),
                    if (empty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const ChatEmptyIllustration(),
                                const SizedBox(height: 10),
                                Text(
                                  AppLocalizations.of(
                                    context,
                                    _filter == 'groups'
                                        ? 'chatEmptyGroupsTitle'
                                        : 'chatEmptyTitle',
                                  ),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: colors.text,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  AppLocalizations.of(
                                    context,
                                    _filter == 'groups'
                                        ? 'chatNoGroups'
                                        : chat.error == 'chatNetwork'
                                        ? 'chatEmptyOfflineHint'
                                        : 'chatEmptyHint',
                                  ),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: colors.muted,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, ChatProvider chat, ChatColors colors) {
    final button = OutlinedButton.styleFrom(
      foregroundColor: colors.text,
      backgroundColor: colors.surface.withValues(alpha: .65),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      minimumSize: const Size(0, 44),
      shape: const StadiumBorder(),
      side: BorderSide(color: colors.border),
    );
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 10,
      runSpacing: 8,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                AppLocalizations.of(context, 'chatTitle'),
                style: TextStyle(
                  color: colors.text,
                  fontSize: 30,
                  height: 1.1,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.7,
                ),
              ),
            ),
            const SizedBox(height: 5),
            ChatConnectionLabel(connection: chat.connection, fontSize: 12),
          ],
        ),
        Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              key: const ValueKey('chat-create-group'),
              onPressed: _createGroup,
              style: button,
              label: Text(AppLocalizations.of(context, 'chatCreateGroup')),
              icon: const Icon(Icons.group_add_outlined, size: 20),
            ),
            IconButton.outlined(
              key: const ValueKey('chat-refresh'),
              onPressed: () => unawaited(chat.refresh()),
              style: IconButton.styleFrom(
                foregroundColor: colors.text,
                backgroundColor: colors.surface.withValues(alpha: .65),
                side: BorderSide(color: colors.border),
              ),
              tooltip: AppLocalizations.of(context, 'chatRefresh'),
              icon: const Icon(Icons.refresh_rounded, size: 22),
            ),
          ],
        ),
      ],
    );
  }
}

class ChatErrorBanner extends StatelessWidget {
  const ChatErrorBanner({super.key, required this.chat});

  final ChatProvider chat;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final foreground = dark ? const Color(0xFFFFE6EA) : const Color(0xFF991D2E);
    return Semantics(
      liveRegion: true,
      child: Material(
        color: dark ? const Color(0xFF462030) : const Color(0xFFFFE4E8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: dark ? const Color(0xFF9A384D) : const Color(0xFFF6A5B0),
          ),
        ),
        child: Padding(
          padding: const EdgeInsetsDirectional.only(
            start: 10,
            top: 3,
            bottom: 3,
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: dark
                      ? const Color(0xFFB6344C)
                      : const Color(0xFFE33049),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  chat.error == 'chatNetwork'
                      ? Icons.wifi_off_rounded
                      : Icons.error_outline_rounded,
                  size: 20,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  AppLocalizations.of(context, chat.error ?? 'chatFailed'),
                  style: TextStyle(
                    fontSize: 13,
                    color: foreground,
                    height: 1.3,
                  ),
                ),
              ),
              IconButton(
                onPressed: chat.clearError,
                color: foreground,
                icon: const Icon(Icons.close, size: 20),
                tooltip: AppLocalizations.of(context, 'close'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

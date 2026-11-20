import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/localization/app_localizations.dart';
import '../widgets/chat_avatar.dart';
import '../widgets/chat_theme.dart';
import '../../domain/entities/chat_group_permissions.dart';
import '../../domain/entities/chat_models.dart';
import '../providers/chat_provider.dart';
import '../widgets/chat_conversation_scope.dart';
import '../widgets/chat_group_member_tile.dart';
import 'chat_group_compose_screen.dart';
import 'chat_list_screen.dart';

class ChatGroupInfoScreen extends StatefulWidget {
  const ChatGroupInfoScreen({super.key, required this.conversationId});
  final String conversationId;

  @override
  State<ChatGroupInfoScreen> createState() => _ChatGroupInfoScreenState();
}

class _ChatGroupInfoScreenState extends State<ChatGroupInfoScreen> {
  final _search = TextEditingController();
  bool _busy = false, _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_load());
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading || _busy) return;
    setState(() => _loading = true);
    await context.read<ChatProvider>().loadConversation(widget.conversationId, withMembers: true);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _rename(ChatConversation group) async {
    final provider = context.read<ChatProvider>();
    final session = provider.generation;
    final epoch = provider.conversationEpoch(widget.conversationId);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => ChatConversationScope(
        provider: provider,
        conversationId: widget.conversationId,
        child: _RenameGroupDialog(name: group.name ?? ''),
      ),
    );
    if (result != null && mounted && session == provider.generation
        && epoch == provider.conversationEpoch(widget.conversationId)) {
      await _change('rename', name: result);
    }
  }

  Future<void> _add(ChatConversation group) async {
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => ChatGroupComposeScreen(group: group),
    ));
  }

  void _memberAction(ChatMemberAction action, ChatMember member) {
    final operation = switch (action) {
      ChatMemberAction.promote => 'promote',
      ChatMemberAction.demote => 'demote',
      ChatMemberAction.transferOwner => 'owner',
      ChatMemberAction.remove => 'remove',
    };
    unawaited(_change(operation, member: member));
  }

  Future<void> _change(String action, {String? name, ChatMember? member}) async {
    if (_busy || _loading) return;
    final chat = context.read<ChatProvider>();
    final session = chat.generation;
    final epoch = chat.conversationEpoch(widget.conversationId);
    // Lock before opening confirmation, so two taps cannot queue two mutations.
    setState(() => _busy = true);
    try {
      if (const ['remove', 'owner', 'leave'].contains(action)) {
        final label = switch (action) {
          'owner' => 'chatTransferOwner',
          'remove' => 'chatRemoveMember',
          _ => 'chatLeaveGroup',
        };
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => ChatConversationScope(
            provider: chat,
            conversationId: widget.conversationId,
            child: AlertDialog(
              title: Text(AppLocalizations.of(context, label)),
              content: Text(member?.user.displayName
                ?? AppLocalizations.of(context, 'chatLeaveConfirm')),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false),
                  child: Text(AppLocalizations.of(context, 'chatCancel'))),
                TextButton(onPressed: () => Navigator.pop(context, true),
                  child: Text(AppLocalizations.of(context, 'chatConfirm'))),
              ],
            ),
          ),
        );
        if (confirmed != true) return;
      }
      if (!mounted || session != chat.generation
          || epoch != chat.conversationEpoch(widget.conversationId)) return;
      await chat.changeGroup(
        widget.conversationId,
        action == 'promote' || action == 'demote' ? 'role' : action,
        name: name,
        userId: member?.user.userId,
        role: action == 'promote' ? 'admin' : 'member',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _summary(ChatConversation? group, List<ChatMember> members) {
    final colors = ChatColors.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: colors.surface, borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.border)),
      child: Row(children: [
        ChatAvatar(name: group?.displayName ?? '', group: true, size: 56),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(group?.displayName ?? '', maxLines: 2, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: colors.text)),
          const SizedBox(height: 4),
          Text(AppLocalizations.of(context, 'chatMemberCount')
            .replaceAll('{count}', '${group?.memberCount ?? members.length}'),
            style: TextStyle(fontSize: 11, color: colors.muted)),
        ])),
        if (group?.canManage == true) IconButton.outlined(
          onPressed: _busy || _loading ? null : () => _rename(group!),
          tooltip: AppLocalizations.of(context, 'chatRenameGroup'), icon: Icon(Icons.edit_outlined, size: 19, color: colors.accent)),
      ]),
    );
  }

  Widget _memberList(ChatProvider chat, ChatConversation? group, List<ChatMember> members) {
    final query = _search.text.trim().toLowerCase();
    final visible = members.where((member) =>
      '${member.user.displayName} ${member.user.username}'.toLowerCase().contains(query)).toList();
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: TextField(
        key: const ValueKey('chat-member-search'),
        controller: _search,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          hintText: AppLocalizations.of(context, 'chatSearchMembers'),
          prefixIcon: const Icon(Icons.search),
          suffixIcon: query.isEmpty ? null : IconButton(
            onPressed: () => setState(_search.clear), icon: const Icon(Icons.close),
            tooltip: AppLocalizations.of(context, 'close')),
        ),
      )),
      if (group?.canManage == true) Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: SizedBox(width: double.infinity, child: FilledButton.icon(
          key: const ValueKey('chat-group-add'),
          onPressed: group == null || _busy || _loading || group.memberCount >= 100 ? null : () => _add(group),
          icon: const Icon(Icons.person_add_outlined),
          label: Text(AppLocalizations.of(context, 'chatAddMembers')),
        )),
      ),
      Expanded(child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          key: const ValueKey('chat-group-members'),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            for (final member in visible) ...[
              ChatGroupMemberTile(
                member: member,
                enabled: !_busy && !_loading,
                actions: group == null ? const [] : ChatGroupPermissions.memberActions(group, member, chat.userId),
                onAction: (action) => _memberAction(action, member),
              ),
              Divider(height: 1, color: ChatColors.of(context).border),
            ],
            if (visible.isEmpty && !_loading) Padding(
              padding: const EdgeInsets.all(24),
              child: Text(AppLocalizations.of(context, 'chatNoUsers'), textAlign: TextAlign.center),
            ),
          ],
        ),
      )),
    ]);
  }

  Widget _settings(ChatConversation? group, {bool compact = false}) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      children: [
        if (group?.canManage == true) ListTile(
          key: const ValueKey('chat-group-rename'),
          enabled: !_busy && !_loading,
          leading: const Icon(Icons.edit_outlined),
          title: Text(AppLocalizations.of(context, 'chatRenameGroup')),
          onTap: () => _rename(group!),
        ),
        Padding(padding: const EdgeInsets.all(16), child: Text(
          AppLocalizations.of(context, group?.myRole == 'owner'
            ? 'chatOwnerHelp' : group?.myRole == 'admin' ? 'chatAdminHelp' : 'chatMemberHelp'),
        )),
        if (compact) _footer(group),
      ],
    );
  }

  Widget _footer(ChatConversation? group) {
    final c = ChatColors.of(context);
    final canLeave = group != null && ChatGroupPermissions.canLeave(group);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.border))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        if (group?.myRole == 'owner') Padding(padding: const EdgeInsets.only(bottom: 8),
          child: Text(AppLocalizations.of(context, canLeave ? 'chatLastMemberHelp' : 'chatTransferRequired'),
            style: TextStyle(fontSize: 11, color: c.muted))),
        OutlinedButton.icon(
          key: const ValueKey('chat-group-leave'),
          onPressed: _busy || _loading || !canLeave ? null : () => _change('leave'),
          icon: const Icon(Icons.logout_rounded, size: 18),
          label: Text(AppLocalizations.of(context, 'chatLeaveGroup')),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final group = chat.conversation(widget.conversationId);
    final members = chat.members(widget.conversationId);
    final compact = MediaQuery.sizeOf(context).height - MediaQuery.viewInsetsOf(context).bottom < 420;
    return ChatConversationScope(
      provider: chat,
      conversationId: widget.conversationId,
      child: ChatTheme(child: DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(AppLocalizations.of(context, 'chatGroupInfo'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(AppLocalizations.of(context, 'chatGroupDescription'), maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10, color: ChatColors.of(context).muted)),
            ]),
            actions: [IconButton(
              key: const ValueKey('chat-group-refresh'),
              onPressed: _busy || _loading ? null : _load,
              tooltip: AppLocalizations.of(context, 'chatRefresh'),
              icon: const Icon(Icons.refresh),
            )],
          ),
          body: SafeArea(child: Column(children: [
            if (_busy || _loading) const LinearProgressIndicator(),
            if (chat.error != null) ChatErrorBanner(chat: chat),
            if (!compact) _summary(group, members),
            TabBar(tabs: [
              Tab(key: const ValueKey('chat-group-members-tab'), iconMargin: const EdgeInsets.only(bottom: 3),
                icon: compact ? null : const Icon(Icons.people_outline, size: 18),
                text: AppLocalizations.of(context, 'chatMembers')),
              Tab(key: const ValueKey('chat-group-settings-tab'), iconMargin: const EdgeInsets.only(bottom: 3),
                icon: compact ? null : const Icon(Icons.settings_outlined, size: 18),
                text: AppLocalizations.of(context, 'chatGroupSettings')),
            ]),
            Expanded(child: TabBarView(children: [
              _memberList(chat, group, members),
              _settings(group, compact: compact),
            ])),
            if (!compact) _footer(group),
          ])),
        ),
      )),
    );
  }
}

class _RenameGroupDialog extends StatefulWidget {
  const _RenameGroupDialog({required this.name});
  final String name;
  @override
  State<_RenameGroupDialog> createState() => _RenameGroupDialogState();
}

class _RenameGroupDialogState extends State<_RenameGroupDialog> {
  late final TextEditingController _name;
  bool get _valid => _name.text.trim().isNotEmpty && _name.text.trim().length <= 100;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.name);
  }
  @override
  void dispose() { _name.dispose(); super.dispose(); }

  void _save() { if (_valid) Navigator.pop(context, _name.text.trim()); }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(AppLocalizations.of(context, 'chatRenameGroup')),
    content: TextField(
      key: const ValueKey('chat-group-rename-input'),
      controller: _name,
      maxLength: 100,
      autofocus: true,
      onChanged: (_) => setState(() {}),
      onSubmitted: (_) => _save(),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context),
        child: Text(AppLocalizations.of(context, 'chatCancel'))),
      TextButton(key: const ValueKey('chat-group-rename-save'), onPressed: _valid ? _save : null,
        child: Text(AppLocalizations.of(context, 'chatSave'))),
    ],
  );
}

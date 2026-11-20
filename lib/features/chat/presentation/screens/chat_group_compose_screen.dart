import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/localization/app_localizations.dart';
import '../widgets/chat_theme.dart';
import '../widgets/chat_avatar.dart';
import '../../domain/entities/chat_models.dart';
import '../providers/chat_provider.dart';
import '../widgets/chat_conversation_scope.dart';
import 'chat_list_screen.dart';

class ChatGroupComposeScreen extends StatefulWidget {
  const ChatGroupComposeScreen({super.key, this.group});
  final ChatConversation? group;
  @override
  State<ChatGroupComposeScreen> createState() => _ChatGroupComposeScreenState();
}
class _ChatGroupComposeScreenState extends State<ChatGroupComposeScreen> {
  final _name = TextEditingController(), _search = TextEditingController();
  final _selected = <int, ChatUser>{};
  List<ChatUser> _users = [];
  late ChatProvider _chat;
  late int _session;
  int? _epoch;
  Timer? _debounce;
  int _searchId = 0, _after = 0;
  bool _busy = false, _loading = false, _more = false;
  String? _error, _fingerprint, _clientId;
  bool get _current => mounted && _session == _chat.generation
    && (widget.group == null || (_epoch == _chat.conversationEpoch(widget.group!.id)
      && !_chat.wasRemoved(widget.group!.id)));
  @override
  void initState() {
    super.initState(); _chat = context.read<ChatProvider>(); _session = _chat.generation;
    if (widget.group != null) _epoch = _chat.conversationEpoch(widget.group!.id);
    _chat.addListener(_sessionChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _find(false));
  }
  void _sessionChanged() {
    if (_current || !mounted) return;
    _selected.clear(); _users = []; _name.clear(); _search.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ModalRoute.of(context)?.isActive == true) Navigator.of(context).removeRoute(ModalRoute.of(context)!);
    });
  }
  @override
  void dispose() {
    _chat.removeListener(_sessionChanged); _debounce?.cancel(); _name.dispose(); _search.dispose(); super.dispose();
  }
  void _searchChanged(String value) {
    _debounce?.cancel(); _searchId++;
    _debounce = Timer(const Duration(milliseconds: 300), () => _find(false));
  }
  Future<void> _find(bool append) async {
    if (!_current) return;
    final request = ++_searchId;
    setState(() { _loading = true; _error = null; });
    try {
      final page = await _chat.findGroupUsers(_search.text.trim(), afterUserId: append ? _after : 0);
      if (!_current || request != _searchId) return;
      final existing = widget.group == null ? <int>{} : _chat.members(widget.group!.id).map((member) => member.user.userId).toSet();
      setState(() {
        _users = {
          for (final user in append ? _users : <ChatUser>[]) user.userId: user,
          for (final user in page.items)
            if (!existing.contains(user.userId) && user.userId != _chat.userId) user.userId: user,
        }.values.toList();
        _after = page.items.isEmpty ? 0 : page.items.last.userId; _more = page.hasMore;
      });
    } on Object { if (_current && request == _searchId) setState(() => _error = 'chatFailed'); }
    finally { if (_current && request == _searchId) setState(() => _loading = false); }
  }
  void _select(ChatUser user, bool selected) {
    final maximum = widget.group == null ? 99 : 100 - _chat.members(widget.group!.id).length;
    if (selected && _selected.length >= maximum) { setState(() => _error = 'chatGroupInvalid'); return; }
    setState(() { if (selected) _selected[user.userId] = user; else _selected.remove(user.userId); });
  }
  Future<void> _submit() async {
    if (_busy || !_current) return;
    final users = _selected.keys.toList()..sort();
    if (users.length < (widget.group == null ? 2 : 1) || (widget.group == null && _name.text.trim().isEmpty)) {
      setState(() => _error = 'chatGroupInvalid'); return;
    }
    FocusScope.of(context).unfocus();
    setState(() { _busy = true; _error = null; });
    if (widget.group == null) {
      final fingerprint = '${_name.text.trim()}\u0000${users.join(',')}';
      if (fingerprint != _fingerprint) { _fingerprint = fingerprint; _clientId = const Uuid().v4(); }
      final group = await _chat.createGroup(_clientId!, _name.text, users);
      if (_current && group != null) { Navigator.pop(context, group); return; }
    } else {
      final success = await _chat.changeGroup(widget.group!.id, 'add', userIds: users);
      if (_current && success) { Navigator.pop(context); return; }
    }
    if (_current) setState(() => _busy = false);
  }
  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final content = ChatTheme(child: Scaffold(appBar: AppBar(title: Text(AppLocalizations.of(context, widget.group == null ? 'chatCreateGroup' : 'chatAddMembers')),
      actions: [IconButton(key: const ValueKey('chat-group-save'), onPressed: _busy ? null : _submit,
        tooltip: AppLocalizations.of(context, 'chatSave'), icon: const Icon(Icons.check))]),
      body: SafeArea(child: Column(children: [
        if (chat.error != null) ChatErrorBanner(chat: chat),
        if (_error != null) Padding(padding: const EdgeInsets.all(8), child: Text(AppLocalizations.of(context, _error!))),
        if (_busy || _loading) const LinearProgressIndicator(),
        if (widget.group == null) Padding(padding: const EdgeInsets.all(12), child: TextField(key: const ValueKey('chat-group-name'),
          controller: _name, enabled: !_busy, maxLength: 100, decoration: InputDecoration(
            prefixIcon: const Icon(Icons.groups_outlined), labelText: AppLocalizations.of(context, 'chatGroupName')))),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: TextField(key: const ValueKey('chat-group-user-search'), controller: _search, maxLength: 100, enabled: !_busy,
          onChanged: _searchChanged, decoration: InputDecoration(counterText: '', hintText: AppLocalizations.of(context, 'chatSearch'), prefixIcon: const Icon(Icons.search)))),
        Padding(padding: const EdgeInsets.all(8), child: Text('${AppLocalizations.of(context, 'chatSelected')}: ${_selected.length}')),
        if (_selected.isNotEmpty) SizedBox(height: 46, child: ListView(scrollDirection: Axis.horizontal, children: [
          for (final user in _selected.values) Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: InputChip(
            avatar: ChatAvatar(name: user.displayName, userId: user.userId, size: 24),
            label: Text(user.displayName), onDeleted: _busy ? null : () => _select(user, false))),
        ])),
        Expanded(child: ListView(children: [
          for (final user in _users) CheckboxListTile(key: ValueKey('chat-group-user-${user.userId}'), value: _selected.containsKey(user.userId),
            secondary: ChatAvatar(name: user.displayName, userId: user.userId, size: 38),
            title: Text(user.displayName, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            subtitle: Text('${user.username} · ${user.department}', maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11)),
            onChanged: _busy ? null : (value) => _select(user, value == true)),
          if (_users.isEmpty && !_loading) Padding(padding: const EdgeInsets.all(24), child: Text(
            AppLocalizations.of(context, 'chatNoUsers'), textAlign: TextAlign.center)),
          if (_error != null) TextButton(onPressed: _loading || _busy ? null : () => _find(false),
            child: Text(AppLocalizations.of(context, 'chatRetry'))),
          if (_more) TextButton(onPressed: _loading || _busy ? null : () => _find(true), child: Text(AppLocalizations.of(context, 'chatMore'))),
        ])),
      ]))));
    return widget.group == null ? content : ChatConversationScope(provider: chat, conversationId: widget.group!.id, child: content);
  }
}

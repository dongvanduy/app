import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../domain/entities/chat_models.dart';
import '../providers/chat_provider.dart';
import '../widgets/chat_message_bubble.dart';
import 'chat_list_screen.dart';
import 'chat_group_info_screen.dart';
import '../widgets/chat_conversation_scope.dart';
import '../widgets/chat_composer.dart';
import '../widgets/chat_day_divider.dart';
import '../widgets/chat_theme.dart';
import '../widgets/chat_thread_header.dart';
import '../controllers/chat_mention_controller.dart';
import '../widgets/chat_mention_suggestions.dart';

class ChatThreadScreen extends StatefulWidget {
  const ChatThreadScreen({super.key, required this.conversationId});
  final String conversationId;
  @override
  State<ChatThreadScreen> createState() => _ChatThreadScreenState();
}

class _ChatThreadScreenState extends State<ChatThreadScreen> with WidgetsBindingObserver {
  final _draft = ChatMentionController();
  final _draftFocus = FocusNode();
  final _scroll = ScrollController();
  final _viewport = GlobalKey();
  final _keys = <String, GlobalKey>{};
  final _readyImages = <String>{};
  late ChatProvider _chat;
  late int _generation;
  bool _emojis = false, _readingScheduled = false, _initialized = false;
  String? _newestId;
  String? _dismissedMention;
  int? _highlightedMentionUserId;
  bool _memberFetchQueued = false;
  String get _mentionSignature => '${_draft.text}\u0000${_draft.selection.extentOffset}';
  bool get _mentionQueryVisible => mounted && _chat.foreground && _generation == _chat.generation
    && _draftFocus.hasFocus && !_emojis && ModalRoute.of(context)?.isCurrent == true
    && _chat.conversation(widget.conversationId)?.isGroup == true
    && _dismissedMention != _mentionSignature && _draft.query != null;
  List<ChatUser> get _mentionUsers => !_mentionQueryVisible
    || _chat.membersState(widget.conversationId) != ChatMemberLoadState.ready
    ? const [] : _draft.suggestions(_chat.members(widget.conversationId));
  int _mentionIndex(List<ChatUser> users) => users.isEmpty ? -1 : _highlightedMentionUserId == null
    ? 0 : users.indexWhere((user) => user.userId == _highlightedMentionUserId);

  void _onDraftFocus() {
    if (!mounted) return;
    setState(() { if (!_draftFocus.hasFocus) _dismissedMention = _mentionSignature; });
  }
  void _dismissMentions() {
    setState(() => _dismissedMention = _mentionSignature); _draftFocus.requestFocus();
  }
  void _beginMention() {
    if (_generation != _chat.generation || _chat.wasRemoved(widget.conversationId)) return;
    if (_draft.beginMention()) {
      _draftFocus.requestFocus();
      setState(() { _emojis = false; _dismissedMention = null; _highlightedMentionUserId = null; });
    }
  }
  void _chooseMention(ChatUser user, {String? signature}) {
    if (_generation != _chat.generation || !_chat.foreground || _chat.wasRemoved(widget.conversationId)
        || _chat.conversation(widget.conversationId)?.isGroup != true || ModalRoute.of(context)?.isCurrent != true
        || _chat.membersState(widget.conversationId) != ChatMemberLoadState.ready
        || signature != null && signature != _mentionSignature) return;
    final current = _draft.suggestions(_chat.members(widget.conversationId)).where((candidate) => candidate.userId == user.userId);
    if (current.isEmpty) return;
    if (_draft.choose(current.first)) {
      _draftFocus.requestFocus(); setState(() { _emojis = false; _dismissedMention = null; });
    }
  }
  void _ensureMentionMembers() {
    if (_memberFetchQueued || !_mentionQueryVisible
        || _chat.membersState(widget.conversationId) != ChatMemberLoadState.idle) return;
    _memberFetchQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _memberFetchQueued = false;
      if (mounted && _mentionQueryVisible && _chat.membersState(widget.conversationId) == ChatMemberLoadState.idle) {
        unawaited(_loadMentionMembers());
      }
    });
  }
  Future<void> _loadMentionMembers({bool focus = false}) async {
    if (focus && mounted) {
      _draftFocus.requestFocus(); setState(() => _dismissedMention = null);
    }
    final epoch = _chat.conversationEpoch(widget.conversationId);
    final loaded = await _chat.reloadMembers(widget.conversationId);
    if (!loaded || !mounted || _generation != _chat.generation
        || epoch != _chat.conversationEpoch(widget.conversationId) || ModalRoute.of(context)?.isCurrent != true) return;
    if (!_chat.threadReady(widget.conversationId) && !_chat.opening) {
      await _chat.openConversation(widget.conversationId);
    }
  }
  KeyEventResult _onMentionKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || !_mentionQueryVisible) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      _dismissMentions(); return KeyEventResult.handled;
    }
    final users = _mentionUsers;
    if (users.isEmpty) return KeyEventResult.ignored;
    final index = _mentionIndex(users);
    if (key == LogicalKeyboardKey.enter) {
      if (index >= 0) _chooseMention(users[index]);
    }
    else if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.arrowUp) {
      final next = index < 0 ? (key == LogicalKeyboardKey.arrowDown ? 0 : users.length - 1)
        : (index + (key == LogicalKeyboardKey.arrowDown ? 1 : -1) + users.length) % users.length;
      setState(() => _highlightedMentionUserId = users[next].userId);
    } else { return KeyEventResult.ignored; }
    return KeyEventResult.handled;
  }
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _chat = context.read<ChatProvider>(); _generation = _chat.generation;
    _draft.restore(_chat.draft(widget.conversationId), _chat.draftMentions(widget.conversationId));
    _draftFocus.onKeyEvent = _onMentionKey;
    _draftFocus.addListener(_onDraftFocus);
    _draft.addListener(_onDraft); _scroll.addListener(_scheduleRead); _chat.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) unawaited(_chat.openConversation(widget.conversationId)); });
  }
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _chat.removeListener(_changed); _chat.closeConversation(widget.conversationId);
    _draft.removeListener(_onDraft); _draftFocus.removeListener(_onDraftFocus);
    _draft.dispose(); _draftFocus.dispose(); _scroll.dispose();
    super.dispose();
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) { if (state == AppLifecycleState.resumed) _scheduleRead(); }
  void _onDraft() {
    if (_generation != _chat.generation) return;
    _chat.setDraft(widget.conversationId, _draft.text, mentions: _draft.mentions);
    setState(() { _highlightedMentionUserId = null; if (_dismissedMention != _mentionSignature) _dismissedMention = null; });
  }
  void _changed() {
    if (!mounted) return;
    if (_generation != _chat.generation || _chat.wasRemoved(widget.conversationId)) {
      _draft.clear(); _readyImages.clear(); return;
    }
    final messages = _chat.messages(widget.conversationId);
    final latest = messages.isEmpty ? null : messages.last.id;
    final preserve = _initialized && latest != _newestId && _scroll.hasClients && _scroll.offset > 60;
    final pixels = _scroll.hasClients ? _scroll.offset : 0.0;
    final extent = _scroll.hasClients ? _scroll.position.maxScrollExtent : 0.0;
    _newestId = latest; _initialized = true;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      if (preserve) _scroll.jumpTo((pixels + _scroll.position.maxScrollExtent - extent).clamp(0.0, _scroll.position.maxScrollExtent).toDouble());
      _scheduleRead();
    });
  }
  void _scheduleRead() {
    if (_readingScheduled || !mounted) return;
    _readingScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _readingScheduled = false;
      if (!mounted || !_chat.foreground || _generation != _chat.generation || ModalRoute.of(context)?.isCurrent != true) return;
      final viewport = _viewport.currentContext?.findRenderObject();
      if (viewport is! RenderBox || !viewport.hasSize) return;
      final bounds = viewport.localToGlobal(Offset.zero) & viewport.size;
      String? sequence;
      for (final message in _chat.messages(widget.conversationId)) {
        if (message.sequence == null || message.senderUserId == _chat.userId) continue;
        final box = _keys[message.id]?.currentContext?.findRenderObject();
        if (box is! RenderBox || !box.hasSize || !bounds.overlaps(box.localToGlobal(Offset.zero) & box.size)) continue;
        if (message.image != null && !_readyImages.contains(message.id)) break;
        sequence = message.sequence;
      }
      if (sequence != null) unawaited(_chat.markRead(widget.conversationId, sequence));
    });
  }
  void _send() {
    if (_draft.text.length > 4000 || (_draft.text.trim().isEmpty && _chat.draftImage(widget.conversationId) == null)) return;
    final text = _draft.text;
    final mentions = _draft.mentions;
    _draft.clear();
    setState(() => _emojis = false);
    unawaited(_chat.send(widget.conversationId, text, mentions: mentions));
    if (_scroll.hasClients) _scroll.animateTo(0, duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
  }
  void _toggleEmoji() {
    _dismissedMention = _mentionSignature;
    final opening = !_emojis;
    if (opening) { _draftFocus.unfocus(); } else { _draftFocus.requestFocus(); }
    setState(() => _emojis = opening);
  }
  void _onDraftTap() { setState(() { _emojis = false; _dismissedMention = null; }); }
  Future<void> _pick() async {
    final camera = await showModalBottomSheet<bool>(context: context, builder: (context) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min,
      children: [ListTile(leading: const Icon(Icons.photo_library_outlined), title: Text(AppLocalizations.of(context, 'chatGallery')),
        onTap: () => Navigator.pop(context, false)), ListTile(leading: const Icon(Icons.camera_alt_outlined),
        title: Text(AppLocalizations.of(context, 'chatCamera')), onTap: () => Navigator.pop(context, true))])));
    if (camera != null && mounted && _generation == _chat.generation) await _chat.pickImage(widget.conversationId, camera: camera);
  }
  Future<void> _groupInfo() async {
    await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => ChatGroupInfoScreen(conversationId: widget.conversationId)));
    if (mounted) _scheduleRead();
  }
  Widget _history(ChatProvider chat, ChatConversation? conversation, List<ChatMessage> messages) {
    return ListView.builder(
      key: const ValueKey('chat-message-list'), controller: _scroll, reverse: true,
      padding: const EdgeInsets.only(bottom: 10), itemCount: messages.length + 1,
      itemBuilder: (context, index) {
        if (index == messages.length) {
          if (chat.hasOlder(widget.conversationId)) return Center(child: TextButton(
            onPressed: chat.loadingOlder ? null : () => unawaited(chat.loadOlder(widget.conversationId)),
            child: Text(AppLocalizations.of(context, 'chatOlder')),
          ));
          if (!chat.threadReady(widget.conversationId) && !chat.opening) return Center(child: TextButton(
            onPressed: () => unawaited(chat.openConversation(widget.conversationId)),
            child: Text(AppLocalizations.of(context, 'chatRetry')),
          ));
          return const SizedBox(height: 8);
        }
        final message = messages[index];
        final firstOfDay = index == messages.length - 1 || !chatSameDay(message.createdAt, messages[index + 1].createdAt);
        return Column(mainAxisSize: MainAxisSize.min, children: [
          if (firstOfDay) ChatDayDivider(date: message.createdAt),
          ChatMessageBubble(
            key: _keys.putIfAbsent(message.id, () => GlobalKey()), message: message, provider: chat,
            peerRead: conversation?.participantLastReadSequence ?? '0', onImageLayout: _scheduleRead,
            onImageReady: (ready) {
              if (ready) { _readyImages.add(message.id); } else { _readyImages.remove(message.id); }
              _scheduleRead();
            },
          ),
        ]);
      },
    );
  }

  Widget _composer(ChatProvider chat, ChatConversation? conversation, bool compact) {
    final users = _mentionUsers;
    final showMentions = _mentionQueryVisible;
    final signature = _mentionSignature;
    return ChatComposer(
      mentionSuggestions: !showMentions ? null : ChatMentionSuggestions(
        users: users, selected: _mentionIndex(users),
        state: chat.membersState(widget.conversationId), compact: compact,
        onSelected: (user) => _chooseMention(user, signature: signature),
        onRetry: () => unawaited(_loadMentionMembers(focus: true)), onDismiss: _dismissMentions),
      onMention: conversation?.isGroup == true ? _beginMention : null,
      inputError: _draft.failureKey,
      controller: _draft, focusNode: _draftFocus, ready: chat.threadReady(widget.conversationId),
      showEmojis: _emojis, compactHeight: compact, image: chat.draftImage(widget.conversationId),
      onSend: _send, onAttach: () => unawaited(_pick()), onToggleEmojis: _toggleEmoji,
      onDraftTap: _onDraftTap, onRemoveImage: () => chat.removeDraftImage(widget.conversationId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final conversation = chat.conversation(widget.conversationId);
    final messages = chat.messages(widget.conversationId).reversed.toList();
    final colors = ChatColors.of(context);
    final compact = MediaQuery.sizeOf(context).height - MediaQuery.viewInsetsOf(context).bottom < 420;
    final showMentions = _mentionQueryVisible;
    _ensureMentionMembers(); _scheduleRead();
    return ChatConversationScope(
      provider: chat, conversationId: widget.conversationId,
      child: ChatTheme(child: PopScope(
        canPop: !_emojis && !showMentions,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) setState(() { _emojis = false; _dismissedMention = _mentionSignature; });
        },
        child: Scaffold(
          appBar: ChatThreadHeader(
            conversation: conversation, connection: chat.connection,
            onGroupInfo: () => unawaited(_groupInfo()), onRefresh: () => unawaited(chat.refresh())),
          body: DecoratedBox(
            decoration: BoxDecoration(gradient: LinearGradient(colors: [colors.surface, colors.background],
              begin: Alignment.topLeft, end: Alignment.bottomRight)),
            child: SafeArea(top: false, child: Column(children: [
              if (chat.error != null) ChatErrorBanner(chat: chat),
              if (chat.opening) const LinearProgressIndicator(),
              Expanded(child: LayoutBuilder(builder: (context, constraints) => Column(children: [
                Expanded(key: _viewport, child: _history(chat, conversation, messages)),
                // When an IME or error banner leaves little room, keep all composer actions reachable.
                ConstrainedBox(constraints: BoxConstraints(maxHeight: constraints.maxHeight),
                  child: SingleChildScrollView(reverse: true, primary: false,
                    child: _composer(chat, conversation, compact))),
              ]))),
            ])),
          ),
        ),
      )),
    );
  }
}

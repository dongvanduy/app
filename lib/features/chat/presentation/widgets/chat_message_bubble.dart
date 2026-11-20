import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../domain/entities/chat_models.dart';
import '../../domain/entities/chat_mentions.dart';
import '../providers/chat_provider.dart';
import 'chat_avatar.dart';
import 'chat_conversation_scope.dart';
import 'chat_day_divider.dart';
import 'chat_system_message.dart';
import 'chat_theme.dart';
import 'chat_mention_text.dart';

class ChatMessageBubble extends StatelessWidget {
  const ChatMessageBubble({super.key, required this.message, required this.provider, required this.peerRead,
    required this.onImageReady, required this.onImageLayout});
  final ChatMessage message;
  final ChatProvider provider;
  final String peerRead;
  final ValueChanged<bool> onImageReady;
  final VoidCallback onImageLayout;

  Widget _systemNote(BuildContext context) {
    final c = ChatColors.of(context);
    return Center(child: Container(
      constraints: const BoxConstraints(maxWidth: 280),
      margin: const EdgeInsets.fromLTRB(24, 6, 24, 14),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: c.incoming, borderRadius: BorderRadius.circular(12)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.groups_outlined, size: 17, color: c.muted),
          const SizedBox(width: 8),
          Expanded(child: Text(chatSystemText(context, message),
            style: TextStyle(fontSize: 11, color: c.text, height: 1.4))),
        ]),
        const SizedBox(height: 4),
        Text(chatTime(message.createdAt), style: TextStyle(fontSize: 10, color: c.muted)),
      ]),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (message.kind == 'system') return _systemNote(context);
    final own = message.senderUserId == provider.userId;
    final c = ChatColors.of(context);
    final conversation = provider.conversation(message.conversationId);
    final group = conversation?.isGroup == true;
    final senderName = message.sender?.displayName ?? conversation?.participant?.displayName ?? '';
    final readCount = group && message.sequence != null ? provider.readers(message).length : 0;
    final read = message.sequence != null && (group ? readCount > 0 : compareChatSequence(message.sequence!, peerRead) <= 0);
    final status = message.delivery == ChatDelivery.sending ? 'chatSending'
      : message.delivery == ChatDelivery.failed ? 'chatSendFailed' : read ? 'chatRead' : 'chatSent';
    final statusIcon = message.delivery == ChatDelivery.sending ? Icons.schedule_outlined
      : message.delivery == ChatDelivery.failed ? Icons.error_outline : read ? Icons.done_all_rounded : Icons.check_rounded;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (!own) ...[
          Padding(padding: const EdgeInsets.only(top: 17),
            child: ChatAvatar(name: senderName, userId: message.senderUserId, size: 30)),
          const SizedBox(width: 8),
        ] else const SizedBox(width: 38),
        Expanded(child: Column(crossAxisAlignment: own ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
          if (!own && senderName.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 4),
            child: Text(senderName, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: c.text))),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              border: !own && validChatMentions(message.text, message.mentions).any((mention) => mention.userId == provider.userId)
                ? Border.all(color: c.accent.withValues(alpha: .6), width: 2) : null,
              gradient: own ? ChatColors.sentGradient : null,
              color: own ? null : c.incoming,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(14), topRight: const Radius.circular(14),
                bottomLeft: Radius.circular(own ? 14 : 4), bottomRight: Radius.circular(own ? 4 : 14),
              ),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              if (message.image != null) ChatMessageImage(message: message, provider: provider,
                onReady: onImageReady, onLayout: onImageLayout),
              if (message.text.isNotEmpty) Padding(padding: EdgeInsets.only(top: message.image != null ? 8 : 0),
                child: SelectionArea(child: ChatMentionText(text: message.text, mentions: message.mentions, own: own,
                  style: TextStyle(color: own ? Colors.white : c.text, fontSize: 14, height: 1.4)))),
            ]),
          ),
          if (own && group && message.sequence != null) Padding(padding: const EdgeInsets.only(top: 4),
            child: TextButton(
              onPressed: () => _readers(context),
              style: TextButton.styleFrom(backgroundColor: c.readPill, foregroundColor: c.text,
                minimumSize: const Size(0, 28), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              child: Text(AppLocalizations.of(context, 'chatReadBy').replaceAll('{count}', '$readCount'),
                style: const TextStyle(fontSize: 11)),
            )),
          Padding(padding: const EdgeInsets.only(top: 4), child: Row(
            mainAxisSize: MainAxisSize.min, children: [
              Text(chatTime(message.createdAt), style: TextStyle(fontSize: 10, color: c.muted)),
              if (own) ...[
                const SizedBox(width: 4),
                if (message.delivery != ChatDelivery.sent) Flexible(child: Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Text(AppLocalizations.of(context, status), maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10, color: message.delivery == ChatDelivery.failed ? c.danger : c.muted)))),
                Tooltip(message: AppLocalizations.of(context, status),
                  child: Icon(statusIcon, size: 15, color: message.delivery == ChatDelivery.failed ? c.danger : c.accent)),
              ],
            ],
          )),
          if (message.delivery == ChatDelivery.failed) TextButton.icon(
            onPressed: () => unawaited(provider.retry(message.clientMessageId)),
            style: TextButton.styleFrom(foregroundColor: c.danger, minimumSize: const Size(0, 30),
              padding: const EdgeInsets.symmetric(horizontal: 4), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
            icon: const Icon(Icons.refresh, size: 15),
            label: Text(AppLocalizations.of(context, 'chatRetry'), style: const TextStyle(fontSize: 12)),
          ),
        ])),
      ]),
    );
  }

  Future<void> _readers(BuildContext context) async {
    await showModalBottomSheet<void>(context: context, builder: (context) => ChatConversationScope(provider: provider,
      conversationId: message.conversationId, child: SafeArea(child: AnimatedBuilder(animation: provider,
        builder: (context, _) => ListView(shrinkWrap: true, padding: const EdgeInsets.symmetric(vertical: 12), children: [
          ListTile(leading: const Icon(Icons.done_all_rounded), title: Text(AppLocalizations.of(context, 'chatReaders'))),
          for (final member in provider.readers(message)) ListTile(
            leading: ChatAvatar(name: member.user.displayName, userId: member.user.userId, size: 36),
            title: Text(member.user.displayName)),
        ])))));
    onImageLayout();
  }
}

class ChatMessageImage extends StatefulWidget {
  const ChatMessageImage({super.key, required this.message, required this.provider, required this.onReady, required this.onLayout});
  final ChatMessage message;
  final ChatProvider provider;
  final ValueChanged<bool> onReady;
  final VoidCallback onLayout;
  @override
  State<ChatMessageImage> createState() => _ChatMessageImageState();
}

class _ChatMessageImageState extends State<ChatMessageImage> {
  late Future<Uint8List> _image;
  int _request = 0;
  bool _ready = false;
  @override
  void initState() { super.initState(); _image = widget.provider.loadImage(widget.message); }
  @override
  void dispose() { widget.onReady(false); super.dispose(); }
  void _report(bool ready) {
    if (_ready == ready) return;
    _ready = ready;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) { setState(() {}); widget.onReady(ready); widget.onLayout(); }
    });
  }
  void _retry() {
    _report(false);
    setState(() { _request++; _image = widget.provider.loadImage(widget.message); });
  }
  Future<void> _view(Uint8List bytes) async {
    final provider = widget.provider;
    final generation = provider.generation;
    await Navigator.of(context).push<void>(MaterialPageRoute(builder: (context) => ChatConversationScope(provider: provider,
      conversationId: widget.message.conversationId, child: _ChatImageViewer(bytes: bytes, provider: provider, generation: generation))));
    if (mounted) widget.onLayout();
  }
  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(future: _image, builder: (context, snapshot) {
    if (snapshot.hasError) { _report(false); return _failure(context); }
    if (!snapshot.hasData) return const SizedBox(height: 170, child: Center(child: CircularProgressIndicator()));
    return InkWell(onTap: _ready ? () => unawaited(_view(snapshot.data!)) : null,
      child: ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.memory(snapshot.data!, key: ValueKey(_request),
        height: 190, width: double.infinity, fit: BoxFit.contain, gaplessPlayback: true,
        frameBuilder: (context, child, frame, synchronouslyLoaded) {
          if (frame != null || synchronouslyLoaded) _report(true);
          return child;
        }, errorBuilder: (context, error, stack) { _report(false); return _failure(context); })));
  });
  Widget _failure(BuildContext context) => SizedBox(height: 170, child: Center(child: TextButton.icon(
    onPressed: _retry, icon: const Icon(Icons.refresh), label: Text(AppLocalizations.of(context, 'chatImageFailed')))));
}

class _ChatImageViewer extends StatefulWidget {
  const _ChatImageViewer({required this.bytes, required this.provider, required this.generation});
  final Uint8List bytes;
  final ChatProvider provider;
  final int generation;
  @override
  State<_ChatImageViewer> createState() => _ChatImageViewerState();
}

class _ChatImageViewerState extends State<_ChatImageViewer> {
  @override
  void initState() { super.initState(); widget.provider.addListener(_checkSession); }
  void _checkSession() {
    if (mounted && widget.generation != widget.provider.generation && ModalRoute.of(context)?.isCurrent == true) {
      Navigator.of(context).maybePop();
    }
  }
  @override
  void dispose() { widget.provider.removeListener(_checkSession); super.dispose(); }
  @override
  Widget build(BuildContext context) => Scaffold(backgroundColor: Colors.black,
    appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: Text(AppLocalizations.of(context, 'chatImage'))),
    body: Center(child: InteractiveViewer(minScale: .5, maxScale: 5,
      child: Image.memory(widget.bytes, fit: BoxFit.contain))));
}

import 'package:flutter/material.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../domain/entities/chat_models.dart';
import 'chat_emoji_picker.dart';
import 'chat_theme.dart';

class ChatComposer extends StatelessWidget {
  const ChatComposer({super.key, required this.controller, required this.focusNode,
    required this.ready, required this.showEmojis, required this.compactHeight,
    required this.onSend, required this.onAttach, required this.onToggleEmojis,
    required this.onDraftTap, required this.onRemoveImage, this.image, this.mentionSuggestions,
    this.onMention, this.inputError});

  final TextEditingController controller;
  final FocusNode focusNode;
  final ChatDraftImage? image;
  final Widget? mentionSuggestions;
  final VoidCallback? onMention;
  final String? inputError;
  final bool ready, showEmojis, compactHeight;
  final VoidCallback onSend, onAttach, onToggleEmojis, onDraftTap, onRemoveImage;

  Widget _tool(BuildContext context, String key, IconData icon, String label, VoidCallback callback) =>
    SizedBox(width: 36, height: 44, child: IconButton(
      key: ValueKey(key), onPressed: callback, padding: EdgeInsets.zero,
      tooltip: AppLocalizations.of(context, label), icon: Icon(icon, size: 22)));

  @override
  Widget build(BuildContext context) {
    final c = ChatColors.of(context);
    final tooLong = controller.text.length > 4000;
    final canSend = ready && !tooLong && (controller.text.trim().isNotEmpty || image != null);
    final error = tooLong ? 'chatTextTooLong' : inputError;
    return TextFieldTapRegion(child: Container(
      key: const ValueKey('chat-composer'),
      decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.border))),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (image != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(children: [
          ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.memory(image!.bytes,
            width: 72, height: compactHeight ? 40 : 68, fit: BoxFit.contain,
            errorBuilder: (context, error, stack) => const Icon(Icons.broken_image_outlined))),
          const SizedBox(width: 8),
          Expanded(child: Text(image!.fileName, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: c.muted))),
          IconButton(key: const ValueKey('chat-remove-image'), onPressed: onRemoveImage,
            tooltip: AppLocalizations.of(context, 'chatRemoveImage'), icon: const Icon(Icons.close, size: 20)),
        ])),
        if (mentionSuggestions != null) mentionSuggestions!,
        if (showEmojis && mentionSuggestions == null) ChatEmojiPicker(onSelected: (emoji) => insertChatEmoji(controller, emoji),
          height: compactHeight ? 96 : 190),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          _tool(context, 'chat-attach', Icons.attach_file_rounded, 'chatImage', onAttach),
          _tool(context, 'chat-emoji', Icons.sentiment_satisfied_alt_outlined, 'chatEmoji', onToggleEmojis),
          if (onMention != null) _tool(context, 'chat-mention', Icons.alternate_email, 'chatMentionInsert', onMention!),
          const SizedBox(width: 4),
          Expanded(child: TextField(
            key: const ValueKey('chat-draft'), controller: controller, focusNode: focusNode,
            onTap: onDraftTap, minLines: 1,
            maxLines: compactHeight ? (showEmojis || image != null || mentionSuggestions != null ? 1 : 2) : 5,
            style: TextStyle(fontSize: 14, color: c.text, height: 1.35),
            keyboardType: TextInputType.multiline, textInputAction: TextInputAction.newline,
            decoration: InputDecoration(hintText: AppLocalizations.of(context, 'chatCompose'),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
          )),
          const SizedBox(width: 6),
          Container(width: 44, height: 44,
            decoration: BoxDecoration(gradient: canSend ? ChatColors.sentGradient : null,
              color: canSend ? null : c.tint, borderRadius: BorderRadius.circular(13)),
            child: IconButton(key: const ValueKey('chat-send'), onPressed: canSend ? onSend : null,
              tooltip: AppLocalizations.of(context, 'chatSend'),
              style: IconButton.styleFrom(foregroundColor: Colors.white, disabledForegroundColor: c.muted),
              icon: const Icon(Icons.send_rounded, size: 21)),
          ),
        ]),
        if (error != null) Padding(padding: const EdgeInsets.only(top: 5), child: Align(alignment: Alignment.centerLeft,
          child: Text(AppLocalizations.of(context, error), style: TextStyle(color: c.danger, fontSize: 11)))),
      ]),
    ));
  }
}

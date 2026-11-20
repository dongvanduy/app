import 'package:flutter/material.dart';
import '../../domain/entities/chat_models.dart';
import 'chat_theme.dart';
import '../formatters/chat_mention_spans.dart';

class ChatMentionText extends StatelessWidget {
  const ChatMentionText({super.key, required this.text, required this.mentions, required this.style, this.own = false});
  final String text;
  final List<ChatMention> mentions;
  final TextStyle style;
  final bool own;
  @override
  Widget build(BuildContext context) {
    final c = ChatColors.of(context);
    final spans = chatMentionSpans(text, mentions, TextStyle(color: own ? Colors.white : c.accent,
      backgroundColor: own ? Colors.white.withValues(alpha: .18) : c.tint, fontWeight: FontWeight.w700));
    return Text.rich(TextSpan(children: spans), style: style);
  }
}

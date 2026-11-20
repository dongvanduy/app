import 'package:flutter/painting.dart';
import '../../domain/entities/chat_mentions.dart';
import '../../domain/entities/chat_models.dart';

List<TextSpan> chatMentionSpans(String text, Iterable<ChatMention> mentions, TextStyle mentionStyle) {
  final spans = <TextSpan>[];
  var cursor = 0;
  for (final mention in validChatMentions(text, mentions)) {
    if (mention.start > cursor) spans.add(TextSpan(text: text.substring(cursor, mention.start)));
    spans.add(TextSpan(text: text.substring(mention.start, mention.start + mention.length), style: mentionStyle));
    cursor = mention.start + mention.length;
  }
  if (cursor < text.length) spans.add(TextSpan(text: text.substring(cursor)));
  return spans;
}

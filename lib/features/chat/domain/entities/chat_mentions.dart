import 'chat_models.dart';

const maximumChatMentions = 100;

bool _splitsSurrogate(String text, int offset) => offset > 0 && offset < text.length
  && text.codeUnitAt(offset - 1) >= 0xd800 && text.codeUnitAt(offset - 1) <= 0xdbff
  && text.codeUnitAt(offset) >= 0xdc00 && text.codeUnitAt(offset) <= 0xdfff;

/// Invalid metadata remains plain text. Conflicting spans never select an arbitrary user.
List<ChatMention> validChatMentions(String text, Iterable<ChatMention> mentions) {
  final items = mentions.toList();
  if (items.length > maximumChatMentions) return const [];
  final valid = items.where((item) => item.userId > 0 && item.start >= 0 && item.length >= 2
    && item.start < text.length && item.length <= text.length - item.start && text[item.start] == '@'
    && !_splitsSurrogate(text, item.start) && !_splitsSurrogate(text, item.start + item.length)).toList()
    ..sort((a, b) => a.start.compareTo(b.start));
  final result = <ChatMention>[];
  var index = 0;
  while (index < valid.length) {
    var next = index + 1;
    var end = valid[index].start + valid[index].length;
    while (next < valid.length && valid[next].start < end) {
      final candidateEnd = valid[next].start + valid[next].length;
      if (candidateEnd > end) end = candidateEnd;
      next++;
    }
    if (next == index + 1) result.add(valid[index]);
    index = next;
  }
  return List.unmodifiable(result);
}

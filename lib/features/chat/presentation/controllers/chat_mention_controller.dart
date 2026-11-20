import 'package:flutter/material.dart';

import '../../domain/entities/chat_mentions.dart';
import '../../domain/entities/chat_models.dart';
import '../formatters/chat_mention_spans.dart';

typedef ChatMentionQuery = ({int start, int end, String search});

String normalizeChatMentionSearch(String value) {
  var result = value.toLowerCase().replaceAll(RegExp(r'[\u0300-\u036f]'), '');
  const replacements = {
    '[àáạảãâầấậẩẫăằắặẳẵ]': 'a', '[èéẹẻẽêềếệểễ]': 'e', '[ìíịỉĩ]': 'i',
    '[òóọỏõôồốộổỗơờớợởỡ]': 'o', '[ùúụủũưừứựửữ]': 'u', '[ỳýỵỷỹ]': 'y', 'đ': 'd',
  };
  for (final entry in replacements.entries) { result = result.replaceAll(RegExp(entry.key), entry.value); }
  return result.trim().replaceAll(RegExp(r'\s+'), ' ');
}

class ChatMentionController extends TextEditingController {
  ChatMentionController({String text = '', List<ChatMention> mentions = const []})
    : _mentions = validChatMentions(text, mentions), super(text: text);
  List<ChatMention> _mentions;
  String? _failureKey;
  List<ChatMention> get mentions => List.unmodifiable(_mentions);
  String? get failureKey => _failureKey;
  bool get _composing => value.composing.isValid && !value.composing.isCollapsed;

  List<ChatMention> _afterEdit(String next, int start, int end) {
    final delta = next.length - text.length;
    final shifted = <ChatMention>[];
    for (final mention in _mentions) {
      final mentionEnd = mention.start + mention.length;
      if (end <= mention.start) {
        shifted.add(mention.at(mention.start + delta));
      } else if (start >= mentionEnd) {
        shifted.add(mention);
      }
      // Any edit inside a selected label turns that label back into plain text.
    }
    return validChatMentions(next, shifted);
  }

  List<ChatMention> _rebase(String next) {
    final oldSelection = selection;
    if (oldSelection.isValid && oldSelection.start <= text.length && oldSelection.end <= text.length) {
      final inserted = next.length - text.length + oldSelection.end - oldSelection.start;
      if (inserted >= 0 && oldSelection.start + inserted <= next.length
          && next.substring(0, oldSelection.start) == text.substring(0, oldSelection.start)
          && next.substring(oldSelection.start + inserted) == text.substring(oldSelection.end)) {
        return _afterEdit(next, oldSelection.start, oldSelection.end);
      }
    }
    // IME and programmatic replacements may not use the previous selection.
    var start = 0, oldEnd = text.length, newEnd = next.length;
    while (start < oldEnd && start < newEnd && text[start] == next[start]) { start++; }
    while (oldEnd > start && newEnd > start && text[oldEnd - 1] == next[newEnd - 1]) { oldEnd--; newEnd--; }
    return _afterEdit(next, start, oldEnd);
  }

  @override
  set value(TextEditingValue next) {
    if (next.text != text) {
      _mentions = _rebase(next.text);
      _failureKey = null;
    }
    super.value = next;
  }

  void restore(String text, List<ChatMention> mentions) {
    _mentions = validChatMentions(text, mentions);
    _failureKey = null;
    super.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }

  bool _boundary(int offset) => offset == 0 || RegExp(r'[\s(,;:\[{（，；：、【「]').hasMatch(text[offset - 1]);

  ChatMentionQuery? get query {
    if (!selection.isValid || !selection.isCollapsed || _composing) return null;
    final caret = selection.extentOffset;
    if (caret <= 0 || caret > text.length) return null;
    final start = text.lastIndexOf('@', caret - 1);
    if (start < 0 || !_boundary(start)
        || _mentions.any((item) => start >= item.start && start < item.start + item.length)) return null;
    final search = text.substring(start + 1, caret);
    if (search.length > 100 || search.contains(RegExp(r'[\r\n@]'))) return null;
    return (start: start, end: caret, search: search);
  }

  bool _fail(String key) { _failureKey = key; notifyListeners(); return false; }

  List<ChatUser> suggestions(Iterable<ChatMember> members) {
    final target = query;
    if (target == null) return const [];
    final search = normalizeChatMentionSearch(target.search);
    return members.map((member) => member.user).where((user) =>
      normalizeChatMentionSearch('${user.displayName} ${user.username}').contains(search)).toList();
  }

  bool beginMention() {
    if (_composing) return _fail('chatMentionFinishInput');
    if (_mentions.length >= maximumChatMentions) return _fail('chatMentionTooMany');
    if (query != null) return true;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : start;
    if (start > text.length || end > text.length) return false;
    final prefix = _boundary(start) ? '' : ' ';
    final suffix = end < text.length && !RegExp(r'\s').hasMatch(text[end]) ? ' ' : '';
    final replacement = '$prefix@$suffix';
    final next = text.replaceRange(start, end, replacement);
    if (next.length > 4000) return _fail('chatTextTooLong');
    _mentions = _afterEdit(next, start, end);
    _failureKey = null;
    super.value = TextEditingValue(text: next,
      selection: TextSelection.collapsed(offset: start + prefix.length + 1));
    return true;
  }

  bool choose(ChatUser user) {
    final target = query;
    if (target == null || user.userId <= 0) return false;
    if (_mentions.length >= maximumChatMentions) return _fail('chatMentionTooMany');
    final label = '@${user.displayName.trim()}';
    final end = target.end < text.length && text[target.end] == ' ' ? target.end + 1 : target.end;
    final next = text.replaceRange(target.start, end, '$label ');
    if (next.length > 4000) return _fail('chatTextTooLong');
    _mentions = validChatMentions(next, [
      ..._afterEdit(next, target.start, end),
      ChatMention(userId: user.userId, start: target.start, length: label.length),
    ]);
    _failureKey = null;
    super.value = TextEditingValue(text: next, selection: TextSelection.collapsed(offset: target.start + label.length + 1));
    return true;
  }

  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    if (withComposing && _composing) {
      return super.buildTextSpan(context: context, style: style, withComposing: withComposing);
    }
    final colors = Theme.of(context).colorScheme;
    return TextSpan(style: style, children: chatMentionSpans(text, _mentions, TextStyle(
      color: colors.primary, backgroundColor: colors.primaryContainer.withValues(alpha: .55), fontWeight: FontWeight.w700,
    )));
  }
}

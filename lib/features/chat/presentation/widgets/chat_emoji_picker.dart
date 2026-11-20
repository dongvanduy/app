import 'package:flutter/material.dart';

const chatEmojis = ['😀','😃','😄','😁','😆','😅','😂','🤣','😊','🙂','😉','😍','🥰','😘','😎','🤔','🤗','😢','😭','😮',
  '😴','😡','😱','🥳','👍','👎','👏','🙌','🙏','💪','👋','👌','✌️','❤️','💔','🔥','🎉','✅','⭐','💯'];

bool insertChatEmoji(TextEditingController controller, String emoji) {
  final selection = controller.selection;
  final start = selection.isValid ? selection.start : controller.text.length;
  final end = selection.isValid ? selection.end : start;
  final text = controller.text.replaceRange(start, end, emoji);
  if (text.length > 4000) return false;
  controller.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: start + emoji.length));
  return true;
}

class ChatEmojiPicker extends StatelessWidget {
  const ChatEmojiPicker({super.key, required this.onSelected, this.height = 190});
  final ValueChanged<String> onSelected;
  final double height;
  @override
  Widget build(BuildContext context) => SizedBox(height: height,
    child: GridView.count(crossAxisCount: 8, padding: const EdgeInsets.all(8),
      children: [for (final emoji in chatEmojis) Semantics(label: emoji, button: true,
        child: InkWell(onTap: () => onSelected(emoji), child: Center(child: Text(emoji, style: const TextStyle(fontSize: 24)))))]));
}

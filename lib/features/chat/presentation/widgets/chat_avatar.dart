import 'package:flutter/material.dart';
import 'chat_theme.dart';

String chatInitials(String name) {
  final words = name.trim().split(RegExp(r'\s+')).where((word) => word.isNotEmpty).toList();
  if (words.isEmpty) return '?';
  final letters = words.length == 1 ? words.first.runes.take(2)
    : [words.first.runes.first, words.last.runes.first];
  return String.fromCharCodes(letters).toUpperCase();
}

class ChatAvatar extends StatelessWidget {
  const ChatAvatar({super.key, required this.name, this.userId = 0,
    this.group = false, this.size = 40, this.onHeader = false});
  final String name;
  final int userId;
  final bool group, onHeader;
  final double size;
  static const _tones = [
    [Color(0xFFA06DB0), Color(0xFF5732A3)],
    [Color(0xFF8CCCA9), Color(0xFF4CA47F)],
    [Color(0xFF6EC5FF), Color(0xFF377BEC)],
    [Color(0xFFFFBC7A), Color(0xFFDA7D4D)],
    [Color(0xFFE991B5), Color(0xFFB9588F)],
    [Color(0xFF9186EC), Color(0xFF5A52B8)],
  ];
  @override
  Widget build(BuildContext context) {
    final colors = ChatColors.of(context);
    return ExcludeSemantics(child: Container(
      width: size, height: size, alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(group ? size * .26 : size / 2),
        color: group ? onHeader ? Colors.white.withValues(alpha: .16) : colors.tint : null,
        gradient: group ? null : LinearGradient(colors: _tones[userId.abs() % _tones.length],
          begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
      child: group ? Icon(Icons.groups_outlined, size: size * .55, color: onHeader ? Colors.white : colors.accent)
        : Text(chatInitials(name), style: TextStyle(fontSize: size * .32, fontWeight: FontWeight.w700, color: Colors.white)),
    ));
  }
}

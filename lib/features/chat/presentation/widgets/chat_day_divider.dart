import 'package:flutter/material.dart';
import '../../../../core/localization/app_localizations.dart';
import 'chat_theme.dart';

bool chatSameDay(DateTime a, DateTime b) {
  final left = a.toLocal(), right = b.toLocal();
  return left.year == right.year && left.month == right.month && left.day == right.day;
}

String chatTime(DateTime value) {
  final local = value.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

class ChatDayDivider extends StatelessWidget {
  const ChatDayDivider({super.key, required this.date});
  final DateTime date;
  @override
  Widget build(BuildContext context) {
    final c = ChatColors.of(context);
    final now = DateTime.now();
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    final label = chatSameDay(date, now) ? AppLocalizations.of(context, 'chatToday')
      : chatSameDay(date, yesterday) ? AppLocalizations.of(context, 'chatYesterday')
      : MaterialLocalizations.of(context).formatMediumDate(date.toLocal());
    return Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 12), child: Row(children: [
      Expanded(child: Divider(color: c.border)),
      Container(margin: const EdgeInsets.symmetric(horizontal: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(color: c.incoming, borderRadius: BorderRadius.circular(20)),
        child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: c.muted))),
      Expanded(child: Divider(color: c.border)),
    ]));
  }
}

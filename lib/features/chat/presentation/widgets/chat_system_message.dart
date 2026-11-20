import 'package:flutter/widgets.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../domain/entities/chat_models.dart';

String chatSystemText(BuildContext context, ChatMessage message) {
  final event = message.systemEvent;
  if (event == null) return '';
  return AppLocalizations.of(context, 'chatEvent_${event.type}')
    .replaceAll('{actor}', message.sender?.displayName ?? '')
    .replaceAll('{users}', event.affectedUsers.map((user) => user.displayName).join(', '))
    .replaceAll('{name}', event.name ?? '');
}

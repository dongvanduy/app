import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../pe_system/presentation/widgets/business_widgets.dart';
import 'lookup_widgets.dart';

typedef HistoryField = ({String label, String? value, bool preview});

Future<void> showHistoryDetail(
  BuildContext context,
  String id,
  List<HistoryField> fields,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: LookupColors(context).surface,
    builder:
        (context) => FractionallySizedBox(
          heightFactor: .9,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${bt(context, 'lookup_full_details')} · $id',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: bt(context, 'lookup_close'),
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: SelectionArea(
                      child: ListView(
                        key: const ValueKey('lookup-detail-scroll'),
                        children: [
                          Text('ID: $id'),
                          for (final field in fields)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    bt(context, field.label),
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: LookupColors(context).accent,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    lookupValue(field.value),
                                    key: ValueKey('detail-${field.label}'),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    key: const ValueKey('lookup-copy'),
                    onPressed: () async {
                      final content = [
                        'ID: $id',
                        ...fields.map(
                          (field) =>
                              '${bt(context, field.label)}: ${lookupValue(field.value)}',
                        ),
                      ].join('\n\n');
                      final copied = bt(context, 'lookup_copied');
                      final failed = bt(context, 'lookup_copy_failed');
                      try {
                        await Clipboard.setData(ClipboardData(text: content));
                        if (context.mounted) {
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(SnackBar(content: Text(copied)));
                        }
                      } catch (_) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(SnackBar(content: Text(failed)));
                        }
                      }
                    },
                    icon: const Icon(Icons.copy),
                    label: Text(bt(context, 'lookup_copy')),
                  ),
                ],
              ),
            ),
          ),
        ),
  );
}

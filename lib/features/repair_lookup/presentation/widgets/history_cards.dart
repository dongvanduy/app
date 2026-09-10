import 'package:flutter/material.dart';
import '../../domain/entities/repair_lookup_models.dart';
import '../../../pe_system/presentation/widgets/business_widgets.dart';
import 'history_detail_sheet.dart';
import 'lookup_widgets.dart';

String _time(DateTime? value) =>
    value == null ? '—' : '${formatLookupTime(value)} GMT+7';

List<HistoryField> testHistoryFields(TestHistoryEntry entry) => [
  (label: 'lookup_test_group', value: entry.testGroup, preview: false),
  (label: 'lookup_test_code', value: entry.testCode, preview: true),
  (label: 'lookup_error_desc', value: entry.errorDesc, preview: true),
  (label: 'lookup_error_item', value: entry.errorCodeItem, preview: false),
  (label: 'lookup_test_time', value: _time(entry.testTime), preview: false),
  (label: 'lookup_reason_code', value: entry.reasonCode, preview: false),
  (label: 'lookup_reason_desc', value: entry.reasonDesc, preview: true),
  (label: 'lookup_memo', value: entry.memo, preview: true),
];

List<HistoryField> repairHistoryFields(RepairHistoryEntry entry) => [
  (label: 'lookup_test_group', value: entry.testGroup, preview: false),
  (label: 'lookup_test_time', value: _time(entry.testTime), preview: false),
  (label: 'lookup_date3', value: _time(entry.date3), preview: false),
  (label: 'lookup_repairer', value: entry.repairer, preview: false),
  (label: 'lookup_repair_action', value: entry.repairAction, preview: true),
];

class HistoryEntryCard extends StatelessWidget {
  const HistoryEntryCard({
    super.key,
    required this.id,
    required this.number,
    required this.fields,
    required this.repair,
  });
  final String id;
  final int number;
  final List<HistoryField> fields;
  final bool repair;

  @override
  Widget build(BuildContext context) {
    final c = LookupColors(context);
    return LookupCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: c.tint,
                child: Text(
                  '$number',
                  style: TextStyle(
                    color: c.accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                repair ? Icons.build_outlined : Icons.description_outlined,
                color: c.accent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  id,
                  style: TextStyle(color: c.muted, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final field in fields)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    bt(context, field.label),
                    style: TextStyle(fontSize: 12, color: c.muted),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    lookupValue(field.value),
                    maxLines: field.preview ? 4 : null,
                    overflow: field.preview ? TextOverflow.ellipsis : null,
                    style: TextStyle(fontSize: 14, color: c.text, height: 1.35),
                  ),
                ],
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: ValueKey('lookup-details-$id'),
              onPressed: () => showHistoryDetail(context, id, fields),
              icon: const Icon(Icons.open_in_full, size: 16),
              label: Text(bt(context, 'lookup_full_details')),
            ),
          ),
        ],
      ),
    );
  }
}

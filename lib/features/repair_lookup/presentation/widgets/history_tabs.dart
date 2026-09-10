import 'package:flutter/material.dart';
import '../../../pe_system/presentation/widgets/business_widgets.dart';
import '../providers/repair_lookup_provider.dart';
import 'lookup_widgets.dart';

class HistoryTabs extends StatelessWidget {
  const HistoryTabs({super.key, required this.provider});
  final RepairLookupProvider provider;

  @override
  Widget build(BuildContext context) {
    final c = LookupColors(context);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final tab in HistoryTab.values) ...[
            if (tab != HistoryTab.values.first) const SizedBox(width: 8),
            Expanded(
              child: Semantics(
                selected: provider.tab == tab,
                button: true,
                child: OutlinedButton(
                  key: ValueKey('lookup-tab-${tab.name}'),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: provider.tab == tab ? c.accent : c.surface,
                    foregroundColor:
                        provider.tab == tab
                            ? Theme.of(context).colorScheme.onPrimary
                            : c.accent,
                    side: BorderSide(color: c.accent),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 12,
                    ),
                  ),
                  onPressed: () => provider.selectTab(tab),
                  child: Row(
                    children: [
                      Icon(
                        tab == HistoryTab.test
                            ? Icons.delete_outline
                            : Icons.build_outlined,
                        size: 20,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          bt(
                            context,
                            tab == HistoryTab.test
                                ? 'lookup_tests'
                                : 'lookup_repairs',
                          ),
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

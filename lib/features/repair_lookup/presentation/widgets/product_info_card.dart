import 'package:flutter/material.dart';
import '../../domain/entities/repair_lookup_models.dart';
import '../../../pe_system/presentation/widgets/business_widgets.dart';
import '../providers/repair_lookup_provider.dart';
import 'lookup_widgets.dart';

class ProductInfoCard extends StatelessWidget {
  const ProductInfoCard({
    super.key,
    required this.section,
    required this.onRetry,
  });
  final LookupSection<SnInfo> section;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = LookupColors(context);
    final info = section.data;
    final fields = [
      (Icons.account_tree_outlined, 'lookup_wip', info?.wipGroup),
      (Icons.laptop_mac_outlined, 'lookup_product_line', null),
      (Icons.sell_outlined, 'lookup_model', info?.modelName),
      (Icons.error_outline, 'lookup_error_flag', info?.errorFlag),
    ];
    return LookupCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LookupHeading(
            icon: Icons.inventory_2_outlined,
            title: bt(context, 'lookup_product_info'),
          ),
          if (section.status == LookupStatus.success) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Container(
                  key: const ValueKey('lookup-found'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: c.tint,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle, color: c.accent, size: 16),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          bt(context, 'lookup_found'),
                          style: TextStyle(color: c.accent),
                        ),
                      ),
                    ],
                  ),
                ),
                Text('SN: ${info!.sn}', style: TextStyle(color: c.muted)),
              ],
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
                final columns =
                    constraints.maxWidth >= 300 && scale <= 1.3 ? 2 : 1;
                final width =
                    (constraints.maxWidth - (columns - 1) * 12) / columns;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final field in fields)
                      Container(
                        width: width,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: c.background,
                          border: Border.all(color: c.border),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(field.$1, color: c.accent, size: 23),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    bt(context, field.$2),
                                    style: TextStyle(
                                      color: c.muted,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    lookupValue(field.$3),
                                    style: TextStyle(
                                      color: c.text,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ] else
            LookupStatusView(
              status: section.status,
              error: section.error,
              onRetry: onRetry,
            ),
        ],
      ),
    );
  }
}

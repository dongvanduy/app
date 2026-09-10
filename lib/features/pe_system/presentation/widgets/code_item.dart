import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../domain/entities/code_entity.dart';
import '../providers/code_provider.dart';
import 'business_widgets.dart';
import 'dashboard_theme.dart';
import 'dashboard_widgets.dart';

class CodeItem extends StatelessWidget {
  const CodeItem({super.key, required this.code, required this.isFound});
  final CodeEntity code;
  final bool isFound;
  @override
  Widget build(BuildContext context) {
    final recent = context.watch<CodeProvider>().recentlyScannedCodes.contains(
      code.serialNumber,
    );
    final colors = DashboardColors.of(context);
    return DashboardCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  isFound ? Icons.check_circle : Icons.qr_code,
                  color: isFound ? colors.success : colors.accent,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    code.foundOrder == null
                        ? code.serialNumber
                        : '${code.foundOrder}. ${code.serialNumber}',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: recent ? colors.danger : colors.text,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text('${bt(context, 'Model Name')}: ${code.modelName}'),
            Text(
              'Location: ${code.shelfCode} - C${code.columnNumber} L${code.levelNumber} T${code.trayNumber} P${code.positionInTray}',
              style: TextStyle(color: colors.muted),
            ),
            if (isFound || recent) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  if (isFound)
                    Text(
                      bt(context, 'Found'),
                      style: TextStyle(color: colors.success),
                    ),
                  if (recent)
                    Text(
                      bt(context, 'Recently scanned'),
                      style: TextStyle(color: colors.danger),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

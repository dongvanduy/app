import 'package:flutter/material.dart';

import '../../../bga_replace/presentation/bga_replace_screen.dart';
import '../../../inventory_import/presentation/screens/inventory_import_screen.dart';
import '../screens/data_cloud_screen.dart';
import '../screens/pe_system_screen.dart';
import '../screens/retest_screen.dart';
import '../screens/sop_screen.dart';

enum DashboardFeature {
  inventory(
    'inventoryImport',
    'inventoryHomeDescription',
    'inventorySettingsDescription',
    Icons.inventory_2_rounded,
    Color(0xFF00A9ED),
  ),
  bga(
    'bgaReplace',
    'bgaHomeDescription',
    'bgaSettingsDescription',
    Icons.memory_rounded,
    Color(0xFFFF8A17),
  ),
  sop(
    'sop',
    'sopHomeDescription',
    'sopSettingsDescription',
    Icons.picture_as_pdf_rounded,
    Color(0xFFEF3340),
  ),
  search(
    'search',
    'searchHomeDescription',
    'searchSettingsDescription',
    Icons.qr_code_scanner_rounded,
    Color(0xFF6534EB),
  ),
  retest(
    'retest',
    'retestHomeDescription',
    'retestSettingsDescription',
    Icons.directions_run_rounded,
    Color(0xFF435ABC),
  ),
  dataCloud(
    'dataCloud',
    'cloudHomeDescription',
    'cloudSettingsDescription',
    Icons.cloud_rounded,
    Color(0xFF00AE99),
  );

  const DashboardFeature(
    this.titleKey,
    this.homeDescriptionKey,
    this.settingsDescriptionKey,
    this.icon,
    this.color,
  );

  final String titleKey;
  final String homeDescriptionKey;
  final String settingsDescriptionKey;
  final IconData icon;
  final Color color;

  static const homeOrder = [inventory, bga, sop, search, retest, dataCloud];
  static const settingsOrder = [inventory, bga, sop, search, dataCloud, retest];

  Widget buildScreen(BuildContext context) => switch (this) {
    inventory => const InventoryImportScreen(),
    bga => const BgaReplaceScreen(),
    sop => const SopScreen(),
    search => const PESystemScreen(),
    retest => const RetestScreen(),
    dataCloud => const DataCloudScreen(),
  };

  void open(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: RouteSettings(name: '/features/$name'),
        builder: buildScreen,
      ),
    );
  }
}

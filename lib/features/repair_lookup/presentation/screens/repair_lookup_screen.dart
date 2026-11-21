import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/repositories/repair_lookup_repository.dart';
import '../../../pe_system/presentation/screens/qr_scan_page.dart';
import '../../../pe_system/presentation/widgets/business_widgets.dart';
import '../../../pe_system/presentation/widgets/dashboard_theme.dart';
import '../providers/repair_lookup_provider.dart';
import '../widgets/history_cards.dart';
import '../widgets/history_tabs.dart';
import '../widgets/history_timeline.dart';
import '../widgets/lookup_widgets.dart';
import '../widgets/product_info_card.dart';
import '../widgets/sn_search_section.dart';

class RepairLookupScreen extends StatelessWidget {
  const RepairLookupScreen({super.key, required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create:
        (context) => RepairLookupProvider(
          repository: context.read<RepairLookupRepository>(),
        ),
    child: DashboardTheme(child: _RepairLookupBody(onBack: onBack)),
  );
}

class _RepairLookupBody extends StatefulWidget {
  const _RepairLookupBody({required this.onBack});
  final VoidCallback onBack;
  @override
  State<_RepairLookupBody> createState() => _RepairLookupBodyState();
}

class _RepairLookupBodyState extends State<_RepairLookupBody> {
  final _input = TextEditingController();
  final _scroll = ScrollController(keepScrollOffset: false);
  final _offsets = <HistoryTab, double>{};
  late final RepairLookupProvider _provider;
  int _generation = 0;
  HistoryTab _tab = HistoryTab.test;
  int _scrollChange = 0;

  @override
  void initState() {
    super.initState();
    _provider = context.read<RepairLookupProvider>();
    _provider.addListener(_onProviderChanged);
  }

  void _onProviderChanged() {
    if (_generation == _provider.generation && _tab == _provider.tab) return;
    if (_generation != _provider.generation) {
      _offsets.clear();
      _input.value = TextEditingValue(
        text: _provider.sn,
        selection: TextSelection.collapsed(offset: _provider.sn.length),
      );
    } else if (_scroll.hasClients) {
      _offsets[_tab] = _scroll.offset;
    }
    _generation = _provider.generation;
    _tab = _provider.tab;
    final change = ++_scrollChange;
    final offset = _offsets[_tab] ?? 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || change != _scrollChange || !_scroll.hasClients) return;
      _scroll.jumpTo(offset.clamp(0.0, _scroll.position.maxScrollExtent));
    });
  }

  void _scan() {
    FocusScope.of(context).unfocus();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder:
            (_) => QRScanPage(
              onCodeScanned: (value) {
                if (!mounted) return;
                _input.text = value.trim();
                _provider.lookup(value);
              },
            ),
      ),
    );
  }

  @override
  void dispose() {
    _provider.removeListener(_onProviderChanged);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    watchBusinessLanguage(context);
    final provider = context.watch<RepairLookupProvider>();
    final c = LookupColors(context);
    final repair = provider.tab == HistoryTab.repair;
    final title = bt(context, repair ? 'lookup_repairs' : 'lookup_tests');
    final status = repair ? provider.repairs.status : provider.tests.status;
    final error = repair ? provider.repairs.error : provider.tests.error;
    final tests = provider.tests.data?.histories ?? [];
    final repairs = provider.repairs.data?.histories ?? [];
    final count = repair ? repairs.length : tests.length;
    final total =
        repair ? provider.repairs.data?.total : provider.tests.data?.total;
    final countText =
        total == null
            ? ''
            : '${count == total ? '$count' : '$count/$total'} ${bt(context, 'lookup_records')} · ';
    return Material(
      type: MaterialType.transparency,
      child: SafeArea(
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [c.tint, c.background, c.tint],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  IconButton(
                    key: const ValueKey('lookup-back'),
                    tooltip: bt(context, 'lookup_home'),
                    onPressed: widget.onBack,
                    icon: Icon(Icons.arrow_back, color: c.accent),
                  ),
                  Expanded(
                    child: Text(
                      bt(context, 'lookup_title').toUpperCase(),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: c.text,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
              ),
            ),
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1100),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final wide =
                          constraints.maxWidth - 24 >= 720 &&
                          MediaQuery.textScalerOf(context).scale(14) / 14 <=
                              1.3;
                      return CustomScrollView(
                        key: const ValueKey('lookup-scroll'),
                        controller: _scroll,
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        slivers: [
                          SliverPadding(
                            padding: const EdgeInsets.all(12),
                            sliver: SliverToBoxAdapter(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  SnSearchSection(
                                    controller: _input,
                                    onSearch: provider.lookup,
                                    onScan: _scan,
                                  ),
                                  const SizedBox(height: 14),
                                  ProductInfoCard(
                                    section: provider.info,
                                    onRetry: provider.retryInfo,
                                  ),
                                  const SizedBox(height: 14),
                                  HistoryTabs(provider: provider),
                                  const SizedBox(height: 20),
                                  LookupHeading(
                                    icon:
                                        repair
                                            ? Icons.build_outlined
                                            : Icons.delete_outline,
                                    title: title,
                                    subtitle: '${countText}GMT+7',
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (status == LookupStatus.success && count > 0) ...[
                            SliverPadding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              sliver: SliverList(
                                delegate: SliverChildBuilderDelegate((
                                  context,
                                  index,
                                ) {
                                  final first = wide ? index * 2 : index;
                                  HistoryEntryCard card(int entryIndex) =>
                                      HistoryEntryCard(
                                        id:
                                            repair
                                                ? repairs[entryIndex].id
                                                : tests[entryIndex].id,
                                        number: entryIndex + 1,
                                        repair: repair,
                                        fields:
                                            repair
                                                ? repairHistoryFields(
                                                  repairs[entryIndex],
                                                )
                                                : testHistoryFields(
                                                  tests[entryIndex],
                                                ),
                                      );
                                  final id =
                                      repair
                                          ? repairs[first].id
                                          : tests[first].id;
                                  return HistoryTimelineItem(
                                    key: ValueKey(
                                      '${provider.generation}-${provider.tab.name}-$id-$first',
                                    ),
                                    index: first,
                                    wide: wide,
                                    nextChild:
                                        wide && first + 1 < count
                                            ? card(first + 1)
                                            : null,
                                    child: card(first),
                                  );
                                }, childCount: wide ? (count + 1) ~/ 2 : count),
                              ),
                            ),
                            SliverPadding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              sliver: SliverToBoxAdapter(
                                child: HistoryTimelineEnd(wide: wide),
                              ),
                            ),
                          ] else
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  0,
                                  12,
                                  24,
                                ),
                                child: LookupCard(
                                  child: LookupStatusView(
                                    status: status,
                                    error: error,
                                    onRetry:
                                        repair
                                            ? provider.retryRepairs
                                            : provider.retryTests,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

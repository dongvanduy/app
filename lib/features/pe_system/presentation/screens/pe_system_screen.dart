import '../widgets/business_widgets.dart';
import '../widgets/dashboard_theme.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';
import '../providers/code_provider.dart';
import '../widgets/code_item.dart';
import 'qr_scan_page.dart';

class PESystemScreen extends StatelessWidget {
  const PESystemScreen({super.key});
  @override
  Widget build(BuildContext context) =>
      const DashboardTheme(child: _PESystemBody());
}

class _PESystemBody extends StatefulWidget {
  const _PESystemBody();

  @override
  _PESystemScreenState createState() => _PESystemScreenState();
}

class _PESystemScreenState extends State<_PESystemBody> {
  final TextEditingController _scannedCodeController = TextEditingController();
  final FocusNode _scanInputFocus = FocusNode();
  late AudioPlayer _audioPlayer;
  final bool _isKeyboardEnable = false; //Kiem soat trang thai keyboard

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    debugPrint('Initialized _scanInputFocus: ${_scanInputFocus.hashCode}');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final codeProvider = Provider.of<CodeProvider>(context, listen: false);
        codeProvider.fetchSearchList(); //Lay danh sach tu database

        //hien thi ban phim khi moi load vao he thong
        // Future.delayed(const Duration(milliseconds: 100), () {
        //   FocusScope.of(context).requestFocus(_scanInputFocus);
        //   debugPrint('Initial focus requested for _scanInputFocus');
        // });
      }
    });
  }

  Future<void> _handleScanCode(String code, {bool isFromQR = false}) async {
    final provider = Provider.of<CodeProvider>(context, listen: false);
    if (code.isEmpty) {
      if (mounted && !isFromQR) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          //FocusScope.of(context).requestFocus(_scanInputFocus);
          debugPrint('Empty code, cleared TextField, focused _scanInputFocus');
          _scannedCodeController.selection = TextSelection(
            baseOffset: 0,
            extentOffset: _scannedCodeController.text.length,
          );
        });
      }
      return;
    }
    debugPrint('Handling code: $code, isFromQR: $isFromQR');
    final isFound = await provider.handleScanCode(code);
    debugPrint('isFound: $isFound, error: ${provider.error}');

    //Kích hoạt âm thanh
    if (isFound) {
      _audioPlayer.play(AssetSource('sounds/iphone.mp3')).catchError((e) {
        debugPrint('Audio error: $e');
        return null;
      });

      //Kích hoạt rung
      if (await Vibration.hasVibrator()) {
        Vibration.vibrate(duration: 500); //Rung trong 500ms
      } else {
        debugPrint('Device does not support vibration');
      }

      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder:
              (dialogContext) => AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                backgroundColor: Colors.green,
                content: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.check_circle, color: Colors.white),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        bt(context, 'Found!'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
        );

        Future.delayed(const Duration(seconds: 2), () {
          if (mounted && Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
            debugPrint('Dialog closed');
            _scannedCodeController.selection = TextSelection(
              baseOffset: 0,
              extentOffset: _scannedCodeController.text.length,
            );
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                if (!_isKeyboardEnable) {
                  FocusScope.of(context).unfocus(); // Ngăn bàn phím ảo bật
                }
                FocusScope.of(context).requestFocus(_scanInputFocus);
                debugPrint('Focused TextField after dialog');
              }
            });
          }
        });
      }
    } else {
      if (mounted) {
        final errorMessage = provider.error;
        if (errorMessage != null && errorMessage.isNotEmpty) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: Text(errorMessage),
                backgroundColor: Colors.red,
              ),
            );
        }

        _scannedCodeController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _scannedCodeController.text.length,
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            if (!_isKeyboardEnable) {
              FocusScope.of(context).unfocus(); // Ngăn bàn phím ảo bật
            }
            FocusScope.of(context).requestFocus(_scanInputFocus);
            debugPrint('Focused TextField after not found');
          }
        });
      }
    }
  }

  void _openQRScanner() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (context) => QRScanPage(
              onCodeScanned: (code) {
                if (mounted) {
                  _scannedCodeController.text = code;
                  FocusScope.of(context).unfocus();
                  debugPrint('QR code set to TextField: $code');
                  _handleScanCode(code, isFromQR: true);
                }
              },
            ),
      ),
    );
  }

  void _syncSearchLists() async {
    final provider = Provider.of<CodeProvider>(context, listen: false);
    await provider.fetchSearchList();
    debugPrint('Sync search lists triggered');
  }

  @override
  Widget build(BuildContext context) {
    watchBusinessLanguage(context);
    final provider = context.watch<CodeProvider>();
    return BusinessPage(
      title: bt(context, 'search'),
      body: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: provider.fetchSearchList,
              child: CustomScrollView(
                key: const PageStorageKey('search_scroll'),
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.all(16),
                    sliver: SliverToBoxAdapter(
                      child: BusinessSection(
                        title: bt(context, 'Search lists'),
                        icon: Icons.list_alt,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildListSelector(context, provider),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Chip(
                                  avatar: const Icon(
                                    Icons.check_circle_outline,
                                    size: 18,
                                  ),
                                  label: Text(
                                    '${bt(context, 'Found')}: ${provider.foundCount}',
                                  ),
                                ),
                                Chip(
                                  label: Text(
                                    '${bt(context, 'Total')}: ${provider.totalCount}',
                                  ),
                                ),
                                IconButton.filledTonal(
                                  tooltip: bt(context, 'Sync lists'),
                                  onPressed:
                                      provider.isLoading
                                          ? null
                                          : _syncSearchLists,
                                  icon: const Icon(Icons.sync),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (provider.isLoading)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    )
                  else if (provider.codeList.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: BusinessEmptyState(
                        message: bt(context, 'search_empty'),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      sliver: SliverList.builder(
                        itemCount: provider.codeList.length,
                        itemBuilder:
                            (context, index) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: CodeItem(
                                code: provider.codeList[index],
                                isFound: provider.foundCodes.contains(
                                  provider.codeList[index].serialNumber,
                                ),
                              ),
                            ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              key: const ValueKey('search_serial_input'),
              controller: _scannedCodeController,
              focusNode: _scanInputFocus,
              decoration: InputDecoration(
                hintText: bt(context, 'enter_scan_sn'),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  tooltip: bt(context, 'qrScan'),
                  onPressed: _openQRScanner,
                  icon: const Icon(Icons.qr_code_scanner),
                ),
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: _handleScanCode,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListSelector(BuildContext context, CodeProvider provider) {
    if (provider.isLoading) {
      return const Center(child: LinearProgressIndicator(minHeight: 2));
    }
    if (provider.searchLists.isEmpty) {
      return Text(bt(context, 'No search lists'));
    }

    // Dropdown trong "InputDecorator" để đồng bộ style với TextField
    return InputDecorator(
      decoration: InputDecoration(
        labelText: bt(context, 'Search lists'),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        filled: true,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          isExpanded: true,
          itemHeight: null,
          value: provider.selectedSearchListIndex,
          hint: Text(bt(context, 'Choose a list')),
          items:
              provider.searchLists.asMap().entries.map((entry) {
                return DropdownMenuItem<int>(
                  value: entry.key,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(entry.value.listName),
                  ),
                );
              }).toList(),
          onChanged: (value) {
            if (value != null) {
              provider.setSelectedSearchListIndex(value);
            }
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    debugPrint('Disposing _scanInputFocus: ${_scanInputFocus.hashCode}');
    _scannedCodeController.dispose();
    _scanInputFocus.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }
}

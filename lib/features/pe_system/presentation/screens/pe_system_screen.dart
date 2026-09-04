import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';
import '../../../../core/constants/colors.dart';
import '../providers/code_provider.dart';
import '../widgets/code_item.dart';
import 'qr_scan_page.dart';
import '../../../../core/localization/app_localizations.dart';

class PESystemScreen extends StatefulWidget {
  const PESystemScreen({super.key});

  @override
  _PESystemScreenState createState() => _PESystemScreenState();
}

class _PESystemScreenState extends State<PESystemScreen> {
  final TextEditingController _scannedCodeController = TextEditingController();
  final FocusNode _scanInputFocus = FocusNode();
  late AudioPlayer _audioPlayer;
  bool _hasFocus = false;
  bool _isFromQR = false;
  bool _isKeyboardEnable = false;//Kiem soat trang thai keyboard

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    print('Initialized _scanInputFocus: ${_scanInputFocus.hashCode}');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final codeProvider = Provider.of<CodeProvider>(context, listen: false);
        codeProvider.fetchSearchList();//Lay danh sach tu database

        //hien thi ban phim khi moi load vao he thong
        // Future.delayed(const Duration(milliseconds: 100), () {
        //   FocusScope.of(context).requestFocus(_scanInputFocus);
        //   print('Initial focus requested for _scanInputFocus');
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
          print('Empty code, cleared TextField, focused _scanInputFocus');
          _scannedCodeController.selection = TextSelection(
            baseOffset: 0,
            extentOffset: _scannedCodeController.text.length,
          );
        });
      }
      return;
    }
    print('Handling code: $code, isFromQR: $isFromQR');
    final isFound = await provider.handleScanCode(code);
    print('isFound: $isFound, error: ${provider.error}');

    //Kích hoạt âm thanh
    if (isFound) {
      _audioPlayer.play(AssetSource('sounds/iphone.mp3')).catchError((e) {
        print('Audio error: $e');
        return null;

      });

      //Kích hoạt rung
      if(await Vibration.hasVibrator() ?? false) {
        Vibration.vibrate(duration: 500); //Rung trong 500ms
      }else {
        print('Device does not support vibration');
      }

      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            backgroundColor: Colors.green,
            content: const Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Text(
                  'Tìm thấy!',
                  style: TextStyle(
                    //color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        );

        Future.delayed(const Duration(seconds: 2), () {
          if (mounted && Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
            print('Dialog closed');
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
                print('Focused TextField after dialog');
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
            print('Focused TextField after not found');
          }
        });
      }
    }
    _isFromQR = false;
  }

  void _openQRScanner() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => QRScanPage(
          onCodeScanned: (code) {
            if (mounted) {
              _scannedCodeController.text = code;
              _isFromQR = true;
              FocusScope.of(context).unfocus();
              print('QR code set to TextField: $code');
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
    print('Sync search lists triggered');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      // AppBar cố định, màu khớp status bar
      appBar: AppBar(
        elevation: 0,
        backgroundColor: AppColors.background,
        centerTitle: false,
        title: Text(
          AppLocalizations.of(context, 'search')
        ),
      ),

      body: SafeArea(
        top: false, // đã có AppBar xử lý SafeArea phía trên
        child: Column(
          children: [
            // TOP CARD: Dropdown + Sync + Chips
            Card(
              elevation: 2,
              margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Consumer<CodeProvider>(
                  builder: (context, provider, _) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: _buildListSelector(context, provider)),
                            const SizedBox(width: 8),
                            IconButton.filledTonal(
                              tooltip: 'Đồng bộ danh sách',
                              onPressed: _syncSearchLists,
                              icon: const Icon(Icons.sync),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _statChip(
                              context,
                              label: 'Đã tìm',
                              value: '${provider.foundCount}',
                              icon: Icons.check_circle,
                            ),
                            _statChip(
                              context,
                              label: 'Tổng',
                              value: '${provider.totalCount}',
                              icon: Icons.list_alt,
                            )
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),

            // LIST
            Expanded(
              child: Consumer<CodeProvider>(
                builder: (context, provider, _) {
                  if (provider.isLoading) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  return RefreshIndicator.adaptive(
                    onRefresh: () async => _syncSearchLists(),
                    child: CustomScrollView(
                      slivers: [
                        SliverToBoxAdapter(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 250),
                            child: provider.codeList.isNotEmpty
                                ? Padding(
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                              child: Text(
                                'Danh sách (${provider.foundCount}/${provider.totalCount})',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            )
                                : const SizedBox.shrink(),
                          ),
                        ),
                        if (provider.codeList.isNotEmpty)
                          SliverList.builder(
                            itemCount: provider.codeList.length,
                            itemBuilder: (context, index) {
                              final code = provider.codeList[index];
                              return Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                child: Card(
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    side: BorderSide(color: theme.colorScheme.outlineVariant),
                                  ),
                                  child: CodeItem(
                                    code: code,
                                    isFound: provider.foundCodes.contains(code.serialNumber),
                                  ),
                                ),
                              );
                            },
                          )
                        else
                          SliverFillRemaining(
                            hasScrollBody: false,
                            child: Center(
                              child: AnimatedOpacity(
                                duration: const Duration(milliseconds: 250),
                                opacity: 1,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.inbox_outlined,
                                        size: 48, color: theme.colorScheme.outline),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Không có SN nào để hiển thị!\nVui lòng chọn danh sách!',
                                      textAlign: TextAlign.center,
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                        color: theme.colorScheme.outline,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),

            // BOTTOM BAR: Search + QR
            SafeArea(
              top: false,
              child: Card(
                elevation: 3,
                margin: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _scannedCodeController,
                          focusNode: _scanInputFocus,
                          decoration: InputDecoration(
                            hintText: 'Nhập Serial Number…',
                            prefixIcon: const Icon(Icons.search),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                          ),
                          textInputAction: TextInputAction.search,
                          onSubmitted: (value) async {
                            await _handleScanCode(value);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.qr_code_scanner, color: AppColors.textDark),
                        onPressed: _openQRScanner,
                        tooltip: 'Quét mã QR',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }


// ----- Helpers UI -----
  Widget _statChip(BuildContext context,
      {required String label, required String value, required IconData icon}) {
    final theme = Theme.of(context);
    return Chip(
      avatar: Icon(icon, size: 18, color: theme.colorScheme.primary),
      label: Text('$label: $value'),
      side: BorderSide(color: theme.colorScheme.outlineVariant),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  Widget _infoChip(BuildContext context, IconData icon, String text) {
    final theme = Theme.of(context);
    return Chip(
      avatar: Icon(icon, size: 18, color: theme.colorScheme.onSecondaryContainer),
      label: Text(text, overflow: TextOverflow.ellipsis),
      backgroundColor: theme.colorScheme.secondaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  Widget _buildListSelector(BuildContext context, CodeProvider provider) {
    if (provider.isLoading) {
      return const Center(child: LinearProgressIndicator(minHeight: 2));
    }
    if (provider.searchLists.isEmpty) {
      return const Text('Không có danh sách');
    }

    // Dropdown trong "InputDecorator" để đồng bộ style với TextField
    return InputDecorator(
      decoration: InputDecoration(
        labelText: 'Danh sách',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        filled: true,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          isExpanded: true,
          value: provider.selectedSearchListIndex,
          hint: const Text('Chọn danh sách'),
          items: provider.searchLists.asMap().entries.map((entry) {
            return DropdownMenuItem<int>(
              value: entry.key,
              child: Text(entry.value.listName, overflow: TextOverflow.ellipsis),
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
    print('Disposing _scanInputFocus: ${_scanInputFocus.hashCode}');
    _scannedCodeController.dispose();
    _scanInputFocus.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }
}
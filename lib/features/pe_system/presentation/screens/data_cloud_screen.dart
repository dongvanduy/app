import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/dataCloud_provider.dart';
import '../widgets/data_cloud_item.dart';
import '../../../../core/localization/app_localizations.dart';

class DataCloudScreen extends StatefulWidget {
  const DataCloudScreen({super.key});

  @override
  State<DataCloudScreen> createState() => _DataCloudScreenState();
}

class _DataCloudScreenState extends State<DataCloudScreen> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _folderNameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Gọi API khi màn hình được mở
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<DatacloudProvider>(context, listen: false).fetchDataCloud();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _folderNameController.dispose();
    super.dispose();
  }

  void _showContextMenu(
    BuildContext context,
    DataCloudItem item,
    Offset position,
  ) {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    showMenu(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 100, 100),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          value: 'download',
          child: ListTile(
            leading: const Icon(Icons.download),
            title: Text(AppLocalizations.of(context, 'download')),
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: ListTile(
            leading: const Icon(Icons.delete),
            title: Text(AppLocalizations.of(context, 'delete')),
          ),
        ),
      ],
    ).then((value) {
      if (value != null) {
        _handleContextAction(value, item);
      }
    });
  }

  void _handleContextAction(String action, DataCloudItem item) async {
    final provider = Provider.of<DatacloudProvider>(context, listen: false);
    if (action == 'download') {
      final download = await provider.downloadItem(item);
      if (!mounted) return;
      if (download == null) {
        _showMessage(provider.dataCloudError ?? 'Download failed.');
        return;
      }

      try {
        final mobilePlatform = Platform.isAndroid || Platform.isIOS;
        final outputPath = await FilePicker.platform.saveFile(
          dialogTitle: AppLocalizations.of(context, 'download'),
          fileName: download.fileName,
          bytes: mobilePlatform ? download.bytes : null,
        );
        if (outputPath == null || !mounted) return;
        if (!mobilePlatform) {
          await File(outputPath).writeAsBytes(download.bytes, flush: true);
        }
        if (mounted) {
          _showMessage('Saved ${download.fileName}.');
        }
      } catch (error) {
        if (mounted) {
          _showMessage('Unable to save file: $error');
        }
      }
    } else if (action == 'delete') {
      showDialog(
        context: context,
        builder:
            (context) => AlertDialog(
              title: Text(AppLocalizations.of(context, 'confirmDelete')),
              content: const Text('This action cannot be undone!'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(AppLocalizations.of(context, 'cancel')),
                ),
                TextButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    final deleted = await provider.deleteItem(
                      item.path,
                      item.type,
                    );
                    if (!deleted && mounted) {
                      _showMessage(provider.dataCloudError ?? 'Delete failed.');
                    }
                  },
                  child: Text(AppLocalizations.of(context, 'confirmDelete')),
                ),
              ],
            ),
      );
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _pickFiles({bool isFolder = false}) async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.any,
      allowCompression: false,
    );
    if (result == null || !mounted) return;

    final files = result.paths.whereType<String>().map(File.new).toList();
    final provider = context.read<DatacloudProvider>();
    final uploaded = await provider.uploadFiles(files, isFolder: isFolder);
    if (!uploaded && mounted) {
      _showMessage(provider.dataCloudError ?? 'Upload failed.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DatacloudProvider>(
      builder: (context, provider, child) {
        return Scaffold(
          appBar: AppBar(
            title: Text(AppLocalizations.of(context, 'dataCloud')),
            //backgroundColor: const Color(0xFF0055A5),
            elevation: 0,
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh',
                onPressed:
                    provider.isLoadingDataCloud
                        ? null
                        : () => provider.fetchDataCloud(addToHistory: false),
              ),
              IconButton(
                icon: const Icon(Icons.search),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder:
                        (context) => AlertDialog(
                          title: Text(AppLocalizations.of(context, 'search')),
                          content: TextField(
                            controller: _searchController,
                            decoration: InputDecoration(
                              labelText: AppLocalizations.of(
                                context,
                                'enterKeyword',
                              ),
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () {
                                provider.searchDataCloud(
                                  _searchController.text,
                                );
                                Navigator.pop(context);
                              },
                              child: Text(
                                AppLocalizations.of(context, 'search'),
                              ),
                            ),
                          ],
                        ),
                  );
                },
              ),
            ],
          ),
          body: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        provider.dataCloudResponse?.currentPath ??
                            provider.currentPath,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: provider.canGoBack ? provider.goBack : null,
                      tooltip: AppLocalizations.of(context, 'back'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child:
                      provider.isLoadingDataCloud
                          ? const Center(child: CircularProgressIndicator())
                          : provider.dataCloudError != null
                          ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  provider.dataCloudError!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: Colors.red),
                                ),
                                const SizedBox(height: 12),
                                FilledButton.icon(
                                  onPressed:
                                      () => provider.fetchDataCloud(
                                        addToHistory: false,
                                      ),
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('Retry'),
                                ),
                              ],
                            ),
                          )
                          : provider.dataCloudResponse == null ||
                              provider.dataCloudResponse!.items.isEmpty
                          ? Center(
                            child: Text(
                              AppLocalizations.of(context, 'noItemsFound'),
                            ),
                          )
                          : ListView.builder(
                            itemCount: provider.dataCloudResponse!.items.length,
                            itemBuilder: (context, index) {
                              final item =
                                  provider.dataCloudResponse!.items[index];
                              return GestureDetector(
                                onSecondaryTapDown:
                                    (details) => _showContextMenu(
                                      context,
                                      item,
                                      details.globalPosition,
                                    ),
                                onLongPressStart:
                                    (details) => _showContextMenu(
                                      context,
                                      item,
                                      details.globalPosition,
                                    ),
                                child: Card(
                                  elevation: 2,
                                  margin: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.all(16),
                                    leading: Icon(
                                      item.isFolder
                                          ? Icons.folder
                                          : Icons.insert_drive_file,
                                      color:
                                          item.isFolder
                                              ? Colors.orange
                                              : Colors.blue,
                                    ),
                                    title: Text(
                                      item.name,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    subtitle: Text(
                                      item.path,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    trailing: PopupMenuButton<String>(
                                      tooltip: 'Actions',
                                      onSelected:
                                          (action) => _handleContextAction(
                                            action,
                                            item,
                                          ),
                                      itemBuilder:
                                          (context) => [
                                            PopupMenuItem(
                                              value: 'download',
                                              child: Row(
                                                children: [
                                                  const Icon(Icons.download),
                                                  const SizedBox(width: 12),
                                                  Text(
                                                    AppLocalizations.of(
                                                      context,
                                                      'download',
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            PopupMenuItem(
                                              value: 'delete',
                                              child: Row(
                                                children: [
                                                  const Icon(Icons.delete),
                                                  const SizedBox(width: 12),
                                                  Text(
                                                    AppLocalizations.of(
                                                      context,
                                                      'delete',
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                    ),
                                    onTap: () {
                                      if (item.isFolder) {
                                        provider.fetchDataCloud(
                                          path: item.path,
                                        );
                                      } else {
                                        _handleContextAction('download', item);
                                      }
                                    },
                                  ),
                                ),
                              );
                            },
                          ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    ElevatedButton.icon(
                      onPressed:
                          provider.isLoadingDataCloud
                              ? null
                              : () => _pickFiles(),
                      icon: const Icon(Icons.upload_file),
                      label: Text(AppLocalizations.of(context, 'uploadFile')),
                    ),
                    ElevatedButton.icon(
                      onPressed:
                          provider.isLoadingDataCloud
                              ? null
                              : () {
                                showDialog(
                                  context: context,
                                  builder:
                                      (dialogContext) => AlertDialog(
                                        title: Text(
                                          AppLocalizations.of(
                                            dialogContext,
                                            'newFolder',
                                          ),
                                        ),
                                        content: TextField(
                                          controller: _folderNameController,
                                          decoration: const InputDecoration(
                                            labelText: 'Folder Name',
                                          ),
                                          autofocus: true,
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () async {
                                              final folderName =
                                                  _folderNameController.text;
                                              Navigator.pop(dialogContext);
                                              _folderNameController.clear();
                                              final created = await provider
                                                  .createFolder(folderName);
                                              if (!created && mounted) {
                                                _showMessage(
                                                  provider.dataCloudError ??
                                                      'Unable to create folder.',
                                                );
                                              }
                                            },
                                            child: Text(
                                              AppLocalizations.of(
                                                dialogContext,
                                                'create',
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                );
                              },
                      icon: const Icon(Icons.create_new_folder),
                      label: Text(AppLocalizations.of(context, 'newFolder')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

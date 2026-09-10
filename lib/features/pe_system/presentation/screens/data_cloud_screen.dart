import '../widgets/business_widgets.dart';
import '../widgets/dashboard_theme.dart';
import '../widgets/dashboard_widgets.dart';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/dataCloud_provider.dart';
import '../providers/language_provider.dart';
import '../widgets/data_cloud_item.dart';
import '../../../../core/localization/language_converter.dart';

class DataCloudScreen extends StatelessWidget {
  const DataCloudScreen({super.key});
  @override
  Widget build(BuildContext context) =>
      const DashboardTheme(child: _DataCloudBody());
}

class _DataCloudBody extends StatefulWidget {
  const _DataCloudBody();

  @override
  State<_DataCloudBody> createState() => _DataCloudScreenState();
}

class _DataCloudScreenState extends State<_DataCloudBody> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _folderNameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Gọi API khi màn hình được mở
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
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
      items: _itemActions(context, item),
    ).then((value) {
      if (value != null && mounted) {
        _handleContextAction(value, item);
      }
    });
  }

  void _handleContextAction(String action, DataCloudItem item) async {
    final provider = Provider.of<DatacloudProvider>(context, listen: false);
    if (provider.isLoadingDataCloud) return;
    if (action == 'rename') {
      final newName = await showDialog<String>(
        context: context,
        builder: (_) => _RenameDialog(name: item.name),
      );
      if (!mounted || newName == null) return;
      final renamed = await provider.renameItem(item, newName);
      if (!renamed && mounted) {
        _showMessage(provider.dataCloudError ?? bt(context, 'rename_failed'));
      }
      return;
    }
    if (action == 'download') {
      final download = await provider.downloadItem(item);
      if (!mounted) return;
      if (download == null) {
        _showMessage(provider.dataCloudError ?? bt(context, 'download_failed'));
        return;
      }

      try {
        final mobilePlatform = Platform.isAndroid || Platform.isIOS;
        final outputPath = await FilePicker.platform.saveFile(
          dialogTitle: _actionLabel(context, 'download'),
          fileName: download.fileName,
          bytes: mobilePlatform ? download.bytes : null,
        );
        if (outputPath == null || !mounted) return;
        if (!mobilePlatform) {
          await File(outputPath).writeAsBytes(download.bytes, flush: true);
        }
        if (mounted) {
          _showMessage('${bt(context, 'Saved')}: ${download.fileName}');
        }
      } catch (error) {
        if (mounted) {
          _showMessage('${bt(context, 'save_failed')}: $error');
        }
      }
    } else if (action == 'delete') {
      showDialog(
        context: context,
        builder:
            (context) => AlertDialog(
              title: Text(bt(context, 'confirmDelete')),
              content: Text(
                '${bt(context, 'move_to_recycle_bin')}\n${item.name}',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(bt(context, 'cancel')),
                ),
                TextButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    final deleted = await provider.deleteItem(
                      item.path,
                      item.type,
                      itemScope: item.scope,
                    );
                    if (!deleted && mounted) {
                      _showMessage(
                        provider.dataCloudError ??
                            bt(this.context, 'delete_failed'),
                      );
                    }
                  },
                  child: Text(bt(context, 'confirmDelete')),
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

  List<PopupMenuEntry<String>> _itemActions(
    BuildContext context,
    DataCloudItem item,
  ) {
    final provider = context.read<DatacloudProvider>();
    return [
      PopupMenuItem(
        value: 'download',
        child: ListTile(
          leading: const Icon(Icons.download),
          title: Text(_actionLabel(context, 'download')),
        ),
      ),
      if (provider.allowRename && item.scope.allowRename)
        PopupMenuItem(
          value: 'rename',
          child: ListTile(
            leading: const Icon(Icons.drive_file_rename_outline),
            title: Text(bt(context, 'Rename')),
          ),
        ),
      if (provider.allowDelete && item.scope.allowDelete)
        PopupMenuItem(
          value: 'delete',
          child: ListTile(
            leading: const Icon(Icons.delete),
            title: Text(_actionLabel(context, 'delete')),
          ),
        ),
    ];
  }

  String _actionLabel(BuildContext context, String key) {
    return LanguageConverter.translate(
      key,
      context.read<LanguageProvider>().locale,
    );
  }

  Future<void> _pickFolder() async {
    final provider = context.read<DatacloudProvider>();
    final selectedScope = provider.scope;
    final selectedPath = provider.currentPath;
    try {
      final path = await FilePicker.platform.getDirectoryPath();
      if (path == null || !mounted) return;
      final directory = Directory(path).absolute;
      final files = <File>[];
      final relativePaths = <String>[];
      final parent = directory.parent.path;
      await for (final entry in directory.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entry is File) {
          files.add(entry);
          relativePaths.add(
            entry.path
                .substring(parent.length)
                .replaceAll(RegExp(r'^[/\\]+'), ''),
          );
        }
      }
      if (!mounted ||
          provider.scope != selectedScope ||
          provider.currentPath != selectedPath) {
        return;
      }
      final uploaded = await provider.uploadFiles(
        files,
        isFolder: true,
        relativePaths: relativePaths,
      );
      if (!uploaded && mounted) {
        _showMessage(provider.dataCloudError ?? bt(context, 'upload_failed'));
      }
    } catch (error) {
      if (mounted) _showMessage('${bt(context, 'upload_failed')}: $error');
    }
  }

  void _pickFiles({bool isFolder = false}) async {
    final provider = context.read<DatacloudProvider>();
    final selectedScope = provider.scope;
    final selectedPath = provider.currentPath;
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.any,
      allowCompression: false,
    );
    if (result == null || !mounted) return;

    final files = result.paths.whereType<String>().map(File.new).toList();
    if (provider.scope != selectedScope ||
        provider.currentPath != selectedPath) {
      return;
    }
    final uploaded = await provider.uploadFiles(files, isFolder: isFolder);
    if (!uploaded && mounted) {
      _showMessage(provider.dataCloudError ?? bt(context, 'upload_failed'));
    }
  }

  void _search(DatacloudProvider provider) {
    showDialog<void>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: Text(bt(dialogContext, 'search')),
            content: TextField(
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: bt(dialogContext, 'enterKeyword'),
              ),
              onSubmitted: (value) {
                provider.searchDataCloud(value);
                Navigator.pop(dialogContext);
              },
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(bt(dialogContext, 'cancel')),
              ),
              FilledButton(
                onPressed: () {
                  provider.searchDataCloud(_searchController.text);
                  Navigator.pop(dialogContext);
                },
                child: Text(bt(dialogContext, 'search')),
              ),
            ],
          ),
    );
  }

  void _createFolder(DatacloudProvider provider) {
    _folderNameController.clear();
    showDialog<void>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: Text(bt(dialogContext, 'newFolder')),
            content: TextField(
              controller: _folderNameController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: bt(dialogContext, 'Folder Name'),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(bt(dialogContext, 'cancel')),
              ),
              FilledButton(
                onPressed: () async {
                  final name = _folderNameController.text.trim();
                  if (name.isEmpty) return;
                  Navigator.pop(dialogContext);
                  final created = await provider.createFolder(name);
                  if (!created && mounted) {
                    _showMessage(
                      provider.dataCloudError ??
                          bt(context, 'create_folder_failed'),
                    );
                  }
                },
                child: Text(bt(dialogContext, 'create')),
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    watchBusinessLanguage(context);
    final provider = context.watch<DatacloudProvider>();
    final items = provider.dataCloudResponse?.items ?? <DataCloudItem>[];
    return BusinessPage(
      title: bt(context, 'dataCloud'),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: bt(context, 'Refresh'),
          onPressed:
              provider.isLoadingDataCloud
                  ? null
                  : () => provider.fetchDataCloud(addToHistory: false),
        ),
        IconButton(
          icon: const Icon(Icons.search),
          tooltip: bt(context, 'search'),
          onPressed: () => _search(provider),
        ),
      ],
      body: CustomScrollView(
        key: const PageStorageKey('data_cloud_scroll'),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverToBoxAdapter(
              child: BusinessSection(
                title: bt(context, 'Storage'),
                icon: Icons.cloud_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<DataCloudScope>(
                      key: ValueKey(provider.scope),
                      initialValue: provider.scope,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: bt(context, 'Scope'),
                      ),
                      items:
                          DataCloudScope.values
                              .map(
                                (scope) => DropdownMenuItem(
                                  value: scope,
                                  child: Text(bt(context, scope.label)),
                                ),
                              )
                              .toList(),
                      onChanged:
                          provider.isLoadingDataCloud
                              ? null
                              : (scope) {
                                if (scope == null) return;
                                _searchController.clear();
                                provider.changeScope(scope);
                              },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back),
                          tooltip: bt(context, 'back'),
                          onPressed:
                              provider.canGoBack ? provider.goBack : null,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            provider.currentPath.isEmpty
                                ? bt(context, provider.scope.label)
                                : '${bt(context, provider.scope.label)} / ${provider.currentPath}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed:
                              provider.isLoadingDataCloud
                                  ? null
                                  : () => _pickFiles(),
                          icon: const Icon(Icons.upload_file),
                          label: Text(bt(context, 'uploadFile')),
                        ),
                        OutlinedButton.icon(
                          onPressed:
                              provider.isLoadingDataCloud ? null : _pickFolder,
                          icon: const Icon(Icons.drive_folder_upload_outlined),
                          label: Text(bt(context, 'Upload folder')),
                        ),
                        OutlinedButton.icon(
                          onPressed:
                              provider.isLoadingDataCloud
                                  ? null
                                  : () => _createFolder(provider),
                          icon: const Icon(Icons.create_new_folder_outlined),
                          label: Text(bt(context, 'newFolder')),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (provider.isLoadingDataCloud)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
            )
          else if (provider.dataCloudError != null)
            SliverFillRemaining(
              hasScrollBody: false,
              child: BusinessEmptyState(
                message: provider.dataCloudError!,
                error: true,
                onRetry: () => provider.fetchDataCloud(addToHistory: false),
              ),
            )
          else if (items.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: BusinessEmptyState(message: bt(context, 'noItemsFound')),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              sliver: SliverList.builder(
                itemCount: items.length,
                itemBuilder:
                    (context, index) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _fileRow(provider, items[index]),
                    ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _fileRow(DatacloudProvider provider, DataCloudItem item) {
    final pdf = item.name.toLowerCase().endsWith('.pdf');
    final colors = DashboardColors.of(context);
    final color =
        item.isFolder
            ? colors.warning
            : pdf
            ? colors.danger
            : colors.accent;
    return GestureDetector(
      onSecondaryTapDown:
          (details) => _showContextMenu(context, item, details.globalPosition),
      onLongPressStart:
          (details) => _showContextMenu(context, item, details.globalPosition),
      child: DashboardCard(
        onTap: () {
          if (provider.isLoadingDataCloud) return;
          if (item.isFolder) {
            provider.fetchDataCloud(path: item.path);
          } else {
            _handleContextAction('download', item);
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              DashboardIcon(
                icon:
                    item.isFolder
                        ? Icons.folder
                        : pdf
                        ? Icons.picture_as_pdf
                        : Icons.insert_drive_file,
                color: color,
                size: 44,
                iconSize: 23,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.path,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: colors.muted, fontSize: 13),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: bt(context, 'Actions'),
                onSelected: (action) => _handleContextAction(action, item),
                itemBuilder: (context) => _itemActions(context, item),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.name});
  final String name;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _controller = TextEditingController(text: widget.name);
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(bt(context, 'Rename')),
    content: TextField(
      controller: _controller,
      autofocus: true,
      onSubmitted: (value) => Navigator.pop(context, value),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(bt(context, 'cancel')),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context, _controller.text),
        child: Text(bt(context, 'Rename')),
      ),
    ],
  );
}

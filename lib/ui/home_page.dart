import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_paths.dart';
import '../core/app_settings.dart';
import '../core/download_manager.dart';
import '../core/engine_controller.dart';
import '../core/models/download_task.dart';
import '../core/platform_launcher.dart';
import '../core/tracker_service.dart';
import 'add_download_dialog.dart';
import 'settings_page.dart';
import 'widgets/engine_panel.dart';
import 'widgets/status_bar.dart';
import 'widgets/task_tile.dart';

/// Main screen with the download list, engine bootstrap panel and actions.
class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.engine,
    required this.downloads,
    required this.paths,
    required this.settings,
    required this.onSettingsChanged,
    this.addDownloadRequests,
    this.trackerService,
  });

  final EngineController engine;
  final DownloadManager downloads;
  final AppPaths paths;
  final AppSettings settings;
  final Future<void> Function(AppSettings) onSettingsChanged;

  /// Tray "添加下载" requests; incrementing the notifier opens the add dialog.
  final ValueListenable<int>? addDownloadRequests;

  /// Shared tracker state shown in the settings page.
  final TrackerService? trackerService;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _addDialogOpen = false;

  @override
  void initState() {
    super.initState();
    widget.addDownloadRequests?.addListener(_handleAddDownloadRequest);
  }

  @override
  void dispose() {
    widget.addDownloadRequests?.removeListener(_handleAddDownloadRequest);
    super.dispose();
  }

  void _handleAddDownloadRequest() {
    if (!mounted) {
      return;
    }
    if (!widget.engine.isReady) {
      _showMessage('aria2 引擎尚未就绪，请稍后再试');
      return;
    }
    unawaited(_addDownloads());
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        widget.engine,
        widget.downloads,
      ]),
      builder: (context, _) {
        final engine = widget.engine;
        final downloads = widget.downloads;
        final tasks = downloads.tasks;
        final ready = engine.isReady;
        return Scaffold(
          appBar: AppBar(
            titleSpacing: 20,
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text('下载列表', style: Theme.of(context).textTheme.titleSmall),
                if (tasks.isNotEmpty) ...<Widget>[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${tasks.length}',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                ],
              ],
            ),
            actions: <Widget>[
              IconButton(
                tooltip: '打开下载目录',
                onPressed: () =>
                    PlatformLauncher.openDirectory(widget.settings.downloadDir),
                icon: const Icon(Icons.folder_open),
              ),
              IconButton(
                tooltip: '全部暂停',
                onPressed: ready && tasks.any((task) => task.canPause)
                    ? () => _runAction(widget.downloads.pauseAll, '已暂停全部任务')
                    : null,
                icon: const Icon(Icons.pause),
              ),
              IconButton(
                tooltip: '全部继续',
                onPressed: ready && tasks.any((task) => task.canResume)
                    ? () => _runAction(widget.downloads.resumeAll, '已继续全部任务')
                    : null,
                icon: const Icon(Icons.play_arrow),
              ),
              IconButton(
                tooltip: '清除已结束记录',
                onPressed: ready && tasks.any((task) => task.isComplete)
                    ? () => _runAction(
                        widget.downloads.clearCompleted,
                        '已清除已结束记录',
                      )
                    : null,
                icon: const Icon(Icons.cleaning_services_outlined),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: '设置',
                onPressed: _openSettings,
                icon: const Icon(Icons.settings_outlined),
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: ready
              ? _buildReadyBody(tasks)
              : EnginePanel(
                  engine: engine,
                  paths: widget.paths,
                  onRetry: () => engine.start(),
                  onReinstall: () => engine.reinstall(),
                  onOpenSettings: _openSettings,
                ),
          bottomNavigationBar: StatusBar(engine: engine, downloads: downloads),
          floatingActionButton: ready
              ? FloatingActionButton.extended(
                  onPressed: _addDownloads,
                  icon: const Icon(Icons.add),
                  label: const Text('新建下载'),
                )
              : null,
        );
      },
    );
  }

  Widget _buildReadyBody(List<DownloadTask> tasks) {
    final error = widget.downloads.lastError;
    return Column(
      children: <Widget>[
        if (error != null) _errorBanner(error),
        Expanded(
          child: tasks.isEmpty
              ? _emptyState()
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 96),
                  itemCount: tasks.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final task = tasks[index];
                    return TaskTile(
                      key: ValueKey<String>(task.gid),
                      task: task,
                      onAction: (action) => _handleTaskAction(task, action),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _errorBanner(String message) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.warning_amber_rounded, color: scheme.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
          TextButton(
            onPressed: widget.downloads.refresh,
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.inbox_outlined,
            size: 64,
            color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 14),
          Text('还没有下载任务', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            '点击“新建下载”，添加 HTTP/HTTPS/FTP/磁力链接或种子文件。',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: _addDownloads,
            icon: const Icon(Icons.add),
            label: const Text('新建下载'),
          ),
        ],
      ),
    );
  }

  Future<void> _addDownloads() async {
    if (_addDialogOpen) {
      return;
    }
    _addDialogOpen = true;
    AddDownloadRequest? request;
    try {
      request = await showDialog<AddDownloadRequest>(
        context: context,
        builder: (context) =>
            AddDownloadDialog(defaultDir: widget.settings.downloadDir),
      );
    } finally {
      _addDialogOpen = false;
    }
    if (request == null || !mounted) {
      return;
    }
    final dir = request.dir?.trim().isEmpty ?? true
        ? widget.settings.downloadDir
        : request.dir!.trim();
    final urls = <String>[];
    final files = <String>[];
    for (final input in request.inputs) {
      if (_looksLikeSupportedUri(input)) {
        urls.add(input);
      } else if (File(input).existsSync()) {
        files.add(input);
      } else {
        _showMessage('无法识别的链接或文件：$input');
        return;
      }
    }
    try {
      final gids = <String>[];
      if (urls.isNotEmpty) {
        gids.addAll(
          await widget.downloads.addUris(
            urls: urls,
            dir: dir,
            out: urls.length == 1 ? request.out : null,
          ),
        );
      }
      for (final file in files) {
        gids.addAll(await widget.downloads.addLocalFile(file, dir: dir));
      }
      if (mounted) {
        _showMessage('已添加 ${gids.length} 个任务');
      }
    } on Object catch (error) {
      if (mounted) {
        _showMessage('添加失败：$error');
      }
    }
  }

  bool _looksLikeSupportedUri(String input) {
    final uri = Uri.tryParse(input);
    if (uri == null) {
      return false;
    }
    final scheme = uri.scheme.toLowerCase();
    return scheme == 'http' ||
        scheme == 'https' ||
        scheme == 'ftp' ||
        scheme == 'sftp' ||
        scheme == 'magnet';
  }

  Future<void> _handleTaskAction(DownloadTask task, TaskAction action) async {
    try {
      if (action == TaskAction.togglePause) {
        if (task.canResume) {
          await widget.downloads.resume(task);
        } else {
          await widget.downloads.pause(task);
        }
      } else if (action == TaskAction.openFolder) {
        await PlatformLauncher.reveal(task.contentPath);
      } else if (action == TaskAction.openFile) {
        await PlatformLauncher.openFile(task.contentPath);
      } else if (action == TaskAction.copyLink) {
        final uri = task.firstUri;
        if (uri != null) {
          await Clipboard.setData(ClipboardData(text: uri));
          if (mounted) {
            _showMessage('已复制下载链接');
          }
        }
      } else if (action == TaskAction.remove) {
        await widget.downloads.remove(task);
        if (mounted) {
          _showMessage('已移除任务');
        }
      } else if (action == TaskAction.removeWithFiles) {
        final confirmed = await _confirmDeleteFiles(task);
        if (!confirmed) {
          return;
        }
        final deleted = await widget.downloads.remove(task, deleteFiles: true);
        if (mounted) {
          _showMessage('已移除任务并删除 $deleted 个文件');
        }
      }
    } on Object catch (error) {
      if (mounted) {
        _showMessage('操作失败：$error');
      }
    }
  }

  Future<bool> _confirmDeleteFiles(DownloadTask task) async {
    final scheme = Theme.of(context).colorScheme;
    final fileCount = task.files.where((file) => file.path.isNotEmpty).length;
    final message = fileCount > 1
        ? '将删除“${task.displayName}”的全部 $fileCount 个文件，此操作无法撤销。'
        : '将删除“${task.displayName}”的下载文件，此操作无法撤销。';
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('移除并删除文件？'),
        content: Text(message),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: scheme.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _runAction(
    Future<void> Function() action,
    String successMessage,
  ) async {
    try {
      await action();
      if (mounted) {
        _showMessage(successMessage);
      }
    } on Object catch (error) {
      if (mounted) {
        _showMessage('操作失败：$error');
      }
    }
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => SettingsPage(
          initial: widget.settings,
          paths: widget.paths,
          engine: widget.engine,
          trackerService: widget.trackerService,
          onSaved: widget.onSettingsChanged,
        ),
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

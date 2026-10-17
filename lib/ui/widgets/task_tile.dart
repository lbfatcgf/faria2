import 'package:flutter/material.dart';

import '../../core/formatting.dart';
import '../../core/models/download_task.dart';

/// Actions offered by the task context menu.
enum TaskAction {
  togglePause,
  openFolder,
  openFile,
  copyLink,
  remove,
  removeWithFiles,
}

/// One download row.
class TaskTile extends StatelessWidget {
  const TaskTile({super.key, required this.task, required this.onAction});

  final DownloadTask task;
  final ValueChanged<TaskAction> onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = _accentColor(scheme);

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      color: scheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(_statusIcon, size: 20, color: accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        task.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _subtitle(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: task.state == TaskState.error
                              ? scheme.error
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<TaskAction>(
                  tooltip: '更多操作',
                  icon: const Icon(Icons.more_vert, size: 20),
                  onSelected: onAction,
                  itemBuilder: (context) => _menuItems(context),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: task.isMetadataOnly ? null : task.progress,
                  minHeight: 6,
                  backgroundColor: scheme.surfaceContainerHighest,
                  color: accent,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(
                children: <Widget>[
                  Text(
                    task.statusLabel,
                    style: theme.textTheme.labelSmall?.copyWith(color: accent),
                  ),
                  const Spacer(),
                  Flexible(
                    child: Text(
                      _metrics(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData get _statusIcon {
    return switch (task.state) {
      TaskState.active => Icons.downloading,
      TaskState.waiting => Icons.schedule,
      TaskState.paused => Icons.pause_circle_outline,
      TaskState.complete => Icons.check_circle_outline,
      TaskState.error => Icons.error_outline,
      TaskState.removed => Icons.remove_circle_outline,
      TaskState.unknown => Icons.help_outline,
    };
  }

  Color _accentColor(ColorScheme scheme) {
    return switch (task.state) {
      TaskState.active => scheme.primary,
      TaskState.waiting => scheme.tertiary,
      TaskState.paused => scheme.outline,
      TaskState.complete => const Color(0xFF2E9E63),
      TaskState.error => scheme.error,
      _ => scheme.outline,
    };
  }

  String _subtitle() {
    if (task.isMetadataOnly) {
      return '正在解析磁力链接，获取文件列表…';
    }
    if (task.state == TaskState.error) {
      final message = task.errorMessage?.trim();
      return message == null || message.isEmpty
          ? '下载失败（错误码 ${task.errorCode ?? '未知'}）'
          : message;
    }
    return task.dir;
  }

  String _metrics() {
    if (task.state == TaskState.error) {
      return formatPercent(task.progress);
    }
    if (task.state == TaskState.complete) {
      return '已完成 · ${formatBytes(task.totalLength)}';
    }
    final parts = <String>[
      '${formatBytes(task.completedLength)} / ${formatBytes(task.totalLength)}',
      if (task.isActive) formatSpeed(task.downloadSpeed),
      if (task.etaSeconds != null && task.isActive)
        '剩余 ${formatEta(task.etaSeconds!)}',
      if (task.isActive && task.connections > 0) '${task.connections} 连接',
    ];
    return parts.join(' · ');
  }

  List<PopupMenuEntry<TaskAction>> _menuItems(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasFile = task.files.isNotEmpty && !task.isMultiFile;
    return <PopupMenuEntry<TaskAction>>[
      if (task.canPause || task.canResume)
        PopupMenuItem<TaskAction>(
          value: TaskAction.togglePause,
          child: _menuTile(
            task.canResume ? Icons.play_arrow : Icons.pause,
            task.canResume ? '继续' : '暂停',
          ),
        ),
      PopupMenuItem<TaskAction>(
        value: TaskAction.openFolder,
        child: _menuTile(Icons.folder_open, '打开所在文件夹'),
      ),
      if (hasFile)
        PopupMenuItem<TaskAction>(
          value: TaskAction.openFile,
          enabled: task.isComplete,
          child: _menuTile(Icons.open_in_new, '打开文件'),
        ),
      if (task.firstUri != null)
        PopupMenuItem<TaskAction>(
          value: TaskAction.copyLink,
          child: _menuTile(Icons.copy, '复制下载链接'),
        ),
      const PopupMenuDivider(),
      PopupMenuItem<TaskAction>(
        value: TaskAction.remove,
        child: _menuTile(Icons.delete_outline, '移除任务'),
      ),
      PopupMenuItem<TaskAction>(
        value: TaskAction.removeWithFiles,
        child: _menuTile(Icons.delete_forever, '移除并删除文件', color: scheme.error),
      ),
    ];
  }

  Widget _menuTile(IconData icon, String label, {Color? color}) {
    return Row(
      children: <Widget>[
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(color: color)),
      ],
    );
  }
}

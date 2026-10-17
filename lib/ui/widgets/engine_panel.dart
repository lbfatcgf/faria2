import 'package:flutter/material.dart';

import '../../core/app_paths.dart';
import '../../core/engine_controller.dart';
import '../../core/platform_launcher.dart';

/// Shown while the aria2 engine is being located, installed, started or when
/// starting failed.
class EnginePanel extends StatelessWidget {
  const EnginePanel({
    super.key,
    required this.engine,
    required this.paths,
    required this.onRetry,
    required this.onReinstall,
    required this.onOpenSettings,
  });

  final EngineController engine;
  final AppPaths paths;
  final VoidCallback onRetry;
  final VoidCallback onReinstall;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final failed = engine.phase == EnginePhase.failed;
    final progress = engine.progress;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(color: scheme.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: (failed ? scheme.error : scheme.primary)
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          failed
                              ? Icons.error_outline
                              : Icons.cloud_download_outlined,
                          color: failed ? scheme.error : scheme.primary,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              failed ? '下载引擎启动失败' : '正在准备下载引擎',
                              style: theme.textTheme.titleMedium,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              engine.status,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (!failed) ...<Widget>[
                    if (progress == null)
                      const LinearProgressIndicator()
                    else
                      LinearProgressIndicator(value: progress),
                    const SizedBox(height: 8),
                    Text(
                      progress == null
                          ? '首次启动会自动下载 aria2 引擎到 faria2 的缓存目录，请保持网络畅通。'
                          : '已完成 ${(progress * 100).toStringAsFixed(0)}%',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (failed) ...<Widget>[
                    SelectableText(
                      engine.error ?? '未知错误',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.error,
                      ),
                    ),
                    if (engine.errorDetail != null &&
                        engine.errorDetail!.trim().isNotEmpty) ...<Widget>[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        constraints: const BoxConstraints(maxHeight: 180),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: SingleChildScrollView(
                          child: SelectableText(
                            engine.errorDetail!,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Text(
                      'faria2 会在缓存目录中安装 aria2。若网络不可用，'
                      '也可以在设置中手动指定系统里已有的 aria2c。',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: <Widget>[
                      if (failed) ...<Widget>[
                        FilledButton.icon(
                          onPressed: onRetry,
                          icon: const Icon(Icons.refresh),
                          label: const Text('重试启动'),
                        ),
                        OutlinedButton.icon(
                          onPressed: onReinstall,
                          icon: const Icon(Icons.replay),
                          label: const Text('重新安装 aria2'),
                        ),
                      ],
                      OutlinedButton.icon(
                        onPressed: onOpenSettings,
                        icon: const Icon(Icons.settings_outlined),
                        label: const Text('设置'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () =>
                            PlatformLauncher.openDirectory(paths.cacheDir.path),
                        icon: const Icon(Icons.folder_open),
                        label: const Text('打开缓存目录'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () =>
                            PlatformLauncher.openFile(paths.aria2LogFile.path),
                        icon: const Icon(Icons.description_outlined),
                        label: const Text('查看日志'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    '缓存目录：${paths.cacheDir.path}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

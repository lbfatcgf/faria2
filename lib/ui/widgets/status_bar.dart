import 'package:flutter/material.dart';

import '../../core/download_manager.dart';
import '../../core/engine_controller.dart';
import '../../core/formatting.dart';

/// Bottom bar with engine state and global transfer speeds.
class StatusBar extends StatelessWidget {
  const StatusBar({super.key, required this.engine, required this.downloads});

  final EngineController engine;
  final DownloadManager downloads;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final stat = downloads.globalStat;
    final textStyle = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);

    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: scheme.outlineVariant)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 560;
              return Row(
                children: <Widget>[
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: engine.isReady
                          ? const Color(0xFF2E9E63)
                          : scheme.error,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      engine.isReady
                          ? 'aria2 ${engine.aria2Version ?? ''}'.trim()
                          : engine.status,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textStyle,
                    ),
                  ),
                  const Spacer(),
                  Icon(Icons.arrow_downward, size: 14, color: scheme.primary),
                  const SizedBox(width: 2),
                  Text(formatSpeed(stat.downloadSpeed), style: textStyle),
                  const SizedBox(width: 14),
                  Icon(Icons.arrow_upward, size: 14, color: scheme.tertiary),
                  const SizedBox(width: 2),
                  Text(formatSpeed(stat.uploadSpeed), style: textStyle),
                  if (!compact) ...<Widget>[
                    const SizedBox(width: 14),
                    Text(
                      '活跃 ${stat.numActive} · 等待 ${stat.numWaiting}',
                      style: textStyle,
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../core/download_manager.dart';
import '../../core/engine_controller.dart';
import 'title_bar.dart';
import 'window_resize_handles.dart';

/// Wraps the navigator with the custom title bar and frameless resize edges.
class WindowShell extends StatelessWidget {
  const WindowShell({
    super.key,
    required this.child,
    this.downloads,
    this.engine,
    this.trayAvailable = false,
  });

  final Widget child;
  final DownloadManager? downloads;
  final EngineController? engine;
  final bool trayAvailable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.scaffoldBackgroundColor,
      child: Stack(
        children: <Widget>[
          Column(
            children: <Widget>[
              AppTitleBar(
                downloads: downloads,
                engine: engine,
                trayAvailable: trayAvailable,
              ),
              Expanded(child: child),
            ],
          ),
          const Positioned.fill(child: WindowResizeHandles()),
        ],
      ),
    );
  }
}

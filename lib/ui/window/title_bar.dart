import 'dart:async';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/download_manager.dart';
import '../../core/engine_controller.dart';
import '../../core/formatting.dart';

/// Custom frameless title bar with drag, double-click maximize and window
/// controls. It replaces the native decoration on Windows and Linux.
class AppTitleBar extends StatefulWidget {
  const AppTitleBar({
    super.key,
    this.downloads,
    this.engine,
    this.trayAvailable = false,
  });

  final DownloadManager? downloads;
  final EngineController? engine;
  final bool trayAvailable;

  @override
  State<AppTitleBar> createState() => _AppTitleBarState();
}

class _AppTitleBarState extends State<AppTitleBar> with WindowListener {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    unawaited(_refreshMaximized());
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() {
    if (mounted) {
      setState(() => _maximized = true);
    }
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) {
      setState(() => _maximized = false);
    }
  }

  @override
  void onWindowRestore() {
    unawaited(_refreshMaximized());
  }

  Future<void> _refreshMaximized() async {
    try {
      final maximized = await windowManager.isMaximized();
      if (mounted) {
        setState(() => _maximized = maximized);
      }
    } on Object {
      // Not available (for example in widget tests).
    }
  }

  Future<void> _toggleMaximize() async {
    try {
      if (await windowManager.isMaximized()) {
        await windowManager.unmaximize();
      } else {
        await windowManager.maximize();
      }
      await _refreshMaximized();
    } on Object {
      // Ignore window manager failures.
    }
  }

  Future<void> _startDragging() async {
    try {
      await windowManager.startDragging();
    } on Object {
      // Ignore window manager failures.
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } on Object {
      // Ignore window manager failures.
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final closeTooltip = widget.trayAvailable ? '关闭（最小化到托盘）' : '关闭';
    return SizedBox(
      height: 44,
      child: Material(
        color: scheme.surface,
        child: Container(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (details) => unawaited(_startDragging()),
                  onDoubleTap: () => unawaited(_toggleMaximize()),
                  child: Row(
                    children: <Widget>[
                      const SizedBox(width: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(5),
                        child: Image.asset(
                          'assets/icons/tray_icon.png',
                          width: 20,
                          height: 20,
                          filterQuality: FilterQuality.medium,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'faria2',
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 10),
                      _EngineStateBadge(engine: widget.engine),
                      const Spacer(),
                      _TransferSummary(
                        downloads: widget.downloads,
                        engine: widget.engine,
                      ),
                      const SizedBox(width: 8),
                    ],
                  ),
                ),
              ),
              _WindowButton(
                icon: Icons.remove,
                tooltip: '最小化',
                onPressed: () => unawaited(_run(windowManager.minimize)),
              ),
              _WindowButton(
                icon: _maximized ? Icons.filter_none : Icons.crop_square,
                tooltip: _maximized ? '还原' : '最大化',
                onPressed: () => unawaited(_toggleMaximize()),
              ),
              _WindowButton(
                icon: Icons.close,
                tooltip: closeTooltip,
                hoverColor: scheme.error,
                hoverIconColor: scheme.onError,
                onPressed: () => unawaited(_run(windowManager.close)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EngineStateBadge extends StatelessWidget {
  const _EngineStateBadge({this.engine});

  final EngineController? engine;

  @override
  Widget build(BuildContext context) {
    final engine = this.engine;
    if (engine == null) {
      return const SizedBox.shrink();
    }
    return AnimatedBuilder(
      animation: engine,
      builder: (context, _) {
        final scheme = Theme.of(context).colorScheme;
        final ready = engine.isReady;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: ready ? const Color(0xFF2E9E63) : scheme.outline,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              ready
                  ? 'aria2 ${engine.aria2Version ?? ''}'.trim()
                  : engine.status,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        );
      },
    );
  }
}

class _TransferSummary extends StatelessWidget {
  const _TransferSummary({this.downloads, this.engine});

  final DownloadManager? downloads;
  final EngineController? engine;

  @override
  Widget build(BuildContext context) {
    final downloads = this.downloads;
    if (downloads == null) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[?engine, downloads]),
      builder: (context, _) {
        if (engine?.isReady != true) {
          return const SizedBox.shrink();
        }
        final stat = downloads.globalStat;
        final label = stat.numActive > 0
            ? '↓ ${formatSpeed(stat.downloadSpeed)} · ${stat.numActive} 活跃'
            : '空闲';
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              stat.numActive > 0
                  ? Icons.downloading
                  : Icons.pause_circle_outline,
              size: 14,
              color: stat.numActive > 0 ? scheme.primary : scheme.outline,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        );
      },
    );
  }
}

class _WindowButton extends StatefulWidget {
  const _WindowButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.hoverColor,
    this.hoverIconColor,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final Color? hoverColor;
  final Color? hoverIconColor;

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = _hovering
        ? (widget.hoverColor ?? scheme.surfaceContainerHighest)
        : Colors.transparent;
    final foreground = _hovering && widget.hoverIconColor != null
        ? widget.hoverIconColor!
        : scheme.onSurfaceVariant;
    // The title bar lives outside the Navigator/Overlay, so it must not use
    // Tooltip (which requires an Overlay ancestor).
    return Semantics(
      button: true,
      label: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 46,
            height: 44,
            color: background,
            child: Icon(widget.icon, size: 16, color: foreground),
          ),
        ),
      ),
    );
  }
}

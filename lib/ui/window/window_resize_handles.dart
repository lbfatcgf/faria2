import 'dart:async';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// Lets the user resize the frameless window by dragging its edges/corners.
class WindowResizeHandles extends StatefulWidget {
  const WindowResizeHandles({super.key});

  @override
  State<WindowResizeHandles> createState() => _WindowResizeHandlesState();
}

class _WindowResizeHandlesState extends State<WindowResizeHandles>
    with WindowListener {
  static const double _edge = 5;
  static const double _corner = 14;
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_refreshMaximized());
    });
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
      if (mounted && maximized != _maximized) {
        setState(() => _maximized = maximized);
      }
    } on Object {
      // Window manager not available (for example in widget tests).
    }
  }

  Future<void> _startResizing(ResizeEdge edge) async {
    if (_maximized) {
      return;
    }
    try {
      await windowManager.startResizing(edge);
    } on Object {
      // Ignore window manager failures.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_maximized) {
      return const SizedBox.shrink();
    }
    return Stack(
      children: <Widget>[
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: _edge,
          child: _handle(ResizeEdge.top, SystemMouseCursors.resizeUp),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: _edge,
          child: _handle(ResizeEdge.bottom, SystemMouseCursors.resizeDown),
        ),
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: _edge,
          child: _handle(ResizeEdge.left, SystemMouseCursors.resizeLeft),
        ),
        Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          width: _edge,
          child: _handle(ResizeEdge.right, SystemMouseCursors.resizeRight),
        ),
        Positioned(
          left: 0,
          top: 0,
          width: _corner,
          height: _corner,
          child: _handle(ResizeEdge.topLeft, SystemMouseCursors.resizeUpLeft),
        ),
        Positioned(
          right: 0,
          top: 0,
          width: _corner,
          height: _corner,
          child: _handle(ResizeEdge.topRight, SystemMouseCursors.resizeUpRight),
        ),
        Positioned(
          left: 0,
          bottom: 0,
          width: _corner,
          height: _corner,
          child: _handle(
            ResizeEdge.bottomLeft,
            SystemMouseCursors.resizeDownLeft,
          ),
        ),
        Positioned(
          right: 0,
          bottom: 0,
          width: _corner,
          height: _corner,
          child: _handle(
            ResizeEdge.bottomRight,
            SystemMouseCursors.resizeDownRight,
          ),
        ),
      ],
    );
  }

  Widget _handle(ResizeEdge edge, MouseCursor cursor) {
    return MouseRegion(
      cursor: cursor,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanStart: (details) => unawaited(_startResizing(edge)),
        child: const SizedBox.expand(),
      ),
    );
  }
}

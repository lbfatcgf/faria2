import 'dart:async';
import 'dart:io';

import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';

import 'core/app_paths.dart';
import 'core/app_settings.dart';
import 'core/download_manager.dart';
import 'core/engine_controller.dart';
import 'core/platform_launcher.dart';
import 'core/tracker_service.dart';
import 'core/tray_service.dart';
import 'ui/home_page.dart';
import 'ui/theme.dart';
import 'ui/window/window_shell.dart';

/// Root widget: bootstraps paths, settings and the aria2 engine.
class Faria2App extends StatefulWidget {
  const Faria2App({super.key});

  @override
  State<Faria2App> createState() => _Faria2AppState();
}

class _Faria2AppState extends State<Faria2App> with WindowListener {
  late final AppLifecycleListener _lifecycle;
  AppPaths? _paths;
  AppSettings? _settings;
  EngineController? _engine;
  DownloadManager? _downloads;
  TrackerService? _trackerService;
  TrayService? _tray;
  Timer? _trayTimer;
  final ValueNotifier<int> _addDownloadRequests = ValueNotifier<int>(0);
  String _appliedTrackers = '';
  bool _trayReady = false;
  bool _quitting = false;
  Object? _fatalError;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onExitRequested: _handleExitRequested);
    windowManager.addListener(this);
    unawaited(_configureWindow());
    unawaited(_bootstrap());
  }

  Future<void> _configureWindow() async {
    try {
      // Intercept the native close button so faria2 can hide to the tray.
      await windowManager.setPreventClose(true);
    } on Object {
      // Window manager unavailable.
    }
  }

  @override
  void onWindowClose() {
    unawaited(_handleWindowClose());
  }

  Future<void> _handleWindowClose() async {
    if (_quitting) {
      return;
    }
    final minimize = _settings?.minimizeToTray ?? true;
    if (minimize && _trayReady) {
      try {
        await windowManager.hide();
        return;
      } on Object {
        // Fall through to a normal quit.
      }
    }
    await _quit();
  }

  Future<void> _showWindow() async {
    try {
      if (await windowManager.isMinimized()) {
        await windowManager.restore();
      }
      await windowManager.show();
      await windowManager.focus();
    } on Object {
      // Window manager unavailable.
    }
  }

  Future<void> _toggleWindow() async {
    try {
      if (await windowManager.isVisible()) {
        await windowManager.hide();
      } else {
        await _showWindow();
      }
    } on Object {
      // Window manager unavailable.
    }
  }

  Future<void> _quit() async {
    if (_quitting) {
      return;
    }
    _quitting = true;
    _trayTimer?.cancel();
    _trayTimer = null;
    _tray?.dispose();
    _tray = null;
    _trayReady = false;
    _trackerService?.dispose();
    _trackerService = null;
    _downloads?.dispose();
    _downloads = null;
    try {
      await _engine?.shutdown();
    } on Object {
      // Ignore shutdown errors while quitting.
    }
    try {
      await windowManager.setPreventClose(false);
    } on Object {
      // Ignore.
    }
    try {
      await windowManager.destroy();
    } on Object {
      // Ignore.
    }
    // Make sure the process terminates even if the window destroy path fails.
    Timer(const Duration(milliseconds: 800), () => exit(0));
  }

  Future<void> _trayAction(Future<void> Function() action) async {
    try {
      await action();
    } on Object {
      // The engine may not be ready; the tray menu will reflect it later.
    }
    _updateTray();
  }

  void _updateTray() {
    final tray = _tray;
    final engine = _engine;
    final downloads = _downloads;
    if (tray == null || engine == null || downloads == null) {
      return;
    }
    final tasks = downloads.tasks;
    tray.update(
      engineReady: engine.isReady,
      engineStatus: engine.status,
      stat: downloads.globalStat,
      canPause: tasks.any((task) => task.canPause),
      canResume: tasks.any((task) => task.canResume),
    );
  }

  Future<void> _initTray(
    AppPaths paths,
    AppSettings settings,
    DownloadManager downloads,
  ) async {
    final tray = TrayService(
      paths: paths,
      onShowWindow: () => unawaited(_showWindow()),
      onToggleWindow: () => unawaited(_toggleWindow()),
      onAddDownload: () => unawaited(_requestAddDownload()),
      onPauseAll: () => unawaited(_trayAction(downloads.pauseAll)),
      onResumeAll: () => unawaited(_trayAction(downloads.resumeAll)),
      onOpenDownloadFolder: () =>
          unawaited(PlatformLauncher.openDirectory(settings.downloadDir)),
      onQuit: () => unawaited(_quit()),
    );
    final ready = await tray.init();
    if (!mounted) {
      tray.dispose();
      return;
    }
    if (!ready) {
      debugPrint('系统托盘不可用，关闭窗口时将退出。');
      return;
    }
    _tray = tray;
    _trayReady = true;
    _trayTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _updateTray(),
    );
    _updateTray();
    setState(() {});
  }

  /// Brings the window to the front and asks [HomePage] to open its
  /// "新建下载" dialog. Used by the tray menu.
  Future<void> _requestAddDownload() async {
    await _showWindow();
    _addDownloadRequests.value++;
  }

  Future<void> _applyWindowIcon(AppPaths paths) async {
    try {
      final directory = Directory(p.join(paths.cacheDir.path, 'icons'));
      await directory.create(recursive: true);
      final name = Platform.isWindows ? 'app_icon.ico' : 'app_icon.png';
      final file = File(p.join(directory.path, name));
      final data = await rootBundle.load('assets/icons/$name');
      await file.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
      await windowManager.setIcon(file.path);
    } on Object {
      // The window icon is cosmetic.
    }
  }

  Future<void> _bootstrap() async {
    _trackerService?.dispose();
    _trackerService = null;
    _appliedTrackers = '';
    if (!Platform.isWindows && !Platform.isLinux) {
      if (mounted) {
        setState(() {
          _fatalError = UnsupportedError('faria2 目前仅支持 Windows 与 Linux。');
        });
      }
      return;
    }
    try {
      final paths = await AppPaths.resolve();
      final settings = await AppSettings.load(
        paths.settingsFile,
        defaultDownloadDir: paths.downloadsDir.path,
      );
      final engine = EngineController(paths: paths, settings: settings);
      final downloads = DownloadManager();
      final trackerService = TrackerService(settings: settings);
      engine.addListener(() => _handleEngineChange(engine, downloads));
      trackerService.addListener(() => _handleTrackersChanged(trackerService));
      if (!mounted) {
        engine.dispose();
        downloads.dispose();
        trackerService.dispose();
        return;
      }
      setState(() {
        _paths = paths;
        _settings = settings;
        _engine = engine;
        _downloads = downloads;
        _trackerService = trackerService;
      });
      if (!settings.startMinimized) {
        await _showWindow();
      }
      await _applyWindowIcon(paths);
      await _initTray(paths, settings, downloads);
      if (!mounted) {
        return;
      }
      if (settings.startMinimized && !_trayReady) {
        // Never leave the user with no window when the tray is unavailable.
        await _showWindow();
      }
      unawaited(trackerService.refresh());
      await engine.start();
    } on Object catch (error) {
      await _showWindow();
      if (!mounted) {
        return;
      }
      setState(() => _fatalError = error);
    }
  }

  void _handleEngineChange(EngineController engine, DownloadManager downloads) {
    if (!mounted) {
      return;
    }
    final rpc = engine.rpc;
    if (rpc != null) {
      if (downloads.rpc != rpc) {
        downloads.bind(rpc);
      }
    } else if (downloads.isBound) {
      downloads.unbind();
    }
    final trackers = _trackerService?.trackers ?? const <String>[];
    downloads.setTrackers(trackers);
    if (engine.isReady) {
      _applyTrackers(engine, trackers);
    } else {
      // Re-apply the trackers after the engine restarts.
      _appliedTrackers = '';
    }
    if (engine.phase == EnginePhase.failed) {
      // Never leave the user with only a hidden window when startup fails.
      unawaited(_showWindow());
    }
    _updateTray();
    setState(() {});
  }

  void _handleTrackersChanged(TrackerService service) {
    if (!mounted) {
      return;
    }
    final downloads = _downloads;
    final engine = _engine;
    downloads?.setTrackers(service.trackers);
    if (engine != null && engine.isReady) {
      _applyTrackers(engine, service.trackers);
    }
    setState(() {});
  }

  void _applyTrackers(EngineController engine, List<String> trackers) {
    final signature = trackers.join(',');
    if (signature == _appliedTrackers) {
      return;
    }
    _appliedTrackers = signature;
    unawaited(engine.applyBittorrentTrackers(trackers));
  }

  Future<void> _applySettings(AppSettings next) async {
    final paths = _paths;
    if (paths == null) {
      return;
    }
    await next.save(paths.settingsFile);
    if (!mounted) {
      return;
    }
    setState(() => _settings = next);
    _trackerService?.updateSettings(next);
    await _engine?.applySettings(next);
  }

  Future<AppExitResponse> _handleExitRequested() async {
    if (_quitting) {
      return AppExitResponse.exit;
    }
    _quitting = true;
    _trayTimer?.cancel();
    _trayTimer = null;
    _tray?.dispose();
    _tray = null;
    _trayReady = false;
    _trackerService?.dispose();
    _trackerService = null;
    _downloads?.dispose();
    _downloads = null;
    await _engine?.shutdown();
    return AppExitResponse.exit;
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _lifecycle.dispose();
    _trayTimer?.cancel();
    _tray?.dispose();
    _addDownloadRequests.dispose();
    _trackerService?.dispose();
    _engine?.dispose();
    _downloads?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    final themeMode = switch (settings?.themeMode) {
      AppThemeMode.light => ThemeMode.light,
      AppThemeMode.dark => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    return MaterialApp(
      title: 'faria2',
      debugShowCheckedModeBanner: false,
      theme: buildFaria2Theme(Brightness.light),
      darkTheme: buildFaria2Theme(Brightness.dark),
      themeMode: themeMode,
      builder: (context, child) => WindowShell(
        downloads: _downloads,
        engine: _engine,
        trayAvailable: _trayReady,
        child: child ?? const SizedBox.shrink(),
      ),
      home: _buildHome(),
    );
  }

  Widget _buildHome() {
    final error = _fatalError;
    if (error != null) {
      return _FatalErrorPage(
        error: error,
        onRetry: () {
          setState(() => _fatalError = null);
          unawaited(_bootstrap());
        },
      );
    }
    final engine = _engine;
    final downloads = _downloads;
    final paths = _paths;
    final settings = _settings;
    if (engine == null ||
        downloads == null ||
        paths == null ||
        settings == null) {
      return const _SplashScreen();
    }
    return HomePage(
      engine: engine,
      downloads: downloads,
      paths: paths,
      settings: settings,
      onSettingsChanged: _applySettings,
      addDownloadRequests: _addDownloadRequests,
      trackerService: _trackerService,
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.download_for_offline_outlined,
              size: 64,
              color: scheme.primary,
            ),
            const SizedBox(height: 20),
            Text('faria2', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              '正在初始化下载引擎…',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            const SizedBox(width: 220, child: LinearProgressIndicator()),
          ],
        ),
      ),
    );
  }
}

class _FatalErrorPage extends StatelessWidget {
  const _FatalErrorPage({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Icon(Icons.error_outline, size: 56, color: scheme.error),
                const SizedBox(height: 16),
                Text(
                  'faria2 无法启动',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                SelectableText(
                  '$error',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('重试'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

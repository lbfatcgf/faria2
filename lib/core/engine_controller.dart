import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'app_paths.dart';
import 'app_settings.dart';
import 'aria2_asset.dart';
import 'aria2_installer.dart';
import 'aria2_locator.dart';
import 'aria2_process.dart';
import 'aria2_rpc.dart';
import 'aria2_version.dart';
import 'download_client.dart';
import 'network_proxy.dart';

/// Lifecycle of the managed aria2 engine.
enum EnginePhase {
  idle,
  preparing,
  downloading,
  verifying,
  starting,
  ready,
  failed,
}

/// Raised for engine bootstrap problems that should be shown to the user.
class EngineException implements Exception {
  EngineException(this.message, {this.detail});

  final String message;
  final String? detail;

  @override
  String toString() => message;
}

/// Owns the aria2c binary discovery/installation and the running process.
class EngineController extends ChangeNotifier {
  EngineController({required this.paths, required this.settings});

  final AppPaths paths;
  AppSettings settings;

  EnginePhase _phase = EnginePhase.idle;
  String _status = '尚未启动';
  double? _progress;
  String? _error;
  String? _errorDetail;
  List<String> _skippedCandidates = const <String>[];
  Aria2Location? _location;
  String? _aria2Version;
  Aria2Rpc? _rpc;
  Aria2Process? _process;
  int _rpcPort = 0;
  bool _busy = false;
  bool _disposed = false;
  bool _stopping = false;

  EnginePhase get phase => _phase;
  String get status => _status;
  double? get progress => _progress;
  String? get error => _error;
  String? get errorDetail => _errorDetail;

  /// Candidates that were found but failed the `--version` probe.
  List<String> get skippedCandidates => _skippedCandidates;

  Aria2Location? get location => _location;
  String? get aria2Version => _aria2Version;
  Aria2Rpc? get rpc => _rpc;
  int get rpcPort => _rpcPort;
  bool get isReady => _phase == EnginePhase.ready && _rpc != null;
  bool get isBusy => _busy;
  bool get isInstalling =>
      _phase == EnginePhase.downloading || _phase == EnginePhase.verifying;

  String get engineRootPath => paths.engineRoot.path;
  String get cacheDirPath => paths.cacheDir.path;
  String get logPath => paths.aria2LogFile.path;

  /// Locates (installing when necessary) and starts aria2c.
  Future<void> start({bool forceReinstall = false}) async {
    if (_busy || _disposed) {
      return;
    }
    _busy = true;
    _error = null;
    _errorDetail = null;
    _progress = null;
    _skippedCandidates = const <String>[];
    final probeFailures = <String>[];
    try {
      await _stopProcess();
      await paths.ensure();
      await Directory(settings.downloadDir).create(recursive: true);

      final proxy = NetworkProxy(
        enabled: settings.useProxy,
        address: settings.proxyUrl,
      );
      if (!proxy.isValid) {
        throw EngineException(
          '网络代理地址无效：${settings.proxyUrl}',
          detail: '请使用 host:port 或 http://host:port 格式；暂不支持 SOCKS 或需要认证的代理。',
        );
      }

      _set(EnginePhase.preparing, '正在查找 aria2c…');

      Aria2Location? location;
      if (!forceReinstall) {
        final candidates = await Aria2Locator(
          engineRoot: paths.engineRoot,
          customPath: settings.aria2Path,
        ).candidates();
        for (final candidate in candidates) {
          final probe = await probeAria2(candidate.path);
          if (probe.ok) {
            location = candidate.copyWith(version: probe.version);
            break;
          }
          probeFailures.add(
            '${candidate.path}（${candidate.sourceLabel}）：'
            '${_shortenProbeError(probe.detail)}',
          );
        }
        _skippedCandidates = List<String>.unmodifiable(probeFailures);
      }

      if (location == null) {
        final asset = Aria2Assets.resolveHost();
        _set(
          EnginePhase.downloading,
          probeFailures.isEmpty
              ? '未找到 aria2c，正在为当前系统下载 aria2 ${asset.version}…'
              : '已有的 aria2c 无法运行，正在为当前系统下载 aria2 ${asset.version}…',
          progress: 0,
        );
        final installer = Aria2Installer(
          cacheDir: paths.cacheDir,
          asset: asset,
          downloadClient: DownloadClient(client: proxy.createClient()),
          onProgress: (stage, progress) {
            _progress = progress;
            _status = stage;
            _notify();
          },
        );
        location = await installer.install();
        if (settings.aria2Path.isNotEmpty) {
          settings = settings.copyWith(aria2Path: '');
          await settings.save(paths.settingsFile);
        }
      }

      _location = location;
      _aria2Version = location.version;

      _set(EnginePhase.starting, '正在启动 aria2c…');
      final port = settings.rpcPort > 0
          ? settings.rpcPort
          : await _findPreferredPort();
      final process = Aria2Process(
        executable: location.path,
        port: port,
        secret: settings.rpcSecret,
        downloadDir: settings.downloadDir,
        sessionFile: paths.sessionFile,
        logFile: paths.aria2LogFile,
        maxConcurrentDownloads: settings.maxConcurrentDownloads,
        maxConnectionPerServer: settings.maxConnectionPerServer,
        split: settings.split,
        speedLimit: settings.speedLimit,
        proxy: proxy.httpUrl ?? '',
        onExit: _handleUnexpectedExit,
      );
      await process.start();
      final rpc = Aria2Rpc(port: port, secret: settings.rpcSecret);
      final ready = await _waitForRpc(rpc, process);
      if (!ready) {
        final logTail = await process.readLogTail();
        await process.stop();
        rpc.close();
        throw EngineException(
          'aria2c 启动超时，无法连接本地 RPC 端口 $port。',
          detail: logTail.isEmpty ? null : logTail,
        );
      }

      _process = process;
      _rpc = rpc;
      _rpcPort = port;
      _progress = null;
      _set(EnginePhase.ready, 'aria2c ${location.version ?? '未知'} 已就绪');
    } on Object catch (error) {
      await _stopProcess();
      _phase = EnginePhase.failed;
      _status = 'aria2c 启动失败';
      _error = _describeError(error);
      final details = <String>[
        if (probeFailures.isNotEmpty)
          '以下 aria2c 已找到但无法运行：\n${probeFailures.join('\n')}',
        if (error is EngineException && error.detail != null) error.detail!,
        if (error is! EngineException) error.toString(),
      ];
      _errorDetail = details.isEmpty ? null : details.join('\n\n');
      _notify();
    } finally {
      _busy = false;
      _notify();
    }
  }

  /// Applies the merged BitTorrent tracker list to the running aria2c.
  /// An empty list clears the global option.
  Future<void> applyBittorrentTrackers(List<String> trackers) async {
    final rpc = _rpc;
    if (rpc == null) {
      return;
    }
    try {
      await rpc.changeGlobalOption(<String, String>{
        'bt-tracker': trackers.join(','),
      });
    } on Object {
      // Best effort: the engine may be restarting or shutting down.
    }
  }

  /// Restarts the engine, applying the current settings.
  Future<void> restart() async {
    await _stopProcess();
    await start();
  }

  /// Deletes the managed binary and installs it again from the official
  /// download source.
  Future<void> reinstall() async {
    await _stopProcess();
    try {
      if (await paths.engineRoot.exists()) {
        await paths.engineRoot.delete(recursive: true);
      }
    } on Object {
      // The next install attempt will surface any permission problem.
    }
    _location = null;
    _aria2Version = null;
    settings = settings.copyWith(aria2Path: '');
    await settings.save(paths.settingsFile);
    await start();
  }

  /// Applies new settings, restarting the engine only when needed.
  Future<void> applySettings(AppSettings next) async {
    final engineChanged = !settings.engineEquals(next);
    settings = next;
    _notify();
    if (engineChanged) {
      await restart();
    }
  }

  /// Stops aria2c and releases the RPC client.
  Future<void> shutdown() async {
    await _stopProcess();
    _phase = EnginePhase.idle;
    _status = '已停止';
    _notify();
  }

  Future<void> _stopProcess() async {
    final rpc = _rpc;
    final process = _process;
    _rpc = null;
    _process = null;
    _stopping = true;
    try {
      if (rpc != null) {
        try {
          await rpc.shutdown().timeout(const Duration(seconds: 2));
        } on Object {
          // The process may already be gone.
        }
        rpc.close();
      }
      if (process != null) {
        await process.stop();
      }
    } on Object {
      // Shutdown must never throw during app quit.
    } finally {
      _stopping = false;
    }
  }

  void _handleUnexpectedExit(int exitCode, String? lastError) {
    if (_stopping || _disposed) {
      return;
    }
    _process = null;
    final rpc = _rpc;
    _rpc = null;
    rpc?.close();
    _phase = EnginePhase.failed;
    _status = 'aria2c 已退出';
    _error = 'aria2c 进程意外退出（退出码 $exitCode）。';
    _errorDetail = lastError;
    _notify();
  }

  Future<bool> _waitForRpc(Aria2Rpc rpc, Aria2Process process) async {
    final deadline = DateTime.now().add(const Duration(seconds: 25));
    while (DateTime.now().isBefore(deadline)) {
      if (!process.isRunning) {
        return false;
      }
      if (await rpc.ping()) {
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    return false;
  }

  /// Prefers [AppSettings.preferredRpcPort] so external tools can use a
  /// predictable ws://127.0.0.1:16800/jsonrpc endpoint, falling back to a free
  /// port when it is occupied.
  Future<int> _findPreferredPort() async {
    final preferred = AppSettings.preferredRpcPort;
    if (await _isPortAvailable(preferred)) {
      return preferred;
    }
    return _findFreePort();
  }

  Future<bool> _isPortAvailable(int port) async {
    try {
      final socket = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        port,
      );
      await socket.close();
      return true;
    } on Object {
      return false;
    }
  }

  Future<int> _findFreePort() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    return port;
  }

  String _shortenProbeError(String detail) {
    final trimmed = detail.trim();
    if (trimmed.isEmpty) {
      return '无法运行';
    }
    final lines = trimmed.split(RegExp(r'\r?\n')).take(4).join('\n');
    return lines.length > 500 ? '${lines.substring(0, 500)}…' : lines;
  }

  String _describeError(Object error) {
    if (error is EngineException) {
      return error.message;
    }
    if (error is Aria2InstallException) {
      return error.message;
    }
    if (error is UnsupportedError) {
      return error.message ?? '$error';
    }
    if (error is Aria2ProcessException) {
      return error.message;
    }
    return '启动 aria2c 时发生错误：$error';
  }

  void _set(EnginePhase phase, String status, {double? progress}) {
    _phase = phase;
    _status = status;
    _progress = progress;
    _notify();
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_stopProcess());
    super.dispose();
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Raised when the aria2c process cannot be started.
class Aria2ProcessException implements Exception {
  Aria2ProcessException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => cause == null ? message : '$message（$cause）';
}

/// Owns the aria2c child process and forwards its output to a log file.
class Aria2Process {
  Aria2Process({
    required this.executable,
    required this.port,
    required this.secret,
    required this.downloadDir,
    required this.sessionFile,
    required this.logFile,
    this.maxConcurrentDownloads = 5,
    this.maxConnectionPerServer = 8,
    this.split = 8,
    this.speedLimit = '',
    this.proxy = '',
    this.onExit,
  });

  final String executable;
  final int port;
  final String secret;
  final String downloadDir;
  final File sessionFile;
  final File logFile;
  final int maxConcurrentDownloads;
  final int maxConnectionPerServer;
  final int split;
  final String speedLimit;

  /// Normalized HTTP proxy URL (for example `http://127.0.0.1:7890`), empty
  /// when no proxy should be used.
  final String proxy;
  final void Function(int exitCode, String? error)? onExit;

  Process? _process;
  StreamSubscription<String>? _stdoutSubscription;
  StreamSubscription<String>? _stderrSubscription;
  IOSink? _logSink;
  Completer<int>? _exitCompleter;
  bool _stopping = false;
  String? _lastError;

  bool get isRunning => _process != null;
  int get processId => _process?.pid ?? -1;
  String? get lastError => _lastError;

  /// Command line arguments used to start aria2c.
  List<String> buildArguments() {
    final arguments = <String>[
      '--no-conf=true',
      '--enable-rpc=true',
      '--rpc-listen-all=false',
      '--rpc-listen-port=$port',
      if (secret.isNotEmpty) '--rpc-secret=$secret',
      if (proxy.isNotEmpty) '--all-proxy=$proxy',
      '--dir=$downloadDir',
      '--continue=true',
      '--auto-file-renaming=true',
      '--file-allocation=none',
      '--max-concurrent-downloads=$maxConcurrentDownloads',
      '--max-connection-per-server=$maxConnectionPerServer',
      '--split=$split',
      '--min-split-size=1M',
      '--save-session=${sessionFile.path}',
      '--save-session-interval=30',
      '--auto-save-interval=30',
      '--summary-interval=0',
      '--console-log-level=warn',
      '--seed-time=0',
      '--bt-save-metadata=false',
      '--stop-with-process=$pid',
    ];
    if (speedLimit.trim().isNotEmpty) {
      arguments.add('--max-overall-download-limit=${speedLimit.trim()}');
    }
    return arguments;
  }

  /// Environment variables that aria2 interprets as proxy settings. Values
  /// that aria2 cannot parse (for example `socks5://` URLs) make aria2 abort
  /// at startup, so they are removed from the child environment.
  static const List<String> proxyEnvironmentKeys = <String>[
    'all_proxy',
    'ALL_PROXY',
    'http_proxy',
    'HTTP_PROXY',
    'https_proxy',
    'HTTPS_PROXY',
    'ftp_proxy',
    'FTP_PROXY',
  ];

  /// Returns a copy of [source] without any proxy environment variables.
  ///
  /// Proxying is controlled exclusively by the application's proxy setting and
  /// the explicit `--all-proxy` argument; inheriting `all_proxy=socks5://...`
  /// (or a stale proxy) would otherwise override it or make aria2 abort.
  static Map<String, String> withoutProxyEnvironment(
    Map<String, String> source,
  ) {
    final environment = Map<String, String>.from(source);
    for (final key in proxyEnvironmentKeys) {
      environment.remove(key);
    }
    return environment;
  }

  /// Starts aria2c and gives up when the process exits immediately.
  Future<void> start() async {
    if (_process != null) {
      return;
    }
    await logFile.parent.create(recursive: true);
    await Directory(downloadDir).create(recursive: true);
    await _rotateLogIfNeeded();
    _logSink = logFile.openWrite(mode: FileMode.append);

    _exitCompleter = Completer<int>();
    final args = <String>[
      ...buildArguments(),
      if (await _hasSession()) '--input-file=${sessionFile.path}',
    ];
    final environment = withoutProxyEnvironment(Platform.environment);
    if (proxyEnvironmentKeys.any(
      (key) => (Platform.environment[key] ?? '').isNotEmpty,
    )) {
      _writeLog('[${_timestamp()}] [faria2] 已忽略系统代理环境变量；代理由应用内“网络代理”设置控制');
    }

    Process process;
    try {
      process = await Process.start(
        executable,
        args,
        workingDirectory: downloadDir,
        runInShell: false,
        environment: environment,
        includeParentEnvironment: false,
      );
    } on Object catch (error) {
      await _logSink?.close();
      _logSink = null;
      throw Aria2ProcessException('无法启动 aria2c：$executable', cause: error);
    }

    _process = process;
    _stdoutSubscription = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_handleLine);
    _stderrSubscription = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_handleErrorLine);

    unawaited(
      process.exitCode.then((code) async {
        _process = null;
        await _stdoutSubscription?.cancel();
        await _stderrSubscription?.cancel();
        await _logSink?.flush();
        await _logSink?.close();
        _logSink = null;
        final completer = _exitCompleter;
        if (completer != null && !completer.isCompleted) {
          completer.complete(code);
        }
        if (!_stopping) {
          onExit?.call(code, _lastError);
        }
      }),
    );
  }

  /// Stops aria2c, escalating to a forced kill when it does not exit.
  Future<int> stop({Duration grace = const Duration(seconds: 3)}) async {
    final process = _process;
    if (process == null) {
      return -1;
    }
    _stopping = true;
    try {
      // SIGTERM lets aria2 save its session file before exiting. On Windows
      // the signal argument is ignored and TerminateProcess is used.
      process.kill(ProcessSignal.sigterm);
      final exited = await _waitForExit(grace);
      if (!exited) {
        process.kill(ProcessSignal.sigkill);
        await _waitForExit(const Duration(seconds: 5));
      }
    } on Object {
      process.kill(ProcessSignal.sigkill);
    } finally {
      _stopping = false;
    }
    final completer = _exitCompleter;
    if (completer == null) {
      return -1;
    }
    return completer.future;
  }

  Future<bool> _waitForExit(Duration timeout) async {
    final completer = _exitCompleter;
    if (completer == null) {
      return true;
    }
    try {
      await completer.future.timeout(timeout);
      return true;
    } on TimeoutException {
      return false;
    }
  }

  Future<bool> _hasSession() async {
    try {
      if (!await sessionFile.exists()) {
        return false;
      }
      final stat = await sessionFile.stat();
      return stat.size > 0;
    } on Object {
      return false;
    }
  }

  Future<void> _rotateLogIfNeeded() async {
    try {
      if (!await logFile.exists()) {
        return;
      }
      final stat = await logFile.stat();
      if (stat.size > 8 * 1024 * 1024) {
        await logFile.delete();
      }
    } on Object {
      // Ignore log rotation failures.
    }
  }

  void _handleLine(String line) {
    _writeLog('[${_timestamp()}] $line');
  }

  void _handleErrorLine(String line) {
    if (line.trim().isNotEmpty) {
      _lastError = line.trim();
    }
    _writeLog('[${_timestamp()}] [stderr] $line');
  }

  void _writeLog(String line) {
    try {
      _logSink?.writeln(line);
    } on Object {
      // Logging must never crash the download engine.
    }
  }

  String _timestamp() => DateTime.now().toIso8601String();

  /// Tail of the aria2 log, used for error messages in the UI.
  Future<String> readLogTail({int lines = 20}) async {
    try {
      if (!await logFile.exists()) {
        return '';
      }
      final content = await logFile.readAsString();
      final allLines = const LineSplitter().convert(content);
      final start = allLines.length > lines ? allLines.length - lines : 0;
      return allLines.sublist(start).join('\n');
    } on Object {
      return '';
    }
  }
}

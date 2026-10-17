import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'network_proxy.dart';

/// Theme preference of the application.
enum AppThemeMode {
  system,
  light,
  dark;

  static AppThemeMode parse(Object? value) {
    return switch (value) {
      'light' => AppThemeMode.light,
      'dark' => AppThemeMode.dark,
      _ => AppThemeMode.system,
    };
  }
}

/// Persisted application settings.
class AppSettings {
  const AppSettings({
    required this.downloadDir,
    this.rpcPort = 0,
    this.maxConcurrentDownloads = 5,
    this.maxConnectionPerServer = 8,
    this.split = 8,
    this.speedLimit = '',
    this.aria2Path = '',
    this.rpcSecret = '',
    this.themeMode = AppThemeMode.system,
    this.minimizeToTray = true,
    this.useProxy = false,
    this.proxyUrl = defaultProxyAddress,
    this.trackerUrls = const <String>[],
    this.manualTrackers = const <String>[],
  });

  final String downloadDir;

  /// 0 means "pick a free port automatically".
  final int rpcPort;
  final int maxConcurrentDownloads;
  final int maxConnectionPerServer;
  final int split;

  /// Global download speed limit understood by aria2, e.g. `1M`, empty for
  /// unlimited.
  final String speedLimit;

  /// Optional user supplied aria2c path. When empty faria2 looks in its own
  /// cache directory and on PATH.
  final String aria2Path;
  final String rpcSecret;
  final AppThemeMode themeMode;

  /// When true, closing the window hides it to the system tray and keeps
  /// downloads running in the background.
  final bool minimizeToTray;

  /// Whether aria2c and faria2's own HTTP requests use [proxyUrl].
  final bool useProxy;

  /// HTTP proxy address, e.g. `127.0.0.1:7890`.
  final String proxyUrl;

  /// Additional tracker-list URLs. The built-in sources are always used.
  final List<String> trackerUrls;

  /// User supplied trackers (one per entry). Merged with the downloaded lists.
  final List<String> manualTrackers;

  /// Port tried first when [rpcPort] is 0 (automatic). Many aria2 frontends
  /// default to 16800, so a fixed preferred port makes external tools work
  /// without extra configuration. If it is taken a free port is used instead.
  static const int preferredRpcPort = 16800;

  static AppSettings defaults(String downloadDir) {
    return AppSettings(downloadDir: downloadDir, rpcSecret: generateSecret());
  }

  AppSettings copyWith({
    String? downloadDir,
    int? rpcPort,
    int? maxConcurrentDownloads,
    int? maxConnectionPerServer,
    int? split,
    String? speedLimit,
    String? aria2Path,
    String? rpcSecret,
    AppThemeMode? themeMode,
    bool? minimizeToTray,
    bool? useProxy,
    String? proxyUrl,
    List<String>? trackerUrls,
    List<String>? manualTrackers,
  }) {
    return AppSettings(
      downloadDir: downloadDir ?? this.downloadDir,
      rpcPort: rpcPort ?? this.rpcPort,
      maxConcurrentDownloads:
          maxConcurrentDownloads ?? this.maxConcurrentDownloads,
      maxConnectionPerServer:
          maxConnectionPerServer ?? this.maxConnectionPerServer,
      split: split ?? this.split,
      speedLimit: speedLimit ?? this.speedLimit,
      aria2Path: aria2Path ?? this.aria2Path,
      rpcSecret: rpcSecret ?? this.rpcSecret,
      themeMode: themeMode ?? this.themeMode,
      minimizeToTray: minimizeToTray ?? this.minimizeToTray,
      useProxy: useProxy ?? this.useProxy,
      proxyUrl: proxyUrl ?? this.proxyUrl,
      trackerUrls: trackerUrls ?? this.trackerUrls,
      manualTrackers: manualTrackers ?? this.manualTrackers,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'downloadDir': downloadDir,
      'rpcPort': rpcPort,
      'maxConcurrentDownloads': maxConcurrentDownloads,
      'maxConnectionPerServer': maxConnectionPerServer,
      'split': split,
      'speedLimit': speedLimit,
      'aria2Path': aria2Path,
      'rpcSecret': rpcSecret,
      'themeMode': themeMode.name,
      'minimizeToTray': minimizeToTray,
      'useProxy': useProxy,
      'proxyUrl': proxyUrl,
      'trackerUrls': trackerUrls,
      'manualTrackers': manualTrackers,
    };
  }

  factory AppSettings.fromJson(
    Map<String, dynamic> json, {
    required String defaultDownloadDir,
  }) {
    final downloadDir = _asString(json['downloadDir']);
    return AppSettings(
      downloadDir: downloadDir.isEmpty ? defaultDownloadDir : downloadDir,
      rpcPort: _clamp(_asInt(json['rpcPort'], 0), 0, 65535),
      maxConcurrentDownloads: _clamp(
        _asInt(json['maxConcurrentDownloads'], 5),
        1,
        16,
      ),
      maxConnectionPerServer: _clamp(
        _asInt(json['maxConnectionPerServer'], 8),
        1,
        16,
      ),
      split: _clamp(_asInt(json['split'], 8), 1, 16),
      speedLimit: _asString(json['speedLimit']),
      aria2Path: _asString(json['aria2Path']),
      rpcSecret: _asString(json['rpcSecret']),
      themeMode: AppThemeMode.parse(json['themeMode']),
      minimizeToTray: json['minimizeToTray'] is bool
          ? json['minimizeToTray'] as bool
          : true,
      useProxy: json['useProxy'] is bool ? json['useProxy'] as bool : false,
      proxyUrl: _asString(json['proxyUrl']).isEmpty
          ? defaultProxyAddress
          : _asString(json['proxyUrl']),
      trackerUrls: _asStringList(json['trackerUrls']),
      manualTrackers: _asStringList(json['manualTrackers']),
    );
  }

  /// Loads settings from [file], returning defaults when the file is missing
  /// or unreadable.
  static Future<AppSettings> load(
    File file, {
    required String defaultDownloadDir,
  }) async {
    try {
      if (!await file.exists()) {
        return AppSettings.defaults(defaultDownloadDir);
      }
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) {
        return AppSettings.defaults(defaultDownloadDir);
      }
      // An empty RPC secret is a valid choice: aria2 then runs without
      // authentication. Defaults still generate a random secret for new
      // installations.
      return AppSettings.fromJson(
        decoded,
        defaultDownloadDir: defaultDownloadDir,
      );
    } on Object {
      return AppSettings.defaults(defaultDownloadDir);
    }
  }

  Future<void> save(File file) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(toJson()),
    );
  }

  static String generateSecret() {
    final random = Random.secure();
    final buffer = StringBuffer();
    for (var i = 0; i < 16; i++) {
      buffer.write(random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  /// Whether [other] requires an aria2 restart (everything except the theme).
  bool engineEquals(AppSettings other) {
    return downloadDir == other.downloadDir &&
        rpcPort == other.rpcPort &&
        maxConcurrentDownloads == other.maxConcurrentDownloads &&
        maxConnectionPerServer == other.maxConnectionPerServer &&
        split == other.split &&
        speedLimit == other.speedLimit &&
        aria2Path == other.aria2Path &&
        rpcSecret == other.rpcSecret &&
        useProxy == other.useProxy &&
        proxyUrl == other.proxyUrl;
  }
}

String _asString(Object? value) => value is String ? value : '';

List<String> _asStringList(Object? value) {
  if (value is! List) {
    return const <String>[];
  }
  final result = <String>[];
  final seen = <String>{};
  for (final entry in value) {
    if (entry is! String) {
      continue;
    }
    final trimmed = entry.trim();
    if (trimmed.isEmpty || !seen.add(trimmed)) {
      continue;
    }
    result.add(trimmed);
  }
  return List<String>.unmodifiable(result);
}

int _asInt(Object? value, int fallback) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value) ?? fallback;
  }
  return fallback;
}

int _clamp(int value, int min, int max) {
  if (value < min) {
    return min;
  }
  if (value > max) {
    return max;
  }
  return value;
}

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'app_settings.dart';
import 'network_proxy.dart';

/// Downloads BitTorrent trackers from subscription lists, merges them with
/// user-entered trackers and removes duplicates.
///
/// The built-in [defaultUrls] are always fetched; [AppSettings.trackerUrls]
/// adds extra sources. Manual trackers live in a separate list and never
/// replace or remove trackers obtained from the URLs.
class TrackerService extends ChangeNotifier {
  TrackerService({
    required AppSettings settings,
    http.Client Function()? clientFactory,
    this.timeout = const Duration(seconds: 15),
  }) : _settings = settings,
       _proxy = NetworkProxy(
         enabled: settings.useProxy,
         address: settings.proxyUrl,
       ),
       _clientFactory = clientFactory;

  /// Tracker lists published by ngosang/trackerslist.
  static const List<String> defaultUrls = <String>[
    'https://cdn.jsdelivr.net/gh/ngosang/trackerslist@master/trackers_best.txt',
    'https://cdn.jsdelivr.net/gh/ngosang/trackerslist@master/trackers_all.txt',
  ];

  final Duration timeout;
  final http.Client Function()? _clientFactory;

  AppSettings _settings;
  NetworkProxy _proxy;
  List<String> _urlTrackers = const <String>[];
  List<String> _merged = const <String>[];
  bool _loading = false;
  bool _pendingRefresh = false;
  bool _disposed = false;
  String? _lastError;
  DateTime? _lastUpdated;

  /// Merged, de-duplicated trackers (URL sources first, then manual ones).
  List<String> get trackers => _merged;

  /// Trackers parsed from the URL sources only.
  List<String> get urlTrackers => _urlTrackers;

  /// Extra subscription URLs configured by the user.
  List<String> get extraUrls =>
      List<String>.unmodifiable(_settings.trackerUrls);

  /// All subscription URLs, including the built-in ones.
  List<String> get urls => _allUrls();

  int get urlTrackerCount => _urlTrackers.length;
  int get manualTrackerCount => dedupe(_settings.manualTrackers).length;
  int get trackerCount => _merged.length;
  bool get isLoading => _loading;
  String? get lastError => _lastError;
  DateTime? get lastUpdated => _lastUpdated;

  /// Applies new settings. URL or proxy changes trigger a background refresh;
  /// manual tracker changes only recompute the merged list.
  void updateSettings(AppSettings next) {
    final old = _settings;
    _settings = next;
    _proxy = NetworkProxy(enabled: next.useProxy, address: next.proxyUrl);
    final needsFetch =
        !listEquals(old.trackerUrls, next.trackerUrls) ||
        old.useProxy != next.useProxy ||
        old.proxyUrl != next.proxyUrl;
    _recompute();
    if (needsFetch) {
      if (_loading) {
        _pendingRefresh = true;
      } else {
        unawaited(refresh());
      }
    } else {
      _notify();
    }
  }

  /// Fetches every subscription URL and refreshes the merged tracker list.
  Future<void> refresh() async {
    if (_loading || _disposed) {
      return;
    }
    _loading = true;
    _lastError = null;
    _notify();

    final sources = _allUrls();
    final fetched = <String>[];
    final errors = <String>[];
    final client = _clientFactory?.call() ?? _proxy.createClient();
    try {
      await Future.wait(
        sources.map((url) async {
          try {
            final response = await client.get(Uri.parse(url)).timeout(timeout);
            if (response.statusCode < 200 || response.statusCode >= 300) {
              errors.add('$url: HTTP ${response.statusCode}');
              return;
            }
            fetched.addAll(
              parseTrackerList(
                utf8.decode(response.bodyBytes, allowMalformed: true),
              ),
            );
          } on Object catch (error) {
            errors.add('$url: $error');
          }
        }),
      );
    } finally {
      client.close();
    }
    if (_disposed) {
      return;
    }

    if (fetched.isNotEmpty) {
      _urlTrackers = dedupe(fetched);
      _lastUpdated = DateTime.now();
    }
    _lastError = errors.isEmpty ? null : errors.join('\n');
    _loading = false;
    _recompute();
    _notify();

    if (_pendingRefresh) {
      _pendingRefresh = false;
      unawaited(refresh());
    }
  }

  void _recompute() {
    _merged = dedupe(<String>[..._urlTrackers, ..._settings.manualTrackers]);
  }

  List<String> _allUrls() {
    final result = <String>[];
    final seen = <String>{};
    for (final url in <String>[...defaultUrls, ..._settings.trackerUrls]) {
      final trimmed = url.trim();
      final uri = Uri.tryParse(trimmed);
      if (trimmed.isEmpty || uri == null) {
        continue;
      }
      final scheme = uri.scheme.toLowerCase();
      if ((scheme != 'http' && scheme != 'https') || uri.host.isEmpty) {
        continue;
      }
      if (seen.add(trimmed)) {
        result.add(trimmed);
      }
    }
    return result;
  }

  /// Parses a tracker list file (one tracker per line, `#` comments allowed).
  static List<String> parseTrackerList(String text) {
    final result = <String>[];
    final seen = <String>{};
    for (final line in const LineSplitter().convert(text)) {
      final value = line.trim();
      if (value.isEmpty || value.startsWith('#')) {
        continue;
      }
      if (!isTrackerUrl(value) || !seen.add(value)) {
        continue;
      }
      result.add(value);
    }
    return result;
  }

  /// Keeps valid, unique trackers in their original order.
  static List<String> dedupe(Iterable<String> values) {
    final result = <String>[];
    final seen = <String>{};
    for (final value in values) {
      final trimmed = value.trim();
      if (trimmed.isEmpty || !isTrackerUrl(trimmed)) {
        continue;
      }
      if (seen.add(trimmed)) {
        result.add(trimmed);
      }
    }
    return List<String>.unmodifiable(result);
  }

  /// aria2 supports HTTP(S) and UDP trackers.
  static bool isTrackerUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || uri.host.isEmpty) {
      return false;
    }
    return switch (uri.scheme.toLowerCase()) {
      'http' || 'https' || 'udp' => true,
      _ => false,
    };
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

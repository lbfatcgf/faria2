import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'aria2_rpc.dart';
import 'models/download_task.dart';
import 'models/global_stat.dart';

/// Raised when a user action could not be performed.
class DownloadException implements Exception {
  DownloadException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Polls aria2 for the task list and exposes actions to the UI.
class DownloadManager extends ChangeNotifier {
  DownloadManager({
    Duration pollInterval = const Duration(seconds: 1),
    this.notifyInterval = const Duration(milliseconds: 250),
  }) : _pollInterval = pollInterval;

  final Duration _pollInterval;

  /// UI refresh rate limiter; polling may be faster than rendering.
  final Duration notifyInterval;

  Aria2Rpc? _rpc;
  Timer? _timer;
  final List<DownloadTask> _tasks = <DownloadTask>[];
  List<String> _trackers = const <String>[];
  GlobalStat _globalStat = GlobalStat.empty;
  String? _lastError;
  bool _refreshing = false;
  bool _disposed = false;
  int _generation = 0;
  DateTime? _lastNotify;

  Aria2Rpc? get rpc => _rpc;
  bool get isBound => _rpc != null;

  /// BitTorrent trackers applied to newly added torrents and magnet links.
  List<String> get trackers => _trackers;

  void setTrackers(List<String> trackers) {
    _trackers = List<String>.unmodifiable(trackers);
  }

  /// aria2 options for a torrent/magnet download, empty when there are no
  /// trackers.
  static Map<String, String> btTrackerOptions(List<String> trackers) {
    if (trackers.isEmpty) {
      return const <String, String>{};
    }
    return <String, String>{'bt-tracker': trackers.join(',')};
  }

  List<DownloadTask> get tasks => List<DownloadTask>.unmodifiable(_tasks);
  GlobalStat get globalStat => _globalStat;
  String? get lastError => _lastError;
  bool get hasActiveTasks => _globalStat.numActive > 0;

  void bind(Aria2Rpc rpc) {
    if (identical(_rpc, rpc)) {
      return;
    }
    _generation++;
    _rpc = rpc;
    _lastError = null;
    _timer?.cancel();
    _timer = Timer.periodic(_pollInterval, (_) => refresh());
    unawaited(refresh());
    notifyListeners();
  }

  void unbind() {
    _generation++;
    _timer?.cancel();
    _timer = null;
    _rpc = null;
    _tasks.clear();
    _globalStat = GlobalStat.empty;
    _lastError = null;
    notifyListeners();
  }

  /// Fetches the current task list from aria2.
  Future<void> refresh() async {
    final rpc = _rpc;
    if (rpc == null || _refreshing || _disposed) {
      return;
    }
    final generation = _generation;
    _refreshing = true;
    try {
      final active = await rpc.tellActive();
      final waiting = await rpc.tellWaiting();
      final stopped = await rpc.tellStopped();
      final globalStat = await rpc.getGlobalStat();
      if (_disposed || generation != _generation) {
        return;
      }
      final tasks = <String, DownloadTask>{};
      for (final raw in <Map<String, dynamic>>[
        ...active,
        ...waiting,
        ...stopped,
      ]) {
        final task = DownloadTask.fromJson(raw);
        if (task.isHiddenMetadata) {
          continue;
        }
        tasks[task.gid] = task;
      }
      _tasks
        ..clear()
        ..addAll(tasks.values);
      _sortTasks();
      _globalStat = globalStat;
      _lastError = null;
      _notifyThrottled(force: true);
    } on Object catch (error) {
      if (_disposed || generation != _generation) {
        return;
      }
      _lastError = error is Aria2RpcException
          ? error.message
          : error.toString();
      _notifyThrottled(force: true);
    } finally {
      _refreshing = false;
    }
  }

  /// Adds one or more URIs (http/https/ftp/magnet).
  Future<List<String>> addUris({
    required List<String> urls,
    String? dir,
    String? out,
  }) async {
    final rpc = _requireRpc();
    final gids = <String>[];
    for (final url in urls) {
      final trimmed = url.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      final isMagnet = trimmed.toLowerCase().startsWith('magnet:');
      gids.add(
        await rpc.addUri(
          <String>[trimmed],
          dir: dir,
          out: out,
          options: <String, String>{
            'continue': 'true',
            if (isMagnet) ...btTrackerOptions(_trackers),
          },
        ),
      );
    }
    await refresh();
    return gids;
  }

  /// Adds a local .torrent or .metalink file.
  Future<List<String>> addLocalFile(String path, {String? dir}) async {
    final rpc = _requireRpc();
    final file = File(path);
    if (!await file.exists()) {
      throw DownloadException('文件不存在：$path');
    }
    final encoded = base64Encode(await file.readAsBytes());
    final lower = path.toLowerCase();
    final gid = lower.endsWith('.torrent')
        ? await rpc.addTorrent(
            encoded,
            dir: dir,
            options: btTrackerOptions(_trackers),
          )
        : lower.endsWith('.metalink') || lower.endsWith('.meta4')
        ? await rpc.addMetalink(encoded, dir: dir)
        : throw DownloadException('仅支持 .torrent 与 .metalink 文件');
    await refresh();
    return <String>[gid];
  }

  Future<void> pause(DownloadTask task) async {
    await _requireRpc().pause(task.gid);
    await refresh();
  }

  Future<void> resume(DownloadTask task) async {
    await _requireRpc().unpause(task.gid);
    await refresh();
  }

  Future<void> pauseAll() async {
    await _requireRpc().pauseAll();
    await refresh();
  }

  Future<void> resumeAll() async {
    await _requireRpc().unpauseAll();
    await refresh();
  }

  /// Removes a task and, when [deleteFiles] is true, its downloaded files.
  /// Returns the number of deleted files.
  Future<int> remove(DownloadTask task, {bool deleteFiles = false}) async {
    final rpc = _requireRpc();
    var deleted = 0;
    if (task.state == TaskState.active ||
        task.state == TaskState.waiting ||
        task.state == TaskState.paused) {
      try {
        await rpc.remove(task.gid);
      } on Object {
        // It may have completed in the meantime.
      }
    }
    try {
      await rpc.removeDownloadResult(task.gid);
    } on Object {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      try {
        await rpc.removeDownloadResult(task.gid);
      } on Object {
        // Already removed.
      }
    }
    if (deleteFiles) {
      deleted = await deleteFilesOf(task);
    }
    await refresh();
    return deleted;
  }

  /// Removes every finished task from the list.
  Future<void> clearCompleted() async {
    await _requireRpc().purgeDownloadResult();
    await refresh();
  }

  /// Deletes the files belonging to [task] and its .aria2 control files.
  Future<int> deleteFilesOf(DownloadTask task) async {
    var deleted = 0;
    final dir = task.dir;
    final candidates = <String>{};
    for (final file in task.files) {
      final path = file.path;
      if (path.isEmpty) {
        continue;
      }
      final inDir = dir.isEmpty || p.equals(dir, path) || p.isWithin(dir, path);
      if (!inDir) {
        continue;
      }
      candidates
        ..add(path)
        ..add('$path.aria2');
    }
    for (final candidate in candidates) {
      try {
        final file = File(candidate);
        if (await file.exists()) {
          await file.delete();
          deleted++;
        }
      } on Object {
        // Keep going, report the number of removed files.
      }
    }
    return deleted;
  }

  Aria2Rpc _requireRpc() {
    final rpc = _rpc;
    if (rpc == null) {
      throw DownloadException('aria2 尚未就绪，请稍后再试。');
    }
    return rpc;
  }

  void _sortTasks() {
    final order = <String, int>{};
    for (var i = 0; i < _tasks.length; i++) {
      order[_tasks[i].gid] = i;
    }
    _tasks.sort((a, b) {
      final rank = _rank(a.state).compareTo(_rank(b.state));
      if (rank != 0) {
        return rank;
      }
      return (order[a.gid] ?? 0).compareTo(order[b.gid] ?? 0);
    });
  }

  int _rank(TaskState state) {
    return switch (state) {
      TaskState.active => 0,
      TaskState.waiting => 1,
      TaskState.paused => 2,
      TaskState.error => 3,
      TaskState.complete => 4,
      TaskState.removed => 5,
      TaskState.unknown => 6,
    };
  }

  void _notifyThrottled({bool force = false}) {
    final now = DateTime.now();
    if (!force &&
        _lastNotify != null &&
        now.difference(_lastNotify!) < notifyInterval) {
      return;
    }
    _lastNotify = now;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    _rpc = null;
    super.dispose();
  }
}

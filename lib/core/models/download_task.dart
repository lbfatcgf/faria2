import 'package:path/path.dart' as p;

/// The state reported by aria2 for a download.
enum TaskState {
  active,
  waiting,
  paused,
  complete,
  error,
  removed,
  unknown;

  static TaskState parse(Object? value) {
    return switch (value) {
      'active' => TaskState.active,
      'waiting' => TaskState.waiting,
      'paused' => TaskState.paused,
      'complete' => TaskState.complete,
      'error' => TaskState.error,
      'removed' => TaskState.removed,
      _ => TaskState.unknown,
    };
  }
}

/// One file inside a download (a torrent download may contain many files).
class DownloadFile {
  const DownloadFile({
    required this.index,
    required this.path,
    required this.length,
    required this.completedLength,
    required this.selected,
    this.uri,
  });

  final String index;
  final String path;
  final int length;
  final int completedLength;
  final bool selected;
  final String? uri;

  String get name => path.isEmpty ? '未命名文件' : p.basename(path);

  double get progress => length > 0 ? completedLength / length : 0;

  factory DownloadFile.fromJson(Map<String, dynamic> json) {
    final uris = json['uris'];
    String? firstUri;
    if (uris is List && uris.isNotEmpty) {
      final first = uris.first;
      if (first is Map && first['uri'] is String) {
        firstUri = first['uri'] as String;
      }
    }
    return DownloadFile(
      index: (json['index'] ?? '0').toString(),
      path: (json['path'] ?? '') as String,
      length: _toInt(json['length']),
      completedLength: _toInt(json['completedLength']),
      selected: (json['selected'] ?? 'true').toString() == 'true',
      uri: firstUri,
    );
  }
}

/// A download task as reported by `aria2.tellStatus`.
class DownloadTask {
  const DownloadTask({
    required this.gid,
    required this.state,
    required this.totalLength,
    required this.completedLength,
    required this.downloadSpeed,
    required this.uploadSpeed,
    required this.connections,
    required this.dir,
    required this.files,
    this.errorCode,
    this.errorMessage,
    this.torrentName,
    this.followedBy,
    this.belongsTo,
    this.infoHash,
    this.numSeeders,
    this.verifiedLength,
    this.bitfield,
  });

  final String gid;
  final TaskState state;
  final int totalLength;
  final int completedLength;
  final int downloadSpeed;
  final int uploadSpeed;
  final int connections;
  final String dir;
  final List<DownloadFile> files;
  final String? errorCode;
  final String? errorMessage;
  final String? torrentName;
  final String? followedBy;
  final String? belongsTo;
  final String? infoHash;
  final int? numSeeders;
  final int? verifiedLength;
  final String? bitfield;

  factory DownloadTask.fromJson(Map<String, dynamic> json) {
    final rawFiles = json['files'];
    final files = <DownloadFile>[];
    if (rawFiles is List) {
      for (final entry in rawFiles) {
        if (entry is Map<String, dynamic>) {
          files.add(DownloadFile.fromJson(entry));
        } else if (entry is Map) {
          files.add(DownloadFile.fromJson(Map<String, dynamic>.from(entry)));
        }
      }
    }

    String? torrentName;
    final bittorrent = json['bittorrent'];
    if (bittorrent is Map && bittorrent['info'] is Map) {
      final info = bittorrent['info'];
      if (info is Map && info['name'] is String) {
        torrentName = info['name'] as String;
      }
    }

    return DownloadTask(
      gid: (json['gid'] ?? '') as String,
      state: TaskState.parse(json['status']),
      totalLength: _toInt(json['totalLength']),
      completedLength: _toInt(json['completedLength']),
      downloadSpeed: _toInt(json['downloadSpeed']),
      uploadSpeed: _toInt(json['uploadSpeed']),
      connections: _toInt(json['connections']),
      dir: (json['dir'] ?? '') as String,
      files: List<DownloadFile>.unmodifiable(files),
      errorCode: json['errorCode']?.toString(),
      errorMessage: json['errorMessage'] as String?,
      torrentName: torrentName,
      followedBy: _toFirstString(json['followedBy']),
      belongsTo: _toFirstString(json['belongsTo']),
      infoHash: _toNonEmptyString(json['infoHash']),
      numSeeders: json['numSeeders'] == null
          ? null
          : _toInt(json['numSeeders']),
      verifiedLength: json['verifiedLength'] == null
          ? null
          : _toInt(json['verifiedLength']),
      bitfield: json['bitfield'] as String?,
    );
  }

  /// A magnet link that is still fetching metadata has no files yet.
  bool get isMetadataOnly =>
      files.isEmpty &&
      totalLength == 0 &&
      (state == TaskState.active ||
          state == TaskState.waiting ||
          state == TaskState.paused);

  /// The completed metadata task that spawned a real download is not
  /// interesting for the user, hide it from the list.
  bool get isHiddenMetadata =>
      files.isEmpty && state == TaskState.complete && followedBy != null;

  String get displayName {
    if (torrentName != null && torrentName!.isNotEmpty) {
      return torrentName!;
    }
    if (files.isNotEmpty) {
      return files.first.name;
    }
    final uri = firstUri;
    if (uri != null && uri.isNotEmpty) {
      final parsed = Uri.tryParse(uri);
      if (parsed != null && parsed.pathSegments.isNotEmpty) {
        final last = parsed.pathSegments.lastWhere(
          (segment) => segment.isNotEmpty,
          orElse: () => '',
        );
        if (last.isNotEmpty) {
          return Uri.decodeComponent(last);
        }
      }
      return uri;
    }
    return gid;
  }

  String? get firstUri {
    for (final file in files) {
      if (file.uri != null && file.uri!.isNotEmpty) {
        return file.uri;
      }
    }
    return null;
  }

  /// The path of the downloaded file, or the target directory for torrents.
  String get contentPath {
    if (files.isEmpty) {
      return dir;
    }
    return files.first.path;
  }

  bool get isMultiFile => files.length > 1;

  double get progress {
    if (totalLength <= 0) {
      return state == TaskState.complete ? 1 : 0;
    }
    return (completedLength / totalLength).clamp(0.0, 1.0);
  }

  bool get isActive => state == TaskState.active;
  bool get isPaused => state == TaskState.paused;
  bool get isComplete => state == TaskState.complete;
  bool get isWaiting => state == TaskState.waiting;

  bool get canPause => state == TaskState.active || state == TaskState.waiting;
  bool get canResume => state == TaskState.paused;
  bool get canRemove => true;

  /// Remaining seconds based on the current speed, null if unknown.
  int? get etaSeconds {
    if (downloadSpeed <= 0 || totalLength <= 0) {
      return null;
    }
    final remaining = totalLength - completedLength;
    if (remaining <= 0) {
      return 0;
    }
    return (remaining / downloadSpeed).ceil();
  }

  String get statusLabel {
    return switch (state) {
      TaskState.active => isMetadataOnly ? '正在获取元数据' : '下载中',
      TaskState.waiting => '等待中',
      TaskState.paused => '已暂停',
      TaskState.complete => '已完成',
      TaskState.error => '出错',
      TaskState.removed => '已移除',
      TaskState.unknown => '未知状态',
    };
  }
}

int _toInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value) ?? 0;
  }
  return 0;
}

String? _toNonEmptyString(Object? value) {
  if (value is String && value.isNotEmpty) {
    return value;
  }
  return null;
}

/// aria2 returns gid references either as a string or as an array of strings.
String? _toFirstString(Object? value) {
  if (value is String && value.isNotEmpty) {
    return value;
  }
  if (value is List && value.isNotEmpty) {
    return _toNonEmptyString(value.first);
  }
  return null;
}

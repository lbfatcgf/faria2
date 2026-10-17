import 'package:faria2/core/models/download_task.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses an active HTTP download', () {
    final task = DownloadTask.fromJson(<String, dynamic>{
      'gid': '2089b05ecca3d829',
      'status': 'active',
      'totalLength': '1048576',
      'completedLength': '524288',
      'downloadSpeed': '65536',
      'uploadSpeed': '0',
      'connections': '4',
      'dir': '/home/user/Downloads',
      'files': <dynamic>[
        <String, dynamic>{
          'index': '1',
          'path': '/home/user/Downloads/ubuntu.iso',
          'length': '1048576',
          'completedLength': '524288',
          'selected': 'true',
          'uris': <dynamic>[
            <String, dynamic>{'uri': 'https://example.com/ubuntu.iso'},
          ],
        },
      ],
    });

    expect(task.gid, '2089b05ecca3d829');
    expect(task.state, TaskState.active);
    expect(task.isActive, isTrue);
    expect(task.displayName, 'ubuntu.iso');
    expect(task.contentPath, '/home/user/Downloads/ubuntu.iso');
    expect(task.progress, closeTo(0.5, 0.0001));
    expect(task.etaSeconds, 8);
    expect(task.statusLabel, '下载中');
    expect(task.firstUri, 'https://example.com/ubuntu.iso');
    expect(task.files.single.uri, 'https://example.com/ubuntu.iso');
  });

  test('parses a torrent with bittorrent info', () {
    final task = DownloadTask.fromJson(<String, dynamic>{
      'gid': 'abc',
      'status': 'complete',
      'totalLength': '100',
      'completedLength': '100',
      'downloadSpeed': '0',
      'uploadSpeed': '0',
      'connections': '0',
      'dir': '/downloads',
      'bittorrent': <String, dynamic>{
        'info': <String, dynamic>{'name': 'Example torrent'},
      },
      'files': <dynamic>[
        <String, dynamic>{
          'index': '1',
          'path': '/downloads/a.bin',
          'length': '60',
          'completedLength': '60',
          'selected': 'true',
        },
        <String, dynamic>{
          'index': '2',
          'path': '/downloads/b.bin',
          'length': '40',
          'completedLength': '40',
          'selected': 'true',
        },
      ],
    });

    expect(task.displayName, 'Example torrent');
    expect(task.isMultiFile, isTrue);
    expect(task.progress, 1.0);
    expect(task.isComplete, isTrue);
    expect(task.statusLabel, '已完成');
  });

  test('detects a magnet link that is fetching metadata', () {
    final task = DownloadTask.fromJson(<String, dynamic>{
      'gid': 'feedbeef',
      'status': 'active',
      'totalLength': '0',
      'completedLength': '0',
      'downloadSpeed': '0',
      'uploadSpeed': '0',
      'connections': '0',
      'dir': '/downloads',
      'files': <dynamic>[],
    });

    expect(task.isMetadataOnly, isTrue);
    expect(task.displayName, 'feedbeef');
    expect(task.statusLabel, '正在获取元数据');
    expect(task.progress, 0);
  });

  test('hides the completed metadata carrier of a torrent', () {
    final task = DownloadTask.fromJson(<String, dynamic>{
      'gid': 'meta',
      'status': 'complete',
      'totalLength': '0',
      'completedLength': '0',
      'followedBy': <dynamic>['real-gid'],
      'files': <dynamic>[],
    });
    expect(task.isHiddenMetadata, isTrue);
  });

  test('keeps error details', () {
    final task = DownloadTask.fromJson(<String, dynamic>{
      'gid': 'err',
      'status': 'error',
      'errorCode': '3',
      'errorMessage': 'Resource not found',
      'totalLength': '0',
      'completedLength': '0',
      'files': <dynamic>[],
    });
    expect(task.state, TaskState.error);
    expect(task.errorMessage, 'Resource not found');
    expect(task.statusLabel, '出错');
  });

  test('parse handles unknown states', () {
    expect(TaskState.parse('something'), TaskState.unknown);
    expect(TaskState.parse(null), TaskState.unknown);
  });
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

/// Simple cross-platform file/folder picker built on dart:io so that no
/// platform plugin is required.
class PathPickerDialog extends StatefulWidget {
  const PathPickerDialog({
    super.key,
    required this.initialPath,
    this.selectFile = false,
    this.fileExtensions = const <String>[],
  });

  final String initialPath;
  final bool selectFile;

  /// Optional lowercase extension filter, e.g. `['.torrent', '.metalink']`.
  final List<String> fileExtensions;

  @override
  State<PathPickerDialog> createState() => _PathPickerDialogState();
}

class _PathPickerDialogState extends State<PathPickerDialog> {
  late Directory _directory;
  late Future<List<FileSystemEntity>> _entries;

  @override
  void initState() {
    super.initState();
    _directory = _initialDirectory();
    _entries = _list(_directory);
  }

  Directory _initialDirectory() {
    final initial = widget.initialPath.trim();
    if (initial.isNotEmpty) {
      final type = FileSystemEntity.typeSync(initial);
      if (type == FileSystemEntityType.directory) {
        return Directory(initial);
      }
      if (type == FileSystemEntityType.file) {
        return File(initial).parent;
      }
    }
    final home =
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '';
    if (home.isNotEmpty) {
      final dir = Directory(home);
      if (dir.existsSync()) {
        return dir;
      }
    }
    return Directory.current;
  }

  Future<List<FileSystemEntity>> _list(Directory directory) async {
    final entries = await directory.list(followLinks: false).toList();
    final visible = entries.where((entity) {
      final name = p.basename(entity.path);
      if (name.startsWith('.')) {
        return false;
      }
      if (entity is Directory) {
        return true;
      }
      if (!widget.selectFile) {
        return false;
      }
      if (widget.fileExtensions.isEmpty) {
        return true;
      }
      final lower = name.toLowerCase();
      return widget.fileExtensions.any(
        (extension) => lower.endsWith(extension),
      );
    }).toList();
    visible.sort((a, b) {
      final aDir = a is Directory;
      final bDir = b is Directory;
      if (aDir != bDir) {
        return aDir ? -1 : 1;
      }
      return p
          .basename(a.path)
          .toLowerCase()
          .compareTo(p.basename(b.path).toLowerCase());
    });
    return visible;
  }

  void _navigate(Directory directory) {
    setState(() {
      _directory = directory;
      _entries = _list(directory);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isRoot = _directory.parent.path == _directory.path;
    return AlertDialog(
      title: Text(widget.selectFile ? '选择文件' : '选择文件夹'),
      content: SizedBox(
        width: 560,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                IconButton(
                  tooltip: '上一级',
                  onPressed: isRoot ? null : () => _navigate(_directory.parent),
                  icon: const Icon(Icons.arrow_upward),
                ),
                IconButton(
                  tooltip: '刷新',
                  onPressed: () => setState(() => _entries = _list(_directory)),
                  icon: const Icon(Icons.refresh),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Tooltip(
                    message: _directory.path,
                    child: Text(
                      _directory.path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 16),
            Expanded(
              child: FutureBuilder<List<FileSystemEntity>>(
                future: _entries,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        '无法读取文件夹：${snapshot.error}',
                        style: TextStyle(color: scheme.error),
                      ),
                    );
                  }
                  final entries = snapshot.data ?? const <FileSystemEntity>[];
                  if (entries.isEmpty) {
                    return Center(
                      child: Text(
                        '这里没有可用的条目',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    );
                  }
                  return ListView.builder(
                    itemCount: entries.length,
                    itemBuilder: (context, index) {
                      final entity = entries[index];
                      final isDirectory = entity is Directory;
                      final name = p.basename(entity.path);
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          isDirectory
                              ? Icons.folder_outlined
                              : Icons.description_outlined,
                          color: isDirectory ? scheme.primary : null,
                        ),
                        title: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () {
                          if (isDirectory) {
                            _navigate(Directory(entity.path));
                          } else {
                            Navigator.of(context).pop(entity.path);
                          }
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_directory.path),
          child: Text(widget.selectFile ? '使用此文件夹' : '选择此文件夹'),
        ),
      ],
    );
  }
}

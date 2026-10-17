import 'package:flutter/material.dart';

import 'widgets/path_picker_dialog.dart';

/// Values collected by [AddDownloadDialog].
class AddDownloadRequest {
  const AddDownloadRequest({required this.inputs, this.dir, this.out});

  final List<String> inputs;
  final String? dir;
  final String? out;
}

/// Dialog for adding one or more links (one per line) or torrent files.
class AddDownloadDialog extends StatefulWidget {
  const AddDownloadDialog({super.key, required this.defaultDir});

  final String defaultDir;

  @override
  State<AddDownloadDialog> createState() => _AddDownloadDialogState();
}

class _AddDownloadDialogState extends State<AddDownloadDialog> {
  late final TextEditingController _links;
  late final TextEditingController _dir;
  late final TextEditingController _out;
  String? _error;

  @override
  void initState() {
    super.initState();
    _links = TextEditingController();
    _dir = TextEditingController(text: widget.defaultDir);
    _out = TextEditingController();
  }

  @override
  void dispose() {
    _links.dispose();
    _dir.dispose();
    _out.dispose();
    super.dispose();
  }

  Future<void> _pickTorrent() async {
    final path = await showDialog<String>(
      context: context,
      builder: (context) => PathPickerDialog(
        initialPath: widget.defaultDir,
        selectFile: true,
        fileExtensions: const <String>['.torrent', '.metalink', '.meta4'],
      ),
    );
    if (path == null || !mounted) {
      return;
    }
    final current = _links.text.trim();
    _links.text = current.isEmpty ? path : '$current\n$path';
    setState(() {});
  }

  void _submit() {
    final inputs = _links.text
        .split(RegExp(r'[\r\n]+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (inputs.isEmpty) {
      setState(() => _error = '请输入下载链接，或选择一个 .torrent / .metalink 文件。');
      return;
    }
    final dir = _dir.text.trim();
    if (dir.isEmpty) {
      setState(() => _error = '请填写保存目录。');
      return;
    }
    final out = _out.text.trim();
    Navigator.of(context).pop(
      AddDownloadRequest(
        inputs: inputs,
        dir: dir,
        out: out.isEmpty ? null : out,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('新建下载'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              TextField(
                controller: _links,
                minLines: 4,
                maxLines: 8,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '下载链接',
                  hintText:
                      '每行一个链接，支持 HTTP/HTTPS/FTP/Magnet\n'
                      '也可以粘贴本地 .torrent 文件路径',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  OutlinedButton.icon(
                    onPressed: _pickTorrent,
                    icon: const Icon(Icons.attach_file, size: 18),
                    label: const Text('选择种子文件'),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '支持 HTTP、HTTPS、FTP、磁力链接以及 .torrent/.metalink 文件。',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _dir,
                decoration: const InputDecoration(
                  labelText: '保存目录',
                  prefixIcon: Icon(Icons.folder_outlined),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _out,
                decoration: const InputDecoration(
                  labelText: '保存文件名（可选）',
                  hintText: '仅对单个链接有效',
                ),
              ),
              if (_error != null) ...<Widget>[
                const SizedBox(height: 14),
                Text(_error!, style: TextStyle(color: scheme.error)),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.download),
          label: const Text('开始下载'),
        ),
      ],
    );
  }
}

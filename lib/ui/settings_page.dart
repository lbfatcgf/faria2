import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_paths.dart';
import '../core/app_settings.dart';
import '../core/engine_controller.dart';
import '../core/network_proxy.dart';
import '../core/platform_launcher.dart';
import '../core/tracker_service.dart';
import 'widgets/path_picker_dialog.dart';

/// Settings form; saves through [onSaved] and then closes itself.
class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.initial,
    required this.paths,
    required this.engine,
    required this.onSaved,
    this.trackerService,
  });

  final AppSettings initial;
  final AppPaths paths;
  final EngineController engine;
  final Future<void> Function(AppSettings) onSaved;

  /// Shared tracker state used for the status line and manual refresh.
  final TrackerService? trackerService;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _downloadDir;
  late final TextEditingController _aria2Path;
  late final TextEditingController _rpcPort;
  late final TextEditingController _rpcSecret;
  late final TextEditingController _speedLimit;
  late final TextEditingController _proxyUrl;
  late final TextEditingController _manualTrackers;
  late final TextEditingController _newTrackerUrl;
  late List<String> _trackerUrls;
  late bool _useProxy;
  late int _maxConcurrentDownloads;
  late int _maxConnectionPerServer;
  late int _split;
  late AppThemeMode _themeMode;
  late bool _minimizeToTray;
  late bool _startMinimized;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final settings = widget.initial;
    _downloadDir = TextEditingController(text: settings.downloadDir);
    _aria2Path = TextEditingController(text: settings.aria2Path);
    _rpcPort = TextEditingController(
      text: settings.rpcPort == 0 ? '' : '${settings.rpcPort}',
    );
    _rpcSecret = TextEditingController(text: settings.rpcSecret);
    _speedLimit = TextEditingController(text: settings.speedLimit);
    _proxyUrl = TextEditingController(text: settings.proxyUrl);
    _manualTrackers = TextEditingController(
      text: settings.manualTrackers.join('\n'),
    );
    _newTrackerUrl = TextEditingController();
    _trackerUrls = List<String>.of(settings.trackerUrls);
    _useProxy = settings.useProxy;
    _maxConcurrentDownloads = settings.maxConcurrentDownloads;
    _maxConnectionPerServer = settings.maxConnectionPerServer;
    _split = settings.split;
    _themeMode = settings.themeMode;
    _minimizeToTray = settings.minimizeToTray;
    _startMinimized = settings.startMinimized;
  }

  @override
  void dispose() {
    _downloadDir.dispose();
    _aria2Path.dispose();
    _rpcPort.dispose();
    _rpcSecret.dispose();
    _speedLimit.dispose();
    _proxyUrl.dispose();
    _manualTrackers.dispose();
    _newTrackerUrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (_useProxy && NetworkProxy.normalize(_proxyUrl.text) == null) {
      _showMessage('代理地址格式不正确，请使用 host:port 或 http://host:port');
      return;
    }
    for (final tracker in _parseTrackerLines(_manualTrackers.text)) {
      if (!TrackerService.isTrackerUrl(tracker)) {
        _showMessage('无效的 tracker：$tracker');
        return;
      }
    }
    setState(() => _saving = true);
    final updated = widget.initial.copyWith(
      downloadDir: _downloadDir.text.trim(),
      aria2Path: _aria2Path.text.trim(),
      rpcPort: int.tryParse(_rpcPort.text.trim()) ?? 0,
      rpcSecret: _rpcSecret.text.trim(),
      speedLimit: _speedLimit.text.trim(),
      maxConcurrentDownloads: _maxConcurrentDownloads,
      maxConnectionPerServer: _maxConnectionPerServer,
      split: _split,
      themeMode: _themeMode,
      minimizeToTray: _minimizeToTray,
      startMinimized: _startMinimized,
      useProxy: _useProxy,
      proxyUrl: _proxyUrl.text.trim().isEmpty
          ? defaultProxyAddress
          : _proxyUrl.text.trim(),
      trackerUrls: List<String>.unmodifiable(_trackerUrls),
      manualTrackers: _parseTrackerLines(_manualTrackers.text),
    );
    try {
      await widget.onSaved(updated);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } on Object catch (error) {
      if (mounted) {
        _showMessage('保存失败：$error');
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _pickDirectory() async {
    final path = await showDialog<String>(
      context: context,
      builder: (context) =>
          PathPickerDialog(initialPath: _downloadDir.text.trim()),
    );
    if (path != null && mounted) {
      _downloadDir.text = path;
    }
  }

  Future<void> _pickAria2Binary() async {
    final path = await showDialog<String>(
      context: context,
      builder: (context) => PathPickerDialog(
        initialPath: _aria2Path.text.trim().isEmpty
            ? widget.paths.cacheDir.path
            : _aria2Path.text.trim(),
        selectFile: true,
      ),
    );
    if (path != null && mounted) {
      _aria2Path.text = path;
    }
  }

  Future<void> _confirmReinstall() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重新安装 aria2？'),
        content: const Text(
          '将删除缺省缓存目录中的 aria2 引擎，并在下次启动时重新下载安装。'
          '手动指定的 aria2c 路径会被清除。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('重新安装'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    try {
      await widget.engine.reinstall();
      if (mounted) {
        _showMessage('aria2 已重新安装');
      }
    } on Object catch (error) {
      if (mounted) {
        _showMessage('重新安装失败：$error');
      }
    }
  }

  Future<void> _copyRpcSecret() async {
    final secret = _rpcSecret.text.trim();
    if (secret.isEmpty) {
      _showMessage('当前未启用 RPC 密钥');
      return;
    }
    await Clipboard.setData(ClipboardData(text: secret));
    if (mounted) {
      _showMessage('已复制 RPC 密钥');
    }
  }

  void _regenerateRpcSecret() {
    setState(() {
      _rpcSecret.text = AppSettings.generateSecret();
    });
    _showMessage('已生成新的 RPC 密钥，保存后生效');
  }

  Future<void> _copyRpcInfo(EngineController engine) async {
    if (engine.rpcPort == 0) {
      _showMessage('引擎尚未启动，暂无 RPC 连接信息');
      return;
    }
    final secret = engine.settings.rpcSecret;
    final info = <String>[
      'WebSocket: ws://127.0.0.1:${engine.rpcPort}/jsonrpc',
      'HTTP: http://127.0.0.1:${engine.rpcPort}/jsonrpc',
      secret.isEmpty ? 'RPC 密钥: 未启用' : 'RPC 密钥: $secret',
    ].join('\n');
    await _copyText(info, '已复制 RPC 连接信息');
  }

  Future<void> _copyText(String text, String message) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      _showMessage(message);
    }
  }

  Widget _endpointRow(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value ?? '-',
              maxLines: 2,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
          if (value != null)
            IconButton(
              tooltip: '复制 $label 地址',
              visualDensity: VisualDensity.compact,
              onPressed: () => _copyText(value, '$label 地址已复制'),
              icon: const Icon(Icons.copy, size: 15),
            ),
        ],
      ),
    );
  }

  List<String> _parseTrackerLines(String text) {
    final result = <String>[];
    final seen = <String>{};
    for (final line in text.split(RegExp(r'[\r\n]+'))) {
      final value = line.trim();
      if (value.isEmpty || !seen.add(value)) {
        continue;
      }
      result.add(value);
    }
    return List<String>.unmodifiable(result);
  }

  void _addTrackerUrl() {
    final value = _newTrackerUrl.text.trim();
    final uri = Uri.tryParse(value);
    if (value.isEmpty ||
        uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      _showMessage('请输入有效的 http/https 订阅链接');
      return;
    }
    if (TrackerService.defaultUrls.contains(value) ||
        _trackerUrls.contains(value)) {
      _showMessage('该订阅链接已存在');
      return;
    }
    setState(() {
      _trackerUrls = <String>[..._trackerUrls, value];
      _newTrackerUrl.clear();
    });
  }

  void _removeTrackerUrl(String url) {
    setState(() {
      _trackerUrls = _trackerUrls.where((item) => item != url).toList();
    });
  }

  Widget _trackerStatus() {
    final service = widget.trackerService;
    if (service == null) {
      return const SizedBox.shrink();
    }
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        final updated = service.lastUpdated;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                if (service.isLoading)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(Icons.public, size: 16, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '已合并 ${service.trackerCount} 个 tracker'
                    '（订阅 ${service.urlTrackerCount}'
                    ' + 手动 ${service.manualTrackerCount}）',
                    style: theme.textTheme.labelMedium,
                  ),
                ),
              ],
            ),
            if (updated != null) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                '最后更新：${updated.toLocal().toString().split('.').first}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            if (service.lastError != null) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                service.lastError!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.error,
                ),
              ),
            ],
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: service.isLoading ? null : () => service.refresh(),
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('刷新 Tracker'),
            ),
          ],
        );
      },
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: const Text('保存'),
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: <Widget>[
            _section('下载', <Widget>[
              TextFormField(
                controller: _downloadDir,
                decoration: InputDecoration(
                  labelText: '默认下载目录',
                  prefixIcon: const Icon(Icons.folder_outlined),
                  suffixIcon: IconButton(
                    tooltip: '选择文件夹',
                    onPressed: _pickDirectory,
                    icon: const Icon(Icons.folder_open),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '请填写默认下载目录';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 18),
              Text('界面主题', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SegmentedButton<AppThemeMode>(
                  segments: const <ButtonSegment<AppThemeMode>>[
                    ButtonSegment<AppThemeMode>(
                      value: AppThemeMode.system,
                      label: Text('跟随系统'),
                      icon: Icon(Icons.brightness_auto_outlined),
                    ),
                    ButtonSegment<AppThemeMode>(
                      value: AppThemeMode.light,
                      label: Text('浅色'),
                      icon: Icon(Icons.light_mode_outlined),
                    ),
                    ButtonSegment<AppThemeMode>(
                      value: AppThemeMode.dark,
                      label: Text('深色'),
                      icon: Icon(Icons.dark_mode_outlined),
                    ),
                  ],
                  selected: <AppThemeMode>{_themeMode},
                  onSelectionChanged: (selection) =>
                      setState(() => _themeMode = selection.first),
                ),
              ),
            ]),
            const SizedBox(height: 16),
            _section('窗口与托盘', <Widget>[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _startMinimized,
                onChanged: (value) => setState(() => _startMinimized = value),
                title: const Text('启动时最小化到系统托盘'),
                subtitle: const Text('启动后不显示主窗口，可从托盘菜单显示；托盘不可用时会自动显示窗口。'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _minimizeToTray,
                onChanged: (value) => setState(() => _minimizeToTray = value),
                title: const Text('关闭窗口时最小化到系统托盘'),
                subtitle: const Text('在后台继续下载；可通过托盘菜单重新打开窗口、暂停任务或退出。'),
              ),
              const SizedBox(height: 8),
              Text(
                '托盘图标依赖桌面环境支持（GNOME 需要 AppIndicator 扩展）。'
                '托盘不可用时，关闭窗口会直接退出应用。',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ]),
            const SizedBox(height: 16),
            _section('aria2 引擎', <Widget>[
              AnimatedBuilder(
                animation: widget.engine,
                builder: (context, _) => _engineStatus(context),
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _aria2Path,
                decoration: InputDecoration(
                  labelText: 'aria2c 路径（可选）',
                  hintText: '留空则由 faria2 自动查找或安装',
                  prefixIcon: const Icon(Icons.terminal_outlined),
                  suffixIcon: IconButton(
                    tooltip: '选择 aria2c',
                    onPressed: _pickAria2Binary,
                    icon: const Icon(Icons.folder_open),
                  ),
                ),
                validator: (value) {
                  final path = value?.trim() ?? '';
                  if (path.isEmpty) {
                    return null;
                  }
                  if (!File(path).existsSync()) {
                    return '文件不存在';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  OutlinedButton.icon(
                    onPressed: () => widget.engine.restart(),
                    icon: const Icon(Icons.restart_alt),
                    label: const Text('重启引擎'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _confirmReinstall,
                    icon: const Icon(Icons.replay),
                    label: const Text('重新安装 aria2'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => PlatformLauncher.openDirectory(
                      widget.paths.cacheDir.path,
                    ),
                    icon: const Icon(Icons.folder_open),
                    label: const Text('缓存目录'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => PlatformLauncher.openFile(
                      widget.paths.aria2LogFile.path,
                    ),
                    icon: const Icon(Icons.description_outlined),
                    label: const Text('查看日志'),
                  ),
                ],
              ),
            ]),
            const SizedBox(height: 16),
            _section('连接与速度', <Widget>[
              _slider(
                label: '最大同时下载数',
                description: '同时进行的下载任务数量',
                value: _maxConcurrentDownloads,
                min: 1,
                max: 16,
                onChanged: (value) =>
                    setState(() => _maxConcurrentDownloads = value),
              ),
              _slider(
                label: '单服务器连接数',
                description: '每个服务器允许的最大连接数',
                value: _maxConnectionPerServer,
                min: 1,
                max: 16,
                onChanged: (value) =>
                    setState(() => _maxConnectionPerServer = value),
              ),
              _slider(
                label: '分片数',
                description: '每个文件切分的下载分片数量',
                value: _split,
                min: 1,
                max: 16,
                onChanged: (value) => setState(() => _split = value),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _speedLimit,
                decoration: const InputDecoration(
                  labelText: '全局下载限速（可选）',
                  hintText: '例如 1M、500K，留空表示不限速',
                  prefixIcon: Icon(Icons.speed_outlined),
                ),
                validator: (value) {
                  final text = value?.trim() ?? '';
                  if (text.isEmpty) {
                    return null;
                  }
                  if (!RegExp(
                    r'^[0-9]+(\.[0-9]+)?[KMG]?$',
                    caseSensitive: false,
                  ).hasMatch(text)) {
                    return '格式不正确，例如 1M 或 500K';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _rpcPort,
                keyboardType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                ],
                decoration: const InputDecoration(
                  labelText: 'aria2 RPC 端口',
                  hintText: '留空或 0 优先使用 16800，被占用时自动选择空闲端口',
                  prefixIcon: Icon(Icons.settings_ethernet),
                ),
                validator: (value) {
                  final text = value?.trim() ?? '';
                  if (text.isEmpty) {
                    return null;
                  }
                  final port = int.tryParse(text);
                  if (port == null || port < 0 || port > 65535) {
                    return '端口需在 0-65535 之间（0 表示自动）';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _rpcSecret,
                decoration: InputDecoration(
                  labelText: 'RPC 密钥（可选）',
                  hintText: '留空表示不启用密钥',
                  helperText: 'aria2 RPC 仅监听 127.0.0.1；留空时本机任意程序均可调用。',
                  helperMaxLines: 2,
                  prefixIcon: const Icon(Icons.key_outlined),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      IconButton(
                        tooltip: '复制密钥',
                        onPressed: _copyRpcSecret,
                        icon: const Icon(Icons.copy, size: 18),
                      ),
                      IconButton(
                        tooltip: '重新生成',
                        onPressed: _regenerateRpcSecret,
                        icon: const Icon(Icons.autorenew, size: 18),
                      ),
                    ],
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 16),
            _section('网络代理', <Widget>[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _useProxy,
                onChanged: (value) => setState(() => _useProxy = value),
                title: const Text('使用网络代理'),
                subtitle: const Text('aria2c 与 faria2 的网络请求都会经过此代理'),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _proxyUrl,
                enabled: _useProxy,
                decoration: const InputDecoration(
                  labelText: '代理地址',
                  hintText: '127.0.0.1:7890',
                  helperText:
                      '支持 host:port 或 http://host:port；暂不支持 SOCKS 与认证代理。',
                  helperMaxLines: 2,
                  prefixIcon: Icon(Icons.router_outlined),
                ),
                validator: (value) {
                  if (!_useProxy) {
                    return null;
                  }
                  if (NetworkProxy.normalize(value ?? '') == null) {
                    return '请输入 host:port 或 http://host:port';
                  }
                  return null;
                },
              ),
            ]),
            const SizedBox(height: 16),
            _section('BitTorrent Tracker', <Widget>[
              _trackerStatus(),
              const SizedBox(height: 12),
              Text('默认订阅链接', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 6),
              for (final url in TrackerService.defaultUrls)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: SelectableText(
                    url,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              const SizedBox(height: 12),
              Text('额外订阅链接', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 6),
              if (_trackerUrls.isEmpty)
                Text(
                  '暂无额外链接',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              for (final url in _trackerUrls)
                Row(
                  children: <Widget>[
                    Expanded(
                      child: SelectableText(
                        url,
                        maxLines: 1,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                    IconButton(
                      tooltip: '删除链接',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _removeTrackerUrl(url),
                      icon: const Icon(Icons.close, size: 16),
                    ),
                  ],
                ),
              TextFormField(
                controller: _newTrackerUrl,
                decoration: InputDecoration(
                  labelText: '添加订阅链接',
                  hintText: 'https://example.com/trackers.txt',
                  suffixIcon: IconButton(
                    tooltip: '添加链接',
                    onPressed: _addTrackerUrl,
                    icon: const Icon(Icons.add),
                  ),
                ),
                onFieldSubmitted: (value) => _addTrackerUrl(),
              ),
              const SizedBox(height: 16),
              Text('手动 Tracker', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 6),
              TextFormField(
                controller: _manualTrackers,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(
                  hintText: 'udp://tracker.example.com:6969/announce\n每行一个',
                  alignLabelWithHint: true,
                ),
                validator: (value) {
                  for (final line in (value ?? '').split(RegExp(r'[\r\n]+'))) {
                    final tracker = line.trim();
                    if (tracker.isEmpty) {
                      continue;
                    }
                    if (!TrackerService.isTrackerUrl(tracker)) {
                      return '无效的 tracker：$tracker';
                    }
                  }
                  return null;
                },
              ),
              const SizedBox(height: 6),
              Text(
                '手动输入的 tracker 会与订阅链接获取的列表合并并去重，不会覆盖或影响订阅结果。',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ]),
            const SizedBox(height: 16),
            _section('关于', <Widget>[
              Text(
                'faria2 1.0.1',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 6),
              Text(
                'faria2 是一个基于 aria2 的跨平台下载器。启动时自动寻找系统中的 aria2c；'
                '如果找不到，会为当前操作系统下载 aria2 并安装到 faria2 的缓存目录，'
                '然后以本地 RPC 模式启动 aria2c。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              SelectableText(
                '缓存目录：${widget.paths.cacheDir.path}\n'
                '配置目录：${widget.paths.supportDir.path}',
                style: Theme.of(context).textTheme.labelSmall,
              ),
              const SizedBox(height: 8),
              Text(
                'faria2 以 MIT 许可证发布。\n'
                'aria2 是 GPLv2 软件，由 faria2 在运行时从官方发布渠道下载，'
                '不随应用一起分发。',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => showLicensePage(
                  context: context,
                  applicationName: 'faria2',
                  applicationVersion: '1.0.1',
                  applicationLegalese: 'MIT License',
                ),
                icon: const Icon(Icons.article_outlined, size: 18),
                label: const Text('开源许可'),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _engineStatus(BuildContext context) {
    final engine = widget.engine;
    final scheme = Theme.of(context).colorScheme;
    final location = engine.location;
    final running = engine.isReady;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: running ? const Color(0xFF2E9E63) : scheme.outline,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                running ? '运行中' : engine.status,
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const Spacer(),
              if (engine.aria2Version != null)
                Text(
                  'aria2 ${engine.aria2Version}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          _infoRow('可执行文件', location?.path ?? '尚未找到'),
          _infoRow('来源', location?.sourceLabel ?? '-'),
          _infoRow('RPC 端口', engine.rpcPort == 0 ? '-' : '${engine.rpcPort}'),
          _infoRow(
            'RPC 认证',
            engine.settings.rpcSecret.isEmpty ? '未启用（无密钥）' : '已启用',
          ),
          _endpointRow(
            'WebSocket',
            engine.rpcPort == 0
                ? null
                : 'ws://127.0.0.1:${engine.rpcPort}/jsonrpc',
          ),
          _endpointRow(
            'HTTP',
            engine.rpcPort == 0
                ? null
                : 'http://127.0.0.1:${engine.rpcPort}/jsonrpc',
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => _copyRpcInfo(engine),
              icon: const Icon(Icons.link, size: 16),
              label: const Text('复制连接信息'),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            engine.settings.rpcSecret.isEmpty
                ? '外部程序可直接连接；RPC 仅监听 127.0.0.1。'
                : '外部程序连接时需在 JSON-RPC 参数首位携带 token:<RPC 密钥>。',
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          _infoRow('引擎目录', widget.paths.engineRoot.path),
          if (engine.skippedCandidates.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: scheme.errorContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 16,
                        color: scheme.error,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '已跳过 ${engine.skippedCandidates.length} 个无法运行的 aria2c',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: scheme.onErrorContainer),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  for (final item in engine.skippedCandidates)
                    Text(
                      item,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onErrorContainer,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              maxLines: 3,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
        ],
      ),
    );
  }

  Widget _slider({
    required String label,
    required String description,
    required int value,
    required int min,
    required int max,
    required ValueChanged<int> onChanged,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(label, style: theme.textTheme.labelLarge),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$value',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ),
          Slider(
            value: value.toDouble(),
            min: min.toDouble(),
            max: max.toDouble(),
            divisions: max - min,
            label: '$value',
            onChanged: (next) => onChanged(next.round()),
          ),
          Text(
            description,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }
}

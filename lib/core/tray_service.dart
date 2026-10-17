import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:tray_manager/tray_manager.dart';

import 'app_paths.dart';
import 'formatting.dart';
import 'models/global_stat.dart';

/// Owns the system tray icon and its context menu.
///
/// The tray is optional: desktops without a StatusNotifierItem host (for
/// example GNOME without the AppIndicator extension) simply get [isReady] ==
/// false and faria2 falls back to quitting when the window is closed.
class TrayService {
  TrayService({
    required this.paths,
    required this.onShowWindow,
    required this.onToggleWindow,
    required this.onAddDownload,
    required this.onPauseAll,
    required this.onResumeAll,
    required this.onOpenDownloadFolder,
    required this.onQuit,
  });

  final AppPaths paths;
  final void Function() onShowWindow;
  final void Function() onToggleWindow;
  final void Function() onAddDownload;
  final void Function() onPauseAll;
  final void Function() onResumeAll;
  final void Function() onOpenDownloadFolder;
  final void Function() onQuit;

  TrayIcon? _icon;
  Image? _image;
  Menu? _menu;
  // Keep every native menu item alive while the tray icon exists; the Dart
  // wrappers own native handles with finalizers.
  MenuItem? _showItem;
  MenuItem? _addItem;
  MenuItem? _pauseItem;
  MenuItem? _resumeItem;
  MenuItem? _folderItem;
  MenuItem? _quitItem;
  bool _ready = false;

  bool get isReady => _ready;

  /// Native menu items kept referenced while the tray icon exists. The Dart
  /// wrappers own native handles with finalizers, so they must not be
  /// collected while the menu is in use.
  List<MenuItem?> get menuItems => <MenuItem?>[
    _showItem,
    _addItem,
    _pauseItem,
    _resumeItem,
    _folderItem,
    _quitItem,
  ];

  Future<bool> init() async {
    if (!Platform.isWindows && !Platform.isLinux) {
      return false;
    }
    // StatusNotifierItem needs a D-Bus session; without one the native tray
    // backend cannot be initialized.
    if (Platform.isLinux &&
        (Platform.environment['DBUS_SESSION_BUS_ADDRESS'] ?? '').isEmpty) {
      return false;
    }
    try {
      final iconPath = await _writeTrayIcon();
      if (iconPath == null) {
        return false;
      }

      final icon = TrayIcon.create();
      if (icon == null) {
        return false;
      }
      final menu = Menu.create();
      if (menu == null) {
        icon.dispose();
        return false;
      }

      final showItem = MenuItem.createWithLabelAndType(
        '显示',
        MenuItemType.normal,
      );
      final addItem = MenuItem.createWithLabelAndType(
        '添加下载',
        MenuItemType.normal,
      );
      final pauseItem = MenuItem.createWithLabelAndType(
        '全部暂停',
        MenuItemType.normal,
      );
      final resumeItem = MenuItem.createWithLabelAndType(
        '全部继续',
        MenuItemType.normal,
      );
      final folderItem = MenuItem.createWithLabelAndType(
        '打开下载目录',
        MenuItemType.normal,
      );
      final quitItem = MenuItem.createWithLabelAndType(
        '退出',
        MenuItemType.normal,
      );

      _listen(showItem, onShowWindow);
      _listen(addItem, onAddDownload);
      _listen(pauseItem, onPauseAll);
      _listen(resumeItem, onResumeAll);
      _listen(folderItem, onOpenDownloadFolder);
      _listen(quitItem, onQuit);

      menu.addItem(showItem);
      menu.addItem(addItem);
      menu.addSeparator();
      menu.addItem(pauseItem);
      menu.addItem(resumeItem);
      menu.addItem(folderItem);
      menu.addSeparator();
      menu.addItem(quitItem);

      final image = Image.fromFile(iconPath);
      if (image != null) {
        icon.icon = image;
      }
      icon.setTooltip('faria2');
      icon.setContextMenu(menu);
      // On Linux the StatusNotifierItem host only shows a menu when a trigger
      // is configured; without this the Menu property is /NO_DBUSMENU and
      // right-clicking the icon does nothing.
      icon.setContextMenuTrigger(ContextMenuTrigger.rightClicked);
      if (!icon.setVisible(true)) {
        icon.dispose();
        menu.dispose();
        return false;
      }
      icon.addListener((event) {
        if (event is TrayIconClickedEvent) {
          onToggleWindow();
        } else if (event is TrayIconDoubleClickedEvent) {
          onShowWindow();
        }
      });

      _icon = icon;
      _image = image;
      _menu = menu;
      _showItem = showItem;
      _addItem = addItem;
      _pauseItem = pauseItem;
      _resumeItem = resumeItem;
      _folderItem = folderItem;
      _quitItem = quitItem;
      _ready = true;
      return true;
    } on Object {
      _disposeQuietly();
      return false;
    }
  }

  /// Updates the tooltip with the current transfer speed and toggles the
  /// enabled state of the pause/resume entries.
  void update({
    required bool engineReady,
    required String engineStatus,
    required GlobalStat stat,
    required bool canPause,
    required bool canResume,
  }) {
    if (!_ready) {
      return;
    }
    try {
      final tooltip = engineReady
          ? 'faria2 · ↓ ${formatSpeed(stat.downloadSpeed)} · '
                '活跃 ${stat.numActive} / 等待 ${stat.numWaiting}'
          : 'faria2 · $engineStatus';
      _icon?.setTooltip(tooltip);
      _pauseItem?.isEnabled = engineReady && canPause;
      _resumeItem?.isEnabled = engineReady && canResume;
    } on Object {
      // Updating a tooltip must never break the app.
    }
  }

  void dispose() {
    _ready = false;
    _disposeQuietly();
  }

  void _disposeQuietly() {
    try {
      _icon?.setVisible(false);
    } on Object {
      // Ignore.
    }
    try {
      _icon?.dispose();
    } on Object {
      // Ignore.
    }
    try {
      _menu?.dispose();
    } on Object {
      // Ignore.
    }
    try {
      _image?.dispose();
    } on Object {
      // Ignore.
    }
    _icon = null;
    _image = null;
    _menu = null;
    _showItem = null;
    _addItem = null;
    _pauseItem = null;
    _resumeItem = null;
    _folderItem = null;
    _quitItem = null;
  }

  void _listen(MenuItem? item, void Function() callback) {
    item?.addListener((event) {
      if (event is MenuItemClickedEvent) {
        callback();
      }
    });
  }

  /// Copies the bundled tray icon next to the cache so the native layer can
  /// load it from disk.
  Future<String?> _writeTrayIcon() async {
    try {
      final directory = Directory(p.join(paths.cacheDir.path, 'icons'));
      await directory.create(recursive: true);
      final file = File(p.join(directory.path, 'tray_icon.png'));
      final data = await rootBundle.load('assets/icons/tray_icon.png');
      await file.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
      return file.path;
    } on Object {
      return null;
    }
  }
}

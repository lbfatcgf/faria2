import 'dart:io';

import 'package:faria2/core/app_paths.dart';
import 'package:faria2/core/app_settings.dart';
import 'package:faria2/core/download_manager.dart';
import 'package:faria2/core/engine_controller.dart';
import 'package:faria2/core/models/download_task.dart';
import 'package:faria2/ui/home_page.dart';
import 'package:faria2/ui/settings_page.dart';
import 'package:faria2/ui/theme.dart';
import 'package:faria2/ui/widgets/status_bar.dart';
import 'package:faria2/ui/widgets/task_tile.dart';
import 'package:faria2/ui/window/window_resize_handles.dart';
import 'package:faria2/ui/window/window_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('status bar shows the engine state', (tester) async {
    final paths = AppPaths(
      cacheDir: Directory('/tmp/faria2-test/cache'),
      supportDir: Directory('/tmp/faria2-test/support'),
      downloadsDir: Directory('/tmp/faria2-test/downloads'),
    );
    final engine = EngineController(
      paths: paths,
      settings: AppSettings.defaults('/tmp/faria2-test/downloads'),
    );
    final downloads = DownloadManager();
    addTearDown(engine.dispose);
    addTearDown(downloads.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildFaria2Theme(Brightness.light),
        home: Scaffold(
          bottomNavigationBar: StatusBar(engine: engine, downloads: downloads),
        ),
      ),
    );

    expect(find.textContaining('尚未启动'), findsOneWidget);
    expect(find.textContaining('0 B/s'), findsWidgets);
  });

  testWidgets('task tile renders name, state and progress', (tester) async {
    final task = DownloadTask.fromJson(<String, dynamic>{
      'gid': 'gid-1',
      'status': 'active',
      'totalLength': '2048',
      'completedLength': '1024',
      'downloadSpeed': '1024',
      'uploadSpeed': '0',
      'connections': '2',
      'dir': '/tmp',
      'files': <dynamic>[
        <String, dynamic>{
          'index': '1',
          'path': '/tmp/example.bin',
          'length': '2048',
          'completedLength': '1024',
          'selected': 'true',
        },
      ],
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: buildFaria2Theme(Brightness.light),
        home: Scaffold(
          body: TaskTile(task: task, onAction: (action) {}),
        ),
      ),
    );

    expect(find.text('example.bin'), findsOneWidget);
    expect(find.text('下载中'), findsOneWidget);
    expect(
      find.text('1.0 KiB / 2.0 KiB · 1.0 KiB/s · 剩余 00:00:01 · 2 连接'),
      findsOneWidget,
    );
    final indicator = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(indicator.value, closeTo(0.5, 0.0001));
  });

  testWidgets('home page shows the engine bootstrap panel when idle', (
    tester,
  ) async {
    final paths = AppPaths(
      cacheDir: Directory('/tmp/faria2-test/cache'),
      supportDir: Directory('/tmp/faria2-test/support'),
      downloadsDir: Directory('/tmp/faria2-test/downloads'),
    );
    final settings = AppSettings.defaults(paths.downloadsDir.path);
    final engine = EngineController(paths: paths, settings: settings);
    final downloads = DownloadManager();
    addTearDown(engine.dispose);
    addTearDown(downloads.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildFaria2Theme(Brightness.light),
        home: HomePage(
          engine: engine,
          downloads: downloads,
          paths: paths,
          settings: settings,
          onSettingsChanged: (next) async {},
        ),
      ),
    );

    expect(find.text('下载列表'), findsOneWidget);
    expect(find.text('正在准备下载引擎'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.textContaining('缓存目录'), findsWidgets);
  });

  testWidgets(
    'tray add-download request is ignored before the engine is ready',
    (tester) async {
      final paths = AppPaths(
        cacheDir: Directory('/tmp/faria2-test/cache'),
        supportDir: Directory('/tmp/faria2-test/support'),
        downloadsDir: Directory('/tmp/faria2-test/downloads'),
      );
      final settings = AppSettings.defaults(paths.downloadsDir.path);
      final engine = EngineController(paths: paths, settings: settings);
      final downloads = DownloadManager();
      final requests = ValueNotifier<int>(0);
      addTearDown(engine.dispose);
      addTearDown(downloads.dispose);
      addTearDown(requests.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildFaria2Theme(Brightness.light),
          home: HomePage(
            engine: engine,
            downloads: downloads,
            paths: paths,
            settings: settings,
            onSettingsChanged: (next) async {},
            addDownloadRequests: requests,
          ),
        ),
      );

      requests.value++;
      await tester.pump();

      expect(find.text('aria2 引擎尚未就绪，请稍后再试'), findsOneWidget);
    },
  );

  testWidgets('settings page renders the main sections', (tester) async {
    final paths = AppPaths(
      cacheDir: Directory('/tmp/faria2-test/cache'),
      supportDir: Directory('/tmp/faria2-test/support'),
      downloadsDir: Directory('/tmp/faria2-test/downloads'),
    );
    final settings = AppSettings.defaults(paths.downloadsDir.path);
    final engine = EngineController(paths: paths, settings: settings);
    addTearDown(engine.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildFaria2Theme(Brightness.light),
        home: SettingsPage(
          initial: settings,
          paths: paths,
          engine: engine,
          onSaved: (next) async {},
        ),
      ),
    );

    expect(find.text('设置'), findsOneWidget);
    expect(find.text('下载'), findsOneWidget);
    expect(find.text('默认下载目录'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('窗口与托盘'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('窗口与托盘'), findsOneWidget);
    expect(find.text('关闭窗口时最小化到系统托盘'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('aria2 引擎'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('aria2 引擎'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('复制连接信息'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('复制连接信息'), findsOneWidget);
    expect(find.text('WebSocket'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('连接与速度'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('连接与速度'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('网络代理'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('使用网络代理'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('BitTorrent Tracker'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('手动 Tracker'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('关于'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('faria2 以 MIT 许可证发布'), findsOneWidget);
    expect(find.text('开源许可'), findsOneWidget);
  });

  testWidgets('settings page saves an empty RPC secret', (tester) async {
    final paths = AppPaths(
      cacheDir: Directory('/tmp/faria2-test/cache'),
      supportDir: Directory('/tmp/faria2-test/support'),
      downloadsDir: Directory('/tmp/faria2-test/downloads'),
    );
    final settings = AppSettings.defaults(
      paths.downloadsDir.path,
    ).copyWith(rpcSecret: 'old-secret');
    final engine = EngineController(paths: paths, settings: settings);
    addTearDown(engine.dispose);
    AppSettings? saved;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildFaria2Theme(Brightness.light),
        home: SettingsPage(
          initial: settings,
          paths: paths,
          engine: engine,
          onSaved: (next) async {
            saved = next;
          },
        ),
      ),
    );

    final secretField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.labelText == 'RPC 密钥（可选）',
    );
    await tester.scrollUntilVisible(
      secretField,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(secretField, findsOneWidget);

    await tester.enterText(secretField, '');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.rpcSecret, isEmpty);
  });

  testWidgets('window shell renders the custom title bar', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildFaria2Theme(Brightness.light),
        builder: (context, child) =>
            WindowShell(child: child ?? const SizedBox.shrink()),
        home: const Scaffold(body: Center(child: Text('content'))),
      ),
    );

    expect(find.text('faria2'), findsOneWidget);
    expect(find.text('content'), findsOneWidget);
    expect(find.byType(WindowResizeHandles), findsOneWidget);
  });
}

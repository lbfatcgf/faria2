import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'models/download_task.dart';
import 'models/global_stat.dart';

/// Error returned by the aria2 JSON-RPC endpoint or by the transport.
class Aria2RpcException implements Exception {
  Aria2RpcException(this.code, this.message, {this.method});

  final int code;
  final String message;
  final String? method;

  @override
  String toString() {
    final prefix = method == null ? '' : '$method: ';
    return '$prefix$message (code $code)';
  }
}

/// Small typed wrapper around the aria2 JSON-RPC interface.
class Aria2Rpc {
  Aria2Rpc({
    required this.port,
    required this.secret,
    http.Client? client,
    this.timeout = const Duration(seconds: 10),
  }) : _client = client ?? http.Client();

  final int port;
  final String secret;
  final Duration timeout;
  final http.Client _client;
  int _nextId = 0;
  bool _closed = false;

  Uri get endpoint => Uri.parse('http://127.0.0.1:$port/jsonrpc');

  /// Builds the positional parameter list. aria2 expects the secret as the
  /// first parameter prefixed with `token:`; without a secret no token is
  /// sent at all.
  static List<Object?> buildParams(String secret, List<Object?> params) {
    if (secret.isEmpty) {
      return List<Object?>.of(params);
    }
    return <Object?>['token:$secret', ...params];
  }

  /// Sends a raw JSON-RPC request and returns the decoded `result`.
  Future<dynamic> call(String method, [List<Object?> params = const []]) async {
    if (_closed) {
      throw Aria2RpcException(-32000, 'RPC 客户端已关闭');
    }
    final body = jsonEncode(<String, Object?>{
      'jsonrpc': '2.0',
      'id': 'faria2-${_nextId++}',
      'method': method,
      'params': buildParams(secret, params),
    });

    http.Response response;
    try {
      response = await _client
          .post(
            endpoint,
            headers: const <String, String>{'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(timeout);
    } on TimeoutException {
      throw Aria2RpcException(-32001, '连接 aria2 超时', method: method);
    } on SocketException catch (error) {
      throw Aria2RpcException(
        -32002,
        '无法连接 aria2：${error.message}',
        method: method,
      );
    } on http.ClientException catch (error) {
      throw Aria2RpcException(
        -32002,
        '无法连接 aria2：${error.message}',
        method: method,
      );
    }

    final text = utf8.decode(response.bodyBytes, allowMalformed: true);
    if (response.statusCode != 200) {
      throw Aria2RpcException(
        response.statusCode,
        'aria2 RPC 返回 HTTP ${response.statusCode}',
        method: method,
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(text);
    } on Object {
      throw Aria2RpcException(-32700, '无法解析 aria2 的响应', method: method);
    }
    if (decoded is! Map<String, dynamic>) {
      throw Aria2RpcException(-32700, 'aria2 返回了无效的响应', method: method);
    }
    final error = decoded['error'];
    if (error is Map) {
      final code = error['code'];
      final message = error['message'];
      throw Aria2RpcException(
        code is int ? code : -32000,
        message is String ? message : 'aria2 调用失败',
        method: method,
      );
    }
    return decoded['result'];
  }

  Future<bool> ping() async {
    try {
      await call('aria2.getVersion');
      return true;
    } on Object {
      return false;
    }
  }

  Future<String> getVersion() async {
    final result = await call('aria2.getVersion');
    if (result is Map && result['version'] is String) {
      return result['version'] as String;
    }
    throw Aria2RpcException(-32603, 'aria2 未返回版本信息');
  }

  Future<GlobalStat> getGlobalStat() async {
    final result = await call('aria2.getGlobalStat');
    if (result is Map<String, dynamic>) {
      return GlobalStat.fromJson(result);
    }
    return GlobalStat.empty;
  }

  Future<String> addUri(
    List<String> uris, {
    String? dir,
    String? out,
    Map<String, String> options = const <String, String>{},
  }) async {
    final merged = <String, String>{
      ...options,
      if (dir != null && dir.isNotEmpty) 'dir': dir,
      if (out != null && out.isNotEmpty) 'out': out,
    };
    final result = await call('aria2.addUri', <Object?>[uris, merged]);
    return result.toString();
  }

  Future<String> addTorrent(
    String base64Torrent, {
    List<String> uris = const <String>[],
    String? dir,
    Map<String, String> options = const <String, String>{},
  }) async {
    final merged = <String, String>{
      ...options,
      if (dir != null && dir.isNotEmpty) 'dir': dir,
    };
    final result = await call('aria2.addTorrent', <Object?>[
      base64Torrent,
      uris,
      merged,
    ]);
    return result.toString();
  }

  Future<String> addMetalink(
    String base64Metalink, {
    String? dir,
    Map<String, String> options = const <String, String>{},
  }) async {
    final merged = <String, String>{
      ...options,
      if (dir != null && dir.isNotEmpty) 'dir': dir,
    };
    final result = await call('aria2.addMetalink', <Object?>[
      base64Metalink,
      merged,
    ]);
    return result.toString();
  }

  Future<List<Map<String, dynamic>>> tellActive() async {
    return _asMapList(await call('aria2.tellActive'));
  }

  Future<List<Map<String, dynamic>>> tellWaiting({
    int offset = 0,
    int num = 1000,
  }) async {
    return _asMapList(await call('aria2.tellWaiting', <Object?>[offset, num]));
  }

  Future<List<Map<String, dynamic>>> tellStopped({
    int offset = 0,
    int num = 1000,
  }) async {
    return _asMapList(await call('aria2.tellStopped', <Object?>[offset, num]));
  }

  Future<Map<String, dynamic>> tellStatus(
    String gid, {
    List<String> keys = const <String>[],
  }) async {
    final result = await call('aria2.tellStatus', <Object?>[gid, keys]);
    if (result is Map<String, dynamic>) {
      return result;
    }
    throw Aria2RpcException(-32603, 'aria2 未返回任务状态');
  }

  Future<void> pause(String gid) async {
    await call('aria2.pause', <Object?>[gid]);
  }

  Future<void> unpause(String gid) async {
    await call('aria2.unpause', <Object?>[gid]);
  }

  Future<void> pauseAll() async {
    await call('aria2.pauseAll');
  }

  Future<void> unpauseAll() async {
    await call('aria2.unpauseAll');
  }

  Future<void> remove(String gid) async {
    await call('aria2.remove', <Object?>[gid]);
  }

  Future<void> removeDownloadResult(String gid) async {
    await call('aria2.removeDownloadResult', <Object?>[gid]);
  }

  Future<void> purgeDownloadResult() async {
    await call('aria2.purgeDownloadResult');
  }

  Future<void> changeGlobalOption(Map<String, String> options) async {
    await call('aria2.changeGlobalOption', <Object?>[options]);
  }

  Future<void> shutdown() async {
    await call('aria2.shutdown');
  }

  void close() {
    _closed = true;
    _client.close();
  }

  List<Map<String, dynamic>> _asMapList(dynamic value) {
    if (value is! List) {
      return const <Map<String, dynamic>>[];
    }
    return value
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList(growable: false);
  }
}

/// Convenience wrapper for parsing a task from a raw status map.
DownloadTask taskFromJson(Map<String, dynamic> json) =>
    DownloadTask.fromJson(json);

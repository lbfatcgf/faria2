import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Raised when downloading an engine archive fails.
class DownloadException implements Exception {
  DownloadException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Minimal streaming HTTP downloader with progress reporting.
class DownloadClient {
  DownloadClient({http.Client? client, this.userAgent = 'faria2/1.0'})
    : _client = client ?? http.Client();

  final http.Client _client;
  final String userAgent;

  /// Downloads [url] into [target], calling [onProgress] with the number of
  /// received bytes and the total size (when known).
  Future<void> download(
    Uri url,
    File target, {
    void Function(int received, int? total)? onProgress,
    Duration responseTimeout = const Duration(seconds: 30),
  }) async {
    await target.parent.create(recursive: true);
    final request = http.Request('GET', url)..headers['User-Agent'] = userAgent;
    final streamed = await _client
        .send(request)
        .timeout(
          responseTimeout,
          onTimeout: () => throw DownloadException('连接下载服务器超时：$url'),
        );
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      throw DownloadException('下载失败（HTTP ${streamed.statusCode}）：$url');
    }
    final total = streamed.contentLength;
    final sink = target.openWrite();
    var received = 0;
    try {
      await for (final chunk in streamed.stream) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
  }

  void close() => _client.close();
}

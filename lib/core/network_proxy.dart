import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Default address used when the "网络代理" switch is enabled.
const String defaultProxyAddress = '127.0.0.1:7890';

/// HTTP proxy configuration shared by aria2c and faria2's own HTTP requests.
///
/// Only unauthenticated HTTP proxies are supported (the common Clash/V2Ray
/// mixed port setup). SOCKS proxies are rejected because aria2's --all-proxy
/// does not speak SOCKS.
class NetworkProxy {
  const NetworkProxy({required this.enabled, required this.address});

  final bool enabled;
  final String address;

  /// Normalizes `host:port` / `http://host:port` to `http://host:port`.
  /// Returns null when the value is not a usable HTTP proxy.
  static String? normalize(String raw) {
    var value = raw.trim();
    if (value.isEmpty) {
      return null;
    }
    if (!value.contains('://')) {
      value = 'http://$value';
    }
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme.toLowerCase() != 'http') {
      return null;
    }
    if (uri.host.isEmpty || uri.userInfo.isNotEmpty || !uri.hasPort) {
      return null;
    }
    if (uri.port <= 0 || uri.port > 65535) {
      return null;
    }
    if (uri.path.isNotEmpty && uri.path != '/') {
      return null;
    }
    final host = uri.host.contains(':') ? '[${uri.host}]' : uri.host;
    return 'http://$host:${uri.port}';
  }

  bool get isValid => !enabled || normalize(address) != null;

  /// The value passed to aria2's `--all-proxy` option, or null when disabled.
  String? get httpUrl => enabled ? normalize(address) : null;

  /// Builds an HTTP client that routes requests through the proxy.
  /// The caller owns the returned client and must close it.
  http.Client createClient() {
    final url = httpUrl;
    if (url == null) {
      return http.Client();
    }
    final uri = Uri.parse(url);
    final host = uri.host.contains(':') ? '[${uri.host}]' : uri.host;
    final proxy = 'PROXY $host:${uri.port}';
    final client = HttpClient()
      ..findProxy = ((target) => proxy)
      ..connectionTimeout = const Duration(seconds: 20);
    return IOClient(client);
  }
}

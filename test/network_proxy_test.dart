import 'package:faria2/core/network_proxy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizes host:port and http URLs', () {
    expect(NetworkProxy.normalize('127.0.0.1:7890'), 'http://127.0.0.1:7890');
    expect(
      NetworkProxy.normalize(' http://127.0.0.1:7890 '),
      'http://127.0.0.1:7890',
    );
    expect(NetworkProxy.normalize('http://[::1]:7890'), 'http://[::1]:7890');
  });

  test('rejects unsupported or malformed proxies', () {
    expect(NetworkProxy.normalize(''), isNull);
    expect(NetworkProxy.normalize('socks5://127.0.0.1:7890'), isNull);
    expect(NetworkProxy.normalize('127.0.0.1'), isNull);
    expect(NetworkProxy.normalize('user:pass@127.0.0.1:7890'), isNull);
    expect(NetworkProxy.normalize('http://127.0.0.1:7890/path'), isNull);
  });

  test('httpUrl is null when the proxy is disabled', () {
    const disabled = NetworkProxy(enabled: false, address: '127.0.0.1:7890');
    const enabled = NetworkProxy(enabled: true, address: '127.0.0.1:7890');
    expect(disabled.httpUrl, isNull);
    expect(enabled.httpUrl, 'http://127.0.0.1:7890');
    expect(enabled.isValid, isTrue);
    expect(
      const NetworkProxy(
        enabled: true,
        address: 'socks5://127.0.0.1:7890',
      ).isValid,
      isFalse,
    );
  });
}

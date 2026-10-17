import 'package:faria2/core/aria2_rpc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('prepends the token when a secret is configured', () {
    expect(Aria2Rpc.buildParams('s3cret', <Object?>['gid']), <Object?>[
      'token:s3cret',
      'gid',
    ]);
    expect(Aria2Rpc.buildParams('s3cret', const <Object?>[]), <Object?>[
      'token:s3cret',
    ]);
  });

  test('omits the token when no secret is configured', () {
    expect(Aria2Rpc.buildParams('', <Object?>['gid']), <Object?>['gid']);
    expect(Aria2Rpc.buildParams('', const <Object?>[]), isEmpty);
  });
}
